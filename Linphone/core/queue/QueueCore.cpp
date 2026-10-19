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

#include "QueueCore.hpp"
#include "core/App.hpp"
#include "model/core/CoreModel.hpp"
#include "tool/Utils.hpp"

#include <QJsonArray>
#include <QJsonDocument>

DEFINE_ABSTRACT_OBJECT(QueueCore)

static const QString ServicePath = QStringLiteral("/gamaphone/v1/files");
static constexpr qint64 RereadDelaySecs = 10 * 60;

QSharedPointer<QueueCore> QueueCore::create(QSharedPointer<FusionClient> client) {
	auto sharedPointer = QSharedPointer<QueueCore>(new QueueCore(client), &QObject::deleteLater);
	sharedPointer->setSelf(sharedPointer);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

QueueCore::QueueCore(QSharedPointer<FusionClient> client) : QObject(nullptr), mClient(client) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
}

QueueCore::~QueueCore() {
}

void QueueCore::setSelf(QSharedPointer<QueueCore> me) {
	mCoreModelConnection = SafeConnection<QueueCore, CoreModel>::create(me, CoreModel::getInstance());
	// Compte connecté (démarrage, réseau retrouvé) : première lecture. Les renouvellements d'enregistrement suivants
	// ne relisent rien.
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
	// Retour sur l'application, venant d'une autre : relecture si la dernière date de plus de 10 minutes.
	connect(App::getInstance(), &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
		if (state == Qt::ApplicationActive) read(ReadMode::IfStale);
	});
	// Compte peut-être déjà connecté avant la création de cet objet.
	read(ReadMode::IfNeverRead);
}

bool QueueCore::isAgent() const {
	return mAgent;
}

QString QueueCore::getAgentStatus() const {
	return mAgentStatus;
}

QVariantList QueueCore::getQueues() const {
	return mQueues;
}

int QueueCore::getConnectedCount() const {
	return mConnectedCount;
}

int QueueCore::getQueueCount() const {
	return mQueues.size();
}

QStringList QueueCore::getPendingQueues() const {
	return mPendingQueues;
}

QString QueueCore::getErrorText() const {
	return mErrorText;
}

void QueueCore::refresh() {
	read(ReadMode::Always);
}

void QueueCore::setQueueConnected(const QString &queueId, bool connected) {
	if (queueId.isEmpty() || mPendingQueues.contains(queueId)) return;
	setErrorText(QString());
	setPending(queueId, true);
	const QByteArray body =
	    QJsonDocument(QJsonObject{{"queue", queueId}, {"connected", connected}}).toJson(QJsonDocument::Compact);
	mClient->withCredentials([this, queueId, body](const FusionClient::Credentials &credentials) {
		if (!adoptAccount(credentials)) {
			setPending(queueId, false);
			setErrorText("Compte non connecté : réessayez dans un instant.");
			return;
		}
		const int generation = mGeneration;
		mClient->send(credentials, "POST", ServicePath, body,
		              [this, queueId, generation](const FusionClient::Reply &reply) {
			              if (generation != mGeneration) return; // compte changé entre-temps
			              setPending(queueId, false);
			              if (reply.status == 200) {
				              applyState(reply.answer);
				              return;
			              }
			              if (reply.status == 404 && reply.error == "queue") {
				              setErrorText("Cette file ne vous est plus attribuée.");
				              read(ReadMode::Always);
			              } else setErrorText("Le serveur des files ne répond pas. Réessayez.");
		              });
	});
}

// Changement de compte : l'état affiché est celui de l'ancien, on l'efface. Faux si le compte n'est pas connecté.
bool QueueCore::adoptAccount(const FusionClient::Credentials &credentials) {
	const QString key = credentials.key();
	if (key != mAccountKey) {
		mAccountKey = key;
		++mGeneration;
		mReading = false;
		mHaveRead = false;
		mLastAttempt = QDateTime();
		clearState();
	}
	return credentials.isValid();
}

void QueueCore::read(ReadMode mode) {
	if (mReading) return;
	mReading = true;
	mClient->withCredentials([this, mode](const FusionClient::Credentials &credentials) {
		// adoptAccount remet mReading à faux si le compte a changé : on le repose avant d'envoyer.
		const bool connected = adoptAccount(credentials);
		if (!connected || (mode == ReadMode::IfNeverRead && mHaveRead) ||
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
			              // Lecture en échec : on garde l'état affiché.
			              if (reply.status == 200) applyState(reply.answer);
		              });
	});
}

void QueueCore::applyState(const QJsonObject &state) {
	mHaveRead = true;
	QVariantList queues;
	int connectedCount = 0;
	for (const QJsonValue &value : state.value("queues").toArray()) {
		const QJsonObject queue = value.toObject();
		const bool connected = queue.value("connected").toBool();
		if (connected) ++connectedCount;
		queues.append(QVariantMap{{"id", queue.value("id").toString()},
		                          {"name", queue.value("name").toString()},
		                          {"number", queue.value("number").toString()},
		                          {"connected", connected}});
	}
	const bool agent = state.value("agent").toBool();
	const QString agentStatus = state.value("status").toString();
	if (agent == mAgent && agentStatus == mAgentStatus && queues == mQueues) return;
	mAgent = agent;
	mAgentStatus = agentStatus;
	mQueues = queues;
	mConnectedCount = connectedCount;
	emit stateChanged();
}

void QueueCore::clearState() {
	if (!mPendingQueues.isEmpty()) {
		mPendingQueues.clear();
		emit pendingQueuesChanged();
	}
	setErrorText(QString());
	if (!mAgent && mQueues.isEmpty() && mAgentStatus.isEmpty()) return;
	mAgent = false;
	mAgentStatus.clear();
	mQueues.clear();
	mConnectedCount = 0;
	emit stateChanged();
}

void QueueCore::setPending(const QString &queueId, bool pending) {
	if (pending == mPendingQueues.contains(queueId)) return;
	if (pending) mPendingQueues.append(queueId);
	else mPendingQueues.removeAll(queueId);
	emit pendingQueuesChanged();
}

void QueueCore::setErrorText(const QString &text) {
	if (text == mErrorText) return;
	mErrorText = text;
	emit errorTextChanged();
}
