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

#ifndef SUPERVISION_CORE_H_
#define SUPERVISION_CORE_H_

#include "core/fusion/FusionClient.hpp"
#include "tool/AbstractObject.hpp"

#include <QObject>
#include <QPointer>
#include <QSharedPointer>
#include <QTimer>
#include <QVariantList>

class QNetworkReply;

// Tableau des files en direct : tant que la page est affichée (start / stop), une connexion reste ouverte vers le
// serveur du compte (fusion-files, /gamaphone/v1/supervision/direct), qui envoie l'état complet de toutes les files
// du domaine à chaque changement. Aucune relecture périodique : les durées avancent dans la page, à partir des heures
// reçues. Coupure : nouvelle connexion, de plus en plus espacée (2 s, puis jusqu'à 30 s).
class SupervisionCore : public QObject, public AbstractObject {
	Q_OBJECT
	// Files du domaine : id, name, number, calls [{id, number, name, state, since, agents}],
	// agents [{id, name, extension, state, since, with}]. Heures en secondes depuis 1970 (heure du serveur).
	Q_PROPERTY(QVariantList queues READ getQueues NOTIFY queuesChanged)
	// Heure du serveur moins heure du PC, en secondes : durée = maintenant + écart - heure reçue.
	Q_PROPERTY(qint64 clockOffset READ getClockOffset NOTIFY queuesChanged)
	// Connexion en direct établie (état reçu au moins une fois depuis la dernière coupure).
	Q_PROPERTY(bool live READ isLive NOTIFY liveChanged)
	// Un état a déjà été reçu (sinon : chargement).
	Q_PROPERTY(bool loaded READ isLoaded NOTIFY queuesChanged)

public:
	static QSharedPointer<SupervisionCore> create(QSharedPointer<FusionClient> client);
	SupervisionCore(QSharedPointer<FusionClient> client);
	~SupervisionCore();

	QVariantList getQueues() const;
	qint64 getClockOffset() const;
	bool isLive() const;
	bool isLoaded() const;

	// Page du tableau affichée / quittée.
	Q_INVOKABLE void start();
	Q_INVOKABLE void stop();

signals:
	void queuesChanged();
	void liveChanged();

private:
	void connectStream();
	void scheduleReconnect();
	void readStream();
	void applyEvent(const QByteArray &data);
	void setLive(bool live);

	QSharedPointer<FusionClient> mClient;
	QPointer<QNetworkReply> mReply;
	QTimer mReconnect;
	QByteArray mBuffer;
	QVariantList mQueues;
	qint64 mClockOffset = 0;
	int mRetryDelayMs = 2000;
	bool mWanted = false;
	bool mLive = false;
	bool mLoaded = false;

	DECLARE_ABSTRACT_OBJECT
};

#endif
