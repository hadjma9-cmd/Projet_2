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

#include <QJsonArray>
#include <QJsonDocument>

DEFINE_ABSTRACT_OBJECT(SharedContactsCore)

QSharedPointer<SharedContactsCore> SharedContactsCore::create(QSharedPointer<FusionClient> client) {
	auto sharedPointer = QSharedPointer<SharedContactsCore>(new SharedContactsCore(client), &QObject::deleteLater);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

SharedContactsCore::SharedContactsCore(QSharedPointer<FusionClient> client) : QObject(nullptr), mClient(client) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
}

SharedContactsCore::~SharedContactsCore() {
}

bool SharedContactsCore::isBusy() const {
	return mBusy;
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
		else emit failed(errorMessage(reply));
	});
}

void SharedContactsCore::deleteContact(const QString &name, const QStringList &phones) {
	if (mBusy) return;
	const QByteArray body =
	    QJsonDocument(QJsonObject{{"name", name.trimmed()}, {"phones", QJsonArray::fromStringList(phones)}})
	        .toJson(QJsonDocument::Compact);
	post("/gamaphone/v1/contacts/delete", body, [this, name](const FusionClient::Reply &reply) {
		if (reply.status == 200) emit contactDeleted(reply.answer.value("name").toString(name));
		else emit failed(errorMessage(reply));
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
	if (reply.status == 401) return "Le serveur a refusé l'identification de ce poste.";
	return "Le serveur ne répond pas. Réessayez.";
}
