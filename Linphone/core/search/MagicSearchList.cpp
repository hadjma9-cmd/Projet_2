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

#include "MagicSearchList.hpp"
#include "core/App.hpp"
#include "core/friend/FriendCore.hpp"
#include "model/tool/ToolModel.hpp"
#include "tool/Utils.hpp"
#include <QSharedPointer>
#include <linphone++/linphone.hh>

// =============================================================================

namespace {
// When mShowMe is false, hide from the list the SIP address(es) of the local
// account(s) currently signed in on this profile: each user must not see his
// own SIP account (but still sees everyone else). To be called in the SDK thread.
bool isOwnAccountAddress(const std::shared_ptr<linphone::Core> &core,
                         const std::shared_ptr<const linphone::Address> &addr) {
	if (!addr) return false;
	for (auto &account : core->getAccountList()) {
		auto params = account->getParams();
		auto identity = params ? params->getIdentityAddress() : nullptr;
		if (identity && identity->weakEqual(addr)) return true;
	}
	return false;
}
} // namespace

DEFINE_ABSTRACT_OBJECT(MagicSearchList)

QSharedPointer<MagicSearchList> MagicSearchList::create() {
	auto model = QSharedPointer<MagicSearchList>(new MagicSearchList(), &QObject::deleteLater);
	model->moveToThread(App::getInstance()->thread());
	model->setSelf(model);
	return model;
}

MagicSearchList::MagicSearchList(QObject *parent) : ListProxy(parent) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
	mSourceFlags = (int)linphone::MagicSearch::Source::Friends | (int)linphone::MagicSearch::Source::LdapServers;
	mAggregationFlag = LinphoneEnums::MagicSearchAggregation::Friend;
	mSearchFilter = "*";
}

MagicSearchList::~MagicSearchList() {
	mustBeInMainThread("~" + getClassName());
	// Desinscription aupres du SDK : sans elle, la recherche et ses resultats restaient en memoire
	// apres chaque fermeture d'une liste de contacts (Nouvel appel, clavier...).
	if (mMagicSearch) emit mMagicSearch->removeListener();
}

