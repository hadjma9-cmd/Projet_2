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

#ifndef SHARED_CONTACTS_CORE_H_
#define SHARED_CONTACTS_CORE_H_

#include "core/fusion/FusionClient.hpp"
#include "tool/AbstractObject.hpp"

#include <QDateTime>
#include <QObject>
#include <QSharedPointer>
#include <QStringList>

// Contacts partagés avec l'entreprise : créés et supprimés dans FusionPBX par le service fusion-files, dans le domaine
// du compte (jamais un autre). Ils reviennent ensuite dans Gamaphone par l'annuaire, comme ceux saisis dans le portail.
// Seuls les postes du groupe FusionPBX des contacts d'équipe peuvent les créer et les supprimer (le serveur le
// vérifie ; ici, on cache seulement ce qu'il refuserait). Ce droit est lu à la connexion du compte et au retour sur
// l'application (au plus toutes les 10 minutes), sans relecture périodique.
class SharedContactsCore : public QObject, public AbstractObject {
	Q_OBJECT
	// Une demande attend la réponse du serveur.
	Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged)
	// Ce poste peut créer et supprimer les contacts d'équipe. Faux tant que le serveur ne l'a pas confirmé.
	Q_PROPERTY(bool teamContactsAllowed READ isTeamContactsAllowed NOTIFY teamContactsAllowedChanged)

public:
	static QSharedPointer<SharedContactsCore> create(QSharedPointer<FusionClient> client);
	SharedContactsCore(QSharedPointer<FusionClient> client);
	~SharedContactsCore();
	void setSelf(QSharedPointer<SharedContactsCore> me);

	bool isBusy() const;
	bool isTeamContactsAllowed() const;
	// Relecture des droits du poste (ouverture du formulaire de création).
	Q_INVOKABLE void refreshRights();

	// force : créer même si un des numéros existe déjà dans le domaine (après confirmation).
	Q_INVOKABLE void
	createContact(const QString &givenName, const QString &familyName, const QStringList &phones, bool force);
	// Le contact du domaine qui a un de ces numéros (le nom départage s'il y en a plusieurs).
	Q_INVOKABLE void deleteContact(const QString &name, const QStringList &phones);

signals:
	void busyChanged();
	void teamContactsAllowedChanged();
	void contactCreated(QString name);
	// Un des numéros appartient déjà à ce contact du domaine : proposer de créer quand même.
	void duplicateFound(QString name, QString number);
	void contactDeleted(QString name);
	void failed(QString message);

private:
	enum class ReadMode {
		Always,     // demande de l'interface
		IfStale,    // retour sur l'application : au plus toutes les 10 minutes
		IfNeverRead // compte connecté ou changé : une fois
	};

	void post(const QString &path, const QByteArray &body, FusionClient::Callback done);
	void setBusy(bool busy);
	void setTeamContactsAllowed(bool allowed);
	void readRights(ReadMode mode);
	static QString errorMessage(const FusionClient::Reply &reply);

	QSharedPointer<SafeConnection<SharedContactsCore, CoreModel>> mCoreModelConnection;
	QSharedPointer<FusionClient> mClient;
	bool mBusy = false;
	bool mTeamContactsAllowed = false;
	QString mRightsAccountKey; // poste@domaine des droits connus
	int mRightsGeneration = 0; // change avec le compte : les réponses d'un ancien compte sont ignorées
	bool mReadingRights = false;
	bool mRightsRead = false;
	QDateTime mLastRightsAttempt; // dernière lecture envoyée, réussie ou non

	DECLARE_ABSTRACT_OBJECT
};

#endif
