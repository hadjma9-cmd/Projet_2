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

#include "AccountModel.hpp"

#include "core/path/Paths.hpp"
#include "model/core/CoreModel.hpp"
#include "model/setting/SettingsModel.hpp"
#include "model/tool/ToolModel.hpp"
#include "tool/Utils.hpp"
#include "tool/providers/AvatarProvider.hpp"
#include <QBuffer>
#include <QDebug>
#include <QFile>
#include <QHttpMultiPart>
#include <QImage>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QUrl>

DEFINE_ABSTRACT_OBJECT(AccountModel)

AccountModel::AccountModel(const std::shared_ptr<linphone::Account> &account, QObject *parent)
    : ::Listener<linphone::Account, linphone::AccountListener>(account, parent) {
	mustBeInLinphoneThread(getClassName());
	connect(CoreModel::getInstance().get(), &CoreModel::defaultAccountChanged, this,
	        &AccountModel::onDefaultAccountChanged);
	// Verification periodique des abonnements de presence : minuterie unique dans CoreModel::start().
	// Chaque AccountModel (y compris ceux, temporaires, des notifications) lancait la sienne.

	// Hack because Account doesn't provide callbacks on updated data
	connect(this, &AccountModel::defaultAccountChanged, this, [this]() {
		emit pictureUriChanged(Utils::coreStringToAppString(mMonitor->getParams()->getPictureUri()));
		emit displayNameChanged(
		    Utils::coreStringToAppString(mMonitor->getParams()->getIdentityAddress()->getDisplayName()));
	});

	connect(CoreModel::getInstance().get(), &CoreModel::unreadNotificationsChanged, this, [this]() {
		if (mMonitor->getState() == linphone::RegistrationState::Ok)
			emit unreadNotificationsChanged(mMonitor->getUnreadChatMessageCount(), mMonitor->getMissedCallsCount());
	});
	connect(CoreModel::getInstance().get(), &CoreModel::accountRemoved, this,
	        [this](const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::Account> &account) {
		        if (account == mMonitor) {
			        if (mToRemove && account->getState() == linphone::RegistrationState::None) {
				        lInfo() << log().arg("Disabled account removed");
				        auto authInfo = mMonitor->findAuthInfo();
				        if (authInfo) {
					        lInfo() << log().arg("Removing authinfo for disabled account");
					        CoreModel::getInstance()->getCore()->removeAuthInfo(authInfo);
				        }
				        removeUserData(mMonitor);
				        emit removed();
			        }
		        }
	        });
}

AccountModel::~AccountModel() {
	mustBeInLinphoneThread("~" + getClassName());
}

void AccountModel::onRegistrationStateChanged(const std::shared_ptr<linphone::Account> &account,
                                              linphone::RegistrationState state,
                                              const std::string &message) {
	// Cleared and None are the last state on processes after being change. Check for accountRemoved for account that
	// was not registered.
	if (mToRemove && (state == linphone::RegistrationState::Cleared || state == linphone::RegistrationState::None)) {
		lInfo() << log().arg("Account removed on state [%1]").arg((int)state);
		auto authInfo = mMonitor->findAuthInfo();
		if (authInfo) {
			lInfo() << log().arg("Removing authinfo");
			CoreModel::getInstance()->getCore()->removeAuthInfo(authInfo);
		}
		removeUserData(mMonitor);
		emit removed();
	} else if (state == linphone::RegistrationState::Ok) {
		// Force refreshing notifications when account is connected to retrieve
		// messages received while account was disconnected
		refreshUnreadNotifications();
		refreshPresenceSubscriptions();
	}
	emit registrationStateChanged(account, state, message);
}