void MagicSearchList::setSelf(const QSharedPointer<MagicSearchList> &me) {
	mCoreModelConnection = SafeConnection<MagicSearchList, CoreModel>::create(me, CoreModel::getInstance());
	mCoreModelConnection->makeConnectToModel(
	    &CoreModel::friendCreated, [this](const std::shared_ptr<linphone::Friend> &f) {
		    // Liste recreee (annuaire LDAP enregistre...) : meme masquage du compte local que pour les resultats
		    // de recherche, sinon son propre compte reapparaissait dans Contacts et au Clavier.
		    if (!mShowMe && f && isOwnAccountAddress(CoreModel::getInstance()->getCore(), f->getAddress())) return;
		    auto friendCore = FriendCore::create(f);
		    // Suite dans le fil de l'interface, a qui la liste appartient : elle etait parcourue et modifiee ici, dans
		    // le fil du SDK, pendant que l'interface pouvait la lire (plantage aleatoire).
		    mCoreModelConnection->invokeToCore([this, friendCore]() {
			    // Meme contact deja affiche : meme fiche (FriendCore::create la partage) ou meme adresse SIP.
			    auto haveContact =
			        std::find_if(mList.begin(), mList.end(), [friendCore](const QSharedPointer<QObject> &item) {
				        auto itemCore = item.objectCast<FriendCore>();
				        if (!itemCore) return false;
				        if (itemCore == friendCore) return true;
				        return !itemCore->getDefaultAddress().isEmpty() &&
				               itemCore->getDefaultAddress() == friendCore->getDefaultAddress();
			        });
			    if (haveContact == mList.end()) {
				    connect(friendCore.get(), &FriendCore::removed, this,
				            qOverload<QObject *>(&MagicSearchList::remove));
				    add(friendCore);
				    emit friendCreated(getCount() - 1, new FriendGui(friendCore));
			    }
		    });
	    });
	mCoreModelConnection->invokeToModel([this] {
		auto linphoneSearch = CoreModel::getInstance()->getCore()->createMagicSearch();
		linphoneSearch->setLimitedSearch(false);
		auto magicSearch = Utils::makeQObject_ptr<MagicSearchModel>(linphoneSearch);
		mCoreModelConnection->invokeToCore([this, magicSearch] {
			mMagicSearch = magicSearch;
			mMagicSearch->setSelf(mMagicSearch);
			mModelConnection = SafeConnection<MagicSearchList, MagicSearchModel>::create(
			    mCoreModelConnection->mCore.mQData, mMagicSearch);
			mModelConnection->makeConnectToCore(
			    &MagicSearchList::lSearch,
			    [this](QString filter, int sourceFlags, LinphoneEnums::MagicSearchAggregation aggregationFlag,
			           int maxResults) {
				    // Nouvelle recherche : on vide la liste. Relance de la meme recherche (retour
				    // sur l'onglet, passage de minuit) : on garde les resultats affiches, remplaces
				    // d'un coup a l'arrivee des nouveaux, au lieu d'une liste vide le temps que
				    // l'annuaire LDAP reponde.
				    QString searchKey =
				        QStringLiteral("%1|%2|%3|%4")
				            .arg(filter, QString::number(sourceFlags),
				                 QString::number(static_cast<int>(aggregationFlag)), QString::number(maxResults));
				    if (searchKey != mLastSearchKey) resetData();
				    mLastSearchKey = searchKey;
				    mModelConnection->invokeToModel([this, filter, sourceFlags, aggregationFlag, maxResults]() {
					    mMagicSearch->search(filter, sourceFlags, aggregationFlag, maxResults);
				    });
			    });
			mModelConnection->makeConnectToModel(
			    &MagicSearchModel::searchResultsReceived,
			    [this](const std::list<std::shared_ptr<linphone::SearchResult>> &results) {
				    lInfo() << log().arg("Search result received : Safe Connection =") << mModelConnection.get();
				    lInfo() << log().arg("this =") << this;
				    auto *contacts = new QList<QSharedPointer<FriendCore>>();
				    auto ldapContacts = ToolModel::getLdapFriendList();
				    auto core = CoreModel::getInstance()->getCore();
				    for (auto it : results) {
					    QSharedPointer<FriendCore> contact;
					    auto linphoneFriend = it->getFriend();
					    bool isStored = false;
					    // Resultat de l'annuaire : on affiche le contact de la liste ldap_friends, abonne a
					    // la presence, plutot que l'objet neuf renvoye par la recherche (presence inconnue,
					    // jamais mis a jour).
					    if (linphoneFriend && linphoneFriend->getAddress() &&
					        it->hasSourceFlag(linphone::MagicSearch::Source::LdapServers)) {
						    auto fList = linphoneFriend->getFriendList();
						    if (!fList || fList->getDisplayName() != "app_friends") {
							    if (auto listed = ldapContacts->findFriendByAddress(linphoneFriend->getAddress()))
								    linphoneFriend = listed;
						    }
					    }
					    if (linphoneFriend) {
						    if (!mShowMe && isOwnAccountAddress(core, linphoneFriend->getAddress())) {
							    lDebug() << log().arg("do not show my own address in this contact list");
							    continue;
						    }
						    isStored =
						        (ldapContacts->findFriendByAddress(linphoneFriend->getAddress()) != linphoneFriend);
						    contact = FriendCore::create(linphoneFriend, isStored, it->getSourceFlags());
						    contacts->append(contact);
					    } else if (auto address = it->getAddress()) {
						    if (!mShowMe && isOwnAccountAddress(core, address)) {
							    lDebug() << log().arg("do not show my own address in this contact list");
							    continue;
						    }
						    auto linphoneFriend = core->createFriend();
						    linphoneFriend->setAddress(address);
						    contact = FriendCore::create(linphoneFriend, isStored, it->getSourceFlags());
						    auto displayName = Utils::coreStringToAppString(address->getDisplayName());
						    auto splitted = displayName.split(" ");
						    if (!displayName.isEmpty() && splitted.size() > 0) {
							    contact->setGivenName(splitted[0]);
							    splitted.removeFirst();
							    contact->setFamilyName(splitted.join(" "));
						    } else {
							    contact->setGivenName(displayName.isEmpty()
							                              ? Utils::coreStringToAppString(address->getUsername())
							                              : displayName);
						    }
						    contact->setDefaultFullAddress(Utils::coreStringToAppString(
						        address->asStringUriOnly())); // linphone Friend object remove specific address.
						    contact->setDefaultAddress(Utils::coreStringToAppString(address->asStringUriOnly()));
						    contacts->append(contact);
					    } else if (!it->getPhoneNumber().empty()) {
						    auto phoneNumber = it->getPhoneNumber();
						    linphoneFriend = core->createFriend();
						    linphoneFriend->addPhoneNumber(phoneNumber);
						    contact = FriendCore::create(linphoneFriend, isStored, it->getSourceFlags());
						    contact->setGivenName(Utils::coreStringToAppString(it->getPhoneNumber()));
						    contact->appendPhoneNumber(tr("device_id"),
						                               Utils::coreStringToAppString(it->getPhoneNumber()));
						    contacts->append(contact);
					    }
				    }
				    mModelConnection->invokeToCore([this, contacts]() {
					    mergeResults(*contacts);
					    delete contacts;
					    emit resultsProcessed();
				    });
			    });
			lDebug() << log().arg("Initialized");
			emit initialized();
		});
	});
}

