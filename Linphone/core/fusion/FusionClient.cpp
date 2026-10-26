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

#include "FusionClient.hpp"
#include "core/App.hpp"
#include "model/core/CoreModel.hpp"
#include "tool/Utils.hpp"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QJsonDocument>
#include <QMessageAuthenticationCode>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

DEFINE_ABSTRACT_OBJECT(FusionClient)

static constexpr int RequestTimeoutMs = 10000;

QSharedPointer<FusionClient> FusionClient::create() {
	auto sharedPointer = QSharedPointer<FusionClient>(new FusionClient(), &QObject::deleteLater);
	sharedPointer->setSelf(sharedPointer);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

FusionClient::FusionClient() : QObject(nullptr) {
	mustBeInMainThread(getClassName());
	mNetwork = new QNetworkAccessManager(this);
}

FusionClient::~FusionClient() {
}

void FusionClient::setSelf(QSharedPointer<FusionClient> me) {
	mCoreModelConnection = SafeConnection<FusionClient, CoreModel>::create(me, CoreModel::getInstance());
}

// Identifiants SIP du compte par défaut, s'il est connecté. Le HA1 enregistré par le moteur sert tel quel quand il a
// été calculé pour ce domaine ; sinon il est recalculé depuis le mot de passe.
FusionClient::Credentials FusionClient::readCredentials() {
	mustBeInLinphoneThread(QStringLiteral("[FusionClient] readCredentials"));
	Credentials credentials;
	auto core = CoreModel::getInstance()->getCore();
	auto account = core ? core->getDefaultAccount() : nullptr;
	if (!account) return credentials;
	auto state = account->getState();
	if (state != linphone::RegistrationState::Ok && state != linphone::RegistrationState::Refreshing)
		return credentials;
	auto identity = account->getParams()->getIdentityAddress();
	auto authInfo = account->findAuthInfo();
	if (!identity || !authInfo) return credentials;

	credentials.user = Utils::coreStringToAppString(identity->getUsername());
	credentials.domain = Utils::coreStringToAppString(identity->getDomain()).toLower();
	const QString algorithm = Utils::coreStringToAppString(authInfo->getAlgorithm());
	const QString realm = Utils::coreStringToAppString(authInfo->getRealm());
	const QString ha1 = Utils::coreStringToAppString(authInfo->getHa1());
	const QString password = Utils::coreStringToAppString(authInfo->getPassword());
	if (!ha1.isEmpty() && (algorithm.isEmpty() || algorithm.compare("MD5", Qt::CaseInsensitive) == 0) &&
	    (realm.isEmpty() || realm.compare(credentials.domain, Qt::CaseInsensitive) == 0))
		credentials.ha1 = ha1.toLower().toUtf8();
	else if (!password.isEmpty())
		credentials.ha1 =
		    QCryptographicHash::hash((credentials.user + ":" + credentials.domain + ":" + password).toUtf8(),
		                             QCryptographicHash::Md5)
		        .toHex();
	return credentials;
}

void FusionClient::withCredentials(std::function<void(const Credentials &)> ready) {
	mCoreModelConnection->invokeToModel([this, ready]() {
		const Credentials credentials = readCredentials();
		mCoreModelConnection->invokeToCore([ready, credentials]() { ready(credentials); });
	});
}

void FusionClient::send(const Credentials &credentials,
                        const QByteArray &method,
                        const QString &path,
                        const QByteArray &body,
                        Callback done,
                        int timeoutMs) {
	sendOnce(credentials, method, path, body, done, false, timeoutMs > 0 ? timeoutMs : RequestTimeoutMs);
}

// Demande signée : HMAC-SHA256, clé = HA1, message = méthode, chemin, heure et empreinte du corps (voir le service).
QNetworkRequest FusionClient::signedRequest(const Credentials &credentials,
                                            const QByteArray &method,
                                            const QString &path,
                                            const QByteArray &body) const {
	QUrl url;
	url.setScheme("https");
	url.setHost(credentials.domain);
	url.setPath(path);
	QNetworkRequest request(url);
	request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
	const QByteArray time = QByteArray::number(QDateTime::currentSecsSinceEpoch() + mClockOffset);
	const QByteArray bodyHash = QCryptographicHash::hash(body, QCryptographicHash::Sha256).toHex();
	const QByteArray message = method + '\n' + path.toUtf8() + '\n' + time + '\n' + bodyHash;
	request.setRawHeader("X-Gama-User", credentials.key().toUtf8());
	request.setRawHeader("X-Gama-Time", time);
	// Version de Gamaphone, pour les journaux du serveur et l'e-mail des journaux envoyés au support (non signée).
	request.setRawHeader("X-Gama-Version", QCoreApplication::applicationVersion().toUtf8());
	request.setRawHeader(
	    "X-Gama-Signature",
	    QMessageAuthenticationCode::hash(message, credentials.ha1, QCryptographicHash::Sha256).toHex());
	return request;
}

// Connexion en direct (GET signé, réponse « text/event-stream ») : pas de délai maximal, le serveur envoie un signal
// de vie régulier. L'appelant lit la réponse au fil de l'eau et la libère.
QNetworkReply *FusionClient::openStream(const Credentials &credentials, const QString &path) {
	QNetworkRequest request = signedRequest(credentials, "GET", path, QByteArray());
	request.setRawHeader("Accept", "text/event-stream");
	return mNetwork->get(request);
}

qint64 FusionClient::clockOffset() const {
	return mClockOffset;
}

void FusionClient::sendOnce(const Credentials &credentials,
                            const QByteArray &method,
                            const QString &path,
                            const QByteArray &body,
                            Callback done,
                            bool clockRetried,
                            int timeoutMs) {
	QNetworkRequest request = signedRequest(credentials, method, path, body);
	request.setTransferTimeout(timeoutMs);

	QNetworkReply *reply;
	if (method == "GET") reply = mNetwork->get(request);
	else {
		request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
		reply = mNetwork->sendCustomRequest(request, method, body);
	}

	connect(reply, &QNetworkReply::finished, this,
	        [this, reply, credentials, method, path, body, done, clockRetried, timeoutMs]() {
		        reply->deleteLater();
		        Reply result;
		        result.status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
		        result.answer = QJsonDocument::fromJson(reply->readAll()).object();
		        result.error = result.answer.value("error").toString();
		        if (reply->error() != QNetworkReply::NoError) result.networkError = reply->errorString();

		        if (result.status == 401 && result.error == "clock" && !clockRetried) {
			        mClockOffset = result.answer.value("server_time").toInteger() - QDateTime::currentSecsSinceEpoch();
			        lInfo() << log().arg("Clock offset with the Gamaphone service:") << mClockOffset << "s";
			        sendOnce(credentials, method, path, body, done, true, timeoutMs);
			        return;
		        }
		        if (result.status < 200 || result.status >= 300)
			        lWarning() << log().arg("Gamaphone service request failed:") << method << path << result.status
			                   << result.error << result.networkError;
		        done(result);
	        });
}