void AccountModel::refreshPresenceSubscriptions() {
	mustBeInLinphoneThread(sLog().arg(Q_FUNC_INFO));
	// Recree uniquement les abonnements morts. L'ancienne version desactivait puis reactivait
	// des listes entieres : tous les contacts etaient desabonnes (SUBSCRIBE Expires: 0) a chaque
	// passage et a chaque reenregistrement, sans reabonnement fiable derriere.
	int alive = 0, restarted = 0;
	for (auto &friendList : CoreModel::getInstance()->getCore()->getFriendsLists()) {
		if (!friendList->subscriptionsEnabled()) continue;
		for (auto &contact : friendList->getFriends()) {
			if (!contact->getAddress() || !contact->subscribesEnabled()) continue;
			switch (contact->getSubscriptionState()) {
				case linphone::SubscriptionState::Active:
				case linphone::SubscriptionState::OutgoingProgress:
				case linphone::SubscriptionState::Pending:
				case linphone::SubscriptionState::Expiring:
					++alive;
					continue;
				default:
					break;
			}
			// Absent, termine par le serveur ou en erreur : on libere l'eventuel ancien dialogue
			// puis on envoie un SUBSCRIBE neuf (done() applique le changement).
			contact->edit();
			contact->enableSubscribes(false);
			contact->done();
			contact->edit();
			contact->enableSubscribes(true);
			contact->done();
			++restarted;
		}
	}
	lInfo() << sLog().arg("Presence subscriptions checked: %1 alive, %2 restarted").arg(alive).arg(restarted);
}

void AccountModel::onConferenceInformationUpdated(const std::shared_ptr<linphone::Account> &account,
                                                  const std::list<std::shared_ptr<linphone::ConferenceInfo>> &infos) {
	emit conferenceInformationUpdated(account, infos);
}

void AccountModel::onMessageWaitingIndicationChanged(
    const std::shared_ptr<linphone::Account> &account,
    const std::shared_ptr<const linphone::MessageWaitingIndication> &mwi) {
	auto userData = getUserData(account);
	if (!userData) userData = std::make_shared<AccountUserData>();
	userData->showMwi = mwi->hasMessageWaiting();
	for (auto summary : mwi->getSummaries()) {
		qInfo() << "[MWI] new" << summary->getNbNew() << "new+urgent" << summary->getNbNewUrgent() << "old"
		        << summary->getNbOld() << "old+urgent" << summary->getNbOldUrgent();

		userData->voicemailCount = summary->getNbNew();
		emit voicemailCountChanged(summary->getNbNew());
	}
	setUserData(account, userData);
	emit showMwiChanged(mwi->hasMessageWaiting());
}

void AccountModel::setPictureUri(QString uri) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	auto oldPictureUri = Utils::coreStringToAppString(params->getPictureUri());
	if (!oldPictureUri.isEmpty()) {
		QString appPrefix = QStringLiteral("image://%1/").arg(AvatarProvider::ProviderId);
		if (oldPictureUri.startsWith(appPrefix)) {
			oldPictureUri = Paths::getAvatarsDirPath() + oldPictureUri.mid(appPrefix.length());
		}
		QFile oldPicture(oldPictureUri);
		if (!oldPicture.remove()) qWarning() << log().arg("Cannot delete old avatar file at " + oldPictureUri);
	}
	params->setPictureUri(Utils::appStringToCoreString(uri));
	mMonitor->setParams(params);
	// Publier la photo pour que les autres postes la voient. On reutilise
	// ldap_photo_url_template : avatar.php lit ses parametres via $_REQUEST, la meme URL
	// sert donc en GET (lecture) et en POST (envoi).
	uploadAvatarToRemoteDirectory(uri);
	// Hack because Account doesn't provide callbacks on updated data
	// emit pictureUriChanged(uri);
	auto core = CoreModel::getInstance()->getCore();
	emit CoreModel::getInstance()->defaultAccountChanged(core, core->getDefaultAccount());
}

