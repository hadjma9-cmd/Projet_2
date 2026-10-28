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

#include "ForwardCore.hpp"
#include "core/App.hpp"
#include "model/core/CoreModel.hpp"

#include <QJsonDocument>

DEFINE_ABSTRACT_OBJECT(ForwardCore)

static const QString ServicePath = QStringLiteral("/gamaphone/v1/renvoi");
static constexpr qint64 RereadDelaySecs = 30;

QSharedPointer<ForwardCore> ForwardCore::create(QSharedPointer<FusionClient> client) {
	auto sharedPointer = QSharedPointer<ForwardCore>(new ForwardCore(client), &QObject::deleteLater);
	sharedPointer->setSelf(sharedPointer);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

ForwardCore::ForwardCore(QSharedPointer<FusionClient> client) : QObject(nullptr), mClient(client) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
}

ForwardCore::~ForwardCore() {
}

void ForwardCore::setSelf(QSharedPointer<ForwardCore> me) {
	mCoreModelConnection = SafeConnection<ForwardCore, CoreModel>::create(me, CoreModel::getInstance());
	// Compte connecté (démarrage, réseau retrouvé) : première lecture, pour le rappel de la fenêtre principale.
	mCoreModelConnection->makeConnectToModel(
	    &CoreModel::accountRegistrationStateChanged,
	    [this](const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::Account> &account,
	           linphone::RegistrationState state, const std::string &message) {
		    if (state != linphone::RegistrationState::Ok || account != core->getDefaultAccount()) return;
		    mCoreModelConnection->invokeToCore([this]() { read(ReadMode::IfNeverRead); });
	    });
	mCoreModelConnection->makeConnectToModel(&CoreModel::defaultAccountChanged, [this]() {
		mCoreModelConnection->invokeToCore([this]() { read(ReadMode::IfNeverRead); });
	});
	// Retour sur l'application : le renvoi a pu être changé ailleurs (portail, autre appareil).
	connect(App::getInstance(), &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
		if (state == Qt::ApplicationActive) read(ReadMode::IfStale);
	});
	read(ReadMode::IfNeverRead);
}

bool ForwardCore::isLoaded() const {
	return mLoaded;
}

bool ForwardCore::isEnabled() const {
	return mEnabled;
}

QString ForwardCore::getDestination() const {
	return mDestination;
}

QString ForwardCore::getVoicemail() const {
	return mVoicemail;
}

bool ForwardCore::isSaving() const {
	return mSaving;
}

QString ForwardCore::getErrorText() const {
	return mErrorText;
}

void ForwardCore::setSaving(bool saving) {
	if (mSaving == saving) return;
	mSaving = saving;
	emit savingChanged();
}

void ForwardCore::setErrorText(const QString &text) {
	if (mErrorText == text) return;
	mErrorText = text;
	emit errorTextChanged();
}

void ForwardCore::refresh() {
	read(ReadMode::Always);
}

// Changement de compte : le renvoi connu est celui de l'ancien. Faux si le compte n'est pas connecté.
bool ForwardCore::adoptAccount(const FusionClient::Credentials &credentials) {
	const QString key = credentials.key();
	if (key != mAccountKey) {
		mAccountKey = key;
		++mGeneration;
		mReading = false;
		mLastAttempt = QDateTime();
		mLoaded = false;
		mEnabled = false;
		mDestination.clear();
		mVoicemail.clear();
		emit changed();
	}
	return credentials.isValid();
}

void ForwardCore::read(ReadMode mode) {
	if (mReading) return;
	mReading = true;
	mClient->withCredentials([this, mode](const FusionClient::Credentials &credentials) {
		const bool connected = adoptAccount(credentials);
		if (!connected || (mode == ReadMode::IfNeverRead && mLoaded) ||
		    (mode == ReadMode::IfStale && mLastAttempt.isValid() &&
		     mLastAttempt.secsTo(QDateTime::currentDateTimeUtc()) < RereadDelaySecs)) {
			mReading = false;
			return;
		}
		mReading = true;
		mLastAttempt = QDateTime::currentDateTimeUtc();
		const int generation = mGeneration;
		mClient->send(credentials, "GET", ServicePath, QByteArray(),
		              [this, generation](const FusionClient::Reply &reply) {
			              if (generation != mGeneration) return; // compte changé entre-temps
			              mReading = false;
			              // Lecture en échec : on garde le renvoi affiché.
			              if (reply.status == 200) apply(reply.answer);
		              });
	});
}

void ForwardCore::save(bool enabled, const QString &destination) {
	if (mSaving) return;
	setSaving(true);
	setErrorText(QString());
	const QByteArray body = QJsonDocument(QJsonObject{{"enabled", enabled}, {"destination", destination.trimmed()}})
	                            .toJson(QJsonDocument::Compact);
	mClient->withCredentials([this, body](const FusionClient::Credentials &credentials) {
		if (!adoptAccount(credentials)) {
			setSaving(false);
			setErrorText(QStringLiteral("Gamaphone n'est pas connecté : le renvoi n'a pas pu être enregistré."));
			return;
		}
		const int generation = mGeneration;
		mClient->send(credentials, "POST", ServicePath, body, [this, generation](const FusionClient::Reply &reply) {
			if (generation != mGeneration) return;
			setSaving(false);
			if (reply.status == 200) {
				apply(reply.answer);
				emit saved();
				return;
			}
			lWarning() << log().arg("Forward not saved on the server:") << reply.status << reply.error;
			if (reply.error == QLatin1String("destination"))
				setErrorText(QStringLiteral("Ce numéro n'est pas valide."));
			else if (reply.error == QLatin1String("self"))
				setErrorText(QStringLiteral("Impossible de renvoyer vos appels vers votre propre poste."));
			else setErrorText(QStringLiteral("Le renvoi n'a pas pu être enregistré. Réessayez dans un instant."));
		});
	});
}

void ForwardCore::apply(const QJsonObject &answer) {
	mLoaded = true;
	mEnabled = answer.value("enabled").toBool();
	mDestination = answer.value("destination").toString();
	mVoicemail = answer.value("voicemail").toString();
	emit changed();
}
