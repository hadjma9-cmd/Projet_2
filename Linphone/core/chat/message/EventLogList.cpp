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

#include "EventLogList.hpp"
#include "ChatMessageCore.hpp"
#include "ChatMessageGui.hpp"
#include "EventLogGui.hpp"
#include "core/App.hpp"
#include "core/call-history/CallHistoryGui.hpp"
#include "core/chat/ChatCore.hpp"
#include "core/chat/ChatGui.hpp"
#include "model/chat/message/EventLogModel.hpp"
#include "model/core/CoreModel.hpp"
#include "tool/Utils.hpp"
#include <QSharedPointer>
#include <algorithm>
#include <linphone++/linphone.hh>

// =============================================================================

DEFINE_ABSTRACT_OBJECT(EventLogList)

QSharedPointer<EventLogList> EventLogList::create() {
	auto model = QSharedPointer<EventLogList>(new EventLogList(), &QObject::deleteLater);
	model->moveToThread(App::getInstance()->thread());
	model->setSelf(model);
	return model;
}

EventLogList::EventLogList(QObject *parent) : ListProxy(parent) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
	// Conversation ou historique supprime : ses evenements en cache sont perimes.
	connect(App::getInstance(), &App::chatEventsInvalidated, this,
	        [this](const QString &chatId) { dropFromCache(chatId); });
}

EventLogList::~EventLogList() {
	mustBeInMainThread("~" + getClassName());
}

ChatGui *EventLogList::getChat() const {
	if (mChatCore) return new ChatGui(mChatCore);
	else return nullptr;
}

QSharedPointer<ChatCore> EventLogList::getChatCore() const {
	return mChatCore;
}

void EventLogList::disconnectItem(const QSharedPointer<EventLogCore> &item) {
	auto message = item->getChatMessageCore();
	if (message) {
		disconnect(message.get(), &ChatMessageCore::isReadChanged, this, nullptr);
		disconnect(message.get(), &ChatMessageCore::deleted, this, nullptr);
		disconnect(message.get(), &ChatMessageCore::edited, this, nullptr);
		disconnect(message.get(), &ChatMessageCore::isRetractedChanged, this, nullptr);
	}
}

void EventLogList::connectItem(const QSharedPointer<EventLogCore> &item) {
	auto message = item->getChatMessageCore();
	if (message) {
		connect(message.get(), &ChatMessageCore::isReadChanged, this, [this] {
			if (mChatCore) emit mChatCore->lUpdateUnreadCount();
		});
		connect(message.get(), &ChatMessageCore::deleted, this, [this, item] {
			if (mChatCore) emit mChatCore->lUpdateLastMessage();
			remove(item);
		});
		connect(message.get(), &ChatMessageCore::isRetractedChanged, this, [this, item] {
			if (mChatCore) emit mChatCore->lUpdateUnreadCount();
		});
		connect(message.get(), &ChatMessageCore::edited, this, [this, item] {
			// Conversation lue ici, dans le fil de l'interface a qui elle appartient. Lue auparavant dans le fil du
			// SDK, elle pouvait avoir change (ou etre nulle) si l'on changeait de conversation entre-temps.
			auto chatCore = mChatCore;
			auto chatModel = chatCore ? chatCore->getModel() : nullptr;
			auto eventLogModel = item->getModel();
			if (!chatModel || !eventLogModel) return;
			mCoreModelConnection->invokeToModel([this, chatCore, chatModel, eventLogModel, item]() {
				auto newEventLog = EventLogCore::create(eventLogModel->getEventLog(), chatModel->getMonitor());
				bool wasLastMessage = chatModel->getLastChatMessage() == eventLogModel->getEventLog()->getChatMessage();
				mCoreModelConnection->invokeToCore([this, chatCore, newEventLog, wasLastMessage, item] {
					// Le message modifie appartient a chatCore, meme si une autre conversation est affichee.
					if (wasLastMessage) chatCore->setLastMessage(newEventLog->getChatMessageCore());
					if (mChatCore != chatCore) return;
					connectItem(newEventLog);
					replace(item, newEventLog);
				});
			});
		});
	}
}