void AccountModel::uploadAvatarToRemoteDirectory(const QString &uri) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams();
	auto url = ToolModel::getRemoteAvatarUrl(params ? params->getIdentityAddress() : nullptr);
	if (url.isEmpty()) return; // aucun annuaire distant configure

	// L'URI peut etre un chemin de provider QML (image://<id>/<fichier>) ou une URL file://
	QString localPath = uri;
	const QString appPrefix = QStringLiteral("image://%1/").arg(AvatarProvider::ProviderId);
	if (localPath.startsWith(appPrefix)) localPath = Paths::getAvatarsDirPath() + localPath.mid(appPrefix.length());
	else if (localPath.startsWith("file://")) localPath = QUrl(localPath).toLocalFile();

	// Normaliser avant l'envoi. Le fichier choisi par l'utilisateur garde son format
	// d'origine (createAvatar() conserve l'extension), or le serveur le stocke sous
	// <user>.jpg et le sert en image/jpeg : un BMP ou un PNG s'y retrouvait mal declare
	// et n'etait pas affichable. On convertit donc reellement en JPEG.
	QImage image(localPath);
	if (image.isNull()) {
		lWarning() << log().arg("Cannot decode avatar image: ") << localPath;
		return;
	}
	// Un avatar s'affiche petit et sera retelecharge par tous les postes : inutile d'y
	// transporter la resolution d'origine.
	if (image.width() > 256 || image.height() > 256)
		image = image.scaled(256, 256, Qt::KeepAspectRatio, Qt::SmoothTransformation);
	QByteArray jpeg;
	QBuffer buffer(&jpeg);
	buffer.open(QIODevice::WriteOnly);
	if (!image.save(&buffer, "JPEG", 85)) {
		lWarning() << log().arg("Cannot encode avatar to JPEG");
		return;
	}
	buffer.close();

	auto multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);
	QHttpPart imagePart;
	imagePart.setHeader(QNetworkRequest::ContentTypeHeader, QVariant("image/jpeg"));
	imagePart.setHeader(QNetworkRequest::ContentDispositionHeader,
	                    QVariant("form-data; name=\"avatar\"; filename=\"avatar.jpg\""));
	imagePart.setBody(jpeg);
	multiPart->append(imagePart);

	auto manager = new QNetworkAccessManager(this);
	auto reply = manager->post(QNetworkRequest(QUrl(url)), multiPart);
	multiPart->setParent(reply);
	connect(reply, &QNetworkReply::finished, this, [this, reply, manager, url]() {
		if (reply->error() != QNetworkReply::NoError)
			lWarning() << log().arg("Avatar upload failed: ") << reply->errorString();
		else lInfo() << log().arg("Avatar uploaded to ") << url;
		reply->deleteLater();
		manager->deleteLater();
	});
}

void AccountModel::onDefaultAccountChanged() {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	emit defaultAccountChanged(CoreModel::getInstance()->getCore()->getDefaultAccount() == mMonitor);
}

void AccountModel::setDefault() {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto core = CoreModel::getInstance()->getCore();
	core->setDefaultAccount(mMonitor);
}

void AccountModel::removeAccount() {
	auto core = CoreModel::getInstance()->getCore();
	auto params = mMonitor ? mMonitor->getParams() : nullptr;
	lInfo() << log()
	               .arg("Removing account [%1]")
	               .arg(params && params->getIdentityAddress()
	                        ? Utils::coreStringToAppString(params->getIdentityAddress()->asString())
	                        : "Null");
	mToRemove = true;
	if (mMonitor) core->removeAccountWithData(mMonitor);
}

std::shared_ptr<linphone::Account> AccountModel::getAccount() const {
	return mMonitor;
}

void AccountModel::resetMissedCallsCount() {
	mMonitor->resetMissedCallsCount();
	emit unreadNotificationsChanged(mMonitor->getUnreadChatMessageCount(), mMonitor->getMissedCallsCount());
}

void AccountModel::refreshUnreadNotifications() {
	if (mMonitor->getState() == linphone::RegistrationState::Ok)
		emit unreadNotificationsChanged(mMonitor->getUnreadChatMessageCount(), mMonitor->getMissedCallsCount());
}

int AccountModel::getMissedCallsCount() const {
	return mMonitor->getMissedCallsCount();
}

int AccountModel::getUnreadMessagesCount() const {
	return mMonitor->getUnreadChatMessageCount();
}

void AccountModel::setDisplayName(QString displayName) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	auto address = params->getIdentityAddress()->clone();
	address->setDisplayName(Utils::appStringToCoreString(displayName));
	params->setIdentityAddress(address);
	mMonitor->setParams(params);
	// Hack because Account doesn't provide callbacks on updated data
	// emit displayNameChanged(displayName);
	auto core = CoreModel::getInstance()->getCore();
	emit CoreModel::getInstance()->defaultAccountChanged(core, core->getDefaultAccount());
}

