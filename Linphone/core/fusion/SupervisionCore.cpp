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

#include "SupervisionCore.hpp"
#include "core/App.hpp"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRandomGenerator>

DEFINE_ABSTRACT_OBJECT(SupervisionCore)

static const QString LivePath = QStringLiteral("/gamaphone/v1/supervision/direct");
static const QString TakePath = QStringLiteral("/gamaphone/v1/supervision/prendre");
static const QString StatsPath = QStringLiteral("/gamaphone/v1/supervision/stats");
// Le serveur fait sonner le poste jusqu'a 12 s avant de repondre.
static constexpr int TakeTimeoutMs = 25000;
static constexpr int FirstRetryMs = 2000;
static constexpr int MaxRetryMs = 30000;
// Le serveur envoie un signal de vie toutes les 10 s : 60 s sans rien, la connexion est morte (coupure silencieuse).
static constexpr int SilenceLimitMs = 60000;

QSharedPointer<SupervisionCore> SupervisionCore::create(QSharedPointer<FusionClient> client) {
	auto sharedPointer = QSharedPointer<SupervisionCore>(new SupervisionCore(client), &QObject::deleteLater);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

SupervisionCore::SupervisionCore(QSharedPointer<FusionClient> client) : QObject(nullptr), mClient(client) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
	mReconnect.setSingleShot(true);
	connect(&mReconnect, &QTimer::timeout, this, &SupervisionCore::connectStream);
	mWatchdog.setSingleShot(true);
	mWatchdog.setInterval(SilenceLimitMs);
	connect(&mWatchdog, &QTimer::timeout, this, [this]() {
		lWarning() << log().arg("Supervision stream silent for too long: reconnecting");
		if (mReply) mReply->abort(); // « finished » relance la connexion
	});
}

SupervisionCore::~SupervisionCore() {
	if (mReply) mReply->abort();
}

QVariantList SupervisionCore::getQueues() const {
	return mQueues;
}

qint64 SupervisionCore::getClockOffset() const {
	return mClockOffset;
}

bool SupervisionCore::isLive() const {
	return mLive;
}

bool SupervisionCore::isLoaded() const {
	return mLoaded;
}

QString SupervisionCore::getTakingCall() const {
	return mTakingCall;
}

QString SupervisionCore::getMyExtension() const {
	return mMyExtension;
}

QVariantMap SupervisionCore::getStats() const {
	return mStats;
}

bool SupervisionCore::isStatsLoading() const {
	return mStatsLoading;
}

QString SupervisionCore::getStatsError() const {
	return mStatsError;
}

void SupervisionCore::loadStats(const QString &period) {
	mStatsPeriod = period;
	mStatsLoading = true;
	mStatsError.clear();
	emit statsChanged();
	const QByteArray body = QJsonDocument(QJsonObject{{"period", period}}).toJson(QJsonDocument::Compact);
	mClient->withCredentials([this, body, period](const FusionClient::Credentials &credentials) {
		if (period != mStatsPeriod) return;
		if (!credentials.isValid()) {
			mStatsLoading = false;
			mStatsError = QStringLiteral("Votre poste n'est pas connecté.");
			emit statsChanged();
			return;
		}
		mClient->send(credentials, "POST", StatsPath, body, [this, period](const FusionClient::Reply &reply) {
			if (period != mStatsPeriod) return; // une autre periode a ete choisie entre-temps
			mStatsLoading = false;
			if (reply.status == 200) mStats = reply.answer.toVariantMap();
			else mStatsError = QStringLiteral("Statistiques indisponibles pour le moment. Réessayez dans un instant.");
			emit statsChanged();
		});
	});
}

void SupervisionCore::setTakingCall(const QString &callId) {
	if (callId == mTakingCall) return;
	mTakingCall = callId;
	emit takingCallChanged();
}

void SupervisionCore::take(const QString &callId) {
	if (callId.isEmpty() || !mTakingCall.isEmpty()) return; // une prise a la fois
	setTakingCall(callId);
	QByteArray token(16, Qt::Uninitialized);
	QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(token.data()), token.size() / 4);
	mPickupToken = QString::fromLatin1(token.toHex());
	mPickupTokenExpiry = QDateTime::currentMSecsSinceEpoch() + TakeTimeoutMs;
	const QByteArray body =
	    QJsonDocument(QJsonObject{{"call", callId}, {"token", mPickupToken}}).toJson(QJsonDocument::Compact);
	mClient->withCredentials([this, body](const FusionClient::Credentials &credentials) {
		if (!credentials.isValid()) {
			setTakingCall(QString());
			emit takeFailed(QStringLiteral("Votre poste n'est pas connecté."));
			return;
		}
		mClient->send(
		    credentials, "POST", TakePath, body,
		    [this](const FusionClient::Reply &reply) {
			    setTakingCall(QString());
			    if (reply.status == 200) return; // l'appel est deja sur ce poste
			    mPickupToken.clear();
			    QString message;
			    if (reply.error == "taken") {
				    const QString by = reply.answer.value("by").toString();
				    message = by.isEmpty() ? QStringLiteral("Cet appel a déjà été pris.")
				                           : QStringLiteral("Déjà pris par %1.").arg(by);
			    } else if (reply.error == "gone") message = QStringLiteral("L'appelant a raccroché.");
			    else if (reply.error == "no_answer") message = QStringLiteral("Votre poste n'a pas décroché.");
			    else if (reply.error == "unreachable") message = QStringLiteral("Votre poste n'est pas joignable.");
			    else if (reply.error == "not_agent")
				    message = QStringLiteral("Seuls les agents de cette file peuvent prendre ses appels.");
			    else message = QStringLiteral("L'appel n'a pas pu être pris. Réessayez dans un instant.");
			    emit takeFailed(message);
		    },
		    TakeTimeoutMs);
	});
}

