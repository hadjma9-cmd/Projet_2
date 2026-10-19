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

#include "UpdateCore.hpp"
#include "core/App.hpp"
#include "model/core/CoreModel.hpp"
#include "tool/Utils.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

DEFINE_ABSTRACT_OBJECT(UpdateCore)

namespace {
constexpr char VersionPath[] = "/gamaphone/v1/version";
constexpr char DownloadPath[] = "/gamaphone/telecharger";
// Sans aucun octet reçu pendant ce délai, le téléchargement est abandonné.
constexpr int IdleTimeoutMs = 30000;
} // namespace

QSharedPointer<UpdateCore> UpdateCore::create(QSharedPointer<FusionClient> client) {
	auto sharedPointer = QSharedPointer<UpdateCore>(new UpdateCore(client), &QObject::deleteLater);
	sharedPointer->setSelf(sharedPointer);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

UpdateCore::UpdateCore(QSharedPointer<FusionClient> client) : QObject(nullptr), mClient(client) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
	mNetwork = new QNetworkAccessManager(this);
}

UpdateCore::~UpdateCore() {
}

// La demande du demarrage part souvent avant que le compte soit connecte : sans reponse du serveur, elle est refaite a
// chaque connexion du compte par defaut (demarrage, reseau retrouve, renouvellement), jusqu'a une reponse.
void UpdateCore::setSelf(QSharedPointer<UpdateCore> me) {
	mCoreModelConnection = SafeConnection<UpdateCore, CoreModel>::create(me, CoreModel::getInstance());
	mCoreModelConnection->makeConnectToModel(
	    &CoreModel::accountRegistrationStateChanged,
	    [this](const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::Account> &account,
	           linphone::RegistrationState state, const std::string &message) {
		    if (state != linphone::RegistrationState::Ok || account != core->getDefaultAccount()) return;
		    mCoreModelConnection->invokeToCore([this]() {
			    if (!mAnswered) check(false);
		    });
	    });
}

QString UpdateCore::getState() const {
	return mState;
}

QString UpdateCore::getErrorText() const {
	return mErrorText;
}

qreal UpdateCore::getProgress() const {
	return mSize > 0 ? qMin<qreal>(1.0, qreal(mReceived) / qreal(mSize)) : 0.0;
}

int UpdateCore::getReceivedMb() const {
	return int(mReceived >> 20);
}

int UpdateCore::getTotalMb() const {
	return int(mSize >> 20);
}

void UpdateCore::setState(const QString &state, const QString &errorText) {
	if (mState == state && mErrorText == errorText) return;
	mState = state;
	mErrorText = errorText;
	emit stateChanged();
}

void UpdateCore::fail(const QString &message) {
	lWarning() << log().arg("Update failed:") << message;
	setState(QStringLiteral("failed"), message);
}

void UpdateCore::check(bool requestedByUser) {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	if (mState == QLatin1String("downloading") || mState == QLatin1String("launching")) return;
	if (mChecking && !requestedByUser) return; // la reponse attendue suffit
	mChecking = true;
	mClient->withCredentials([this, requestedByUser](const FusionClient::Credentials &credentials) {
		if (!credentials.isValid()) {
			mChecking = false;
			mStartWhenReady = false;
			if (requestedByUser)
				Utils::showInformationPopup(QStringLiteral("Mise à jour"),
				                            QStringLiteral("Compte non connecté : réessayez dans un instant."), false);
			return;
		}
		const QByteArray body = QJsonDocument(QJsonObject{{"version", QCoreApplication::applicationVersion()}})
		                            .toJson(QJsonDocument::Compact);
		const QString domain = credentials.domain;
		mClient->send(
		    credentials, "POST", VersionPath, body, [this, requestedByUser, domain](const FusionClient::Reply &reply) {
			    mChecking = false;
			    if (reply.status == 200) mAnswered = true;
			    const bool startNow = mStartWhenReady;
			    mStartWhenReady = false;
			    if (mState == QLatin1String("downloading") || mState == QLatin1String("launching")) return;
			    const QByteArray sum = reply.answer.value("sha256").toString().toLatin1().toLower();
			    const qint64 size = qint64(reply.answer.value("size").toDouble());
			    // Sans empreinte ni taille, l'installeur ne pourrait pas être vérifié : pas de mise à jour.
			    if (reply.status == 200 && reply.answer.value("update").toBool() && sum.size() == 64 && size > 0) {
				    lInfo() << log().arg("Update available on") << domain;
				    mDomain = domain;
				    mSha256 = sum;
				    mSize = size;
				    setState(QStringLiteral("available"));
				    if (startNow) download();
				    return;
			    }
			    if (reply.status == 200) {
				    // À jour (ou l'installeur a été retiré du serveur entre-temps).
				    setState(QStringLiteral("idle"));
				    if (requestedByUser)
					    Utils::showInformationPopup(QStringLiteral("Mise à jour"),
					                                QStringLiteral("Gamaphone est à jour."));
				    return;
			    }
			    // Le serveur n'a pas répondu : un échec déjà affiché reste affiché.
			    if (requestedByUser)
				    Utils::showInformationPopup(
				        QStringLiteral("Mise à jour"),
				        QStringLiteral("Vérification impossible pour le moment. Réessayez plus tard."), false);
		    });
	});
}