void AccountModel::setDialPlan(int index) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	std::string callingCode = "";
	std::string countryCode = "";
	if (index != -1) {
		auto plans = linphone::Factory::get()->getDialPlans();
		std::vector<std::shared_ptr<linphone::DialPlan>> vectorPlans(plans.begin(), plans.end());
		auto plan = vectorPlans[index];
		callingCode = plan->getCountryCallingCode();
		countryCode = plan->getIsoCountryCode();
	}
	auto params = mMonitor->getParams()->clone();
	params->setInternationalPrefix(callingCode);
	params->setInternationalPrefixIsoCountryCode(countryCode);
	mMonitor->setParams(params);
	emit dialPlanChanged(index);
}

void AccountModel::setRegisterEnabled(bool enabled) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	params->enableRegister(enabled);
	mMonitor->setParams(params);
	if (enabled) mMonitor->refreshRegister();
	emit registerEnabledChanged(enabled);
}

std::string AccountModel::getConfigAccountUiSection() {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	return "ui_" + mMonitor->getParams()->getIdentityAddress()->asStringUriOnly();
}

bool AccountModel::getNotificationsAllowed() {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	return mMonitor->getCore()->getConfig()->getBool(getConfigAccountUiSection(), "notifications_allowed", true);
}

void AccountModel::setNotificationsAllowed(bool value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	mMonitor->getCore()->getConfig()->setBool(getConfigAccountUiSection(), "notifications_allowed", value);
	emit notificationsAllowedChanged(value);
}

QString AccountModel::getMwiServerAddress() const {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto mwiAddress = mMonitor->getParams()->getMwiServerAddress();
	return mwiAddress ? Utils::coreStringToAppString(mwiAddress->asString()) : "";
}

void AccountModel::setMwiServerAddress(QString value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto address = value.isEmpty()
	                   ? nullptr
	                   : CoreModel::getInstance()->getCore()->interpretUrl(Utils::appStringToCoreString(value), false);

	if (value.isEmpty() || address) {
		auto params = mMonitor->getParams();
		auto oldAddress = params->getMwiServerAddress();
		if (address != oldAddress && (!address || !address->weakEqual(oldAddress))) {
			auto newParams = params->clone();
			newParams->setMwiServerAddress(address);
			if (!mMonitor->setParams(newParams)) emit mwiServerAddressChanged(value);
		}
	} else {
		//: "Unable to set voicemail server address, failed creating address from %1" : %1 is address
		emit setValueFailed(tr("set_mwi_server_address_failed_error_message").arg(value));
		qWarning() << "Unable to set MWI address, failed creating address from" << value;
	}
}

linphone::TransportType AccountModel::getTransport() const {
	return mMonitor->getParams()->getTransport();
}

void AccountModel::setTransport(linphone::TransportType value, bool save) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	if (mMonitor->getParams()->getServerAddress()) {
		auto params = mMonitor->getParams()->clone();
		auto addressClone = params->getServerAddress()->clone();
		addressClone->setTransport(value);
		params->setServerAddress(addressClone);
		if (save) mMonitor->setParams(params);
		emit transportChanged(value);
		emit registrarUriChanged(Utils::coreStringToAppString(addressClone->asString()));
	}
}

QString AccountModel::getRegistrarUri() const {
	if (mMonitor->getParams()->getServerAddress())
		return Utils::coreStringToAppString(mMonitor->getParams()->getServerAddress()->asStringUriOnly());
	else return "";
}

void AccountModel::setRegistrarUri(QString value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	auto address = CoreModel::getInstance()->getCore()->interpretUrl(Utils::appStringToCoreString(value), false);
	if (address) {
		params->setServerAddress(address);
		mMonitor->setParams(params);
		emit registrarUriChanged(value);
		emit transportChanged(address->getTransport());
	} else {
		//: "Unable to set server address, failed creating address from %1"
		emit setValueFailed(tr("set_server_address_failed_error_message").arg(value));
		qWarning() << "Unable to set ServerAddress, failed creating address from" << value;
	}
}

