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

#include "MagicSearchModel.hpp"

#include <QDebug>

#include "model/core/CoreModel.hpp"
#include "model/friend/FriendsManager.hpp"
#include "model/setting/SettingsModel.hpp"
#include "model/tool/ToolModel.hpp"
#include "tool/Utils.hpp"
#include <functional>

DEFINE_ABSTRACT_OBJECT(MagicSearchModel)

MagicSearchModel::MagicSearchModel(const std::shared_ptr<linphone::MagicSearch> &data, QObject *parent)
    : ::Listener<linphone::MagicSearch, linphone::MagicSearchListener>(data, parent) {
	mustBeInLinphoneThread(getClassName());
}

MagicSearchModel::~MagicSearchModel() {
	mustBeInLinphoneThread("~" + getClassName());
}

void MagicSearchModel::search(QString filter,
                              int sourceFlags,
                              LinphoneEnums::MagicSearchAggregation aggregation,
                              int maxResults) {
	filter = filter.toLower();
	mLastSearch = filter;
	setMaxResults(maxResults);
	if (filter == "" || filter == "*") {
		if (((sourceFlags & (int)LinphoneEnums::MagicSearchSource::LdapServers) > 0) &&
		    !SettingsModel::getInstance()->getSyncLdapContacts())
			sourceFlags &= ~(int)LinphoneEnums::MagicSearchSource::LdapServers;
		if (((sourceFlags & (int)LinphoneEnums::MagicSearchSource::RemoteCardDAV) > 0) &&
		    SettingsModel::getInstance()->getCardDAVMinCharResearch() > 0) {
			sourceFlags &= ~(int)LinphoneEnums::MagicSearchSource::RemoteCardDAV;
		}
		// For complete search, we search only on local contacts.
		// sourceFlags &= ~(int)LinphoneEnums::MagicSearchSource::CallLogs;
		// sourceFlags &= ~(int)LinphoneEnums::MagicSearchSource::ChatRooms;
		// sourceFlags &= ~(int)LinphoneEnums::MagicSearchSource::ConferencesInfo;
	}
	if (((sourceFlags & (int)LinphoneEnums::MagicSearchSource::RemoteCardDAV) > 0) &&
	    SettingsModel::getInstance()->getCardDAVMinCharResearch() > filter.size()) {
		sourceFlags &= ~(int)LinphoneEnums::MagicSearchSource::RemoteCardDAV;
	}
	lInfo() << log().arg("Searching ") << filter << " from " << sourceFlags << " with limit " << maxResults;
	mMonitor->getContactsListAsync(filter != "*" ? Utils::appStringToCoreString(filter) : "", "", sourceFlags,
	                               LinphoneEnums::toLinphone(aggregation));
}

int MagicSearchModel::getMaxResults() const {
	if (!mMonitor->getLimitedSearch()) return -1;
	else return mMonitor->getSearchLimit();
}

void MagicSearchModel::setMaxResults(int maxResults) {
	if (maxResults <= 0 && mMonitor->getLimitedSearch() ||
	    maxResults > 0 && (!mMonitor->getLimitedSearch() || maxResults != mMonitor->getSearchLimit())) {
		mMonitor->setLimitedSearch(maxResults > 0);
		if (maxResults > 0) mMonitor->setSearchLimit(maxResults);
		emit maxResultsChanged(maxResults);
	}
}

void MagicSearchModel::onSearchResultsReceived(const std::shared_ptr<linphone::MagicSearch> &magicSearch) {
	auto results = magicSearch->getLastSearch();
	lInfo() << log().arg("SDK send callback: onSearchResultsReceived : %1 results.").arg(results.size());
	auto appFriends = ToolModel::getAppFriendList();
	auto ldapFriends = ToolModel::getLdapFriendList();
	// La liste ldap_friends est mise a jour avant de diffuser les resultats : les listes affichees
	// y retrouvent ainsi le contact abonne a la presence (MagicSearchList).
	for (auto result : results) {
		if (!result) continue;
		auto f = result->getFriend();
		auto friendsManager = FriendsManager::getInstance();
		if (f) {
			auto fList = f->getFriendList();
			bool isLdap = result->hasSourceFlag(linphone::MagicSearch::Source::LdapServers) != 0;
			// Do not add it into ldap_friends if it already exists in app_friends.
			if (isLdap && (!fList || fList->getDisplayName() !=
			                             "app_friends")) { // Double check because of SDK merging that lead to
				// use a ldap result as of app_friends/ldap_friends.
				f = updateFriendListWithFriend(f, ldapFriends);
			}
			auto friendAddress = f->getAddress() ? f->getAddress() : nullptr;
			if (friendAddress) {
				// friendAddress->clean();
				qDebug() << "friend exists, append to unknown map";
				friendsManager->appendUnknownFriend(friendAddress, f);
				if (friendsManager->isInOtherAddresses(
				        Utils::coreStringToAppString(friendAddress->asStringUriOnly()))) {
					friendsManager->removeOtherAddress(Utils::coreStringToAppString(friendAddress->asStringUriOnly()));
				}
			}
		}
	}
	emit searchResultsReceived(results);
}

