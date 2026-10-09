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

#include "FriendCore.hpp"

#include "core/App.hpp"
#include "model/tool/ToolModel.hpp"
#include "tool/Utils.hpp"
#include "tool/thread/SafeConnection.hpp"
#include <QMutex>
#include <QRegularExpression>
#include <map>
#include <tuple>

DEFINE_ABSTRACT_OBJECT(FriendCore)

// Translation does not work if not in class directly
//: "Adresse SIP"
const QString _addressLabel = FriendCore::tr("sip_address");
//: "Téléphone"
const QString _phoneLabel = FriendCore::tr("device_id");

namespace {
// Une seule fiche par contact SDK : listes de contacts, avatars, historique et conversations
// partagent le meme FriendCore. Chaque copie etait un ecouteur SDK de plus, mise a jour a chaque
// presence et a chaque fin d'appel : jusqu'a 30 copies d'un meme contact ont ete mesurees dans une
// journee, d'ou des gels croissants. La cle reprend aussi isStored et les sources de recherche, qui
// fixent l'etat de la fiche : deux reglages differents gardent deux fiches, comme avant.
using SharedCoreKey = std::tuple<const linphone::Friend *, bool, int>;
QMutex gSharedCoresMutex;
std::map<SharedCoreKey, QWeakPointer<FriendCore>> gSharedCores;
} // namespace

QSharedPointer<FriendCore>
FriendCore::create(const std::shared_ptr<linphone::Friend> &contact, bool isStored, int sourceFlags) {
	// Seules les sources annuaire (LDAP, CardDAV) changent la fiche (mIsLdap, mIsCardDAV).
	const int sharedSourceFlags = sourceFlags & ((int)linphone::MagicSearch::Source::LdapServers |
	                                             (int)linphone::MagicSearch::Source::RemoteCardDAV);
	const SharedCoreKey key{contact.get(), isStored, sharedSourceFlags};
	if (contact) {
		QMutexLocker locker(&gSharedCoresMutex);
		auto it = gSharedCores.find(key);
		if (it != gSharedCores.end()) {
			auto existing = it->second.toStrongRef();
			// Meme contact SDK toujours suivi : un contact supprime lache son objet SDK, dont l'adresse
			// memoire peut alors etre reprise par un autre contact.
			if (existing && existing->mFriendModel && existing->mFriendModel->getFriend() == contact &&
			    existing->mIsStored == isStored)
				return existing;
		}
	}
	auto sharedPointer =
	    QSharedPointer<FriendCore>(new FriendCore(contact, isStored, sourceFlags), &QObject::deleteLater);
	sharedPointer->setSelf(sharedPointer);
	sharedPointer->moveToThread(App::getInstance()->thread());
	if (contact) {
		QMutexLocker locker(&gSharedCoresMutex);
		if (gSharedCores.size() > 512) { // Purge des fiches disparues.
			for (auto it = gSharedCores.begin(); it != gSharedCores.end();)
				it = it->second.isNull() ? gSharedCores.erase(it) : std::next(it);
		}
		gSharedCores[key] = sharedPointer;
	}
	return sharedPointer;
}