QString AccountModel::getOutboundProxyUri() const {
	auto routeAddresses = mMonitor->getParams()->getRoutesAddresses();
	auto outbound =
	    routeAddresses.empty() ? QString() : Utils::coreStringToAppString(routeAddresses.front()->asStringUriOnly());
	return outbound;
}

void AccountModel::setOutboundProxyUri(QString value) {
	auto linOutboundProxyAddress = linphone::Factory::get()->createAddress(Utils::appStringToCoreString(value));
	if (!linOutboundProxyAddress) {
		//: Unable to set outbound proxy uri from address %1.
		//: Please make sure it matches the following format :
		//: sip:host>:<port>;transport=<transport> (:<port> is optional)
		emit setValueFailed(tr("set_outbound_proxy_uri_failed_error_message").arg(value));
		return;
	} else {
		auto params = mMonitor->getParams()->clone();
		params->setRoutesAddresses({linOutboundProxyAddress});
		emit outboundProxyUriChanged(value);
	}
}

bool AccountModel::getOutboundProxyEnabled() const {
	return mMonitor->getParams()->outboundProxyEnabled();
}

void AccountModel::setOutboundProxyEnabled(bool value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	params->enableOutboundProxy(value);
	mMonitor->setParams(params);
	emit outboundProxyEnabledChanged(value);
}

QString AccountModel::getStunServer() const {
	auto policy = mMonitor->getParams()->getNatPolicy();
	if (policy) return Utils::coreStringToAppString(policy->getStunServer());
	else return QString();
}

void AccountModel::setStunServer(QString value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	auto policy = params->getNatPolicy();
	if (!policy) policy = mMonitor->getCore()->createNatPolicy();
	policy->setStunServer(Utils::appStringToCoreString(value));
	policy->enableStun(!value.isEmpty());
	params->setNatPolicy(policy);
	mMonitor->setParams(params);
	emit stunServerChanged(value);
}

bool AccountModel::getIceEnabled() const {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto policy = mMonitor->getParams()->getNatPolicy();
	return policy && policy->iceEnabled();
}

void AccountModel::setIceEnabled(bool value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	auto policy = params->getNatPolicy();
	if (!policy) policy = mMonitor->getCore()->createNatPolicy();
	policy->enableIce(value);
	params->setNatPolicy(policy);
	mMonitor->setParams(params);
	emit iceEnabledChanged(value);
}

bool AccountModel::getAvpfEnabled() const {
	return mMonitor->getParams()->getAvpfMode() == linphone::AVPFMode::Enabled;
}

void AccountModel::setAvpfEnabled(bool value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	params->setAvpfMode(value ? linphone::AVPFMode::Enabled : linphone::AVPFMode::Disabled);
	mMonitor->setParams(params);
	emit avpfEnabledChanged(value);
}

bool AccountModel::getBundleModeEnabled() const {
	return mMonitor->getParams()->rtpBundleEnabled();
}

void AccountModel::setBundleModeEnabled(bool value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	params->enableRtpBundle(value);
	mMonitor->setParams(params);
	emit bundleModeEnabledChanged(value);
}

int AccountModel::getExpire() const {
	return mMonitor->getParams()->getExpires();
}

void AccountModel::setExpire(int value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	params->setExpires(value);
	mMonitor->setParams(params);
	emit expireChanged(value);
}

QString AccountModel::getConferenceFactoryAddress() const {
	auto confAddress = mMonitor->getParams()->getConferenceFactoryAddress();
	return confAddress ? Utils::coreStringToAppString(confAddress->asStringUriOnly()) : QString();
}

void AccountModel::setConferenceFactoryAddress(QString value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	auto address = value.isEmpty()
	                   ? nullptr
	                   : CoreModel::getInstance()->getCore()->interpretUrl(Utils::appStringToCoreString(value), false);
	if (value.isEmpty() || address) {
		params->setConferenceFactoryAddress(address);
		mMonitor->setParams(params);
		emit conferenceFactoryAddressChanged(value);
	} else {
		//: "Unable to set the conversation server address, failed creating address from %1"
		emit setValueFailed(tr("set_conference_factory_address_failed_error_message").arg(value));
		qWarning() << "Unable to set ConferenceFactoryAddress address, failed creating address from" << value;
	}
}

