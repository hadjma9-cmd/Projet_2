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

#ifndef FUSION_CLIENT_H_
#define FUSION_CLIENT_H_

#include "tool/AbstractObject.hpp"
#include "tool/thread/SafeConnection.hpp"

#include <QJsonObject>
#include <QNetworkRequest>
#include <QObject>
#include <QSharedPointer>
#include <functional>

class QNetworkAccessManager;
class QNetworkReply;

// Demandes au service fusion-files du serveur FusionPBX (https://<domaine>/gamaphone/...), signées avec le HA1 du
// compte SIP par défaut : le mot de passe ne circule jamais, et le serveur en déduit le poste et son domaine. Partagé
// par les files d'attente et les contacts partagés.
class FusionClient : public QObject, public AbstractObject {
	Q_OBJECT
public:
	struct Credentials {
		QString user; // poste : partie utilisateur de l'adresse SIP
		QString domain;
		QByteArray ha1; // MD5("poste:domaine:mot de passe") en hexadécimal
		bool isValid() const {
			return !user.isEmpty() && !domain.isEmpty() && !ha1.isEmpty();
		}
		// poste@domaine, vide si le compte n'est pas connecté.
		QString key() const {
			return isValid() ? user + "@" + domain : QString();
		}
	};
	struct Reply {
		int status = 0; // code HTTP, 0 si le serveur n'a pas répondu
		QJsonObject answer;
		QString error; // champ « error » de la réponse
		QString networkError;
	};
	using Callback = std::function<void(const Reply &)>;

	static QSharedPointer<FusionClient> create();
	FusionClient();
	~FusionClient();
	void setSelf(QSharedPointer<FusionClient> me);

	// Identifiants du compte par défaut, lus dans le fil du SDK, puis `ready` dans le fil de l'interface.
	void withCredentials(std::function<void(const Credentials &)> ready);
	// Demande signée ; `done` est appelé dans le fil de l'interface. Horloge du PC décalée : recalage sur celle du
	// serveur et un nouvel essai, sans que l'appelant s'en occupe. `timeoutMs` : silence maximal du serveur (0 = 10 s).
	void send(const Credentials &credentials,
	          const QByteArray &method,
	          const QString &path,
	          const QByteArray &body,
	          Callback done,
	          int timeoutMs = 0);
	// Connexion signée qui reste ouverte (tableau de supervision en direct) ; à libérer par l'appelant.
	QNetworkReply *openStream(const Credentials &credentials, const QString &path);
	// Heure du serveur moins heure du PC, en secondes (recalée à la première demande refusée pour l'horloge).
	qint64 clockOffset() const;

private:
	QNetworkRequest signedRequest(const Credentials &credentials,
	                              const QByteArray &method,
	                              const QString &path,
	                              const QByteArray &body) const;
	static Credentials readCredentials();
	void sendOnce(const Credentials &credentials,
	              const QByteArray &method,
	              const QString &path,
	              const QByteArray &body,
	              Callback done,
	              bool clockRetried,
	              int timeoutMs);

	QSharedPointer<SafeConnection<FusionClient, CoreModel>> mCoreModelConnection;
	QNetworkAccessManager *mNetwork = nullptr;
	qint64 mClockOffset = 0; // heure du serveur moins heure du PC, en secondes

	DECLARE_ABSTRACT_OBJECT
};

#endif