void EventLogList::setChatCore(QSharedPointer<ChatCore> core) {
	if (mChatCore != core) {
		if (mChatCore) {
			disconnect(mChatCore.get(), &ChatCore::eventsInserted, this, nullptr);
			disconnect(mChatCore.get(), &ChatCore::eventListCleared, this, nullptr);
			// Garde les evenements de la conversation quittee pour y revenir sans rechargement,
			// seulement s'ils sont bien les siens (une lecture pour elle peut etre encore en cours).
			if (!mListChatId.isEmpty() && mListChatId == mChatCore->getIdentifier()) {
				auto leftModel = mChatCore->getModel();
				storeInCache(mListChatId, getSharedList<EventLogCore>(),
				             leftModel ? std::weak_ptr<linphone::ChatRoom>(leftModel->getMonitor())
				                       : std::weak_ptr<linphone::ChatRoom>());
			}
		}
		mChatCore = core;
		if (mChatCore) {
			connect(mChatCore.get(), &ChatCore::eventListCleared, this, [this] { resetData(); });
			connect(mChatCore.get(), &ChatCore::eventsInserted, this, [this](QList<QSharedPointer<EventLogCore>> list) {
				auto eventsList = getSharedList<EventLogCore>();
				for (const auto &event : list) {
					lInfo() << log().arg("Try to insert") << event.get();
					auto it = std::find_if(eventsList.begin(), eventsList.end(),
					                       [event](const QSharedPointer<EventLogCore> item) { return item == event; });
					if (it == eventsList.end()) {
						lInfo() << log().arg("Not found in current list, insert");
						connectItem(event);
						prepend(event);
						int index;
						get(event.get(), &index);
						if (event->getChatMessageCore() && !event->getChatMessageCore()->isRemoteMessage()) {
							emit eventInsertedByUser(index);
						}
					} else {
						lInfo() << log().arg("Event already in list, return");
					}
				}
			});
		}
		// Conversation deja visitee : ses evenements s'affichent dans ce meme appel, donc sans
		// image intermediaire ni indicateur de chargement visible. La lecture lancee ensuite est
		// discrete : elle n'ajoute que ce qui est arrive entre-temps (mergeFreshEvents).
		auto currentModel = mChatCore ? mChatCore->getModel() : nullptr;
		const auto cached = currentModel ? takeFromCache(mChatCore->getIdentifier(),
		                                                 std::weak_ptr<linphone::ChatRoom>(currentModel->getMonitor()))
		                                 : QList<QSharedPointer<EventLogCore>>();
		mSilentUpdatePending = !cached.isEmpty();
		if (mSilentUpdatePending) {
			for (auto &event : getSharedList<EventLogCore>()) {
				disconnectItem(event);
			}
			replaceEvents(cached);
			mListChatId = mChatCore->getIdentifier();
			emit modelUpdated();
		}
		lUpdate();
		// setIsUpdating(false);
		emit chatGuiChanged();
	}
}

// Remplacement par suppression puis insertion, et non par reinitialisation du modele : la vue recycle alors les
// bulles de la liste quittee pour la nouvelle (ChatMessagesListView, reuseItems), au lieu de toutes les detruire
// puis d'en construire autant. Les evenements quittes doivent deja etre deconnectes.
void EventLogList::replaceEvents(const QList<QSharedPointer<EventLogCore>> &events) {
	if (!mList.isEmpty()) {
		beginRemoveRows(QModelIndex(), 0, int(mList.size()) - 1);
		mList.clear();
		endRemoveRows();
	}
	if (!events.isEmpty()) {
		beginInsertRows(QModelIndex(), 0, int(events.size()) - 1);
		for (auto &event : events) {
			connectItem(event);
			mList.append(event);
		}
		endInsertRows();
	}
}

void EventLogList::setChatGui(ChatGui *chat) {
	auto chatCore = chat ? chat->mCore : nullptr;
	setChatCore(chatCore);
}

void EventLogList::setDisplayItemsStep(int displayItemsStep) {
	if (mDisplayItemsStep != displayItemsStep) {
		mDisplayItemsStep = displayItemsStep;
		emit displayItemsStepChanged();
	}
}

void EventLogList::markIndexAsRead(int index) {
	if (index < mList.count()) {
		auto eventLog = mList[index].objectCast<EventLogCore>();
		if (eventLog && eventLog->getChatMessageCore()) eventLog->getChatMessageCore()->lMarkAsRead();
	}
}

