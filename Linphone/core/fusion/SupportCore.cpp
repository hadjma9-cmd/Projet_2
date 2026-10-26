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

#include "SupportCore.hpp"
#include "core/App.hpp"
#include "tool/Utils.hpp"

#include <QFile>
#include <QPointer>

DEFINE_ABSTRACT_OBJECT(SupportCore)

static const QString LogsPath = QStringLiteral("/gamaphone/v1/journaux");
// Limite du serveur (150 Mo) : au-delà, inutile d'envoyer.
static constexpr qint64 MaxLogsSize = 150LL * 1024 * 1024;

QSharedPointer<SupportCore> SupportCore::create(QSharedPointer<FusionClient> client) {
	auto sharedPointer = QSharedPointer<SupportCore>(new SupportCore(client), &QObject::deleteLater);
	sharedPointer->moveToThread(App::getInstance()->thread());
	return sharedPointer;
}

SupportCore::SupportCore(QSharedPointer<FusionClient> client) : QObject(nullptr), mClient(client) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
}

SupportCore::~SupportCore() {
}

bool SupportCore::isSending() const {
	return mSending;
}

void SupportCore::setSending(bool sending) {
	if (sending == mSending) return;
	mSending = sending;
	emit sendingChanged();
}

void SupportCore::sendLogs() {
	if (mSending) return;
	setSending(true);
	QPointer<SupportCore> guard(this);
	// Compression dans le fil du moteur, qui écrit ces journaux.
	App::postModelAsync([guard]() {
		const QString path = Utils::coreStringToAppString(linphone::Core::compressLogCollection());
		App::postCoreAsync([guard, path]() {
			if (guard) guard->upload(path);
		});
	});
}

void SupportCore::upload(const QString &compressedPath) {
	QFile file(compressedPath);
	if (compressedPath.isEmpty() || !file.open(QIODevice::ReadOnly)) {
		lWarning() << log().arg("Logs could not be compressed:") << compressedPath;
		setSending(false);
		emit logsFailed(QStringLiteral("Les journaux n'ont pas pu être préparés."));
		return;
	}
	if (file.size() == 0 || file.size() > MaxLogsSize) {
		lWarning() << log().arg("Compressed logs size not sent:") << file.size();
		setSending(false);
		emit logsFailed(file.size() == 0
		                    ? QStringLiteral("Aucun journal à envoyer.")
		                    : QStringLiteral("Les journaux sont trop lourds. Supprimez-les, reproduisez le "
		                                     "problème, puis envoyez-les de nouveau."));
		return;
	}
	const QByteArray body = file.readAll();
	file.close();
	mClient->withCredentials([this, body](const FusionClient::Credentials &credentials) {
		if (!credentials.isValid()) {
			setSending(false);
			emit logsFailed(QStringLiteral("Compte non connecté : réessayez dans un instant."));
			return;
		}
		mClient->send(credentials, "POST", LogsPath, body, [this](const FusionClient::Reply &reply) {
			setSending(false);
			if (reply.status == 201)
				emit logsSent(reply.answer.value("reference").toString(), reply.answer.value("emailed").toBool());
			else emit logsFailed(errorMessage(reply));
		});
	});
}

QString SupportCore::errorMessage(const FusionClient::Reply &reply) {
	if (reply.error == "too_many_logs") return "Trop d'envois en peu de temps. Réessayez dans une heure.";
	if (reply.status == 413 || reply.error == "size") return "Les journaux sont trop lourds pour être envoyés.";
	if (reply.status == 404) return "Le serveur ne reçoit pas encore les journaux : prévenez le support.";
	if (reply.status == 401) return "Le serveur a refusé l'identification de ce poste.";
	return "Le serveur ne répond pas. Réessayez.";
}
