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

#include "SharedContactsCore.hpp"
#include "core/App.hpp"
#include "model/core/CoreModel.hpp"

#include <QJsonArray>
#include <QJsonDocument>

DEFINE_ABSTRACT_OBJECT(SharedContactsCore)

static const QString RightsPath = QStringLiteral("/gamaphone/v1/droits");
static constexpr qint64 RightsRereadDelaySecs = 10 * 60;

QSharedPointer<SharedContactsCore> SharedContactsCore::create(QSharedPointer<FusionClient> client) {
	auto sharedPointer = QSharedPointer<SharedContactsCore>(new SharedContactsCore(client), &QObject::deleteLater);
	sharedPointer->setSelf(sharedPointer);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

SharedContactsCore::SharedContactsCore(QSharedPointer<FusionClient> client) : QObject(nullptr), mClient(client) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
}

SharedContactsCore::~SharedContactsCore() {
}

void SharedContactsCore::setSelf(QSharedPointer<SharedContactsCore> me) {
	mCoreModelConnection = SafeConnection<SharedContactsCore, CoreModel>::create(me, CoreModel::getInstance());
	// Compte connecté (démarrage, réseau retrouvé) ou changé : première lecture des droits.
	mCoreModelConnection->makeConnectToModel(
	    &CoreModel::accountRegistrationStateChanged,
	    [this](const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::Account> &account,
	           linphone::RegistrationState state, const std::string &message) {
		    if (state != linphone::RegistrationState::Ok || account != core->getDefaultAccount()) return;
		    mCoreModelConnection->invokeToCore([this]() { readRights(ReadMode::IfNeverRead); });
	    });
	mCoreModelConnection->makeConnectToModel(&CoreModel::defaultAccountChanged, [this]() {
		mCoreModelConnection->invokeToCore([this]() { readRights(ReadMode::IfNeverRead); });
	});
	// Retour sur l'application : un administrateur a pu ajouter ou retirer le poste du groupe.
	connect(App::getInstance(), &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
		if (state == Qt::ApplicationActive) readRights(ReadMode::IfStale);
	});
	// Compte peut-être déjà connecté avant la création de cet objet.
	readRights(ReadMode::IfNeverRead);
}

bool SharedContactsCore::isBusy() const {
	return mBusy;
}

bool SharedContactsCore::isTeamContactsAllowed() const {
	return mTeamContactsAllowed;
}

void SharedContactsCore::refreshRights() {
	readRights(ReadMode::Always);
}

void SharedContactsCore::setTeamContactsAllowed(bool allowed) {
	if (allowed == mTeamContactsAllowed) return;
	mTeamContactsAllowed = allowed;
	emit teamContactsAllowedChanged();
}

void SharedContactsCore::readRights(ReadMode mode) {
	if (mReadingRights) return;
	mReadingRights = true;
	mClient->withCredentials([this, mode](const FusionClient::Credentials &credentials) {
		const QString key = credentials.key();
		if (key != mRightsAccountKey) { // autre compte (ou déconnecté) : ses droits sont inconnus
			mRightsAccountKey = key;
			++mRightsGeneration;
			mRightsRead = false;
			mLastRightsAttempt = QDateTime();
			setTeamContactsAllowed(false);
		}
		if (!credentials.isValid() || (mode == ReadMode::IfNeverRead && mRightsRead) ||
		    (mode == ReadMode::IfStale && mLastRightsAttempt.isValid() &&
		     mLastRightsAttempt.secsTo(QDateTime::currentDateTimeUtc()) < RightsRereadDelaySecs)) {
			mReadingRights = false;
			return;
		}
		mLastRightsAttempt = QDateTime::currentDateTimeUtc();
		const int generation = mRightsGeneration;
		mClient->send(credentials, "GET", RightsPath, QByteArray(),
		              [this, generation](const FusionClient::Reply &reply) {
			              if (generation != mRightsGeneration) return; // compte changé entre-temps
			              mReadingRights = false;
			              if (reply.status == 200) {
				              mRightsRead = true;
				              setTeamContactsAllowed(reply.answer.value("team_contacts").toBool());
			              } else if (reply.status == 404) {
				              // Serveur pas encore mis à jour : il ne connaît pas ce droit, on ne propose rien.
				              mRightsRead = true;
				              setTeamContactsAllowed(false);
			              } // autre échec (réseau) : on garde ce qui était connu
		              });
	});
}