void EventLogList::displayMore() {
	auto loadMoreItems = [this] {
		if (!mChatCore) return;
		auto chatModel = mChatCore->getModel();
		if (!chatModel) return;
		const QString requestedChatId = mChatCore->getIdentifier();
		// Lus ici, dans le fil de l'interface a qui appartient la liste, et non dans celui de liblinphone.
		const int totalItemsCount = static_cast<int>(mList.count());
		const int step = mDisplayItemsStep;
		mCoreModelConnection->invokeToModel([this, chatModel, requestedChatId, totalItemsCount, step]() {
			mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
			int maxSize = chatModel->getHistorySizeEvents();
			auto newCount = std::min(totalItemsCount + step, maxSize);
			if (newCount <= totalItemsCount) {
				return;
			}
			auto linphoneLogs = chatModel->getHistoryRange(totalItemsCount, newCount);
			QList<QSharedPointer<EventLogCore>> *events = new QList<QSharedPointer<EventLogCore>>();
			for (auto it : linphoneLogs) {
				auto model = EventLogCore::create(it, chatModel->getMonitor());
				if (it->getChatMessage() || model->isHandled()) events->push_front(model);
			}
			mCoreModelConnection->invokeToCore([this, events, requestedChatId] {
				// Conversation changee entre-temps : ces messages plus anciens ne la concernent pas, et
				// le cache les memoriserait avec elle.
				if (!mChatCore || mChatCore->getIdentifier() != requestedChatId) {
					delete events;
					return;
				}
				int currentCount = mList.count();
				if (!events->isEmpty()) {
					for (int i = events->size() - 1; i >= 0; --i) {
						const auto &ev = events->at(i);
						connectItem(ev);
					}
					add(*events);
				}
				delete events;
			});
		});
	};
	if (mIsUpdating) {
		connect(this, &EventLogList::isUpdatingChanged, this, [this, loadMoreItems] {
			if (!mIsUpdating) {
				disconnect(this, &EventLogList::isUpdatingChanged, this, nullptr);
				loadMoreItems();
			}
		});
		return;
	} else loadMoreItems();
}

// Charge les evenements jusqu'a `event` (resultat de recherche absent de la liste), puis emet
// messagesLoadedUpTo(event), ou messagesLoadedUpTo(nullptr) en cas d'echec. S'execute dans le fil
// de l'interface, proprietaire de la liste : seules les requetes a l'historique partent dans celui
// de liblinphone. Auparavant tout se faisait dans ce dernier, liste comprise.
void EventLogList::loadMessagesUpTo(std::shared_ptr<linphone::EventLog> event) {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	auto chatModel = mChatCore ? mChatCore->getModel() : nullptr;
	if (!chatModel || !event) {
		emit messagesLoadedUpTo(nullptr);
		return;
	}
	auto oldestEventLoaded = mList.count() > 0 ? getAt<EventLogCore>(mList.count() - 1) : nullptr;
	auto oldestEventModel = oldestEventLoaded ? oldestEventLoaded->getModel() : nullptr;
	const QString requestedChatId = mChatCore->getIdentifier();
	const int itemsBefore = mItemsToLoadBeforeSearchResult;
	mCoreModelConnection->invokeToModel([this, chatModel, event, oldestEventModel, requestedChatId, itemsBefore] {
		mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
		auto linOldest =
		    oldestEventModel ? std::const_pointer_cast<linphone::EventLog>(oldestEventModel->getEventLog()) : nullptr;
		int filters = static_cast<int>(linphone::ChatRoom::HistoryFilter::ChatMessage) |
		              static_cast<int>(linphone::ChatRoom::HistoryFilter::InfoNoDevice);
		auto beforeEvents = chatModel->getHistoryRangeNear(itemsBefore, 0, event, filters);
		auto linphoneLogs = chatModel->getHistoryRangeBetween(event, linOldest, filters);
		QList<QSharedPointer<EventLogCore>> *events = new QList<QSharedPointer<EventLogCore>>();
		const auto &linChatRoom = chatModel->getMonitor();
		for (const auto &it : beforeEvents) {
			auto model = EventLogCore::create(it, linChatRoom);
			if (it->getChatMessage() || model->isHandled()) events->push_front(model);
		}
		for (const auto &it : linphoneLogs) {
			auto model = EventLogCore::create(it, linChatRoom);
			if (it->getChatMessage() || model->isHandled()) events->push_front(model);
		}
		mCoreModelConnection->invokeToCore([this, events, event, requestedChatId] {
			// Conversation changee entre-temps ; l'echec est signale pour que la recherche ne reste pas
			// en attente.
			if (!mChatCore || mChatCore->getIdentifier() != requestedChatId) {
				delete events;
				emit messagesLoadedUpTo(nullptr);
				return;
			}
			for (const auto &e : *events) {
				connectItem(e);
			}
			add(*events);
			delete events;
			emit messagesLoadedUpTo(event);
		});
	});
}

