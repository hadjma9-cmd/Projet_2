/*
 * Copyright (c) 2010-2024 Belledonne Communications SARL.
 *
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

#ifndef TOOL_MODEL_H_
#define TOOL_MODEL_H_

#include "core/call/CallCore.hpp"
#include "tool/AbstractObject.hpp"

#include <QHash>
#include <QObject>
#include <linphone++/linphone.hh>

class ToolModel : public QObject, public AbstractObject {
	Q_OBJECT
public:
	ToolModel(QObject *parent = nullptr);
	~ToolModel();

	static std::shared_ptr<linphone::Address> interpretUrl(const QString &address);
	static std::shared_ptr<linphone::Call> getCallByRemoteAddress(const QString &remoteAddress);
	static std::shared_ptr<linphone::FriendPhoneNumber> makeLinphoneNumber(const QString &label, const QString &number);
	static std::shared_ptr<linphone::AudioDevice> findAudioDevice(const QString &id,
	                                                              linphone::AudioDevice::Capabilities capability);
	static std::shared_ptr<linphone::Account> findAccount(const std::shared_ptr<const linphone::Address> &address);
	static std::shared_ptr<linphone::Account> findAccount(const QString &address);
	// Contact a afficher pour une adresse : de preference l'instance qui porte la presence (celle de l'onglet
	// Contacts), pour que la pastille soit la meme partout.
	static std::shared_ptr<linphone::Friend> findDisplayedFriendByAddress(const QString &address);
	static bool isMe(const QString &address);
	static bool isLocal(const QString &address);
	static bool isMe(const std::shared_ptr<const linphone::Address> &address);
	static bool isLocal(const std::shared_ptr<linphone::Conference> &conference,
	                    const std::shared_ptr<const linphone::ParticipantDevice> &device);

	static QString getRemoteAvatarUrl(const std::shared_ptr<const linphone::Address> &address);
	// Adresse de messagerie vocale d'un compte (*97) : affichee « Messagerie » partout, a la place de
	// son numero technique et avant tout nom de contact.
	static bool isVoicemailAddress(const std::shared_ptr<const linphone::Address> &address);
	static QString getVoicemailDisplayName();
	static QString getDisplayName(const std::shared_ptr<const linphone::Address> &address);
	static QString getDisplayName(QString address);

	static QString boldTextPart(const QString &text, const QString &regex);
	static QString encodeTextToQmlRichFormat(const QString &text,
	                                         const QString &textPartToBold = QString(),
	                                         const QVariantMap &options = QVariantMap(),
	                                         std::shared_ptr<linphone::ChatRoom> chatRoom = nullptr);

	static std::shared_ptr<linphone::Friend> findFriendByAddress(const QString &address);
	static std::shared_ptr<linphone::Friend>
	findFriendByAddress(const std::shared_ptr<const linphone::Address> &linphoneAddr);

	static bool createCall(const QString &sipAddress,
	                       const QVariantMap &options = {},
	                       const QString &prepareTransfertAddress = "",
	                       const QHash<QString, QString> &headers = {},
	                       linphone::MediaEncryption = linphone::MediaEncryption::None,
	                       QString *errorMessage = nullptr);

	// video : faux pour reunir des appels audio (FusionPBX) sans proposer la video a chaque participant.
	static std::shared_ptr<linphone::Conference>
	createConference(QString subject, QString *message = nullptr, bool video = true);
	static bool
	createGroupCall(QString subject, const std::list<QString> &participantAddresses, QString *message = nullptr);

	static std::shared_ptr<linphone::FriendList> getFriendList(const std::string &listName);
	static std::shared_ptr<linphone::FriendList> getAppFriendList();
	static std::shared_ptr<linphone::FriendList> getLdapFriendList();

	static bool friendIsInFriendList(const std::shared_ptr<linphone::FriendList> &friendList,
	                                 const std::shared_ptr<linphone::Friend> &f);
	// Poste interne : une adresse SIP dont le nom d'utilisateur fait 1 a 5 chiffres (meme regle que
	// FriendCore::isInternalExtension). Seuls les postes internes ont une presence.
	static bool isInternalExtension(const std::shared_ptr<linphone::Friend> &contact);
	// Abonnement de presence reserve aux postes internes : coupe pour les autres (numeros de telephone,
	// adresses externes), qui n'ont pas de statut. Renvoie vrai si le reglage du contact a change.
	static bool applyPresenceSubscriptionRule(const std::shared_ptr<linphone::Friend> &contact);

	static QString getMessageFromContent(std::list<std::shared_ptr<linphone::Content>> contents);
	static QString getMessageFromContent(std::shared_ptr<linphone::Content> content);
	static QString getMessageFromMessage(std::shared_ptr<linphone::ChatMessage> message);

	static void loadDownloadedCodecs();
	static void updateCodecs();

	static QVariantMap createVariant(const std::shared_ptr<const linphone::AudioDevice> &device);
	static QVariantMap createVariant(linphone::Conference::Layout layout);

	static QString getOsProduct();
	static QString computeUserAgent(const std::shared_ptr<linphone::Config> &config);

	static std::shared_ptr<linphone::ConferenceParams>
	getChatRoomParams(std::shared_ptr<linphone::Call> call, std::shared_ptr<linphone::Address> remoteAddress = nullptr);
	static std::shared_ptr<linphone::ChatRoom> lookupCurrentCallChat(std::shared_ptr<CallModel> callModel);
	static std::shared_ptr<linphone::ChatRoom> createCurrentCallChat(std::shared_ptr<CallModel> callModel);
	static bool isEndToEndEncryptedChatAvailable();
	// Meme information, memorisee par le fil du SDK pour etre lue sans requete depuis l'interface.
	static bool isEndToEndEncryptionAvailableCached();
	static void refreshEndToEndEncryptionAvailability();
	static std::shared_ptr<linphone::ChatRoom> lookupChatForAddress(std::shared_ptr<linphone::Address> remoteAddress);
	static std::shared_ptr<linphone::ChatRoom> createChatForAddress(std::shared_ptr<linphone::Address> remoteAddress);
	static std::shared_ptr<linphone::ChatRoom>
	createGroupChatRoom(QString subject, std::list<std::shared_ptr<linphone::Address>> participantsAddresses);

	static LinphoneEnums::Presence
	corePresenceModelToAppPresence(std::shared_ptr<const linphone::PresenceModel> presenceModel);
	// Etat pose par le serveur et non choisi par le contact (appel en cours) : a ignorer.
	static bool isAutomaticPresence(std::shared_ptr<const linphone::PresenceModel> presenceModel);
	// Appel signale par le serveur et deja decroche : « En communication ».
	static bool isAnsweredCallPresence(std::shared_ptr<const linphone::PresenceModel> presenceModel);
	static std::shared_ptr<linphone::PresenceModel> appPresenceToCorePresenceModel(LinphoneEnums::Presence presence,
	                                                                               QString presenceNote);
	static std::string configAccountSection(const std::shared_ptr<linphone::Account> &account);

private:
	DECLARE_ABSTRACT_OBJECT
};

#endif
