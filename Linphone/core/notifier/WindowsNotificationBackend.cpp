#include "WindowsNotificationBackend.hpp"
#include "core/App.hpp"
#include "core/call/CallGui.hpp"
#include "core/chat/ChatGui.hpp"
#include "core/event-filter/LockEventFilter.hpp"
#include "tool/Constants.hpp"
#include "tool/Utils.hpp"

#include "DesktopNotificationManagerCompat.hpp"
#include <windows.foundation.h>
#include <windows.ui.notifications.h>

#include <QDebug>
#include <QPointer>
#include <QQuickWindow>

#include <atomic>
#include <memory>

using namespace Microsoft::WRL;
using namespace ABI::Windows::UI::Notifications;
using namespace ABI::Windows::Foundation;
using namespace Microsoft::WRL::Wrappers;

namespace {
// Texte insere dans le XML de la notification : un nom d'appelant contenant & ou < rendait le XML invalide et la
// notification d'appel ne s'affichait pas.
std::wstring xmlEscaped(const QString &text) {
	return text.toHtmlEscaped().toStdWString();
}
} // namespace

NotificationBackend::NotificationBackend(QObject *parent) : AbstractNotificationBackend(parent) {
	connect(App::getInstance(), &App::sessionLockedChanged, this, [this] {
		if (!App::getInstance()->getSessionLocked()) {
			qDebug() << "Session unlocked, flush pending notifications";
			flushPendingNotifications();
		}
	});
}

void NotificationBackend::flushPendingNotifications() {
	for (const auto &notif : mPendingNotifications) {
		sendNotification(notif.type, notif.data);
	}
	mPendingNotifications.clear();
}

void NotificationBackend::sendMessageNotification(QVariantMap data) {

	IToastNotifier *notifier = nullptr;
	HRESULT hr = DesktopNotificationManagerCompat::CreateToastNotifier(&notifier);
	if (FAILED(hr) || !notifier) {
		lWarning() << "CreateToastNotifier failed:" << Qt::hex << hr;
		return;
	}

	auto msgTxt = data["message"].toString().toStdWString();
	auto remoteAddress = data["remoteAddress"].toString().toStdWString();
	auto chatRoomName = data["chatRoomName"].toString().toStdWString();
	auto chatRoomAddress = data["chatRoomAddress"].toString().toStdWString();
	auto appIcon = Utils::getIconAsPng(Utils::getAppIcon("logo").toString()).toStdWString();
	auto avatarUri = data["avatarUri"].toString().toStdWString();
	bool isGroup = data["isGroupChat"].toBool();
	ChatGui *chat = data["chat"].value<ChatGui *>();

	std::wstring xml = L"<toast>"
	                   L"    <visual>"
	                   L"        <binding template=\"ToastGeneric\">"
	                   L"            <image src=\"file:///" +
	                   appIcon +
	                   L"\" placement=\"appLogoOverride\"/>"
	                   L"            <text><![CDATA[" +
	                   chatRoomName +
	                   L"]]></text>"
	                   L"            <text><![CDATA[" +
	                   (isGroup ? remoteAddress : L"") +
	                   L"]]></text>"
	                   L"            <group>"
	                   L"                <subgroup>"
	                   L"                    <text hint-style=\"body\"><![CDATA[" +
	                   msgTxt +
	                   L"]]></text>"
	                   L"                </subgroup>"
	                   L"            </group>"
	                   L"        </binding>"
	                   L"    </visual>"
	                   L"    <audio silent=\"true\"/>"
	                   L"</toast>";

	ABI::Windows::Data::Xml::Dom::IXmlDocument *doc = nullptr;
	hr = DesktopNotificationManagerCompat::CreateXmlDocumentFromString(xml.c_str(), &doc);
	if (FAILED(hr) || !doc) {
		lWarning() << "CreateXmlDocumentFromString failed:" << Qt::hex << hr;
		notifier->Release();
		return;
	}

	IToastNotification *toast = nullptr;
	hr = DesktopNotificationManagerCompat::CreateToastNotification(doc, &toast);
	if (FAILED(hr) || !toast) {
		lWarning() << "CreateToastNotification failed:" << Qt::hex << hr;
		doc->Release();
		notifier->Release();
		Utils::showInformationPopup(tr("info_popup_error_title"), tr("info_popup_error_creating_notification"), false);
		return;
	}

	EventRegistrationToken token;
	toast->add_Activated(Microsoft::WRL::Callback<ITypedEventHandler<ToastNotification *, IInspectable *>>(
	                         [this, chat](IToastNotification *sender, IInspectable *args) -> HRESULT {
		                         qInfo() << "Message toast clicked!";

		                         Utils::openChat(chat);

		                         return S_OK;
	                         })
	                         .Get(),
	                     &token);

	hr = notifier->Show(toast);
	if (FAILED(hr)) {
		lWarning() << "Toast Show failed:" << Qt::hex << hr;
	}

	toast->Release();
	doc->Release();
	notifier->Release();
}

