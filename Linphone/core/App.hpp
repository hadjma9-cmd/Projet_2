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

#include <QAction>
#include <QCommandLineParser>
#include <QQmlApplicationEngine>
#include <QSharedPointer>

#include "core/account/AccountProxy.hpp"
#include "core/call-history/CallHistoryList.hpp"
#include "core/call/CallProxy.hpp"
#include "core/chat/ChatGui.hpp"
#include "core/chat/ChatList.hpp"
#include "core/conference/ConferenceInfoList.hpp"
#include "core/event-filter/LockEventFilter.hpp"
#include "core/fusion/SharedContactsCore.hpp"
#include "core/fusion/StatusCore.hpp"
#include "core/fusion/UpdateCore.hpp"
#include "core/queue/QueueCore.hpp"
#include "core/setting/SettingsCore.hpp"
#include "core/singleapplication/singleapplication.h"
#include "model/cli/CliModel.hpp"
#include "model/core/CoreModel.hpp"
#include "tool/AbstractObject.hpp"

class CallGui;
class ChatGui;
class Thread;
class Notifier;
class QQmlComponent;
class QQmlIncubator;
class QQuickWindow;
class QSystemTrayIcon;
class DefaultTranslatorCore;
#if defined(Q_OS_WIN) || defined(Q_OS_LINUX)
class NotificationBackend;
#endif
class App : public SingleApplication, public AbstractObject {
	Q_OBJECT
	Q_PROPERTY(bool coreStarted READ getCoreStarted WRITE setCoreStarted NOTIFY coreStartedChanged)
	Q_PROPERTY(int coreGlobalState READ getCoreGlobalState WRITE setCoreGlobalState NOTIFY coreGlobalStateChanged)
	Q_PROPERTY(AccountList *accounts READ getAccounts NOTIFY accountsChanged)
	Q_PROPERTY(AccountGui *currentAccount READ getCurrentAccount NOTIFY currentAccountChanged)
	Q_PROPERTY(CallList *calls READ getCalls NOTIFY callsChanged)
	Q_PROPERTY(ChatList *chats READ getChats NOTIFY chatsChanged)
	Q_PROPERTY(QString shortApplicationVersion READ getShortApplicationVersion CONSTANT)
	Q_PROPERTY(QString qtVersion READ getQtVersion CONSTANT)
	Q_PROPERTY(QString gitBranchName READ getGitBranchName CONSTANT)
	Q_PROPERTY(QString sdkVersion READ getSdkVersion CONSTANT)
	Q_PROPERTY(ChatGui *currentChat READ getCurrentChat WRITE setCurrentChat NOTIFY currentChatChanged)
	Q_PROPERTY(QString localeAsString READ getLocaleAsString CONSTANT)
	Q_PROPERTY(int remainingTimeBeforeOidcTimeout MEMBER mRemainingTimeBeforeOidcTimeout NOTIFY
	               remainingTimeBeforeOidcTimeoutChanged)
	// Change toutes les 15 minutes : les photos distantes des contacts sont alors relues malgre le cache d'images.
	Q_PROPERTY(int avatarRevision MEMBER mAvatarRevision NOTIFY avatarRevisionChanged)
	// Petite fenetre (format telephone, appels audio seulement) au lieu de la grande ; choix retenu d'un lancement a
	// l'autre, comme l'epingle « toujours au premier plan ».
	Q_PROPERTY(bool compactMode READ getCompactMode WRITE setCompactMode NOTIFY compactModeChanged)
	Q_PROPERTY(bool compactPinned READ getCompactPinned WRITE setCompactPinned NOTIFY compactPinnedChanged)
	// Menus reserves a l'administrateur (annuaires, parametres techniques du compte) : caches aux utilisateurs,
	// affiches par Ctrl+Maj+M. Jamais enregistre : tout est de nouveau cache au lancement suivant.
	Q_PROPERTY(bool adminMenus READ getAdminMenus WRITE setAdminMenus NOTIFY adminMenusChanged)

public:
	App(int &argc, char *argv[]);
	~App();
	void setSelf(QSharedPointer<App>(me));
	void connectCoreModel();
	void connectCliModel();
	static App *getInstance();
	static Thread *getLinphoneThread();
	Notifier *getNotifier() const;

