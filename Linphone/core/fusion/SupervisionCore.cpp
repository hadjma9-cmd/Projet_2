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

DEFINE_ABSTRACT_OBJECT(SupervisionCore)

static const QString LivePath = QStringLiteral("/gamaphone/v1/supervision/direct");
static constexpr int FirstRetryMs = 2000;
static constexpr int MaxRetryMs = 30000;

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
	if (mReply) mReply->abort();
	setLive(false);
}

void SupervisionCore::connectStream() {
	if (!mWanted || mReply) return;
	mClient->withCredentials([this](const FusionClient::Credentials &credentials) {
		if (!mWanted || mReply) return;
		if (!credentials.isValid()) { // compte pas encore connecté
			scheduleReconnect();
			return;
		}
		mBuffer.clear();
		QNetworkReply *reply = mClient->openStream(credentials, LivePath);
		mReply = reply;
		connect(reply, &QNetworkReply::readyRead, this, &SupervisionCore::readStream);
		connect(reply, &QNetworkReply::finished, this, [this, reply]() {
			const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
			if (reply->error() != QNetworkReply::NoError && reply->error() != QNetworkReply::OperationCanceledError)
				lWarning() << log().arg("Supervision stream closed:") << status << reply->errorString();
			reply->deleteLater();
			if (mReply == reply) mReply = nullptr;
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
