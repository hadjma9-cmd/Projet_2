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

#ifndef STATUS_CORE_H_
#define STATUS_CORE_H_

#include "core/fusion/FusionClient.hpp"
#include "tool/AbstractObject.hpp"
#include "tool/LinphoneEnums.hpp"

#include <QDateTime>
#include <QJsonObject>
#include <QObject>
#include <QSharedPointer>

// Statut du poste (disponible, occupé, absent, ne pas déranger, hors ligne), le même sur tous ses appareils. Il est
// gardé par le service fusion-files du serveur (https://<domaine>/gamaphone/v1/statut), qui l'applique aussi aux appels
// (« ne pas déranger » de FusionPBX, pause dans les files d'attente) et le conserve, appareils éteints compris.
// Le choix fait dans le menu du statut part au serveur. Le statut est relu à la connexion du compte, au retour sur
// l'application, à l'ouverture du menu, et quand le serveur annonce que la présence du poste a changé (choix fait sur
// un autre appareil). Aucune relecture périodique.
class StatusCore : public QObject, public AbstractObject {
	Q_OBJECT
public:
	static QSharedPointer<StatusCore> create(QSharedPointer<FusionClient> client);
	StatusCore(QSharedPointer<FusionClient> client);
	~StatusCore();
	void setSelf(QSharedPointer<StatusCore> me);

	// Ouverture du menu du statut : relecture.
	Q_INVOKABLE void refresh();
	// Choix de l'utilisateur sur cet appareil (AccountCore), envoyé au serveur.
	void choose(LinphoneEnums::Presence presence);

private:
	enum class ReadMode {
		Always,     // ouverture du menu, présence du poste changée ailleurs
		IfStale,    // retour sur l'application : au plus toutes les 30 secondes
		IfNeverRead // compte connecté ou changé : une fois
	};

	bool adoptAccount(const FusionClient::Credentials &credentials);
	void read(ReadMode mode);
	void apply(const QJsonObject &answer);
	static QString toServer(LinphoneEnums::Presence presence);
	static LinphoneEnums::Presence fromServer(const QString &status);

	QSharedPointer<SafeConnection<StatusCore, CoreModel>> mCoreModelConnection;
	QSharedPointer<FusionClient> mClient;

	QString mAccountKey;   // poste@domaine du statut connu
	int mGeneration = 0;   // change avec le compte : les réponses d'un ancien compte sont ignorées
	QString mServerStatus; // dernier statut connu du serveur
	bool mReading = false;
	bool mHaveRead = false;
	QDateTime mLastAttempt; // dernière lecture envoyée, réussie ou non

	DECLARE_ABSTRACT_OBJECT
};

#endif