	EventCountNotifier *getEventCountNotifier();
	int getEventCount() const;

	// App::postModelAsync(<lambda>) => run lambda in model thread and continue.
	// App::postModelSync(<lambda>) => run lambda in current thread and block connection.
	template <typename Func, typename... Args>
	static auto postModelAsync(Func &&callable, Args &&...args) {
		QMetaObject::invokeMethod(CoreModel::getInstance().get(), callable, args...);
	}
	template <typename Func>
	static auto postModelAsync(Func &&callable) {
		QMetaObject::invokeMethod(CoreModel::getInstance().get(), callable);
	}
	template <typename Func, typename... Args>
	static auto postCoreAsync(Func &&callable, Args &&...args) {
		QMetaObject::invokeMethod(App::getInstance(), callable, args...);
	}
	template <typename Func>
	static auto postCoreAsync(Func &&callable) {
		QMetaObject::invokeMethod(App::getInstance(), callable);
	}
	template <typename Func, typename... Args>
	static auto postCoreSync(Func &&callable, Args &&...args) {
		if (QThread::currentThread() == CoreModel::getInstance()->thread()) {
			bool end = false;
			postCoreAsync([&end, callable, args...]() mutable {
				QMetaObject::invokeMethod(App::getInstance(), callable, args..., Qt::DirectConnection);
				end = true;
			});
			while (!end)
				qApp->processEvents();
		} else {
			QMetaObject::invokeMethod(App::getInstance(), callable, Qt::DirectConnection);
		}
	}
	template <typename Func, typename... Args>
	static auto postModelSync(Func &&callable, Args &&...args) {
		if (QThread::currentThread() != CoreModel::getInstance()->thread()) {
			bool end = false;
			postModelAsync([&end, callable, args...]() mutable {
				QMetaObject::invokeMethod(CoreModel::getInstance().get(), callable, args..., Qt::DirectConnection);
				end = true;
			});
			while (!end)
				qApp->processEvents();
		} else {
			QMetaObject::invokeMethod(CoreModel::getInstance().get(), callable, Qt::DirectConnection);
		}
	}

	template <typename Func, typename... Args>
	static auto postModelBlock(Func &&callable, Args &&...args) {
		if (QThread::currentThread() != CoreModel::getInstance()->thread()) {
			QMetaObject::invokeMethod(CoreModel::getInstance().get(), callable, args..., Qt::BlockingQueuedConnection);
		} else {
			QMetaObject::invokeMethod(CoreModel::getInstance().get(), callable, Qt::DirectConnection);
		}
	}

	void clean();
	void init();
	void initCore();
	void initLocale();
	void initCppInterfaces();
	void initFonts();
	void restartCore();
	// Ferme l'application et la relance dans un processus neuf (voir main.cpp).
	void relaunch();
	static bool relaunchRequested();
	bool autoStartEnabled();
	void setSysTrayIcon();
	QSystemTrayIcon *getSystemTrayIcon() const {
		return mSystemTrayIcon;
	}
	void updateSysTrayCount(int n);
	QLocale getLocale();
	QString getLocaleAsString();

	void onLoggerInitialized();
	void sendCommand(bool firstStart = true);

	bool getCoreStarted() const;

	bool getCompactMode() const;
	void setCompactMode(bool compact);
	bool getAdminMenus() const;
	void setAdminMenus(bool shown);
	bool getCompactPinned() const;
	void setCompactPinned(bool pinned);
	void setCoreStarted(bool started);

	int getCoreGlobalState() const;
	void setCoreGlobalState(int state);

