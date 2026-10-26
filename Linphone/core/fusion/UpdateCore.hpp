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

#ifndef UPDATE_CORE_H_
#define UPDATE_CORE_H_

#include "core/fusion/FusionClient.hpp"
#include "tool/AbstractObject.hpp"

#include <QCryptographicHash>
#include <QFile>
#include <QObject>
#include <QSharedPointer>

class QNetworkAccessManager;
class QNetworkReply;

// Mise à jour de Gamaphone, obligatoire. L'application demande au serveur du compte (service fusion-files) si
// l'installeur qu'il propose est plus récent qu'elle ; si oui, elle le télécharge, vérifie sa taille et son empreinte,
// le lance et se ferme. L'utilisateur ne peut pas remettre à plus tard, sauf si la mise à jour échoue : personne ne
// doit rester sans téléphone à cause d'un téléchargement impossible.
// Demandé une fois par lancement : dès que le compte est connecté (le serveur ne répond qu'à un compte connecté), et de
// nouveau à la connexion suivante tant que le serveur n'a pas répondu. Aucune demande périodique.
class UpdateCore : public QObject, public AbstractObject {
	Q_OBJECT
	// idle : rien à faire ; available : mise à jour à installer ; downloading ; launching : l'installeur démarre ;
	// failed : échec, voir errorText.
	Q_PROPERTY(QString state READ getState NOTIFY stateChanged)
	Q_PROPERTY(QString errorText READ getErrorText NOTIFY stateChanged)
	Q_PROPERTY(qreal progress READ getProgress NOTIFY progressChanged)
	Q_PROPERTY(int receivedMb READ getReceivedMb NOTIFY progressChanged)
	Q_PROPERTY(int totalMb READ getTotalMb NOTIFY progressChanged)
	// Verification demandee par l'utilisateur (page Aide) en cours.
	Q_PROPERTY(bool checking READ isUserChecking NOTIFY userCheckingChanged)

public:
	static QSharedPointer<UpdateCore> create(QSharedPointer<FusionClient> client);
	UpdateCore(QSharedPointer<FusionClient> client);
	~UpdateCore();
	void setSelf(QSharedPointer<UpdateCore> me);

	QString getState() const;
	QString getErrorText() const;
	qreal getProgress() const;
	int getReceivedMb() const;
	int getTotalMb() const;
	bool isUserChecking() const;

	// Demande au serveur. requestedByUser : dire aussi quand il n'y a rien à installer, ou que la demande a échoué.
	void check(bool requestedByUser);
	// Télécharge puis lance l'installeur ; après un échec, redemande d'abord au serveur.
	Q_INVOKABLE void start();
	// Pendant le téléchargement : l'arrête, la mise à jour reste à faire.
	Q_INVOKABLE void cancel();
	// Après un échec seulement : continuer avec la version actuelle, jusqu'au prochain lancement.
	Q_INVOKABLE void dismiss();

signals:
	void stateChanged();
	void progressChanged();
	void userCheckingChanged();
	// Reponse a une verification demandee par l'utilisateur, a afficher sous le bouton (ok : a jour ou mise a jour
	// trouvee ; sinon echec).
	void checkFinished(QString message, bool ok);

private:
	void setState(const QString &state, const QString &errorText = QString());
	void setUserChecking(bool checking);
	void fail(const QString &message);
	void download();
	void receive();
	void finishDownload();
	void launch(const QString &path);

	QSharedPointer<SafeConnection<UpdateCore, CoreModel>> mCoreModelConnection;
	QSharedPointer<FusionClient> mClient;
	QNetworkAccessManager *mNetwork = nullptr;
	QNetworkReply *mReply = nullptr;
	QString mState = QStringLiteral("idle");
	QString mErrorText;
	QString mDomain;    // serveur du compte, d'où vient l'installeur
	QByteArray mSha256; // empreinte attendue, en hexadécimal
	qint64 mSize = 0;   // taille attendue
	qint64 mReceived = 0;
	int mShownPercent = -1;
	bool mCancelled = false;
	bool mStartWhenReady = false; // nouvel essai : télécharger dès que le serveur a répondu
	bool mChecking = false;       // demande au serveur en cours
	bool mUserChecking = false;   // dont une demandee par l'utilisateur
	bool mAnswered = false;       // le serveur a répondu depuis le lancement : plus de demande automatique
	QFile mFile;
	QCryptographicHash mHash{QCryptographicHash::Sha256};

	DECLARE_ABSTRACT_OBJECT
};

#endif