void NotificationBackend::sendCallNotification(QVariantMap data) {
	// Copie de l'appel propre a cette notification : si la notification ne peut pas etre affichee,
	// elle est liberee ici (sinon personne ne le faisait).
	CallGui *call = data["call"].value<CallGui *>();
	if (!call) return;

	IToastNotifier *notifier = nullptr;
	HRESULT hr = DesktopNotificationManagerCompat::CreateToastNotifier(&notifier);
	if (FAILED(hr) || !notifier) {
		lWarning() << "CreateToastNotifier failed:" << Qt::hex << hr;
		call->deleteLater();
		return;
	}

	auto displayName = xmlEscaped(data["displayName"].toString());
	auto remoteAddress = xmlEscaped(data["remoteAddress"].toString());
	int timeout = 2;
	// AbstractNotificationBackend::Notifications[(int)NotificationType::ReceivedCall].getTimeout();

	// Incoming call
	auto callDescription = xmlEscaped(tr("incoming_call"));

	QList<ToastButton> actions;
	QString declineIcon = Utils::getIconAsPng(Utils::getAppIcon("endCall").toString());
	QString acceptIcon = Utils::getIconAsPng(Utils::getAppIcon("phone").toString());
	auto appIcon = xmlEscaped(Utils::getIconAsPng(Utils::getAppIcon("logo").toString()));
	//: Accept
	actions.append(ToastButton(tr("accept_button"), "accept", acceptIcon));
	//: Decline
	actions.append(ToastButton(tr("decline_button"), "decline", declineIcon));
	std::wstring wActions;
	if (!actions.isEmpty()) {
		wActions += L"<actions>";
		for (const auto &action : actions) {
			std::wstring wLabel = xmlEscaped(action.label);
			std::wstring wArg = xmlEscaped(action.argument);
			std::wstring wIcon = xmlEscaped(action.icon);
			qDebug() << "toast icon action" << wIcon;
			wActions +=
			    L"<action content=\"" + wLabel + L"\" arguments=\"" + wArg + L"\" imageUri=\"" + wIcon + L"\"/>";
		}
		wActions += L"</actions>";
	}

	std::wstring xml = L"<toast scenario=\"reminder\">"
	                   L"    <visual>"
	                   L"        <binding template=\"ToastGeneric\">"
	                   L"            <image src=\"file:///" +
	                   appIcon +
	                   L"\" placement=\"appLogoOverride\"/>"
	                   L"            <text hint-style=\"header\">" +
	                   displayName +
	                   L"</text>"
	                   L"            <text hint-style=\"base\">" +
	                   remoteAddress +
	                   L"</text>"
	                   L"            <text hint-style=\"body\">" +
	                   callDescription +
	                   L"</text>"
	                   L"        </binding>"
	                   L"    </visual>" +
	                   wActions +
	                   L"    <audio silent=\"true\"/>"
	                   L"</toast>";

	ABI::Windows::Data::Xml::Dom::IXmlDocument *doc = nullptr;
	hr = DesktopNotificationManagerCompat::CreateXmlDocumentFromString(xml.c_str(), &doc);
	if (FAILED(hr) || !doc) {
		lWarning() << "CreateXmlDocumentFromString failed:" << Qt::hex << hr;
		notifier->Release();
		call->deleteLater();
		return;
	}

	IToastNotification *toast = nullptr;
	hr = DesktopNotificationManagerCompat::CreateToastNotification(doc, &toast);
	if (FAILED(hr) || !toast) {
		lWarning() << "CreateToastNotification failed:" << Qt::hex << hr;
		doc->Release();
		notifier->Release();
		call->deleteLater();
		Utils::showInformationPopup(tr("info_popup_error_title"), tr("info_popup_error_creating_notification"), false);
		return;
	}

	ComPtr<IToastNotification2> toast2;
	hr = toast->QueryInterface(IID_PPV_ARGS(&toast2));
	if (FAILED(hr)) lWarning() << "QueryInterface failed";
	auto callId = call->mCore->getCallId();
	qDebug() << "put tag to toast" << callId;
	hr = toast2->put_Tag(HStringReference(reinterpret_cast<const wchar_t *>(callId.utf16())).Get());
	toast2->put_Group(HStringReference(L"linphone").Get());
	if (FAILED(hr)) lWarning() << "puting tag on toast failed";

	// Vrai quand la notification a transmis `call` a la fenetre d'appel (bouton Accepter ou clic).
	// Ecrit depuis le rappel de la notification Windows, d'ou l'atomique.
	auto handedToWindow = std::make_shared<std::atomic_bool>(false);

	connect(call->mCore.get(), &CallCore::stateChanged, this, [this, call, notifier, toast, handedToWindow] {
		auto state = call->mCore->getState();
		if (state == LinphoneEnums::CallState::End || state == LinphoneEnums::CallState::Error ||
		    state == LinphoneEnums::CallState::StreamsRunning) {
			qDebug() << "Call ended, answered or error, remove toast";
			auto callId = call->mCore->getCallId();
			disconnect(call->mCore.get(), &CallCore::stateChanged, this, nullptr);
			// Only delete `call` when the call was never answered (missed / declined).
			// On accept it is handed to CallsWindow (Utils::openCallsWindow) and becomes
			// mainWindow.call; deleting it on StreamsRunning nulls mainWindow.call mid-call
			// (broken in-call UI, hangup stops propagating). Once in QML it is
			// JavaScript-owned and collected when the window releases it.
			// Decroche depuis l'application (et non depuis la notification) : la copie n'a ete remise a
			// aucune fenetre et personne d'autre ne la tient. Elle est liberee aussi, sinon elle restait
			// en memoire pour toujours avec l'appel SIP qu'elle retient.
			if (state != LinphoneEnums::CallState::StreamsRunning || !handedToWindow->load()) call->deleteLater();

			std::unique_ptr<DesktopNotificationHistoryCompat> history;
			DesktopNotificationManagerCompat::get_History(&history);

			auto hr = history->RemoveGroupedTag(reinterpret_cast<const wchar_t *>(callId.utf16()), L"linphone");
			if (FAILED(hr)) {
				lWarning() << "removing toast failed";
			}
		}
	});

	EventRegistrationToken token;
	toast->add_Activated(Microsoft::WRL::Callback<ITypedEventHandler<ToastNotification *, IInspectable *>>(
	                         [this, call = QPointer<CallGui>(call), handedToWindow](IToastNotification *sender,
	                                                                                IInspectable *args) -> HRESULT {
		                         // `call` est suivi (QPointer) : liberee en fin d'appel, la notification
		                         // ne doit plus s'en servir si on clique dessus apres coup.
		                         qInfo() << "Toast clicked!";
		                         // Cast args en IToastActivatedEventArgs
		                         Microsoft::WRL::ComPtr<IToastActivatedEventArgs> activatedArgs;
		                         HRESULT hr = args->QueryInterface(IID_PPV_ARGS(&activatedArgs));
		                         if (SUCCEEDED(hr)) {
			                         HSTRING argumentsHString;
			                         activatedArgs->get_Arguments(&argumentsHString);

			                         // Convertir HSTRING en wstring
			                         UINT32 length;
			                         const wchar_t *rawStr = WindowsGetStringRawBuffer(argumentsHString, &length);
			                         std::wstring arguments(rawStr, length);
			                         QString arg = QString::fromStdWString(arguments);
			                         qInfo() << "Toast activated with args:" << arg;

			                         if (arg.compare("accept") == 0) {
				                         if (call) {
					                         qDebug() << "Accept call";
					                         // Petite fenetre : pas de fenetre d'appel, `call` reste a la notification
					                         // qui le libere (sinon il n'etait jamais libere, avec l'appel du SDK).
					                         handedToWindow->store(!App::getInstance()->getCompactMode());
					                         Utils::openCallsWindow(call);
					                         call->mCore->lAccept(false);
				                         }
			                         } else if (arg.compare("decline") == 0) {
				                         if (call) {
					                         qDebug() << "Decline call";
					                         call->mCore->lDecline();
				                         }
			                         } else if (arg.isEmpty()) {
				                         if (call) {
					                         handedToWindow->store(!App::getInstance()->getCompactMode());
					                         Utils::openCallsWindow(call);
				                         }
			                         }

			                         WindowsDeleteString(argumentsHString);
		                         }
		                         return S_OK;
	                         })
	                         .Get(),
	                     &token);

	hr = notifier->Show(toast);
	if (FAILED(hr)) {
		lWarning() << "Toast Show failed:" << Qt::hex << hr;
	}

	toast->Release();
	doc->Release();
	notifier->Release();
}