	bool isRestarting() const;
	void setIsRestarting(bool restarting);

	QQuickWindow *getCallsWindow();
	void handleAccountActivity(QSharedPointer<AccountCore> accountCore);
	Q_INVOKABLE void handleAppActivity();
	QQuickWindow *getOrCreateCallsWindow(QVariant callGui = QVariant());
	void setCallsWindowProperty(const char *id, QVariant property);
	void closeCallsWindow();
	// Prepare, masquee et par petits morceaux, la fenetre du prochain appel (voir App.cpp).
	void prepareCallsWindow();

	QQuickWindow *getMainWindow() const;
	void setMainWindow(QQuickWindow *data);
	QQuickWindow *getLastActiveWindow() const;
	void setLastActiveWindow(QQuickWindow *data);

	QSharedPointer<AccountList> getAccountList() const;
	QSharedPointer<StatusCore> getStatus() const;
	void setAccountList(QSharedPointer<AccountList> data);
	Q_INVOKABLE AccountList *getAccounts() const;

	QSharedPointer<ConferenceInfoList> getConferenceInfoList() const;
	void setConferenceInfoList(QSharedPointer<ConferenceInfoList> data);

	QSharedPointer<CallHistoryList> getCallHistoryList() const;
	void setCallHistoryList(QSharedPointer<CallHistoryList> data);

	QSharedPointer<ChatList> getChatList() const;
	ChatList *getChats() const;
	void setChatList(QSharedPointer<ChatList> data);
	ChatGui *getCurrentChat() const;
	void setCurrentChat(ChatGui *chat);

	AccountGui *getCurrentAccount() const;

	QSharedPointer<CallList> getCallList() const;
	void setCallList(QSharedPointer<CallList> data);
	Q_INVOKABLE CallList *getCalls() const;
	QSharedPointer<SettingsCore> getSettings() const;

	void onExitOnCloseChanged(); // Can be used for UniqueConnection
	void onAuthenticationRequested(const std::shared_ptr<linphone::Core> &core,
	                               const std::shared_ptr<linphone::AuthInfo> &authInfo,
	                               linphone::AuthMethod method);

	QString getShortApplicationVersion();
	QString getGitBranchName();
	QString getSdkVersion();
	QString getQtVersion() const;
#if defined(Q_OS_WIN) || defined(Q_OS_LINUX)
	NotificationBackend *getNotificationBackend() const;
#endif

	Q_INVOKABLE void checkForUpdate(bool requestedByUser = false);

	float getScreenRatio() const;
	Q_INVOKABLE void setScreenRatio(float ratio);

#ifdef Q_OS_WIN
	void setSessionLocked(bool locked);
	bool getSessionLocked() const;
#endif

#ifdef Q_OS_LINUX
	Q_INVOKABLE void exportDesktopFile();

	QString getApplicationPath() const;
	bool generateDesktopFile(const QString &confPath, bool remove, bool openInBackground);
#elif defined(Q_OS_MACOS)
	bool event(QEvent *event) override;
#endif

	QQmlApplicationEngine *mEngine = nullptr;
	bool notify(QObject *receiver, QEvent *event) override;

	enum class StatusCode { gRestartCode = 1000, gDeleteDataCode = 1001 };

signals:
	void mainWindowChanged();
	void coreStartedChanged(bool coreStarted);
	void coreGlobalStateChanged(int coreGlobalState);
	void isRestartingChanged(bool restarting);
	void accountsChanged();
	void defaultAccountChanged();
	void callsChanged();
	void currentDateChanged();
	void currentChatChanged();
	void conferenceInfosChanged();
	void chatsChanged();
	// Evenements d'une conversation perimes (conversation ou historique supprime) : a retirer des
	// caches de messages (EventLogList).
	void chatEventsInvalidated(const QString &chatId);
	void callHistoryChanged();
	void localeChanged();
	void lForceOidcTimeout();
	void remainingTimeBeforeOidcTimeoutChanged();
	void avatarRevisionChanged();
	void currentAccountChanged();
	void restartCoreRequested();
	void compactModeChanged();
	void adminMenusChanged();
	void compactPinnedChanged();
#ifdef Q_OS_WIN
	void sessionLockedChanged();
#endif
	// void executeCommand(QString command);

private:
	void createCommandParser();
	QAction *createMarkAsReadAction(QQuickWindow *window);
	void setMacOSDockActions(); // Should only be called on MacOS
	void setAutoStart(bool enabled);
	void setLocale(QString configLocale);