void MagicSearchList::connectContact(FriendCore *data) {
	connect(data, &FriendCore::removed, this, qOverload<QObject *>(&MagicSearchList::remove));
	connect(data, &FriendCore::starredChanged, this, &MagicSearchList::friendStarredChanged);
	connect(data, &FriendCore::presenceChanged, this, &MagicSearchList::friendPresenceChanged);
}

void MagicSearchList::setResults(const QList<QSharedPointer<FriendCore>> &contacts) {
	for (auto item : mList) {
		auto isFriendCore = item.objectCast<FriendCore>();
		if (!isFriendCore) continue;
		disconnect(isFriendCore.get());
	}
	lDebug() << log().arg("SetResults: %1").arg(contacts.size());
	resetData<FriendCore>(contacts);
	for (auto it : contacts) {
		connectContact(it.get());
	}
}

void MagicSearchList::mergeResults(const QList<QSharedPointer<FriendCore>> &contacts) {
	// Identite d'un contact : son adresse SIP, a defaut son nom (contacts sans adresse).
	auto keyOf = [](const QSharedPointer<FriendCore> &contact) {
		auto address = contact->getDefaultAddress();
		return address.isEmpty() ? QStringLiteral("name:") + contact->getFullName() : address.toLower();
	};
	auto friendOf = [](const QSharedPointer<FriendCore> &contact) -> std::shared_ptr<linphone::Friend> {
		auto model = contact->getModel();
		return model ? model->getFriend() : nullptr;
	};
	// Nouveaux resultats par cle (une meme cle peut revenir plusieurs fois).
	QHash<QString, QList<QSharedPointer<FriendCore>>> incoming;
	for (auto &contact : contacts)
		incoming[keyOf(contact)].append(contact);

	// 1. Contacts deja affiches : conserves s'ils sont toujours dans les resultats, retires sinon.
	//    Parcours depuis la fin pour que les indices restent valides pendant les retraits.
	int kept = 0, replaced = 0, removed = 0;
	for (int i = mList.size() - 1; i >= 0; --i) {
		auto current = mList[i].objectCast<FriendCore>();
		if (!current) continue;
		auto it = incoming.find(keyOf(current));
		if (it == incoming.end() || it->isEmpty()) {
			QObject::disconnect(current.get(), nullptr, this, nullptr);
			removeRow(i);
			++removed;
			continue;
		}
		auto fresh = it->takeFirst();
		auto currentFriend = friendOf(current);
		if (currentFriend && currentFriend == friendOf(fresh)) {
			++kept; // Meme contact SDK : on garde l'objet affiche, sa presence reste a jour.
		} else {
			// Le SDK a recree le contact : l'ancien objet ne recevrait plus la presence.
			QObject::disconnect(current.get(), nullptr, this, nullptr);
			connectContact(fresh.get());
			mList[i] = fresh.objectCast<QObject>();
			auto modelIndex = index(i, 0);
			emit dataChanged(modelIndex, modelIndex);
			++replaced;
		}
	}

	// 2. Contacts apparus depuis la derniere recherche : ajoutes a la suite (le proxy les trie).
	QList<QSharedPointer<FriendCore>> added;
	for (auto &contact : contacts) {
		auto it = incoming.find(keyOf(contact));
		if (it != incoming.end() && it->removeOne(contact)) added.append(contact);
	}
	for (auto &contact : added)
		connectContact(contact.get());
	ListProxy::add(added);
	lDebug() << log()
	                .arg("MergeResults: %1 kept, %2 replaced, %3 removed, %4 added")
	                .arg(kept)
	                .arg(replaced)
	                .arg(removed)
	                .arg(added.size());
}