int EventLogList::findFirstUnreadIndex() {
	auto eventList = getSharedList<EventLogCore>();
	auto it = std::find_if(eventList.rbegin(), eventList.rend(), [](const QSharedPointer<EventLogCore> item) {
		auto chatmessage = item->getChatMessageCore();
		return chatmessage && !chatmessage->isRead();
	});
	return it == eventList.rend() ? -1 : std::distance(it, eventList.rend()) - 1;
}

void EventLogList::findChatMessageWithFilter(QString filter, int startIndex, bool forward, bool isFirstResearch) {
	if (!mChatCore) return;
	auto chatModel = mChatCore->getModel();
	if (!chatModel) return;
	if (isFirstResearch) mLastFoundResult.reset();
	auto startEvent =
	    startIndex >= 0 && startIndex < mList.count() ? mList[startIndex].objectCast<EventLogCore>() : nullptr;
	lInfo() << log().arg("searching event starting from index") << startIndex << "| event :"
	        << (startEvent && startEvent->getChatMessageCore() ? startEvent->getChatMessageCore()->getText() : "null")
	        << "| filter :" << filter << "forward =" << forward;
	auto startEventModel = startEvent ? startEvent->getModel() : nullptr;
	// Le fil de liblinphone ne fait que chercher dans l'historique. Tout ce qui touche a la liste
	// (index, dernier resultat, chargement, connexion) se fait ensuite dans le fil de l'interface.
	mCoreModelConnection->invokeToModel([this, chatModel, startEventModel, filter, forward, isFirstResearch] {
		mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
		auto linStartEvent = startEventModel ? startEventModel->getEventLog() : nullptr;
		auto eventLog = chatModel->searchMessageByText(filter, linStartEvent, forward);
		if (!eventLog && isFirstResearch) {
			// event not found, search backward
			lInfo() << log().arg("not found, search backward");
			eventLog = chatModel->searchMessageByText(filter, linStartEvent, !forward);
		}
		if (!eventLog && isFirstResearch) {
			// event not found, search in the entire history
			lInfo() << log().arg("not found, search in entire history");
			eventLog = chatModel->searchMessageByText(filter, nullptr, forward);
		}
		mCoreModelConnection->invokeToCore([this, eventLog] {
			if (!eventLog) {
				lInfo() << log().arg("event not found at all in history");
				emit messageWithFilterFound(-1);
				return;
			}
			lInfo() << log().arg("event with filter found") << eventLog.get();
			const int index = indexOfEventLog(eventLog);
			if (index >= 0) {
				emitFilterResult(index);
				return;
			}
			connect(
			    this, &EventLogList::messagesLoadedUpTo, this,
			    [this](std::shared_ptr<linphone::EventLog> event) { emitFilterResult(indexOfEventLog(event)); },
			    Qt::SingleShotConnection);
			loadMessagesUpTo(eventLog);
		});
	});
}