	QCommandLineParser *mParser = nullptr;
	Thread *mLinphoneThread = nullptr;
	Notifier *mNotifier = nullptr;
	EventCountNotifier *mEventCountNotifier = nullptr;
#if defined(Q_OS_WIN) || defined(Q_OS_LINUX)
	NotificationBackend *mNotificationBackend = nullptr;
#endif
	QSystemTrayIcon *mSystemTrayIcon = nullptr;
	QQuickWindow *mMainWindow = nullptr;
	QQuickWindow *mCallsWindow = nullptr;
	// Preparation en arriere-plan de la fenetre d'appel (creation QML progressive).
	bool adoptCallsWindow(QObject *object);
	void releaseCallsWindowIncubator();
	QQmlComponent *mCallsWindowComponent = nullptr;
	QQmlIncubator *mCallsWindowIncubator = nullptr;
	QQuickWindow *mLastActiveWindow = nullptr;
#ifdef Q_OS_WIN
	LockEventFilter *mLockEventFilter = nullptr;
#endif
	// Holds the current chat displayed in the view
	// to know if we need to display the notification
	ChatGui *mCurrentChat = nullptr;
	QSharedPointer<SettingsCore> mSettings;
	QSharedPointer<AccountList> mAccountList;
	// Service fusion-files du serveur FusionPBX (demandes signees), et ce qui s'en sert : files d'attente du compte par
	// defaut (QueuesCpp en QML) et contacts partages (SharedContactsCpp).
	QSharedPointer<FusionClient> mFusionClient;
	QSharedPointer<QueueCore> mQueues;
	QSharedPointer<SharedContactsCore> mSharedContacts;
	// Mise a jour obligatoire depuis le serveur du compte (UpdateCpp en QML).
	QSharedPointer<UpdateCore> mUpdate;
	// Statut du poste, le même sur tous ses appareils (StatusCpp en QML).
	QSharedPointer<StatusCore> mStatus;
	QSharedPointer<ConferenceInfoList> mConferenceInfoList;
	QSharedPointer<ChatList> mChatList;
	QSharedPointer<CallList> mCallList;
	QSharedPointer<CallHistoryList> mCallHistoryList;
	QSharedPointer<SafeConnection<App, CoreModel>> mCoreModelConnection;
	QSharedPointer<SafeConnection<App, CliModel>> mCliModelConnection;
	bool mAutoStart = false;
	bool mCoreStarted = false;
	int mCoreGlobalState = 0;
	bool mIsRestarting = false;
	bool mPossiblyLookForAddedAccount = false;
	QLocale mLocale = QLocale::system();
	DefaultTranslatorCore *mTranslatorCore = nullptr;
	DefaultTranslatorCore *mDefaultTranslatorCore = nullptr;
	QTimer mDateUpdateTimer;
	QDate mCurrentDate;
	float mScreenRatio = 1;
	QTimer mOIDCRefreshTimer;
	int mRemainingTimeBeforeOidcTimeout = 0;
	QTimer mAvatarRevisionTimer;
	int mAvatarRevision = 0;
	bool mCompactMode = false;
	bool mAdminMenus = false;
	bool mCompactPinned = false;
#ifdef Q_OS_WIN
	bool mSessionLocked = false;
#endif
	DECLARE_ABSTRACT_OBJECT
};