FriendCore::FriendCore(const std::shared_ptr<linphone::Friend> &contact, bool isStored, int sourceFlags)
    : QObject(nullptr) {
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
	if (contact) {
		mustBeInLinphoneThread(getClassName());
		mFriendModel = Utils::makeQObject_ptr<FriendModel>(contact);
		mFriendModel->setSelf(mFriendModel);
		auto presence = mFriendModel->getPresence(contact);
		auto note = mFriendModel->getPresenceNote(contact);
		bool inCall = ToolModel::isAnsweredCallPresence(contact->getPresenceModel());

		lDebug() << "[FriendCore] INITIAL PRESENCE:"
		         << "address=" << Utils::addressUriOnly(contact->getAddress())
		         << "presence=" << static_cast<int>(presence) << "note=" << note;

		App::postCoreAsync([this, presence, note, inCall]() {
			setPresence(presence, note);
			setInCall(inCall);
		});
		mPictureUri = Utils::coreStringToAppString(contact->getPhoto());
		mFullName = mFriendModel->getFullName();
		auto defaultAddress = contact->getAddress();
		if (!defaultAddress) {
			for (auto &address : contact->getAddresses()) {
				if (address) {
					defaultAddress = address;
					break;
				}
			}
		}
		auto vcard = contact->getVcard();
		if (vcard) {
			mOrganization = Utils::coreStringToAppString(vcard->getOrganization());
			mJob = Utils::coreStringToAppString(vcard->getJobTitle());
			mGivenName = Utils::coreStringToAppString(vcard->getGivenName());
			mFamilyName = Utils::coreStringToAppString(vcard->getFamilyName());
			mVCardString = Utils::coreStringToAppString(vcard->asVcard4String());
		}

		auto addresses = contact->getAddresses();
		for (auto &address : addresses) {
			mAddressList.append(Utils::createFriendAddressVariant(
			    tr("sip_address"), Utils::coreStringToAppString(address->asStringUriOnly())));
		}
		mDefaultAddress = defaultAddress ? Utils::coreStringToAppString(defaultAddress->asStringUriOnly()) : QString();
		mDefaultFullAddress = defaultAddress ? Utils::coreStringToAppString(defaultAddress->asString()) : QString();
		// Pas de photo dans la fiche : se rabattre sur celle publiee par l'annuaire distant.
		// L'URL peut renvoyer 404 si l'utilisateur n'en a pas ; Avatar.qml retombe alors sur
		// les initiales en surveillant le statut de chargement de l'image.
		if (mPictureUri.isEmpty()) mPictureUri = ToolModel::getRemoteAvatarUrl(defaultAddress);
		// lDebug() << mDefaultAddress << " / " << mDefaultFullAddress;
		auto phoneNumbers = contact->getPhoneNumbersWithLabel();
		for (auto &phoneNumber : phoneNumbers) {
			auto label = Utils::coreStringToAppString(phoneNumber->getLabel());
			if (label.isEmpty()) label = tr("device_id");
			mPhoneNumberList.append(
			    Utils::createFriendAddressVariant(label, Utils::coreStringToAppString(phoneNumber->getPhoneNumber())));
		}

		auto devices = contact->getDevices();
		for (auto &device : devices) {
			mDeviceList.append(
			    Utils::createFriendDeviceVariant(Utils::coreStringToAppString(device->getDisplayName()),
			                                     // do not use uri only as we want the unique device
			                                     Utils::coreStringToAppString(Utils::addressFull(device->getAddress())),
			                                     LinphoneEnums::fromLinphone(device->getSecurityLevel())));
		}
		updateVerifiedDevicesCount();
		mStarred = contact->getStarred();
		mIsSaved = true;
		mIsStored = isStored;
		mIsLdap = ToolModel::friendIsInFriendList(ToolModel::getLdapFriendList(), contact) ||
		          (sourceFlags & (int)linphone::MagicSearch::Source::LdapServers) != 0;
		mIsCardDAV = (sourceFlags & (int)linphone::MagicSearch::Source::RemoteCardDAV) != 0;
		mIsAppFriend = ToolModel::friendIsInFriendList(ToolModel::getAppFriendList(), contact);
	} else {
		mIsSaved = false;
		mStarred = false;
		mIsStored = false;
		mIsLdap = false;
		mIsCardDAV = false;
	}

	connect(this, &FriendCore::addressChanged, &FriendCore::allAddressesChanged);
	connect(this, &FriendCore::phoneNumberChanged, &FriendCore::allAddressesChanged);
}

FriendCore::FriendCore(const FriendCore &friendCore) {
	// Only copy friend values without models for lambda using and avoid concurrencies.
	mAddressList = friendCore.mAddressList;
	mPhoneNumberList = friendCore.mPhoneNumberList;
	mDefaultAddress = friendCore.mDefaultAddress;
	mDefaultFullAddress = friendCore.mDefaultFullAddress;
	mGivenName = friendCore.mGivenName;
	mFamilyName = friendCore.mFamilyName;
	mFullName = friendCore.mFullName;
	mOrganization = friendCore.mOrganization;
	mJob = friendCore.mJob;
	mPictureUri = friendCore.mPictureUri;
	mIsSaved = friendCore.mIsSaved;
	mIsStored = friendCore.mIsStored;
	mIsLdap = friendCore.mIsLdap;
	mIsAppFriend = friendCore.mIsAppFriend;
	mIsCardDAV = friendCore.mIsCardDAV;
}

FriendCore::~FriendCore() {
	mustBeInMainThread("~" + getClassName());
	if (mFriendModel) emit mFriendModel->removeListener();
}