void EventLogList::findChatMessageById(const QString &messageId) {
	lInfo() << log().arg("Try to find message by id :");
	const auto eventList = getSharedList<EventLogCore>();
	for (int i = 0; i < eventList.size(); ++i) {
		auto messageCore = eventList[i] ? eventList[i]->getChatMessageCore() : nullptr;
		if (messageCore && messageCore->getMessageId() == messageId) {
			emit foundMessagById(i);
			return;
		}
	}
	lInfo() << log().arg("Not found in displayed messages, search in entire history");
	auto chatModel = mChatCore ? mChatCore->getModel() : nullptr;
	if (!chatModel) {
		emit foundMessagById(-1);
		return;
	}
	mCoreModelConnection->invokeToModel([this, chatModel, messageId] {
		mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
		std::shared_ptr<linphone::EventLog> found;
		for (const auto &eventLog : chatModel->getHistory()) {
			auto chatMessage = eventLog->getChatMessage();
			if (chatMessage && Utils::coreStringToAppString(chatMessage->getMessageId()) == messageId) {
				found = eventLog;
				break;
			}
		}
		// Suite dans le fil de l'interface : le signal y est attendu et la liste lui appartient.
		// Auparavant le signal d'echec partait du fil de liblinphone.
		mCoreModelConnection->invokeToCore([this, found] {
			if (!found) {
				lInfo() << log().arg("Not found in entire history, event must have been deleted");
				emit foundMessagById(-1);
				return;
			}
			lInfo() << log().arg("Found in entire history, load messages up to it");
			connect(
			    this, &EventLogList::messagesLoadedUpTo, this,
			    [this](std::shared_ptr<linphone::EventLog> event) {
				    if (event == nullptr) return;
				    const int index = indexOfEventLog(event);
				    lInfo() << log().arg("Index corresponding to chat message id :") << index;
				    emit foundMessagById(index);
			    },
			    Qt::SingleShotConnection);
			loadMessagesUpTo(found);
		});
	});
}

void EventLogList::storeInCache(const QString &chatId,
                                const QList<QSharedPointer<EventLogCore>> &events,
                                const std::weak_ptr<linphone::ChatRoom> &room) {
	if (chatId.isEmpty() || events.isEmpty() || room.expired()) return;
	dropFromCache(chatId); // Retire une version plus ancienne.
	for (auto &event : events) {
		disconnectItem(event); // Hors de la liste, ils ne doivent plus la modifier.
	}
	mCache.prepend({chatId, events, room});
	while (mCache.size() > MaxCachedChats) {
		mCache.removeLast();
	}
}

// Rend les evenements en cache d'une conversation, seulement s'ils appartiennent bien a la meme
// conversation du SDK (comparaison des objets, sans en prendre de reference forte).
QList<QSharedPointer<EventLogCore>> EventLogList::takeFromCache(const QString &chatId,
                                                                const std::weak_ptr<linphone::ChatRoom> &room) {
	for (int i = 0; i < mCache.size(); ++i) {
		if (mCache[i].chatId != chatId) continue;
		auto entry = mCache.takeAt(i);
		const bool sameRoom = !entry.room.expired() && !room.expired() && !entry.room.owner_before(room) &&
		                      !room.owner_before(entry.room);
		if (sameRoom) return entry.events;
		lInfo() << log().arg("cached events dropped: chat room recreated") << chatId;
		return {};
	}
	return {};
}

void EventLogList::dropFromCache(const QString &chatId) {
	for (int i = 0; i < mCache.size(); ++i) {
		if (mCache[i].chatId == chatId) {
			mCache.removeAt(i);
			return;
		}
	}
}

// Compare une lecture fraiche (les plus recents d'abord, comme mList) a la liste affichee.
// Renvoie vrai si la liste est deja a jour, ou l'a ete en ajoutant en tete les seuls evenements
// nouveaux : les messages plus anciens deja charges et la position de lecture sont conserves.
// Renvoie faux s'il faut tout recharger (suppression, modification d'historique...).
bool EventLogList::mergeFreshEvents(const QList<QSharedPointer<EventLogCore>> &fresh) {
	const auto current = getSharedList<EventLogCore>();
	if (current.isEmpty() || !current.first()) return fresh.isEmpty();
	const QString head = current.first()->getEventLogId();
	int newCount = -1;
	for (int k = 0; k < fresh.size(); ++k) {
		if (fresh[k] && fresh[k]->getEventLogId() == head) {
			newCount = k;
			break;
		}
	}
	if (newCount < 0) return false;
	for (int k = newCount; k < fresh.size() && k - newCount < current.size(); ++k) {
		const auto &known = current[k - newCount];
		if (!fresh[k] || !known || known->getEventLogId() != fresh[k]->getEventLogId()) return false;
	}
	for (int k = newCount - 1; k >= 0; --k) {
		connectItem(fresh[k]);
		prepend(fresh[k]);
	}
	return true;
}