bool SupervisionCore::consumePickupToken(const QString &token) {
	if (token.isEmpty() || mPickupToken.isEmpty() || token != mPickupToken ||
	    QDateTime::currentMSecsSinceEpoch() > mPickupTokenExpiry)
		return false;
	mPickupToken.clear();
	return true;
}

void SupervisionCore::setLive(bool live) {
	if (live == mLive) return;
	mLive = live;
	emit liveChanged();
}

void SupervisionCore::start() {
	if (mWanted) return;
	mWanted = true;
	mRetryDelayMs = FirstRetryMs;
	connectStream();
}

void SupervisionCore::stop() {
	mWanted = false;
	mReconnect.stop();
	mWatchdog.stop();
	if (mReply) mReply->abort();
	setLive(false);
	// Fenetre fermee : l'etat garde deviendrait faux (appels finis, durees qui continuent). A la prochaine ouverture,
	// « Chargement » jusqu'a l'etat frais du serveur.
	mQueues.clear();
	mLoaded = false;
	emit queuesChanged();
}

void SupervisionCore::connectStream() {
	if (!mWanted || mReply) return;
	mClient->withCredentials([this](const FusionClient::Credentials &credentials) {
		if (!mWanted || mReply) return;
		if (!credentials.isValid()) { // compte pas encore connecté
			scheduleReconnect();
			return;
		}
		if (credentials.user != mMyExtension) {
			mMyExtension = credentials.user;
			emit myExtensionChanged();
		}
		mBuffer.clear();
		QNetworkReply *reply = mClient->openStream(credentials, LivePath);
		mReply = reply;
		mWatchdog.start();
		connect(reply, &QNetworkReply::readyRead, this, &SupervisionCore::readStream);
		connect(reply, &QNetworkReply::finished, this, [this, reply]() {
			const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
			if (reply->error() != QNetworkReply::NoError && reply->error() != QNetworkReply::OperationCanceledError)
				lWarning() << log().arg("Supervision stream closed:") << status << reply->errorString();
			reply->deleteLater();
			if (mReply == reply) mReply = nullptr;
			mWatchdog.stop();
			setLive(false);
			scheduleReconnect();
		});
	});
}

void SupervisionCore::scheduleReconnect() {
	if (!mWanted) return;
	mReconnect.start(mRetryDelayMs);
	mRetryDelayMs = qMin(mRetryDelayMs * 2, MaxRetryMs);
}

// Messages « text/event-stream » : lignes « data: <json> », séparés par une ligne vide ; « : ... » = signal de vie.
void SupervisionCore::readStream() {
	if (!mReply) return;
	mWatchdog.start(); // donnees ou signal de vie : la connexion vit
	mBuffer += mReply->readAll();
	mBuffer.replace("\r\n", "\n");
	int end;
	while ((end = mBuffer.indexOf("\n\n")) >= 0) {
		const QByteArray event = mBuffer.left(end);
		mBuffer.remove(0, end + 2);
		QByteArray data;
		for (const QByteArray &line : event.split('\n'))
			if (line.startsWith("data:")) data += line.mid(5).trimmed();
		if (!data.isEmpty()) applyEvent(data);
	}
	if (mBuffer.size() > 4 * 1024 * 1024) mBuffer.clear(); // flux incohérent : on repart de zéro
}

void SupervisionCore::applyEvent(const QByteArray &data) {
	const QJsonObject state = QJsonDocument::fromJson(data).object();
	if (!state.contains("queues")) return;
	mQueues = state.value("queues").toArray().toVariantList();
	const qint64 serverTime = state.value("server_time").toInteger();
	mClockOffset = serverTime > 0 ? serverTime - QDateTime::currentSecsSinceEpoch() : mClient->clockOffset();
	mLoaded = true;
	mRetryDelayMs = FirstRetryMs; // la connexion fonctionne : prochaine coupure, nouvel essai rapide
	setLive(true);
	emit queuesChanged();
}