QString AccountModel::getAudioVideoConferenceFactoryAddress() const {
	auto confAddress = mMonitor->getParams()->getAudioVideoConferenceFactoryAddress();
	return confAddress ? Utils::coreStringToAppString(confAddress->asStringUriOnly()) : QString();
}

void AccountModel::setAudioVideoConferenceFactoryAddress(QString value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	auto address = value.isEmpty()
	                   ? nullptr
	                   : CoreModel::getInstance()->getCore()->interpretUrl(Utils::appStringToCoreString(value), false);
	if (value.isEmpty() || address) {
		params->setAudioVideoConferenceFactoryAddress(address);
		mMonitor->setParams(params);
		emit audioVideoConferenceFactoryAddressChanged(value);
	} else {
		//: "Unable to set the meeting server address, failed creating address from %1"
		emit setValueFailed(tr("set_audio_conference_factory_address_failed_error_message").arg(value));
		qWarning() << "Unable to set AudioVideoConferenceFactoryAddress address, failed creating address from" << value;
	}
}

QString AccountModel::getLimeServerUrl() const {
	return Utils::coreStringToAppString(mMonitor->getParams()->getLimeServerUrl());
}

void AccountModel::setLimeServerUrl(QString value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	params->setLimeServerUrl(Utils::appStringToCoreString(value));
	mMonitor->setParams(params);
	emit limeServerUrlChanged(value);
}

QString AccountModel::dialPlanAsString(const std::shared_ptr<linphone::DialPlan> &dialPlan) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	return Utils::coreStringToAppString(dialPlan->getFlag() + " " + dialPlan->getCountry() + " | +" +
	                                    dialPlan->getCountryCallingCode());
}

int AccountModel::getVoicemailCount() {
	auto userData = getUserData(mMonitor);
	if (userData) return userData->voicemailCount;
	else return 0;
}

bool AccountModel::getShowMwi() {
	auto userData = getUserData(mMonitor);
	if (userData) return userData->showMwi;
	else return false;
}

void AccountModel::setVoicemailAddress(QString value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	auto address = value.isEmpty()
	                   ? nullptr
	                   : CoreModel::getInstance()->getCore()->interpretUrl(Utils::appStringToCoreString(value), false);
	if (value.isEmpty() || address) {
		params->setVoicemailAddress(address);
		mMonitor->setParams(params);
		emit voicemailAddressChanged(value);
	} else {
		//: Unable to set voicemail address, failed creating address from %1
		emit setValueFailed(tr("set_voicemail_address_failed_error_message").arg(value));
		qWarning() << "Unable to set VoicemailAddress, failed creating address from" << value;
	}
}

QString AccountModel::getVoicemailAddress() const {
	auto addr = mMonitor->getParams()->getVoicemailAddress();
	return addr ? Utils::coreStringToAppString(addr->asStringUriOnly()) : "";
}

// UserData (see hpp for explanations)

static QMap<const std::shared_ptr<linphone::Account>, std::shared_ptr<AccountUserData>> userDataMap;

void AccountModel::setUserData(const std::shared_ptr<linphone::Account> &account,
                               std::shared_ptr<AccountUserData> &data) {
	mustBeInLinphoneThread(sLog().arg(Q_FUNC_INFO));
	userDataMap[account] = data;
}
std::shared_ptr<AccountUserData> AccountModel::getUserData(const std::shared_ptr<linphone::Account> &account) {
	mustBeInLinphoneThread(sLog().arg(Q_FUNC_INFO));
	if (userDataMap.contains(account)) return userDataMap.value(account);
	else return nullptr;
}
void AccountModel::removeUserData(const std::shared_ptr<linphone::Account> &account) {
	mustBeInLinphoneThread(sLog().arg(Q_FUNC_INFO));
	userDataMap.remove(account);
}

// Up to date there are api to get/set presence from/to a linphone account object
// therefore retrieved/set from core

LinphoneEnums::Presence AccountModel::getPresence() {
	auto presenceModel = CoreModel::getInstance()->getCore()->getPresenceModel(); // No api (yet) at the account level
	return ToolModel::corePresenceModelToAppPresence(presenceModel);
}