void NotificationBackend::sendMissedCallNotification(QVariantMap data) {
	IToastNotifier *notifier = nullptr;
	HRESULT hr = DesktopNotificationManagerCompat::CreateToastNotifier(&notifier);
	if (FAILED(hr) || !notifier) {
		lWarning() << "CreateToastNotifier failed:" << Qt::hex << hr;
		return;
	}

	auto displayName = xmlEscaped(data["displayName"].toString());
	auto number = xmlEscaped(data["number"].toString());
	const QString remoteAddress = data["remoteAddress"].toString();
	auto appIcon = xmlEscaped(Utils::getIconAsPng(Utils::getAppIcon("logo").toString()));
	auto callBackIcon = xmlEscaped(Utils::getIconAsPng(Utils::getAppIcon("phone").toString()));

	// Bouton « Rappeler » ; un clic sur la notification elle-meme ouvre l'historique des appels.
	std::wstring xml = L"<toast>"
	                   L"    <visual>"
	                   L"        <binding template=\"ToastGeneric\">"
	                   L"            <image src=\"file:///" +
	                   appIcon +
	                   L"\" placement=\"appLogoOverride\"/>"
	                   L"            <text hint-style=\"header\">" +
	                   displayName +
	                   L"</text>"
	                   L"            <text hint-style=\"base\">" +
	                   number +
	                   L"</text>"
	                   L"            <text hint-style=\"body\">Appel manqué</text>"
	                   L"        </binding>"
	                   L"    </visual>"
	                   L"    <actions>"
	                   L"        <action content=\"Rappeler\" arguments=\"callback\" imageUri=\"" +
	                   callBackIcon +
	                   L"\"/>"
	                   L"    </actions>"
	                   L"    <audio silent=\"true\"/>"
	                   L"</toast>";

	ABI::Windows::Data::Xml::Dom::IXmlDocument *doc = nullptr;
	hr = DesktopNotificationManagerCompat::CreateXmlDocumentFromString(xml.c_str(), &doc);
	if (FAILED(hr) || !doc) {
		lWarning() << "CreateXmlDocumentFromString failed:" << Qt::hex << hr;
		notifier->Release();
		return;
	}

	IToastNotification *toast = nullptr;
	hr = DesktopNotificationManagerCompat::CreateToastNotification(doc, &toast);
	if (FAILED(hr) || !toast) {
		lWarning() << "CreateToastNotification failed:" << Qt::hex << hr;
		doc->Release();
		notifier->Release();
		return;
	}

	EventRegistrationToken token;
	toast->add_Activated(Microsoft::WRL::Callback<ITypedEventHandler<ToastNotification *, IInspectable *>>(
	                         [remoteAddress](IToastNotification *sender, IInspectable *args) -> HRESULT {
		                         QString arg;
		                         Microsoft::WRL::ComPtr<IToastActivatedEventArgs> activatedArgs;
		                         if (SUCCEEDED(args->QueryInterface(IID_PPV_ARGS(&activatedArgs)))) {
			                         HSTRING argumentsHString;
			                         activatedArgs->get_Arguments(&argumentsHString);
			                         UINT32 length;
			                         const wchar_t *rawStr = WindowsGetStringRawBuffer(argumentsHString, &length);
			                         arg = QString::fromStdWString(std::wstring(rawStr, length));
			                         WindowsDeleteString(argumentsHString);
		                         }
		                         qInfo() << "Missed call toast activated with args:" << arg;
		                         // Rappel de Windows hors du fil de l'interface : l'action y est renvoyee.
		                         QMetaObject::invokeMethod(
		                             App::getInstance(),
		                             [remoteAddress, arg]() {
			                             if (arg.compare("callback") == 0) {
				                             Utils::createCall(remoteAddress);
			                             } else if (auto mainWindow = Utils::getMainWindow()) {
				                             Utils::smartShowWindow(mainWindow);
				                             QMetaObject::invokeMethod(mainWindow, "goToCallHistory");
			                             }
		                             },
		                             Qt::QueuedConnection);
		                         return S_OK;
	                         })
	                         .Get(),
	                     &token);

	hr = notifier->Show(toast);
	if (FAILED(hr)) {
		lWarning() << "Toast Show failed:" << Qt::hex << hr;
	}

	toast->Release();
	doc->Release();
	notifier->Release();
}

void NotificationBackend::sendNotification(NotificationType type, QVariantMap data) {
	if (App::getInstance()->getSessionLocked()) {
		mPendingNotifications.append({type, data});
		return;
	}
	switch (type) {
		case NotificationType::ReceivedCall:
			sendCallNotification(data);
			break;
		case NotificationType::ReceivedMessage:
			sendMessageNotification(data);
			break;
		case NotificationType::MissedCall:
			sendMissedCallNotification(data);
			break;
	}
}
