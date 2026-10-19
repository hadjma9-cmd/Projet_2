/*
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

#include "StatusCore.hpp"
#include "core/App.hpp"
#include "model/core/CoreModel.hpp"
#include "model/tool/ToolModel.hpp"
#include "tool/Utils.hpp"

#include <QJsonDocument>

DEFINE_ABSTRACT_OBJECT(StatusCore)

static const QString ServicePath = QStringLiteral("/gamaphone/v1/statut");
static constexpr qint64 RereadDelaySecs = 30;

QSharedPointer<StatusCore> StatusCore::create(QSharedPointer<FusionClient> client) {
	auto sharedPointer = QSharedPointer<StatusCore>(new StatusCore(client), &QObject::deleteLater);
	sharedPointer->setSelf(sharedPointer);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

StatusCore::StatusCore(QSharedPointer<FusionClient> client) : QObject(nullptr), mClient(client) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
}

StatusCore::~StatusCore() {
}

void StatusCore::setSelf(QSharedPointer<StatusCore> me) {
	mCoreModelConnection = SafeConnection<StatusCore, CoreModel>::create(me, CoreModel::getInstance());
	// Compte connecté (démarrage, réseau retrouvé) : première lecture.
	mCoreModelConnection->makeConnectToModel(
	    &CoreModel::accountRegistrationStateChanged,
	    [this](const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::Account> &account,
	           linphone::RegistrationState state, const std::string &message) {
		    if (state != linphone::RegistrationState::Ok || account != core->getDefaultAccount()) return;
		    mCoreModelConnection->invokeToCore([this]() { read(ReadMode::IfNeverRead); });
	    });
	mCoreModelConnection->makeConnectToModel(&CoreModel::defaultAccountChanged, [this]() {
		mCoreModelConnection->invokeToCore([this]() { read(ReadMode::IfNeverRead); });
	});
	// Présence du poste lui-même, annoncée par le serveur : si elle diffère du statut affiché ici, il a été changé sur
	// un autre appareil, on relit. Les appels en cours (état automatique) ne comptent pas.
	mCoreModelConnection->makeConnectToModel(
	    &CoreModel::notifyPresenceReceivedForUriOrTel,
	    [this](const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::Friend> &linphoneFriend,
	           const std::string &uriOrTel, const std::shared_ptr<const linphone::PresenceModel> &presenceModel) {
		    auto account = core ? core->getDefaultAccount() : nullptr;
		    if (!account || !presenceModel || ToolModel::isAutomaticPresence(presenceModel)) return;
		    auto identity = account->getParams()->getIdentityAddress();
		    auto address = linphone::Factory::get()->createAddress(uriOrTel);
		    if (!identity || !address || !address->weakEqual(identity)) return;
		    const auto announced = ToolModel::corePresenceModelToAppPresence(presenceModel);
		    if (announced == LinphoneEnums::Presence::Undefined) return;
		    mCoreModelConnection->invokeToCore([this, announced]() {
			    auto accountList = App::getInstance()->getAccountList();
			    auto accountCore = accountList ? accountList->getDefaultAccountCore() : nullptr;
			    if (accountCore && accountCore->getPresence() != announced) read(ReadMode::Always);
		    });
	    });
	// Retour sur l'application, venant d'une autre.
	connect(App::getInstance(), &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
		if (state == Qt::ApplicationActive) read(ReadMode::IfStale);
	});
	// Compte peut-être déjà connecté avant la création de cet objet.
	read(ReadMode::IfNeverRead);
}

void StatusCore::refresh() {
	read(ReadMode::Always);
}

QString StatusCore::toServer(LinphoneEnums::Presence presence) {
	switch (presence) {
		case LinphoneEnums::Presence::Busy:
			return QStringLiteral("busy");
		case LinphoneEnums::Presence::Away:
			return QStringLiteral("away");
		case LinphoneEnums::Presence::DoNotDisturb:
			return QStringLiteral("dnd");
		case LinphoneEnums::Presence::Offline:
			return QStringLiteral("offline");
		default:
			return QStringLiteral("online");
	}
}

LinphoneEnums::Presence StatusCore::fromServer(const QString &status) {
	if (status == QLatin1String("busy")) return LinphoneEnums::Presence::Busy;
	if (status == QLatin1String("away")) return LinphoneEnums::Presence::Away;
	if (status == QLatin1String("dnd")) return LinphoneEnums::Presence::DoNotDisturb;
	if (status == QLatin1String("offline")) return LinphoneEnums::Presence::Offline;
	if (status == QLatin1String("online")) return LinphoneEnums::Presence::Online;
	return LinphoneEnums::Presence::Undefined;
}

// Changement de compte : le statut connu est celui de l'ancien. Faux si le compte n'est pas connecté.
bool StatusCore::adoptAccount(const FusionClient::Credentials &credentials) {
	const QString key = credentials.key();
	if (key != mAccountKey) {
		mAccountKey = key;
		++mGeneration;
		mReading = false;
		mHaveRead = false;
		mLastAttempt = QDateTime();
		mServerStatus.clear();
	}
	return credentials.isValid();
}

void StatusCore::read(ReadMode mode) {
	if (mReading) return;
	mReading = true;
	mClient->withCredentials([this, mode](const FusionClient::Credentials &credentials) {
		const bool connected = adoptAccount(credentials);
		if (!connected || (mode == ReadMode::IfNeverRead && mHaveRead) ||
		    (mode == ReadMode::IfStale && mLastAttempt.isValid() &&
		     mLastAttempt.secsTo(QDateTime::currentDateTimeUtc()) < RereadDelaySecs)) {
			mReading = false;
			return;
		}
		mReading = true;
		mLastAttempt = QDateTime::currentDateTimeUtc();
		const int generation = mGeneration;
		mClient->send(credentials, "GET", ServicePath, QByteArray(),
		              [this, generation](const FusionClient::Reply &reply) {
			              if (generation != mGeneration) return; // compte changé entre-temps
			              mReading = false;
			              // Lecture en échec : on garde le statut affiché.
			              if (reply.status == 200) apply(reply.answer);
		              });
	});
}

void StatusCore::choose(LinphoneEnums::Presence presence) {
	const QString status = toServer(presence);
	// Déjà le statut du serveur (note modifiée, statut relu et réappliqué) : rien à envoyer.
	if (mHaveRead && status == mServerStatus) return;
	const QByteArray body = QJsonDocument(QJsonObject{{"status", status}}).toJson(QJsonDocument::Compact);
	mClient->withCredentials([this, body](const FusionClient::Credentials &credentials) {
		if (!adoptAccount(credentials)) return;
		const int generation = mGeneration;
		mClient->send(credentials, "POST", ServicePath, body, [this, generation](const FusionClient::Reply &reply) {
			if (generation != mGeneration) return;
			if (reply.status == 200) {
				apply(reply.answer);
				return;
			}
			lWarning() << log().arg("Status not saved on the server:") << reply.status << reply.error;
			Utils::showInformationPopup(
			    QStringLiteral("Statut"),
			    QStringLiteral("Le statut n'a pas pu être enregistré sur le serveur. Réessayez dans un instant."),
			    false);
			read(ReadMode::Always); // l'appareil reprend le statut que le serveur applique réellement
		});
	});
}

void StatusCore::apply(const QJsonObject &answer) {
	mHaveRead = true;
	const QString status = answer.value("status").toString();
	const auto presence = fromServer(status);
	if (presence == LinphoneEnums::Presence::Undefined) return;
	mServerStatus = status;
	auto accountList = App::getInstance()->getAccountList();
	auto accountCore = accountList ? accountList->getDefaultAccountCore() : nullptr;
	if (!accountCore) return;
	// Aucun statut encore choisi sur le serveur : celui de cet appareil devient celui du poste.
	if (!answer.value("set").toBool()) {
		if (accountCore->getExplicitPresence() != LinphoneEnums::Presence::Undefined)
			choose(accountCore->getExplicitPresence());
		return;
	}
	// « Disponible » sur le serveur et statut automatique ici : c'est la même chose.
	if (presence == LinphoneEnums::Presence::Online &&
	    accountCore->getExplicitPresence() == LinphoneEnums::Presence::Undefined)
		return;
	if (accountCore->getExplicitPresence() != presence) accountCore->applyServerPresence(presence);
}