void SharedContactsCore::createContact(const QString &givenName,
                                       const QString &familyName,
                                       const QStringList &phones,
                                       bool force) {
	if (mBusy) return;
	const QByteArray body = QJsonDocument(QJsonObject{{"given", givenName.trimmed()},
	                                                  {"family", familyName.trimmed()},
	                                                  {"phones", QJsonArray::fromStringList(phones)},
	                                                  {"force", force}})
	                            .toJson(QJsonDocument::Compact);
	post("/gamaphone/v1/contacts", body, [this](const FusionClient::Reply &reply) {
		if (reply.status == 201) emit contactCreated(reply.answer.value("name").toString());
		else if (reply.status == 409 && reply.error == "duplicate")
			emit duplicateFound(reply.answer.value("name").toString(), reply.answer.value("number").toString());
		else {
			if (reply.error == "forbidden") setTeamContactsAllowed(false); // retiré du groupe entre-temps
			emit failed(errorMessage(reply));
		}
	});
}

void SharedContactsCore::deleteContact(const QString &name, const QStringList &phones) {
	if (mBusy) return;
	const QByteArray body =
	    QJsonDocument(QJsonObject{{"name", name.trimmed()}, {"phones", QJsonArray::fromStringList(phones)}})
	        .toJson(QJsonDocument::Compact);
	post("/gamaphone/v1/contacts/delete", body, [this, name](const FusionClient::Reply &reply) {
		if (reply.status == 200) emit contactDeleted(reply.answer.value("name").toString(name));
		else {
			if (reply.error == "forbidden") setTeamContactsAllowed(false); // retiré du groupe entre-temps
			emit failed(errorMessage(reply));
		}
	});
}

void SharedContactsCore::post(const QString &path, const QByteArray &body, FusionClient::Callback done) {
	setBusy(true);
	mClient->withCredentials([this, path, body, done](const FusionClient::Credentials &credentials) {
		if (!credentials.isValid()) {
			setBusy(false);
			emit failed("Compte non connecté : réessayez dans un instant.");
			return;
		}
		mClient->send(credentials, "POST", path, body, [this, done](const FusionClient::Reply &reply) {
			setBusy(false);
			done(reply);
		});
	});
}

void SharedContactsCore::setBusy(bool busy) {
	if (busy == mBusy) return;
	mBusy = busy;
	emit busyChanged();
}

QString SharedContactsCore::errorMessage(const FusionClient::Reply &reply) {
	if (reply.error == "name") return "Saisissez le prénom et le nom.";
	if (reply.error == "phone") return "Numéro de téléphone invalide.";
	if (reply.error == "field") return "Un des champs est trop long.";
	if (reply.error == "not_found") return "Ce contact n'existe plus dans l'annuaire de l'entreprise.";
	if (reply.error == "ambiguous")
		return "Plusieurs contacts ont ce numéro et ce nom : supprimez-le depuis le portail.";
	if (reply.error == "too_many_contacts") return "Trop de modifications en peu de temps. Réessayez plus tard.";
	if (reply.error == "contacts_disabled") return "Les contacts partagés ne sont pas activés sur le serveur.";
	if (reply.error == "forbidden")
		return "Seuls les membres du groupe des contacts d'équipe peuvent créer ou supprimer un contact d'équipe.";
	if (reply.status == 401) return "Le serveur a refusé l'identification de ce poste.";
	return "Le serveur ne répond pas. Réessayez.";
}
