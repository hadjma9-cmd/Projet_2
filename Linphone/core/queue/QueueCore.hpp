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

#ifndef QUEUE_CORE_H_
#define QUEUE_CORE_H_

#include "core/fusion/FusionClient.hpp"
#include "tool/AbstractObject.hpp"

#include <QDateTime>
#include <QJsonObject>
#include <QObject>
#include <QSharedPointer>
#include <QStringList>
#include <QVariantList>

// Files d'attente du Centre d'appels FusionPBX pour le compte par défaut, par le service fusion-files du serveur
// (https://<domaine>/gamaphone/v1/files). Aucune relecture périodique : à la première connexion du compte, au retour
// sur l'application (au plus toutes les 10 minutes) et à l'ouverture du menu du statut ; chaque action renvoie l'état
// complet. Les demandes sont signées avec le HA1 du compte SIP : le mot de passe ne circule jamais.
class QueueCore : public QObject, public AbstractObject {
	Q_OBJECT
	// Le poste est agent du Centre d'appels (sinon rien n'est affiché).
	Q_PROPERTY(bool agent READ isAgent NOTIFY stateChanged)
	// État global de l'agent : Available, Available (On Demand), On Break, Logged Out...
	Q_PROPERTY(QString agentStatus READ getAgentStatus NOTIFY stateChanged)
	// [{id, name, number, connected}], dans l'ordre du serveur.
	Q_PROPERTY(QVariantList queues READ getQueues NOTIFY stateChanged)
	Q_PROPERTY(int connectedCount READ getConnectedCount NOTIFY stateChanged)
	Q_PROPERTY(int queueCount READ getQueueCount NOTIFY stateChanged)
	// Files dont le changement attend la réponse du serveur.
	Q_PROPERTY(QStringList pendingQueues READ getPendingQueues NOTIFY pendingQueuesChanged)
	Q_PROPERTY(QString errorText READ getErrorText NOTIFY errorTextChanged)

public:
	static QSharedPointer<QueueCore> create(QSharedPointer<FusionClient> client);
	QueueCore(QSharedPointer<FusionClient> client);
	~QueueCore();
	void setSelf(QSharedPointer<QueueCore> me);

	bool isAgent() const;
	QString getAgentStatus() const;
	QVariantList getQueues() const;
	int getConnectedCount() const;
	int getQueueCount() const;
	QStringList getPendingQueues() const;
	QString getErrorText() const;

	// Ouverture du menu du statut : relecture immédiate.
	Q_INVOKABLE void refresh();
	Q_INVOKABLE void setQueueConnected(const QString &queueId, bool connected);

signals:
	void stateChanged();
	void pendingQueuesChanged();
	void errorTextChanged();

private:
	enum class ReadMode {
		Always,     // ouverture du menu
		IfStale,    // retour sur l'application : au plus toutes les 10 minutes
		IfNeverRead // compte connecté ou changé : une fois
	};

	bool adoptAccount(const FusionClient::Credentials &credentials);
	void read(ReadMode mode);
	void applyState(const QJsonObject &state);
	void clearState();
	void setPending(const QString &queueId, bool pending);
	void setErrorText(const QString &text);

	QSharedPointer<SafeConnection<QueueCore, CoreModel>> mCoreModelConnection;
	QSharedPointer<FusionClient> mClient;

	QString mAccountKey; // poste@domaine de l'état affiché
	int mGeneration = 0; // change avec le compte : les réponses d'un ancien compte sont ignorées
	bool mAgent = false;
	QString mAgentStatus;
	QVariantList mQueues;
	int mConnectedCount = 0;
	QStringList mPendingQueues;
	QString mErrorText;

	bool mReading = false;
	bool mHaveRead = false; // une lecture a réussi pour ce compte
	QDateTime mLastAttempt; // dernière lecture envoyée, réussie ou non

	DECLARE_ABSTRACT_OBJECT
};

#endif
