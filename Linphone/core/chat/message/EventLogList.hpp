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

#ifndef EVENT_LOG_LIST_H_
#define EVENT_LOG_LIST_H_

#include "core/proxy/ListProxy.hpp"
#include "tool/AbstractObject.hpp"
#include "tool/thread/SafeConnection.hpp"
#include <QLocale>
#include <memory>

namespace linphone {
class ChatRoom;
}

class EventLogGui;
class EventLogCore;
class ChatCore;
class ChatGui;
class ChatModel;
// =============================================================================

class EventLogList : public ListProxy, public AbstractObject {
	Q_OBJECT
public:
	static QSharedPointer<EventLogList> create();
	EventLogList(QObject *parent = Q_NULLPTR);
	~EventLogList();

	QSharedPointer<ChatCore> getChatCore() const;
	ChatGui *getChat() const;
	void setChatCore(QSharedPointer<ChatCore> core);
	void setChatGui(ChatGui *chat);

	void connectItem(const QSharedPointer<EventLogCore> &item);
	void disconnectItem(const QSharedPointer<EventLogCore> &item);

	void loadMessagesUpTo(std::shared_ptr<linphone::EventLog> event);
	void preloadRecentChats(int count);

	void setLastFoundResult(const QSharedPointer<EventLogCore> &eventLog);

	int findFirstUnreadIndex();

	void markIndexAsRead(int index);

	void displayMore();
	void setDisplayItemsStep(int displayItemsStep);

	void findChatMessageWithFilter(QString filter, int startIndex, bool forward = true, bool isFirstResearch = true);
	void findChatMessageById(const QString &messageId);

	void setSelf(QSharedPointer<EventLogList> me);
	virtual QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
	QHash<int, QByteArray> roleNames() const override;

signals:
	void lUpdate();
	void modelUpdated();
	void filterChanged(QString filter);
	void eventInsertedByUser(int index);
	void messageWithFilterFound(int index);
	void foundMessagById(int index);
	void listAboutToBeReset();
	void chatGuiChanged();
	void displayItemsStepChanged();
	void messagesLoadedUpTo(std::shared_ptr<linphone::EventLog> event);

private:
	// Conversations deja ouvertes : leurs evenements deja construits, pour y revenir sans
	// rechargement. Indexees par l'identifiant de la conversation, stable meme si son ChatCore
	// est recree.
	struct CachedEvents {
		QString chatId;
		QList<QSharedPointer<EventLogCore>> events;
		// Conversation du SDK a laquelle appartiennent ces evenements. Une conversation supprimee
		// puis recreee garde le meme identifiant, mais n'est plus le meme objet : ses anciens
		// messages ne doivent pas lui etre rendus (plantage du 17/09 en les marquant lus).
		std::weak_ptr<linphone::ChatRoom> room;
	};
	static constexpr int MaxCachedChats = 10;
	void storeInCache(const QString &chatId,
	                  const QList<QSharedPointer<EventLogCore>> &events,
	                  const std::weak_ptr<linphone::ChatRoom> &room);
	QList<QSharedPointer<EventLogCore>> takeFromCache(const QString &chatId,
	                                                  const std::weak_ptr<linphone::ChatRoom> &room);
	void dropFromCache(const QString &chatId);
	bool mergeFreshEvents(const QList<QSharedPointer<EventLogCore>> &fresh);
	void replaceEvents(const QList<QSharedPointer<EventLogCore>> &events);
	int indexOfEventLog(const std::shared_ptr<linphone::EventLog> &event);
	void emitFilterResult(int index);
	QList<CachedEvents> mCache;
	QString mListChatId;               // conversation dont les evenements sont dans mList
	bool mSilentUpdatePending = false; // prochaine lecture : liste deja affichee depuis le cache

	QString mFilter;
	QSharedPointer<ChatCore> mChatCore;
	QSharedPointer<SafeConnection<EventLogList, CoreModel>> mCoreModelConnection;
	int mDisplayItemsStep = 0;
	int mItemsToLoadBeforeSearchResult = 3;
	QSharedPointer<EventLogCore> mLastFoundResult;
	DECLARE_ABSTRACT_OBJECT
};

#endif