int EventLogList::indexOfEventLog(const std::shared_ptr<linphone::EventLog> &event) {
	if (!event) return -1;
	const auto eventList = getSharedList<EventLogCore>();
	for (int i = 0; i < eventList.size(); ++i) {
		auto model = eventList[i] ? eventList[i]->getModel() : nullptr;
		if (model && model->getEventLog() == event) return i;
	}
	return -1;
}

// Emet le resultat d'une recherche : -1 si introuvable, ou si c'est le meme resultat que le
// precedent (la recherche est arrivee au bout). Auparavant, un resultat introuvable apres
// chargement dereferencait un iterateur hors de la liste.
void EventLogList::emitFilterResult(int index) {
	auto found = index >= 0 && index < mList.count() ? getAt<EventLogCore>(index) : nullptr;
	if (!found) {
		emit messageWithFilterFound(-1);
		return;
	}
	if (mLastFoundResult == found) index = -1;
	mLastFoundResult = found;
	emit messageWithFilterFound(index);
}

// Precharge en arriere-plan les conversations les plus recentes du compte par defaut, pour qu'elles
// s'ouvrent sans chargement des la premiere fois. Ne touche ni a la conversation affichee ni a celles
// deja en cache, et n'occupe que les places libres : les conversations reellement visitees restent
// prioritaires (elles sont placees en tete du cache, les prechargees en queue).
void EventLogList::preloadRecentChats(int count) {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	const int freeSlots = MaxCachedChats - static_cast<int>(mCache.size());
	count = std::min(count, freeSlots);
	const int step = mDisplayItemsStep;
	if (count <= 0 || step <= 0) return;
	QStringList known;
	for (const auto &entry : mCache) {
		known << entry.chatId;
	}
	if (!mListChatId.isEmpty()) known << mListChatId;
	if (mChatCore) known << mChatCore->getIdentifier();
	mCoreModelConnection->invokeToModel([this, count, step, known]() {
		mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
		auto account = CoreModel::getInstance()->getCore()->getDefaultAccount();
		if (!account) return;
		std::vector<std::shared_ptr<linphone::ChatRoom>> rooms;
		for (const auto &room : account->filterChatRooms("")) {
			// Memes exclusions que la liste des conversations (ChatList).
			auto state = room->getState();
			if (state == linphone::ChatRoom::State::CreationFailed ||
			    state == linphone::ChatRoom::State::CreationPending ||
			    state == linphone::ChatRoom::State::TerminationPending ||
			    state == linphone::ChatRoom::State::Instantiated)
				continue;
			rooms.push_back(room);
		}
		std::sort(rooms.begin(), rooms.end(),
		          [](const std::shared_ptr<linphone::ChatRoom> &a, const std::shared_ptr<linphone::ChatRoom> &b) {
			          return a->getLastUpdateTime() > b->getLastUpdateTime();
		          });
		auto *preloaded = new QList<CachedEvents>();
		for (const auto &room : rooms) {
			if (preloaded->size() >= count) break;
			const QString chatId = Utils::coreStringToAppString(room->getIdentifier());
			if (chatId.isEmpty() || known.contains(chatId)) continue;
			QList<QSharedPointer<EventLogCore>> events;
			for (const auto &it : room->getHistoryRangeEvents(0, step)) {
				auto model = EventLogCore::create(it, room);
				if (it->getChatMessage() || model->isHandled()) events.push_front(model);
			}
			if (!events.isEmpty()) preloaded->append({chatId, events, std::weak_ptr<linphone::ChatRoom>(room)});
		}
		mCoreModelConnection->invokeToCore([this, preloaded] {
			for (const auto &entry : *preloaded) {
				// Ouverte ou memorisee entre-temps : la version existante est plus a jour.
				bool known = entry.chatId == mListChatId || (mChatCore && mChatCore->getIdentifier() == entry.chatId);
				for (const auto &cached : mCache) {
					known = known || cached.chatId == entry.chatId;
				}
				if (!known && mCache.size() < MaxCachedChats) mCache.append(entry);
			}
			delete preloaded;
		});
	});
}

