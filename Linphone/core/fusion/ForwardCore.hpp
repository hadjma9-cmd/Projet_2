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

#ifndef FORWARD_CORE_H_
#define FORWARD_CORE_H_

#include "core/fusion/FusionClient.hpp"
#include "tool/AbstractObject.hpp"

#include <QDateTime>
#include <QJsonObject>
#include <QObject>
#include <QSharedPointer>

// Renvoi de tous les appels du poste (Paramètres > Transfert d'appel), appliqué par le serveur
// (https://<domaine>/gamaphone/v1/renvoi, renvoi « Tous les appels » de FusionPBX) : il marche appareils éteints et se
// voit sur tous les appareils du poste. Relu à la connexion du compte, au retour sur l'application et à l'ouverture de
// la page ; aucune relecture périodique.
class ForwardCore : public QObject, public AbstractObject {
	Q_OBJECT
	Q_PROPERTY(bool loaded READ isLoaded NOTIFY changed)
	Q_PROPERTY(bool enabled READ isEnabled NOTIFY changed)
	Q_PROPERTY(QString destination READ getDestination NOTIFY changed)
	// Messagerie du poste (code *99 de FusionPBX), pour « Ma messagerie ».
	Q_PROPERTY(QString voicemail READ getVoicemail NOTIFY changed)
	Q_PROPERTY(bool saving READ isSaving NOTIFY savingChanged)
	Q_PROPERTY(QString errorText READ getErrorText NOTIFY errorTextChanged)

public:
	static QSharedPointer<ForwardCore> create(QSharedPointer<FusionClient> client);
	ForwardCore(QSharedPointer<FusionClient> client);
	~ForwardCore();
	void setSelf(QSharedPointer<ForwardCore> me);

	bool isLoaded() const;
	bool isEnabled() const;
	QString getDestination() const;
	QString getVoicemail() const;
	bool isSaving() const;
	QString getErrorText() const;

	// Ouverture de la page : relecture.
	Q_INVOKABLE void refresh();
	// Enregistrer : le serveur répond avec le renvoi appliqué. Arrêt sans destination : la sienne est gardée.
	Q_INVOKABLE void save(bool enabled, const QString &destination);

signals:
	void changed();
	void savingChanged();
	void errorTextChanged();
	void saved();

private:
	enum class ReadMode {
		Always,     // ouverture de la page
		IfStale,    // retour sur l'application : au plus toutes les 30 secondes
		IfNeverRead // compte connecté ou changé : une fois
	};
	bool adoptAccount(const FusionClient::Credentials &credentials);
	void read(ReadMode mode);
	void apply(const QJsonObject &answer);
	void setSaving(bool saving);
	void setErrorText(const QString &text);

	QSharedPointer<SafeConnection<ForwardCore, CoreModel>> mCoreModelConnection;
	QSharedPointer<FusionClient> mClient;
	QString mAccountKey; // poste@domaine du renvoi connu
	int mGeneration = 0; // change avec le compte : les réponses d'un ancien compte sont ignorées
	bool mLoaded = false;
	bool mEnabled = false;
	QString mDestination;
	QString mVoicemail;
	bool mSaving = false;
	QString mErrorText;
	bool mReading = false;
	QDateTime mLastAttempt; // dernière lecture envoyée, réussie ou non

	DECLARE_ABSTRACT_OBJECT
};

#endif