void UpdateCore::start() {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	if (mState == QLatin1String("available")) download();
	else if (mState == QLatin1String("failed")) {
		// L'installeur a pu changer sur le serveur : on redemande sa taille et son empreinte avant de réessayer.
		mStartWhenReady = true;
		check(false);
	}
}

void UpdateCore::cancel() {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	if (mState != QLatin1String("downloading") || !mReply) return;
	mCancelled = true;
	mReply->abort();
}

void UpdateCore::dismiss() {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	if (mState == QLatin1String("failed")) setState(QStringLiteral("idle"));
}

void UpdateCore::download() {
	const QString folder =
	    QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/Gamaphone-mise-a-jour");
	if (!QDir().mkpath(folder)) {
		fail(QStringLiteral("Impossible de préparer le dossier de téléchargement."));
		return;
	}
	mFile.setFileName(folder + QStringLiteral("/Gamaphone-mise-a-jour.exe.part"));
	if (!mFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
		fail(QStringLiteral("Impossible d'enregistrer la mise à jour sur cet ordinateur."));
		return;
	}
	mHash.reset();
	mReceived = 0;
	mShownPercent = -1;
	mCancelled = false;

	QUrl url;
	url.setScheme("https");
	url.setHost(mDomain);
	url.setPath(DownloadPath);
	QNetworkRequest request(url);
	request.setTransferTimeout(IdleTimeoutMs);
	request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
	// L'installeur vient du serveur du compte et de nulle part ailleurs.
	request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
	lInfo() << log().arg("Downloading update from") << mDomain;
	mReply = mNetwork->get(request);
	connect(mReply, &QNetworkReply::readyRead, this, &UpdateCore::receive);
	connect(mReply, &QNetworkReply::finished, this, &UpdateCore::finishDownload);
	setState(QStringLiteral("downloading"));
	emit progressChanged();
}

void UpdateCore::receive() {
	if (!mReply) return;
	const QByteArray chunk = mReply->readAll();
	if (chunk.isEmpty()) return;
	mHash.addData(chunk);
	if (mFile.write(chunk) != chunk.size()) {
		// Disque plein, par exemple : finishDownload constate l'écart de taille.
		mReply->abort();
		return;
	}
	mReceived += chunk.size();
	const int percent = mSize > 0 ? int(mReceived * 100 / mSize) : 0;
	if (percent != mShownPercent) {
		mShownPercent = percent;
		emit progressChanged();
	}
}

void UpdateCore::finishDownload() {
	if (!mReply) return;
	receive();
	QNetworkReply *reply = mReply;
	mReply = nullptr;
	reply->deleteLater();
	mFile.close();
	const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
	const bool received = reply->error() == QNetworkReply::NoError && status == 200;

	if (mCancelled) {
		mCancelled = false;
		mFile.remove();
		setState(QStringLiteral("available"));
		return;
	}
	if (!received) {
		mFile.remove();
		fail(QStringLiteral("Le téléchargement a échoué. Vérifiez la connexion, puis réessayez."));
		return;
	}
	if (mReceived != mSize || mHash.result().toHex() != mSha256) {
		mFile.remove();
		fail(QStringLiteral("Le fichier reçu est incomplet ou ne correspond pas à celui du serveur."));
		return;
	}
	QString path = mFile.fileName();
	path.chop(int(qstrlen(".part")));
	QFile::remove(path);
	if (!mFile.rename(path)) {
		mFile.remove();
		fail(QStringLiteral("Impossible d'enregistrer la mise à jour sur cet ordinateur."));
		return;
	}
	launch(path);
}

void UpdateCore::launch(const QString &path) {
	setState(QStringLiteral("launching"));
	// Le temps d'afficher « Installation… » : la demande d'autorisation de Windows fige la fenêtre.
	QTimer::singleShot(600, this, [this, path] {
		lInfo() << log().arg("Launching installer") << path;
		if (QProcess::startDetached(path, {})) {
			// L'installeur remplace les fichiers de l'application : elle doit être fermée.
			App::getInstance()->quit();
		} else {
			fail(QStringLiteral(
			    "L'installation n'a pas pu démarrer. L'autorisation de Windows a peut-être été refusée."));
		}
	});
}
