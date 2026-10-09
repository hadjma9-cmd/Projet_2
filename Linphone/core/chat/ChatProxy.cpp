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

#include "ChatProxy.hpp"
#include "ChatGui.hpp"
#include "ChatList.hpp"
#include "core/App.hpp"

#include <QTimer>

DEFINE_ABSTRACT_OBJECT(ChatProxy)

ChatProxy::ChatProxy(QObject *parent) {
	// Liste propre, chargee seulement si elle sert : les vues la remplacent presque toujours, des leur creation,
	// par la liste commune (AppCpp.chats). Elle chargeait auparavant deux fois toutes les conversations
	// (a sa creation, puis ici) pour etre jetee aussitot.
	mList = ChatList::create(false);
	mLoadingOwnList = true;
	setSourceModel(mList.get());
	mLoadingOwnList = false;
	QTimer::singleShot(0, this, [this]() {
		if (mList && sourceModel() == mList.get()) mList->lUpdate();
	});
}

ChatProxy::~ChatProxy() {
}

void ChatProxy::setSourceModel(QAbstractItemModel *model) {
	auto oldChatList = dynamic_cast<ChatList *>(sourceModel());
	if (oldChatList) {
		disconnect(this, &ChatProxy::filterTextChanged, oldChatList, nullptr);
		disconnect(oldChatList, &ChatList::chatAdded, this, nullptr);
		disconnect(oldChatList, &ChatList::dataChanged, this, nullptr);
	}
	auto newChatList = dynamic_cast<ChatList *>(model);
	if (newChatList) {
		// Plus de transmission du texte de recherche a la liste : elle reconstruisait toutes ses conversations
		// a chaque touche (et la liste commune pour toutes les vues). Le filtre est fait ici (filterAcceptsRow).
		connect(newChatList, &ChatList::chatAdded, this, [this](QSharedPointer<ChatCore> chatCore) {
			if (chatCore) {
				emit chatAdded(new ChatGui(chatCore));
			}
		});
		// Liste recue (la liste commune) : rechargee, sinon elle peut rester vide (correctif Linphone 2ae5bb9ce).
		// La liste propre, elle, est chargee plus tard, si elle n'a pas ete remplacee entre-temps (constructeur).
		if (!mLoadingOwnList) newChatList->lUpdate();
	}
	QSortFilterProxyModel::setSourceModel(newChatList);
	// Liste propre creee par le constructeur, remplacee (ex. par la liste commune de l'application) : elle
	// restait en memoire avec une copie de toutes les conversations et de leurs ecouteurs SDK.
	if (mList && mList.get() != newChatList) mList = nullptr;
	sort(0);
	emit modelChanged();
}

int ChatProxy::findChatIndex(ChatGui *chatGui) {
	auto chatList = dynamic_cast<ChatList *>(sourceModel());
	if (chatList) {
		auto listIndex = chatList->findChatIndex(chatGui);
		if (listIndex != -1) {
			listIndex = mapFromSource(chatList->index(listIndex, 0)).row();
			return listIndex;
		}
	}
	return -1;
}

bool ChatProxy::addChatInList(ChatGui *chatGui) {
	auto chatList = dynamic_cast<ChatList *>(sourceModel());
	if (chatList && chatGui) {
		return chatList->addChatInList(chatGui->mCore, true);
	}
	return false;
}

bool ChatProxy::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const {
	if (mFilterText.isEmpty()) return true;
	auto chat = getItemAtSource<ChatList, ChatCore>(sourceRow);
	if (!chat) return false;
	// Memes criteres que le filtre du SDK (Account::filterChatRooms) : nom du contact ou sujet, adresse,
	// participants (adresse et nom).
	auto matches = [this](const QString &text) { return text.contains(mFilterText, Qt::CaseInsensitive); };
	if (matches(chat->getTitle()) || matches(chat->getChatRoomAddress()) || matches(chat->getParticipantAddress()))
		return true;
	for (const auto &participant : chat->getParticipants()) {
		if (participant && (matches(participant->getSipAddress()) || matches(participant->getDisplayName())))
			return true;
	}
	return false;
}

bool ChatProxy::lessThan(const QModelIndex &sourceLeft, const QModelIndex &sourceRight) const {
	if (!mFilterText.isEmpty()) return false;
	auto l = getItemAtSource<ChatList, ChatCore>(sourceLeft.row());
	auto r = getItemAtSource<ChatList, ChatCore>(sourceRight.row());
	if (l && r) return l->getLastUpdatedTime() > r->getLastUpdatedTime();
	return false;
}