void FriendCore::setSelf(SafeSharedPointer<FriendCore> me) {
	setSelf(me.mQDataWeak.lock());
}
void FriendCore::setSelf(QSharedPointer<FriendCore> me) {
	if (me) {
		// Le statut depend des adresses (poste interne ou non) : reaffiche quand elles changent.
		connect(this, &FriendCore::addressChanged, this, &FriendCore::presenceChanged, Qt::UniqueConnection);
		connect(this, &FriendCore::defaultAddressChanged, this, &FriendCore::presenceChanged, Qt::UniqueConnection);
		if (mFriendModel) {
			mFriendModelConnection = SafeConnection<FriendCore, FriendModel>::create(me, mFriendModel);
			mFriendModelConnection->makeConnectToModel(&FriendModel::updated, [this]() {
				mFriendModelConnection->invokeToCore([this]() { emit friendUpdated(); });
			});
			mFriendModelConnection->makeConnectToModel(
			    &FriendModel::removed, [this]() { mFriendModelConnection->invokeToCore([this]() { removed(this); }); });
			mFriendModelConnection->makeConnectToModel(
			    &FriendModel::presenceReceived, [this](LinphoneEnums::Presence presence, QString presenceNote) {
				    auto devices = mFriendModel->getDevices();
				    QVariantList devicesList;
				    for (auto &device : devices) {
					    devicesList.append(Utils::createFriendDeviceVariant(
					        Utils::coreStringToAppString(device->getDisplayName()),
					        // do not use uri only as we want the unique device
					        Utils::coreStringToAppString(Utils::addressFull(device->getAddress())),
					        LinphoneEnums::fromLinphone(device->getSecurityLevel())));
				    }
				    mFriendModelConnection->invokeToCore([this, presence, devicesList, presenceNote]() {
					    setPresence(presence, presenceNote);
					    setDevices(devicesList);
					    updateVerifiedDevicesCount();
				    });
			    });
			mFriendModelConnection->makeConnectToModel(&FriendModel::inCallChanged, [this](bool inCall) {
				mFriendModelConnection->invokeToCore([this, inCall]() { setInCall(inCall); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::pictureUriChanged, [this](const QString &uri) {
				mFriendModelConnection->invokeToCore([this, uri]() { this->onPictureUriChanged(uri); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::starredChanged, [this](bool starred) {
				mFriendModelConnection->invokeToCore([this, starred]() { this->onStarredChanged(starred); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::givenNameChanged, [this](const QString &name) {
				mFriendModelConnection->invokeToCore([this, name]() { setGivenName(name); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::familyNameChanged, [this](const QString &name) {
				mFriendModelConnection->invokeToCore([this, name]() { setFamilyName(name); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::organizationChanged, [this](const QString &orga) {
				mFriendModelConnection->invokeToCore([this, orga]() { setOrganization(orga); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::fullNameChanged, [this](const QString &name) {
				mFriendModelConnection->invokeToCore([this, name]() { setFullName(name); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::jobChanged, [this](const QString &job) {
				mFriendModelConnection->invokeToCore([this, job]() { setJob(job); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::addressesChanged, [this]() {
				auto numbers = mFriendModel->getAddresses();
				QList<QVariant> addr;
				for (auto &num : numbers) {
					addr.append(Utils::createFriendAddressVariant(
					    tr("sip_address"), Utils::coreStringToAppString(num->asStringUriOnly())));
				}
				// Adresses SIP : elles remplacaient la liste des numeros de telephone (resetPhoneNumbers).
				mFriendModelConnection->invokeToCore([this, addr]() { resetAddresses(addr); });
			});
			mFriendModelConnection->makeConnectToModel(&FriendModel::phoneNumbersChanged, [this]() {
				auto numbers = mFriendModel->getPhoneNumbers();
				QList<QVariant> addr;
				for (auto &num : numbers) {
					// Libelle conserve (« Mobile »...), comme a la creation de la fiche ; il etait remplace
					// par le libelle par defaut a chaque mise a jour.
					auto label = Utils::coreStringToAppString(num->getLabel());
					if (label.isEmpty()) label = tr("device_id");
					addr.append(
					    Utils::createFriendAddressVariant(label, Utils::coreStringToAppString(num->getPhoneNumber())));
				}
				mFriendModelConnection->invokeToCore([this, addr]() { resetPhoneNumbers(addr); });
			});
			mFriendModelConnection->makeConnectToModel(
			    &FriendModel::objectNameChanged,
			    [this](const QString &objectName) { lDebug() << "object name changed" << objectName; });

			// From GUI
			mFriendModelConnection->makeConnectToCore(&FriendCore::lSetStarred, [this](bool starred) {
				mFriendModelConnection->invokeToModel([this, starred]() { mFriendModel->setStarred(starred); });
			});
			if (!mCoreModelConnection) {
				mCoreModelConnection = SafeConnection<FriendCore, CoreModel>::create(me, CoreModel::getInstance());
			}
			mCoreModelConnection->makeConnectToModel(
			    &CoreModel::callStateChanged,
			    [this](const std::shared_ptr<linphone::Core> &core, const std::shared_ptr<linphone::Call> &call,
			           linphone::Call::State state, const std::string &message) {
				    if (state != linphone::Call::State::End && state != linphone::Call::State::Released) return;
				    // Seul le contact de cet appel peut voir ses appareils changer (verification de securite en
				    // appel) : chaque fiche vivante refaisait sinon ce calcul a chaque fin d'appel.
				    auto contact = mFriendModel ? mFriendModel->getFriend() : nullptr;
				    auto remoteAddress = call ? call->getRemoteAddress() : nullptr;
				    if (!contact || !remoteAddress) return;
				    bool isThisContact = false;
				    for (auto &address : contact->getAddresses()) {
					    if (address && address->weakEqual(remoteAddress)) {
						    isThisContact = true;
						    break;
					    }
				    }
				    if (!isThisContact) return;
				    auto devices = mFriendModel->getDevices();
				    QVariantList devicesList;
				    for (auto &device : devices) {
					    devicesList.append(Utils::createFriendDeviceVariant(
					        Utils::coreStringToAppString(device->getDisplayName()),
					        // do not use uri only as we want the unique device
					        Utils::coreStringToAppString(Utils::addressFull(device->getAddress())),
					        LinphoneEnums::fromLinphone(device->getSecurityLevel())));
				    }
				    mCoreModelConnection->invokeToCore([this, devicesList]() {
					    setDevices(devicesList);
					    updateVerifiedDevicesCount();
				    });
			    });
			mCoreModelConnection->makeConnectToCore(&FriendCore::saved, [this]() {
				mCoreModelConnection->invokeToModel(
				    [this, f = mFriendModel->getFriend()]() { emit CoreModel::getInstance()->friendUpdated(f); });
			});

		} else { // Create
			mCoreModelConnection = SafeConnection<FriendCore, CoreModel>::create(me, CoreModel::getInstance());
		}
	}
}

void FriendCore::reset(const FriendCore &contact) {
	resetAddresses(contact.getAddresses());
	resetPhoneNumbers(contact.getPhoneNumbers());
	setDefaultAddress(contact.getDefaultAddress());
	setDefaultFullAddress(contact.getDefaultFullAddress());
	setGivenName(contact.getGivenName());
	setFamilyName(contact.getFamilyName());
	setOrganization(contact.getOrganization());
	setFullName(contact.getFullName());
	setJob(contact.getJob());
	setPictureUri(contact.getPictureUri());
	setIsSaved(mFriendModel != nullptr);
}

QString FriendCore::getFullName() const {
	return mFullName;
}

void FriendCore::setFullName(const QString &name) {
	if (mFullName != name) {
		mFullName = name.simplified();
		emit fullNameChanged(name);
		setIsSaved(false);
	}
}

QString FriendCore::getGivenName() const {
	return mGivenName;
}

void FriendCore::setGivenName(const QString &name) {
	if (mGivenName != name) {
		mGivenName = name.simplified();
		emit givenNameChanged(name);
		setIsSaved(false);
	}
}

QString FriendCore::getOrganization() const {
	return mOrganization;
}

void FriendCore::setOrganization(const QString &orga) {
	if (mOrganization != orga) {
		mOrganization = orga;
		emit organizationChanged();
		setIsSaved(false);
	}
}

QString FriendCore::getJob() const {
	return mJob;
}

void FriendCore::setJob(const QString &job) {
	if (mJob != job) {
		mJob = job;
		emit jobChanged();
		setIsSaved(false);
	}
}

QString FriendCore::getFamilyName() const {
	return mFamilyName;
}

void FriendCore::setFamilyName(const QString &name) {
	if (mFamilyName != name) {
		mFamilyName = name.simplified();
		emit familyNameChanged(name);
		setIsSaved(false);
	}
}

bool FriendCore::getStarred() const {
	return mStarred;
}

void FriendCore::onStarredChanged(bool starred) {
	mStarred = starred;
	save();
	emit starredChanged();
}

QString FriendCore::getVCard() const {
	return mVCardString;
}

QList<QVariant> FriendCore::getPhoneNumbers() const {
	return mPhoneNumberList;
}

QVariant FriendCore::getPhoneNumberAt(int index) const {
	if (index < 0 || index >= mPhoneNumberList.count()) return QVariant();
	return mPhoneNumberList[index];
}

void FriendCore::setPhoneNumberAt(int index, const QString &label, const QString &phoneNumber) {
	if (index < 0 || index >= mPhoneNumberList.count()) return;
	auto map = mPhoneNumberList[index].toMap();
	auto oldLabel = map["label"].toString();
	if (/*oldLabel != label || */ map["address"] != phoneNumber) {
		mPhoneNumberList.replace(index,
		                         Utils::createFriendAddressVariant(label.isEmpty() ? oldLabel : label, phoneNumber));
		emit phoneNumberChanged();
		setIsSaved(false);
	}
}

void FriendCore::removePhoneNumber(int index) {
	if (index != -1) mPhoneNumberList.remove(index);
	emit phoneNumberChanged();
	setIsSaved(false);
}

void FriendCore::appendPhoneNumber(const QString &label, const QString &number) {
	mPhoneNumberList.append(Utils::createFriendAddressVariant(label, number));
	emit phoneNumberChanged();
	setIsSaved(false);
}

void FriendCore::resetPhoneNumbers(QList<QVariant> newList) {
	mPhoneNumberList = newList;
	emit phoneNumberChanged();
}

QList<QVariant> FriendCore::getAddresses() const {
	return mAddressList;
}

QVariant FriendCore::getAddressAt(int index) const {
	if (index < 0 || index >= mAddressList.count()) return QVariant();
	return mAddressList[index];
}

void FriendCore::setAddressAt(int index, QString label, QString address) {
	if (index < 0 || index >= mAddressList.count()) return;
	auto map = mAddressList[index].toMap();
	label = label.isEmpty() ? map["label"].toString() : label;
	QString currentAddress = map["address"].toString();

	if (Utils::isUsername(address)) {
		mCoreModelConnection->invokeToModel([this, index, label, currentAddress, address]() {
			auto linphoneAddr = ToolModel::interpretUrl(address);
			QString interpretedAddr = Utils::coreStringToAppString(linphoneAddr->asStringUriOnly());
			if (interpretedAddr != currentAddress) {
				mCoreModelConnection->invokeToCore([this, index, label, interpretedAddr]() {
					mAddressList.replace(index, Utils::createFriendAddressVariant(label, interpretedAddr));
					emit addressChanged();
					setIsSaved(false);
				});
			}
		});
	} else if (address != currentAddress) {
		mAddressList.replace(index, Utils::createFriendAddressVariant(label, address));
		emit addressChanged();
		setIsSaved(false);
	}
}

void FriendCore::removeAddress(int index) {
	if (index < 0 && index >= mAddressList.size()) return;
	auto map = mAddressList[index].toMap();
	if (map["address"].toString() == mDefaultFullAddress) mDefaultFullAddress.clear();
	if (map["address"].toString() == mDefaultAddress) mDefaultAddress.clear();
	mAddressList.remove(index);
	emit addressChanged();
	setIsSaved(false);
}

void FriendCore::appendAddress(const QString &addr) {
	if (addr.isEmpty()) return;
	mCoreModelConnection->invokeToModel([this, addr]() {
		auto linphoneAddr = ToolModel::interpretUrl(addr);
		QString interpretedFullAddress = linphoneAddr ? Utils::coreStringToAppString(linphoneAddr->asString()) : "";
		QString interpretedAddress = linphoneAddr ? Utils::coreStringToAppString(linphoneAddr->asStringUriOnly()) : "";
		mCoreModelConnection->invokeToCore([this, interpretedAddress, interpretedFullAddress]() {
			if (interpretedAddress.isEmpty())
				Utils::showInformationPopup(tr("information_popup_error_title"),
				                            //: "Adresse invalide"
				                            tr("information_popup_invalid_address_message"), false);
			else {
				mAddressList.append(Utils::createFriendAddressVariant(tr("sip_address"), interpretedAddress));
				if (mDefaultFullAddress.isEmpty()) mDefaultFullAddress = interpretedFullAddress;
				if (mDefaultAddress.isEmpty()) mDefaultAddress = interpretedAddress;
				emit addressChanged();
				setIsSaved(false);
			}
		});
	});
}

void FriendCore::resetAddresses(QList<QVariant> newList) {
	mAddressList = newList;
	emit addressChanged();
}

// Display all sip addresses and remove phone numbers duplicates (priority on sip)
QList<QVariant> FriendCore::getAllAddresses() const {
	QList<QVariant> addresses;
	auto addressIt = mAddressList.begin();
	auto phoneNumbers = mPhoneNumberList;
	while (addressIt != mAddressList.end()) {
		auto username = Utils::getUsername(addressIt->toMap()["address"].toString());
		// Retire les numeros identiques a l'identifiant d'une adresse SIP (878 et sip:878@...).
		// Auparavant std::remove_if sans erase : rien n'etait retire, le doublon restait, et
		// l'appel ouvrait un choix entre deux entrees designant le meme poste.
		phoneNumbers.removeIf(
		    [&username](const QVariant &data) { return data.toMap()["address"].toString() == username; });
		++addressIt;
	}
	addresses << phoneNumbers;
	addresses << mAddressList;
	return addresses;
}

QList<QVariant> FriendCore::getDevices() const {
	return mDeviceList;
}

void FriendCore::updateVerifiedDevicesCount() {
	mVerifiedDeviceCount = 0;
	for (auto &device : mDeviceList) {
		auto map = device.toMap();
		if (map["securityLevel"].value<LinphoneEnums::SecurityLevel>() ==
		    LinphoneEnums::SecurityLevel::EndToEndEncryptedAndVerified)
			++mVerifiedDeviceCount;
	}
	emit verifiedDevicesChanged();
}

void FriendCore::setDevices(QVariantList devices) {
	mDeviceList.clear();
	mDeviceList.append(devices);
	emit devicesChanged();
}

LinphoneEnums::SecurityLevel FriendCore::getSecurityLevelForAddress(const QString &address) const {
	for (auto &device : mDeviceList) {
		auto map = device.toMap();
		if (map["address"].toString() == address) {
			return map["securityLevel"].value<LinphoneEnums::SecurityLevel>();
		}
	}
	return LinphoneEnums::SecurityLevel::None;
}

QString FriendCore::getDefaultFullAddress() const {
	return mDefaultFullAddress;
}

void FriendCore::setDefaultFullAddress(const QString &address) {
	if (mDefaultFullAddress != address) {
		mDefaultFullAddress = address;
		emit defaultFullAddressChanged();
	}
}

QString FriendCore::getDefaultAddress() const {
	return mDefaultAddress;
}

void FriendCore::setDefaultAddress(const QString &address) {
	if (mDefaultAddress != address) {
		mDefaultAddress = address;
		emit defaultAddressChanged();
	}
}

QString FriendCore::getPictureUri() const {
	return mPictureUri;
}

void FriendCore::setPictureUri(const QString &uri) {
	if (mPictureUri != uri) {
		mPictureUri = uri;
		emit pictureUriChanged();
		setIsSaved(false);
	}
}

void FriendCore::onPictureUriChanged(QString uri) {
	mPictureUri = uri;
	emit pictureUriChanged();
}

bool FriendCore::getIsSaved() const {
	return mIsSaved;
}
void FriendCore::setIsSaved(bool data) {
	if (mIsSaved != data) {
		mIsSaved = data;
		if (mIsSaved) setIsStored(true);
		emit isSavedChanged(mIsSaved);
	}
}

bool FriendCore::getIsStored() const {
	return mIsStored;
}
void FriendCore::setIsStored(bool data) {
	if (mIsStored != data) {
		mIsStored = data;
		emit isStoredChanged();
	}
}

void FriendCore::writeIntoModel(std::shared_ptr<FriendModel> model) const {
	mustBeInLinphoneThread(QString("[") + gClassName + "] " + Q_FUNC_INFO);
	model->getFriend()->edit();
	// needed to create the vcard if not created yet
	auto name = mGivenName + (mFamilyName.isEmpty() || mGivenName.isEmpty() ? "" : " ") + mFamilyName;
	model->setName(name.isEmpty() ? (mFullName.isEmpty() ? mOrganization : mFullName) : name);
	auto core = CoreModel::getInstance()->getCore();

	std::list<std::shared_ptr<linphone::Address>> addresses;
	for (auto &addr : mAddressList) {
		auto friendAddress = addr.toMap();
		auto address =
		    linphone::Factory::get()->createAddress(Utils::appStringToCoreString(friendAddress["address"].toString()));
		addresses.push_back(address);
	}
	model->resetAddresses(addresses);

	model->setAddress(ToolModel::interpretUrl(mDefaultFullAddress));

	std::list<std::shared_ptr<linphone::FriendPhoneNumber>> phones;
	for (auto &number : mPhoneNumberList) {
		auto friendAddress = number.toMap();
		auto num = linphone::Factory::get()->createFriendPhoneNumber(
		    Utils::appStringToCoreString(friendAddress["address"].toString()),
		    Utils::appStringToCoreString(friendAddress["label"].toString()));
		phones.push_back(num);
	}
	model->resetPhoneNumbers(phones);
	model->setGivenName(mGivenName);
	model->setFamilyName(mFamilyName);
	model->setOrganization(mOrganization);
	model->setFullName(mFullName);
	model->setJob(mJob);
	model->setPictureUri(mPictureUri);
	// Presence reservee aux postes internes : abonnement selon les adresses enregistrees (nouveau contact
	// ou adresse modifiee), applique par done().
	model->getFriend()->enableSubscribes(ToolModel::isInternalExtension(model->getFriend()));
	model->getFriend()->done();
	emit model->updated();
}

void FriendCore::writeFromModel(const std::shared_ptr<FriendModel> &model) {
	mustBeInLinphoneThread(QString("[") + gClassName + "] " + Q_FUNC_INFO);

	QList<QVariant> addresses;
	for (auto &addr : model->getAddresses()) {
		addresses.append(Utils::createFriendAddressVariant(tr("sip_address"),
		                                                   Utils::coreStringToAppString(addr->asStringUriOnly())));
	}
	mAddressList = addresses;
	mDefaultAddress = model->getDefaultAddress();
	mDefaultFullAddress = model->getDefaultFullAddress();

	QList<QVariant> phones;
	for (auto &number : model->getPhoneNumbers()) {
		phones.append(Utils::createFriendAddressVariant(Utils::coreStringToAppString(number->getLabel()),
		                                                Utils::coreStringToAppString(number->getPhoneNumber())));
	}
	mPhoneNumberList = phones;
	mGivenName = model->getGivenName();
	mFamilyName = model->getFamilyName();
	mOrganization = model->getOrganization();
	mJob = model->getJob();
	mPictureUri = model->getPictureUri();
}

void FriendCore::remove() {
	if (mFriendModel) { // Update
		mFriendModelConnection->invokeToModel([this]() { mFriendModel->remove(); });
	}
}

void FriendCore::save() { // Save Values to model
	mustBeInMainThread(getClassName() + "::save()");
	if (mAddressList.size() > 0) {
		auto it = std::find_if(mAddressList.begin(), mAddressList.end(), [this](const QVariant &a) {
			return a.toMap()["address"].toString() == mDefaultFullAddress;
		});
		if (it == mAddressList.end()) {
			mDefaultFullAddress = mAddressList[0].toMap()["address"].toString();
			emit defaultFullAddressChanged();
		}
	} else {
		mDefaultFullAddress = "";
		emit defaultFullAddressChanged();
	}
	FriendCore *thisCopy = new FriendCore(*this); // Pointer to avoid multiple copies in lambdas
	if (mFriendModel) {
		mFriendModelConnection->invokeToModel([this, thisCopy]() { // Copy values to avoid concurrency
			mustBeInLinphoneThread(getClassName() + "::save()");
			thisCopy->writeIntoModel(mFriendModel);
			thisCopy->deleteLater();
			mVCardString = mFriendModel->getVCardAsString();
			mFriendModelConnection->invokeToCore([this]() {
				setIsSaved(true);
				emit saved();
			});
		});
	} else {
		mCoreModelConnection->invokeToModel([this, thisCopy]() {
			std::shared_ptr<linphone::Friend> contact;
			auto core = CoreModel::getInstance()->getCore();
			auto appFriends = ToolModel::getAppFriendList();
			for (auto &addr : mAddressList) {
				auto friendAddress = addr.toMap();
				auto linphoneAddr = ToolModel::interpretUrl(friendAddress["address"].toString());
				contact = appFriends->findFriendByAddress(linphoneAddr);
				if (contact) break;
			}
			if (contact != nullptr) {
				auto friendModel = Utils::makeQObject_ptr<FriendModel>(contact);
				friendModel->setSelf(friendModel);
				mCoreModelConnection->invokeToCore([this, thisCopy, friendModel, contact] {
					mFriendModel = friendModel;
					mCoreModelConnection->invokeToModel([this, thisCopy, contact] {
						thisCopy->writeIntoModel(mFriendModel);
						thisCopy->deleteLater();
						mVCardString = mFriendModel->getVCardAsString();
						emit CoreModel::getInstance()->friendUpdated(contact);
						mCoreModelConnection->invokeToCore([this] {
							setIsSaved(true);
							emit saved();
						});
					});
				});
			} else {
				auto contact = core->createFriend();
				contact->enableSubscribes(true);
				auto friendModel = Utils::makeQObject_ptr<FriendModel>(contact);
				friendModel->setSelf(friendModel);
				mCoreModelConnection->invokeToCore([this, thisCopy, friendModel, contact] {
					mFriendModel = friendModel;
					mCoreModelConnection->invokeToModel([this, thisCopy, contact] {
						auto core = CoreModel::getInstance()->getCore();
						thisCopy->writeIntoModel(mFriendModel);
						thisCopy->deleteLater();
						mVCardString = mFriendModel->getVCardAsString();
						auto carddavListForNewFriends = SettingsModel::getCardDAVListForNewFriends();
						auto listWhereToAddFriend = carddavListForNewFriends != nullptr ? carddavListForNewFriends
						                                                                : ToolModel::getAppFriendList();
						bool created = (listWhereToAddFriend->addFriend(contact) == linphone::FriendList::Status::OK);
						if (created) {
							listWhereToAddFriend->updateSubscriptions();
							if (listWhereToAddFriend->getType() == linphone::FriendList::Type::CardDAV) {
								listWhereToAddFriend->synchronizeFriendsFromServer();
							}
							emit CoreModel::getInstance()->friendCreated(contact);
						}
						mCoreModelConnection->invokeToCore([this, created]() {
							if (created) setSelf(mCoreModelConnection->mCore);
							setIsSaved(created);
							if (created) emit saved();
						});
					});
				});
			}
		});
	}
}

void FriendCore::undo() { // Retrieve values from model
	if (mFriendModel) {
		mFriendModelConnection->invokeToModel([this]() {
			FriendCore *contact = new FriendCore(*this);
			contact->writeFromModel(mFriendModel);
			contact->moveToThread(App::getInstance()->thread());
			mFriendModelConnection->invokeToCore([this, contact]() {
				this->reset(*contact);
				contact->deleteLater();
			});
		});
	}
}

bool FriendCore::isLdap() const {
	return mIsLdap;
}

bool FriendCore::isCardDAV() const {
	return mIsCardDAV;
}

bool FriendCore::isAppFriend() const {
	return mIsAppFriend;
}

bool FriendCore::getReadOnly() const {
	return isLdap() || isCardDAV(); // TODO add conditions for friends retrieved via HTTP
	                                // [misc]vcards-contacts-list=<URL> & CardDAV
}

std::shared_ptr<FriendModel> FriendCore::getModel() {
	return mFriendModel;
}

// FreeSWITCH se sert du champ <note> des notifications de presence pour decrire l'etat
// technique du poste : sur 6 218 notes recues en deux jours, 6 035 etaient de cette nature.
// Affichees telles quelles, elles se presentent comme des phrases ecrites par le contact --
// « Unregistered » sous le nom de quelqu'un. On ne garde donc que ce qui ressemble a un vrai
// message. L'etat, lui, est deja porte par la pastille et par la ligne de statut.
static bool isServerGeneratedNote(const QString &note) {
	// busy, away, offline et do not disturb servent aussi de note par defaut a nos propres
	// publications (ToolModel::appPresenceToCorePresenceModel).
	static const QStringList exactValues = {"unregistered", "registered",   "available",      "unavailable",
	                                        "offline",      "idle",         "busy",           "away",
	                                        "on the phone", "in a meeting", "do not disturb", "dnd"};
	if (exactValues.contains(note.trimmed().toLower())) return true;
	// Etats d'appel, suivis du numero du correspondant : « Talk 222 », « Ring 1000 »...
	static const QRegularExpression callState(QStringLiteral("^(talk|ring|call|hold|early|proceeding)\\s+\\S+$"),
	                                          QRegularExpression::CaseInsensitiveOption);
	return callState.match(note.trimmed()).hasMatch();
}

void FriendCore::setPresence(LinphoneEnums::Presence presence, QString presenceNote) {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	if (isServerGeneratedNote(presenceNote)) presenceNote.clear();
	bool notify = false;
	// Etat inconnu = pas de pastille, plutot qu'une pastille perimee. Ne l'atteignent plus
	// que les vraies absences d'information (abonnement termine sans contenu, en attente de
	// sa relance) : les contacts deconnectes arrivent en Offline et les appels en cours
	// signales par le serveur sont ignores en amont (FriendModel::onPresenceReceived).
	if (presence != mPresence) {
		mPresence = presence;
		notify = true;
	}
	if (presenceNote != mPresenceNote) {
		mPresenceNote = presenceNote;
		notify = true;
	}
	if (notify) emit presenceChanged();
}

void FriendCore::setInCall(bool inCall) {
	mustBeInMainThread(log().arg(Q_FUNC_INFO));
	if (mInCall == inCall) return;
	mInCall = inCall;
	emit presenceChanged();
}

// Statut reserve aux postes internes : une adresse SIP dont l'identifiant fait 1 a 5 chiffres, meme regle que la fiche
// contact et le Clavier (ex. 1000). Un correspondant sans compte VoIP (numero de telephone, ex. 0767338479) n'a aucun
// statut : ni pastille, ni « En ligne » ou « Hors ligne », ni note, ni « En communication ».
bool FriendCore::isInternalExtension() const {
	static const QRegularExpression extension(QStringLiteral("^sip:[0-9]{1,5}@"),
	                                          QRegularExpression::CaseInsensitiveOption);
	if (extension.match(mDefaultAddress).hasMatch()) return true;
	for (const auto &address : mAddressList) {
		if (extension.match(address.toMap().value("address").toString()).hasMatch()) return true;
	}
	return false;
}

// Etat inconnu (Undefined) : ni pastille ni texte, comme avant la premiere information du serveur.
LinphoneEnums::Presence FriendCore::getPresence() const {
	return isInternalExtension() ? mPresence : LinphoneEnums::Presence::Undefined;
}

QString FriendCore::getPresenceNote() const {
	return isInternalExtension() ? mPresenceNote : QString();
}

bool FriendCore::isInCall() const {
	return mInCall && isInternalExtension();
}

// Pendant un appel, pastille bleue « En communication » a la place du statut choisi, qui
// reapparait tel quel a la fin de l'appel.
QUrl FriendCore::getPresenceIcon() {
	if (isInCall()) return Utils::getAppIcon("presenceOnThePhone");
	return Utils::getPresenceIcon(getPresence());
}

QColor FriendCore::getPresenceColor() {
	if (isInCall()) return Utils::getDefaultStyleColor("info_800_main");
	return Utils::getPresenceColor(getPresence());
}

QString FriendCore::getPresenceStatus() {
	if (isInCall()) return Utils::getInCallPresenceStatus();
	return Utils::getPresenceStatus(getPresence());
}
