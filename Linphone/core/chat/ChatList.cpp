/*
 * Copyright (c) 2010-2024 Belledonne Communications SARL.
 *
 * This file is part of linphone-desktop
 * (see https://www.linphone.org).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "ChatList.hpp"
#include "ChatCore.hpp"
#include "ChatGui.hpp"
#include "core/App.hpp"
#include "model/tool/ToolModel.hpp"

#include <QSharedPointer>
#include <QTimer>

#include <linphone++/linphone.hh>

// =============================================================================

DEFINE_ABSTRACT_OBJECT(ChatList)

QSharedPointer<ChatList> ChatList::create() {
	auto model = QSharedPointer<ChatList>(new ChatList(), &QObject::deleteLater);
	model->moveToThread(App::getInstance()->thread());
	model->setSelf(model);
	return model;
}

QSharedPointer<ChatCore> ChatList::createChatCore(const std::shared_ptr<linphone::ChatRoom> &chatroom) {
	auto chatCore = ChatCore::create(chatroom);
	return chatCore;
}

ChatList::ChatList(QObject *parent) : ListProxy(parent) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
	// Index tenu a jour a chaque changement de la liste, quel que soit l'endroit qui la modifie.
	connect(this, &QAbstractItemModel::modelReset, this, &ChatList::rebuildIndex);
	connect(this, &QAbstractItemModel::rowsInserted, this, &ChatList::rebuildIndex);
	connect(this, &QAbstractItemModel::rowsRemoved, this, &ChatList::rebuildIndex);
	connect(this, &QAbstractItemModel::rowsMoved, this, &ChatList::rebuildIndex);
	connect(this, &QAbstractItemModel::layoutChanged, this, &ChatList::rebuildIndex);
}

ChatList::~ChatList() {
	mustBeInMainThread("~" + getClassName());
	mModelConnection->disconnect();
}

void ChatList::disconnectItem(QSharedPointer<ChatCore> chat) {
	disconnect(chat.get(), &ChatCore::deleted, this, nullptr);
	disconnect(chat.get(), &ChatCore::unreadMessagesCountChanged, this, nullptr);
	disconnect(chat.get(), &ChatCore::lastUpdatedTimeChanged, this, nullptr);
	disconnect(chat.get(), &ChatCore::lastMessageChanged, this, nullptr);
}

void ChatList::connectItem(QSharedPointer<ChatCore> chat) {
	connect(
	    chat.get(), &ChatCore::deleted, this,
	    [this, chat] {
		    disconnect(chat.get(), &ChatCore::unreadMessagesCountChanged, this, nullptr);
		    disconnect(chat.get(), &ChatCore::lastUpdatedTimeChanged, this, nullptr);
		    disconnect(chat.get(), &ChatCore::lastMessageChanged, this, nullptr);
		    remove(chat);
	    },
	    Qt::SingleShotConnection);
	auto dataChange = [this, chat] {
		// Defer dataChanged to avoid destroying QML delegates synchronously
		// during a SafeConnection::invokeToCore callback, which causes
		// accessibility to access already-freed QQuickItem data (QTBUG).
		QTimer::singleShot(0, this, [this, chat] {
			int i = -1;
			get(chat.get(), &i);
			if (i != -1) {
				auto modelIndex = index(i);
				if (modelIndex.isValid()) emit dataChanged(modelIndex, modelIndex);
			}
		});
	};
	connect(chat.get(), &ChatCore::unreadMessagesCountChanged, this, [this, dataChange] {
		dataChange();
		auto defaultAccount = App::getInstance()->getAccountList()
		                          ? App::getInstance()->getAccountList()->getDefaultAccountCore()
		                          : nullptr;
		if (defaultAccount && defaultAccount->getRegistrationState() == LinphoneEnums::RegistrationState::Ok)
			emit defaultAccount->lRefreshNotifications();
	});
	connect(chat.get(), &ChatCore::lastUpdatedTimeChanged, this, dataChange);
	connect(chat.get(), &ChatCore::lastMessageChanged, this, dataChange);
}

void ChatList::setSelf(QSharedPointer<ChatList> me) {
	mModelConnection = SafeConnection<ChatList, CoreModel>::create(me, CoreModel::getInstance());
	mModelConnection->makeConnectToCore(&ChatList::lUpdate, [this]() {
		if (mIsUpdating) {
			connect(this, &ChatList::isUpdatingChanged, this, [this] {
				if (!mIsUpdating) {
					disconnect(this, &ChatList::isUpdatingChanged, this, nullptr);
					lUpdate();
				}
			});
			return;
		}
		setIsUpdating(true);
		mModelConnection->invokeToModel([this]() {
			mustBeInLinphoneThread(getClassName());
			// Avoid copy to lambdas
			QList<QSharedPointer<ChatCore>> *chats = new QList<QSharedPointer<ChatCore>>();
			auto currentAccount = CoreModel::getInstance()->getCore()->getDefaultAccount();
			if (!currentAccount) {
				mModelConnection->invokeToCore([this, chats]() {
					for (auto &chat : getSharedList<ChatCore>()) {
						if (chat) {
							disconnectItem(chat);
						}
					}
					beginResetModel();
					mList.clear();
					endResetModel();
					setIsUpdating(false);
				});
				return;
			}
			auto linphoneChatRooms = currentAccount->filterChatRooms(Utils::appStringToCoreString(mFilter));
			for (auto it : linphoneChatRooms) {
				auto state = it->getState();
				if (state == linphone::ChatRoom::State::CreationFailed ||
				    state == linphone::ChatRoom::State::CreationPending ||
				    state == linphone::ChatRoom::State::TerminationPending ||
				    state == linphone::ChatRoom::State::Instantiated) {
					continue;
				}
				auto model = createChatCore(it);
				chats->push_back(model);
			}
			mModelConnection->invokeToCore([this, chats]() {
				mustBeInMainThread(getClassName());
				for (auto &chat : getSharedList<ChatCore>()) {
					if (chat) {
						disconnectItem(chat);
					}
				}
				beginResetModel();
				mList.clear();
				for (auto &chat : *chats) {
					connectItem(chat);
					mList.append(chat);
				}
				endResetModel();
				setIsUpdating(false);
				chats->clear();
				delete chats;
			});
		});
	});

	mModelConnection->makeConnectToModel(
	    &CoreModel::defaultAccountChanged,
	    [this](std::shared_ptr<linphone::Core> core, std::shared_ptr<linphone::Account> account) { lUpdate(); });

	auto addChatToList = [this](const std::shared_ptr<linphone::Core> &core,
	                            const std::shared_ptr<linphone::ChatRoom> &room, bool sendAddSignal = false) {
		mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
		if (!core->getDefaultAccount()) return;
		if (room->getAccount() != core->getDefaultAccount()) {
			qInfo() << log().arg("Chat room to add does not refer to current account, return");
			return;
		}
		if (room->getConferenceInfo()) {
			lWarning() << log().arg("Chatroom to add is a conference, return");
			return;
		}
		bool canAdd = false;
		auto linphoneChatRooms = core->getDefaultAccount()->filterChatRooms(Utils::appStringToCoreString(mFilter));
		for (auto it : linphoneChatRooms) {
			if (it->getIdentifier() == room->getIdentifier()) {
				canAdd = true;
				break;
			}
		}
		if (!canAdd) {
			lInfo() << log().arg("Chat room to add does not match the current filter, return");
			return;
		}
		auto identifier = Utils::coreStringToAppString(room->getIdentifier());
		// Fil du SDK : recherche dans l'index protege (la liste etait lue ici pendant que l'interface pouvait la
		// modifier). Deux ajouts simultanes restent sans doublon : addChatInList verifie a nouveau.
		if (!findChatById(identifier)) {
			auto chatCore = ChatCore::create(room);
			mModelConnection->invokeToCore([this, chatCore, sendAddSignal] { addChatInList(chatCore, sendAddSignal); });
		}
	};
	mModelConnection->makeConnectToModel(
	    &CoreModel::messageReceived,
	    [this, addChatToList](const std::shared_ptr<linphone::Core> &core,
	                          const std::shared_ptr<linphone::ChatRoom> &room,
	                          const std::shared_ptr<linphone::ChatMessage> &message) { addChatToList(core, room); });
	mModelConnection->makeConnectToModel(
	    &CoreModel::messagesReceived,
	    [this, addChatToList](
	        const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::ChatRoom> &room,
	        const std::list<std::shared_ptr<linphone::ChatMessage>> &messages) { addChatToList(core, room); });
	mModelConnection->makeConnectToModel(
	    &CoreModel::messageSent, [this, addChatToList](const std::shared_ptr<linphone::Core> &core,
	                                                   const std::shared_ptr<linphone::ChatRoom> &room,
	                                                   const std::shared_ptr<const linphone::EventLog> &eventLog) {
		    addChatToList(core, room, true);
	    });
	mModelConnection->makeConnectToModel(
	    &CoreModel::newMessageReaction,
	    [this, addChatToList](
	        const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::ChatRoom> &room,
	        const std::shared_ptr<linphone::ChatMessage> &message,
	        const std::shared_ptr<const linphone::ChatMessageReaction> &reaction) { addChatToList(core, room); });
	mModelConnection->makeConnectToModel(&CoreModel::chatRoomStateChanged,
	                                     [this, addChatToList](const std::shared_ptr<linphone::Core> &core,
	                                                           const std::shared_ptr<linphone::ChatRoom> &chatRoom,
	                                                           linphone::ChatRoom::State state) {
		                                     if (state == linphone::ChatRoom::State::Created) {
			                                     bool sendAddSignal = false;
			                                     if (chatRoom == CoreModel::getInstance()->mChatRoomBeingCreated) {
				                                     sendAddSignal = true;
			                                     }
			                                     addChatToList(core, chatRoom, sendAddSignal);
		                                     }
	                                     });

	connect(this, &ChatList::filterChanged, [this](QString filter) {
		mFilter = filter;
		lUpdate();
	});
	lUpdate();
}

int ChatList::findChatIndex(ChatGui *chatGui) {
	if (!chatGui) return -1;
	auto core = chatGui->mCore;
	auto chatList = getSharedList<ChatCore>();
	auto it = std::find_if(chatList.begin(), chatList.end(), [core](const QSharedPointer<ChatCore> item) {
		return item->getIdentifier() == core->getIdentifier();
	});
	return it == chatList.end() ? -1 : std::distance(chatList.begin(), it);
}

QSharedPointer<ChatCore> ChatList::findChatById(const QString &id) {
	// Appele aussi depuis le fil du SDK (notifications, conversation d'un appel) : lecture de l'index protege,
	// jamais de la liste elle-meme, que l'interface peut modifier au meme moment.
	QMutexLocker locker(&mIndexMutex);
	return mIndex.value(id).toStrongRef();
}

void ChatList::rebuildIndex() {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	QHash<QString, QWeakPointer<ChatCore>> index;
	for (const auto &item : mList) {
		if (auto chat = item.objectCast<ChatCore>()) index.insert(chat->getIdentifier(), chat);
	}
	QMutexLocker locker(&mIndexMutex);
	mIndex = std::move(index);
}

bool ChatList::addChatInList(QSharedPointer<ChatCore> chatCore, bool emitAddSignal) {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	if (chatCore->getIdentifier().isEmpty()) {
		lWarning() << "ChatRoom with invalid identifier cannot be added to the list, return";
		return false;
	}
	if (findChatById(chatCore->getIdentifier())) {
		return false;
	}
	connectItem(chatCore);
	lInfo() << "Add ChatRoom" << chatCore->getTitle();
	add(chatCore);
	if (emitAddSignal) {
		CoreModel::getInstance()->mChatRoomBeingCreated = nullptr;
		emit chatAdded(chatCore);
	}
	return true;
}

QVariant ChatList::data(const QModelIndex &index, int role) const {
	int row = index.row();
	if (!index.isValid() || row < 0 || row >= mList.count()) return QVariant();
	if (role == Qt::DisplayRole) return QVariant::fromValue(new ChatGui(mList[row].objectCast<ChatCore>()));
	return QVariant();
}