void MagicSearchList::add(QSharedPointer<FriendCore> contact) {
	connectContact(contact.get());
	ListProxy::add(contact);
}

void MagicSearchList::setSearch(const QString &search) {
	mSearchFilter = search;
	// Filtrage immediat des resultats deja affiches (l'annuaire est souvent deja charge en entier) ; la recherche
	// du SDK, plus lente (delai LDAP, aller-retour reseau), complete ensuite la liste.
	emit searchFilterChanged();
	if (!search.isEmpty()) {
		emit lSearch(search, mSourceFlags, mAggregationFlag, mMaxResults);
	} else {
		beginResetModel();
		mList.clear();
		endResetModel();
	}
}

QString MagicSearchList::getSearch() const {
	return mSearchFilter;
}

int MagicSearchList::getSourceFlags() const {
	return mSourceFlags;
}

void MagicSearchList::setSourceFlags(int flags) {
	if (mSourceFlags != flags) {
		mSourceFlags = flags;
		emit sourceFlagsChanged(mSourceFlags);
	}
}

int MagicSearchList::getMaxResults() const {
	return mMaxResults;
}

void MagicSearchList::setMaxResults(int maxResults) {
	if (mMaxResults != maxResults) {
		mMaxResults = maxResults;
		emit maxResultsChanged(mMaxResults);
	}
}

bool MagicSearchList::getShowMe() const {
	return mShowMe;
}

bool MagicSearchList::getExactNumberMatch() const {
	return mExactNumberMatch;
}

void MagicSearchList::setExactNumberMatch(bool exact) {
	if (mExactNumberMatch != exact) {
		mExactNumberMatch = exact;
		emit exactNumberMatchChanged(mExactNumberMatch);
	}
}

void MagicSearchList::setShowMe(bool showMe) {
	if (mShowMe != showMe) {
		mShowMe = showMe;
		emit showMeChanged(mShowMe);
	}
}

LinphoneEnums::MagicSearchAggregation MagicSearchList::getAggregationFlag() const {
	return mAggregationFlag;
}

void MagicSearchList::setAggregationFlag(LinphoneEnums::MagicSearchAggregation flags) {
	if (mAggregationFlag != flags) {
		mAggregationFlag = flags;
		emit aggregationFlagChanged(mAggregationFlag);
	}
}

QHash<int, QByteArray> MagicSearchList::roleNames() const {
	QHash<int, QByteArray> roles;
	roles[Qt::DisplayRole] = "$modelData";
	roles[Qt::DisplayRole + 1] = "isStored";
	return roles;
}

QVariant MagicSearchList::data(const QModelIndex &index, int role) const {
	int row = index.row();
	if (!index.isValid() || row < 0 || row >= mList.count()) return QVariant();
	if (role == Qt::DisplayRole) {
		return QVariant::fromValue(new FriendGui(mList[row].objectCast<FriendCore>()));
	} else if (role == Qt::DisplayRole + 1) {
		return mList[row].objectCast<FriendCore>()->getIsStored() || mList[row].objectCast<FriendCore>()->isLdap() ||
		       mList[row].objectCast<FriendCore>()->isCardDAV();
	}
	return QVariant();
}

int MagicSearchList::findFriendIndexByAddress(const QString &address) {
	for (int i = 0; i < getCount(); ++i) {
		auto friendCore = getAt<FriendCore>(i);
		if (!friendCore) continue;
		for (auto &friendAddress : friendCore->getAllAddresses()) {
			auto map = friendAddress.toMap();
			if (map["address"].toString() == address) {
				return i;
			}
		}
	}
	return -1;
}

QSharedPointer<FriendCore> MagicSearchList::findFriendByAddress(const QString &address) {
	for (int i = 0; i < getCount(); ++i) {
		auto friendCore = getAt<FriendCore>(i);
		if (!friendCore) continue;
		for (auto &friendAddress : friendCore->getAllAddresses()) {
			auto map = friendAddress.toMap();
			if (map["address"].toString() == address) {
				return friendCore;
			}
		}
	}
	return nullptr;
}