void EventLogList::setSelf(QSharedPointer<EventLogList> me) {
	mCoreModelConnection = SafeConnection<EventLogList, CoreModel>::create(me, CoreModel::getInstance());

	mCoreModelConnection->makeConnectToCore(&EventLogList::lUpdate, [this]() {
		mustBeInMainThread(log().arg(Q_FUNC_INFO));
		if (mIsUpdating) {
			connect(this, &EventLogList::isUpdatingChanged, this, [this] {
				if (!mIsUpdating) {
					disconnect(this, &EventLogList::isUpdatingChanged, this, nullptr);
					lUpdate();
				}
			});
			return;
		}
		setIsUpdating(true);
		// Lecture discrete : la liste tiree du cache reste affichee et connectee pendant la lecture.
		const bool silent = mSilentUpdatePending;
		mSilentUpdatePending = false;
		if (!silent) {
			for (auto &event : getSharedList<EventLogCore>()) {
				disconnectItem(event);
			}
		}
		if (!mChatCore) {
			beginResetModel();
			mList.clear();
			endResetModel();
			mListChatId.clear();
			setIsUpdating(false);
			emit modelUpdated();
			return;
		}
		auto chatModel = mChatCore->getModel();
		if (!chatModel) {
			beginResetModel();
			mList.clear();
			endResetModel();
			mListChatId.clear();
			setIsUpdating(false);
			emit modelUpdated();
			return;
		}
		const QString requestedChatId = mChatCore->getIdentifier();
		const int step = mDisplayItemsStep;
		mCoreModelConnection->invokeToModel([this, chatModel, requestedChatId, silent, step]() {
			mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
			auto linphoneLogs = chatModel->getHistoryRange(0, step);
			QList<QSharedPointer<EventLogCore>> *events = new QList<QSharedPointer<EventLogCore>>();
			for (auto it : linphoneLogs) {
				auto model = EventLogCore::create(it, chatModel->getMonitor());
				if (it->getChatMessage() || model->isHandled()) events->push_front(model);
			}
			mCoreModelConnection->invokeToCore([this, events, requestedChatId, silent,
			                                    room = std::weak_ptr<linphone::ChatRoom>(chatModel->getMonitor())] {
				const QList<QSharedPointer<EventLogCore>> fresh = *events;
				delete events;
				// Conversation changee pendant la lecture : ce resultat n'est plus a afficher, mais il
				// servira si l'utilisateur y revient. Auparavant il remplacait la liste affichee.
				if (!mChatCore || mChatCore->getIdentifier() != requestedChatId) {
					storeInCache(requestedChatId, fresh, room);
					setIsUpdating(false);
					return;
				}
				if (silent && mergeFreshEvents(fresh)) {
					setIsUpdating(false);
					return;
				}
				for (auto &event : getSharedList<EventLogCore>()) {
					disconnectItem(event);
				}
				replaceEvents(fresh);
				mListChatId = requestedChatId;
				setIsUpdating(false);
				emit modelUpdated();
			});
		});
	});

	connect(this, &EventLogList::filterChanged, [this](QString filter) {
		mFilter = filter;
		lUpdate();
	});
	lUpdate();
}

QVariant EventLogList::data(const QModelIndex &index, int role) const {
	int row = index.row();
	if (!index.isValid() || row < 0 || row >= mList.count()) return QVariant();

	auto core = mList[row].objectCast<EventLogCore>();
	if (core->getChatMessageCore()) {
		switch (role) {
			case Qt::DisplayRole:
				return QVariant::fromValue(new EventLogGui(core));
			case Qt::DisplayRole + 1:
				return "chatMessage";
		}
	} else if (core->getCallHistoryCore()) {
		switch (role) {
			case Qt::DisplayRole:
				return QVariant::fromValue(new EventLogGui(core));
			case Qt::DisplayRole + 1:
				return "callLog";
		}
	} else if (core->isEphemeralRelated()) {
		switch (role) {
			case Qt::DisplayRole:
				return QVariant::fromValue(new EventLogGui(core));
			case Qt::DisplayRole + 1:
				return "ephemeralEvent";
		}
	} else {
		switch (role) {
			case Qt::DisplayRole:
				return QVariant::fromValue(new EventLogGui(core));
			case Qt::DisplayRole + 1:
				return "event";
		}
	}
	return QVariant();
}

QHash<int, QByteArray> EventLogList::roleNames() const {
	QHash<int, QByteArray> roles;
	roles[Qt::DisplayRole] = "modelData";
	roles[Qt::DisplayRole + 1] = "eventType";
	return roles;
}