void AccountModel::setPresence(LinphoneEnums::Presence presence,
                               bool userInitiated,
                               bool resetToAuto,
                               QString presenceNote) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));

	if (!mMonitor->getParams()->publishEnabled()) {
		lDebug() << log().arg("cannot set presence as publish is disabled in account params, return");
		return;
	}

	lDebug() << log().arg("presence set request to: " + LinphoneEnums::toString(presence) + " | user initiated? " +
	                      (userInitiated ? "true" : "false") + " | reset to auto? " + (resetToAuto ? "true" : "false"));

	auto core = CoreModel::getInstance()->getCore();

	if (core->getGlobalState() != linphone::GlobalState::On) {
		lWarning() << log().arg("Unable to set presence this time as core state is not ON");
		return;
	}

	if (presence == LinphoneEnums::Presence::Undefined) {
		lWarning() << log().arg("Unable to set Undefined presence");
		return;
	}

	auto accountSection = ToolModel::configAccountSection(mMonitor);

	// Presence strictement manuelle : les mises a jour automatiques (inactivite dans
	// App.cpp, etat d'appel dans AccountCore/CoreModel) ne doivent jamais s'appliquer.
	// Seul un choix explicite de l'utilisateur, ou une remise a l'automatique, passe.
	// Auparavant elles n'etaient bloquees que si explicit_presence etait deja renseigne,
	// donc l'etat pouvait basculer tout seul tant que l'utilisateur n'avait rien choisi.
	if (!resetToAuto && !userInitiated) {
		lDebug() << log().arg("Ignoring automatic presence update (manual presence only)");
		return;
	}

	if (userInitiated) {
		core->getConfig()->setString(accountSection, "explicit_presence",
		                             Utils::appStringToCoreString(LinphoneEnums::toString(presence)));
		core->getConfig()->sync();
	}

	if (resetToAuto) {
		core->getConfig()->cleanEntry(accountSection, "explicit_presence");
		core->getConfig()->sync();
	}

	core->getConfig()->setString(accountSection, "presence_note", Utils::appStringToCoreString(presenceNote));
	core->getConfig()->sync();

	auto presenceModel = ToolModel::appPresenceToCorePresenceModel(presence, presenceNote);
	core->setPresenceModel(presenceModel); // No api (yet) at the account level

	if (presence == LinphoneEnums::Presence::Offline) {
		for (auto friendList : core->getFriendsLists())
			friendList->enableSubscriptions(false);
	} else {
		for (auto friendList : core->getFriendsLists())
			friendList->enableSubscriptions(true);
	}

	setNotificationsAllowed(
	    presence != LinphoneEnums::Presence::Offline && presence != LinphoneEnums::Presence::DoNotDisturb &&
	    (presence != LinphoneEnums::Presence::Away ||
	     core->getConfig()->getBool(accountSection, "allow_notifications_in_presence_away", true)) &&
	    (presence != LinphoneEnums::Presence::Busy ||
	     core->getConfig()->getBool(accountSection, "allow_notifications_in_presence_busy", true)));

	if (!SettingsModel::dndEnabled(core->getConfig())) {
		SettingsModel::getInstance()->enableRinging(presence != LinphoneEnums::Presence::DoNotDisturb);
	}

	emit presenceChanged(presence, userInitiated);
}

bool AccountModel::forwardToVoiceMailInDndPresence() {
	auto accountSection = ToolModel::configAccountSection(mMonitor);
	auto core = CoreModel::getInstance()->getCore();
	return core->getConfig()->getBool(accountSection, "forward_to_voicemail_in_dnd_presence", false);
}

std::list<std::shared_ptr<linphone::ChatRoom>> AccountModel::getChatRooms() {
	return mMonitor->getChatRooms();
}

QString AccountModel::getCcmpServerUrl() const {
	return Utils::coreStringToAppString(mMonitor->getParams()->getCcmpServerUrl());
}

void AccountModel::setCcmpServerUrl(QString value) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	auto params = mMonitor->getParams()->clone();
	params->setCcmpServerUrl(Utils::appStringToCoreString(value));
	mMonitor->setParams(params);
	emit ccmpServerUrlChanged(value);
}
