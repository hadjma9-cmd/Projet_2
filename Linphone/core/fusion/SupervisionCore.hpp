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
#include <QVariantMap>

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
	// Appel en train d'etre pris par ce poste (« Prendre »), vide sinon.
	Q_PROPERTY(QString takingCall READ getTakingCall NOTIFY takingCallChanged)
	// Poste de ce Gamaphone : seuls les appels des files dont il est agent peuvent etre pris.
	Q_PROPERTY(QString myExtension READ getMyExtension NOTIFY myExtensionChanged)
	// Onglet Statistiques : derniere reponse du serveur (period, since, totals, queues, agents ; durees en secondes),
	// lecture en cours, et message d'echec.
	Q_PROPERTY(QVariantMap stats READ getStats NOTIFY statsChanged)
	Q_PROPERTY(bool statsLoading READ isStatsLoading NOTIFY statsChanged)
	Q_PROPERTY(QString statsError READ getStatsError NOTIFY statsChanged)

public:
	static QSharedPointer<SupervisionCore> create(QSharedPointer<FusionClient> client);
	SupervisionCore(QSharedPointer<FusionClient> client);
	~SupervisionCore();

	QVariantList getQueues() const;
	qint64 getClockOffset() const;
	bool isLive() const;
	bool isLoaded() const;
	QString getTakingCall() const;
	QString getMyExtension() const;
	QVariantMap getStats() const;
	bool isStatsLoading() const;
	QString getStatsError() const;

	// Page du tableau affichée / quittée.
	Q_INVOKABLE void start();
	Q_INVOKABLE void stop();
	// « Prendre » : le serveur fait sonner ce poste, qui decroche tout seul (appel portant le jeton envoye), puis
	// l'appelant quitte la file et le rejoint.
	Q_INVOKABLE void take(const QString &callId);
	// Appel entrant portant ce jeton : c'est l'appel demande par « Prendre », a decrocher sans attendre. Une seule
	// fois.
	bool consumePickupToken(const QString &token);
	// Statistiques de la periode : « day » (depuis minuit), « week » (7 jours), « month » (30 jours).
	Q_INVOKABLE void loadStats(const QString &period);

signals:
	void queuesChanged();
	void liveChanged();
	void takingCallChanged();
	void myExtensionChanged();
	void statsChanged();
	// « Prendre » n'a pas abouti : message a afficher.
	void takeFailed(QString message);

private:
	void connectStream();
	void scheduleReconnect();
	void readStream();
	void applyEvent(const QByteArray &data);
	void setLive(bool live);
	void setTakingCall(const QString &callId);

	QSharedPointer<FusionClient> mClient;
	QPointer<QNetworkReply> mReply;
	QTimer mReconnect;
	QTimer mWatchdog; // rien recu depuis 60 s (ni etat, ni signal de vie) : connexion consideree morte
	QByteArray mBuffer;
	QVariantList mQueues;
	qint64 mClockOffset = 0;
	int mRetryDelayMs = 2000;
	bool mWanted = false;
	bool mLive = false;
	bool mLoaded = false;
	QString mTakingCall;
	QString mMyExtension;
	QVariantMap mStats;
	QString mStatsError;
	QString mStatsPeriod; // periode demandee en dernier : une reponse plus ancienne est ignoree
	bool mStatsLoading = false;
	QString mPickupToken;
	qint64 mPickupTokenExpiry = 0; // ms depuis 1970

	DECLARE_ABSTRACT_OBJECT
};

#endif