void MagicSearchModel::onMoreResultsAvailable(const std::shared_ptr<linphone::MagicSearch> &magicSearch,
                                              linphone::MagicSearch::Source source) {
}

// Store LDAP friends in separate list so they can still be retrieved by core->findFriend() for display names,
// but can be amended only by LDAP received friends.
// Done in this place so the application can benefit from user initiated searches for faster ldap name retrieval
// upon incoming call / chat message.

std::shared_ptr<linphone::Friend>
MagicSearchModel::updateFriendListWithFriend(const std::shared_ptr<linphone::Friend> &linphoneFriend,
                                             std::shared_ptr<linphone::FriendList> friendList) {
	mustBeInLinphoneThread(log().arg(Q_FUNC_INFO));
	if (!friendList) return linphoneFriend;
	if (ToolModel::friendIsInFriendList(friendList, linphoneFriend))
		return linphoneFriend; // Already exist. We don't need to manipulate list.

	// Chaque recherche renvoie des objets neufs pour les memes personnes. Les substituer a ceux de
	// la liste desabonnait puis reabonnait tout l'annuaire a chaque recherche, et les nouveaux
	// objets partaient sans presence connue (pastille vide jusqu'au NOTIFY suivant), tandis que
	// les avatars deja affiches restaient lies aux anciens, desabonnes. On garde donc le contact
	// deja present, en y reportant ce qui a pu changer dans l'annuaire.
	auto keepExisting = [&](const std::shared_ptr<linphone::Friend> &existingFriend) {
		bool nameChanged = !linphoneFriend->getName().empty() && existingFriend->getName() != linphoneFriend->getName();
		bool numbersChanged = existingFriend->getPhoneNumbers() != linphoneFriend->getPhoneNumbers();
		auto oldVcard = existingFriend->getVcard();
		auto newVcard = linphoneFriend->getVcard();
		bool vcardChanged = oldVcard && newVcard &&
		                    (oldVcard->getOrganization() != newVcard->getOrganization() ||
		                     oldVcard->getJobTitle() != newVcard->getJobTitle());
		if (nameChanged || numbersChanged || vcardChanged) {
			existingFriend->edit();
			if (nameChanged) existingFriend->setName(linphoneFriend->getName());
			if (numbersChanged) {
				for (auto &number : existingFriend->getPhoneNumbers())
					existingFriend->removePhoneNumber(number);
				for (auto &number : linphoneFriend->getPhoneNumbers())
					existingFriend->addPhoneNumber(number);
			}
			if (vcardChanged) {
				oldVcard->setOrganization(newVcard->getOrganization());
				oldVcard->setJobTitle(newVcard->getJobTitle());
			}
			existingFriend->done(); // Sans nouveau SUBSCRIBE : l'abonnement actif est conserve.
			// La fiche affichee est partagee et dure : on la previent pour qu'elle relise nom, societe
			// et fonction (FriendModel::onUpdated), au lieu d'attendre qu'une fiche neuve soit creee.
			emit CoreModel::getInstance()->friendUpdated(existingFriend);
		}
		return existingFriend;
	};
	for (auto address : linphoneFriend->getAddresses()) {
		if (auto existingFriend = friendList->findFriendByAddress(address)) return keepExisting(existingFriend);
	}
	for (auto number : linphoneFriend->getPhoneNumbers()) {
		if (auto existingFriend = friendList->findFriendByPhoneNumber(number)) return keepExisting(existingFriend);
	}
	qInfo() << log().arg("Adding Friend:") << linphoneFriend.get();
	linphoneFriend->enableSubscribes(true);
	friendList->addFriend(linphoneFriend);
	emit CoreModel::getInstance()->friendCreated(linphoneFriend);
	return linphoneFriend;
}
