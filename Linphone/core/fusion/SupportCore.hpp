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

#ifndef SUPPORT_CORE_H_
#define SUPPORT_CORE_H_

#include "core/fusion/FusionClient.hpp"
#include "tool/AbstractObject.hpp"

#include <QObject>
#include <QSharedPointer>

// Envoi des journaux au support (« Dépannage »). Ils sont compressés par le moteur, puis envoyés au serveur du compte
// (service fusion-files), qui les garde et prévient le support par e-mail. Plus rien ne part vers les serveurs de
// Linphone.
class SupportCore : public QObject, public AbstractObject {
	Q_OBJECT
	// Envoi en cours (compression puis transfert).
	Q_PROPERTY(bool sending READ isSending NOTIFY sendingChanged)

public:
	static QSharedPointer<SupportCore> create(QSharedPointer<FusionClient> client);
	SupportCore(QSharedPointer<FusionClient> client);
	~SupportCore();

	bool isSending() const;
	Q_INVOKABLE void sendLogs();

signals:
	void sendingChanged();
	// reference : à donner au support ; emailed : le support a été prévenu par e-mail.
	void logsSent(QString reference, bool emailed);
	void logsFailed(QString message);

private:
	void setSending(bool sending);
	void upload(const QString &compressedPath);
	static QString errorMessage(const FusionClient::Reply &reply);

	QSharedPointer<FusionClient> mClient;
	bool mSending = false;

	DECLARE_ABSTRACT_OBJECT
};

#endif
