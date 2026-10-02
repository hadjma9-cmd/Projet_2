import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects

import Linphone
import UtilsCpp
import SettingsCpp
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Fill contact, account or call
// Initials will be displayed if there isn't any avatar.
// TODO : get FriendGui from Call.
Loader{
	id: mainItem
	property AccountGui account: null
	property FriendGui contact: null
	property CallGui call: null
	property bool isConference: false
	property bool shadowEnabled: true
	property var _address: account?.core
		? account.core?.identityAddress || ""
		: call
			? call.core.remoteAddress
			: contact
				? contact.core.defaultAddress
				: ''
	readonly property var address: SettingsCpp.hideSipAddresses ? UtilsCpp.getUsername(_address) : _address
	// Requete au moteur SIP seulement si le compte ou la fiche du contact ne donnent pas deja le nom
	// (chaque avatar en lancait une, meme inutile).
	property var displayNameObj: (account?.core && account.core.displayName) || (contact && contact.core.fullName)
		? null
		: UtilsCpp.getDisplayName(_address)
	property var displayNameVal: account?.core && account.core.displayName
		? account.core.displayName
		: contact && contact.core.fullName
			? contact.core.fullName
			: displayNameObj
				? displayNameObj.value
			: ""
	// Source unique de l'avatar, pour que l'image affichee et le test haveAvatar ne
	// puissent pas diverger.
	property string avatarUri: (account?.core
		? account.core.pictureUri
		: contact
			? contact.core.pictureUri
			: computedAvatarUri) || ""
	// L'avatar peut etre une URL distante (annuaire) qui renvoie 404 quand l'utilisateur
	// n'a pas de photo. Sans ce drapeau, haveAvatar resterait vrai et on afficherait une
	// image vide au lieu des initiales.
	// Les echecs sont memorises 10 minutes cote C++ : une vue recreee (defilement) ne relance pas
	// la requete vers une photo absente.
	property bool avatarLoadFailed: avatarUri.length !== 0 && UtilsCpp.isMissingAvatarUrl(avatarUri)
	onAvatarUriChanged: avatarLoadFailed = avatarUri.length !== 0 && UtilsCpp.isMissingAvatarUrl(avatarUri)
	property bool haveAvatar: avatarUri.length !== 0 && !avatarLoadFailed
	// Photo distante : parametre v renouvele toutes les 15 minutes (AppCpp.avatarRevision), pour que le cache
	// d'images ne serve pas indefiniment une ancienne photo (meme URL). Date.now() n'etait lu qu'a la creation de
	// l'avatar : un avatar reste affiche gardait l'ancienne photo. Fichiers locaux et fournisseurs d'images : URL
	// inchangee.
	readonly property string avatarSource: avatarUri.startsWith("http")
		? avatarUri + (avatarUri.indexOf("?") === -1 ? "?" : "&") + "v=" + AppCpp.avatarRevision
		: avatarUri
	// Photo cherchee seulement sans compte ni fiche de contact : avatarUri ne lit computedAvatarUri
	// que dans ce cas.
	property var avatarObj: account?.core || contact ? null : UtilsCpp.findAvatarByAddress(_address)
	property string computedAvatarUri: avatarObj ? avatarObj.value : ''

	// To get the secured property for a friend using an address to find it,
	// override it as secured: friendSecurityLevel === LinphoneEnums.SecurityLevel.EndToEndEncryptedAndVerified
	property var friendSecurityLevelObj: UtilsCpp.getFriendSecurityLevel(_address)
	property var friendSecurityLevel: friendSecurityLevelObj ? friendSecurityLevelObj.value : LinphoneEnums.SecurityLevel.None
	
	// To get the secured property for a specific address,
	// override it as secured: securityLevel === LinphoneEnums.SecurityLevel.EndToEndEncryptedAndVerified
	property var securityLevelObj: UtilsCpp.getFriendAddressSecurityLevel(_address)
	property var securityLevel: securityLevelObj ? securityLevelObj.value : LinphoneEnums.SecurityLevel.None
	property bool secured: call && call.core.encryption === LinphoneEnums.MediaEncryption.Zrtp
						   ? call.core.tokenVerified
						   : contact
							 ? contact.core.devices.length != 0 && contact.core.verifiedDeviceCount === contact.core.devices.length
							 : false
	
	property bool securityBreach: securityLevel === LinphoneEnums.SecurityLevel.Unsafe
	property bool displayPresence: true

	// Construction synchrone : en asynchrone, le composant s'instancie en arriere-plan et
	// certaines liaisons s'evaluent avant que le contact ne soit resolu (findFriendByAddress
	// repond de facon differee). La pastille de presence restait alors vide jusqu'a ce qu'un
	// changement d'onglet reconstruise la vue. ChatListView contournait deja le probleme en
	// forcant asynchronous: false sur ses propres avatars.
	asynchronous: false
	sourceComponent: Component{
		Item {
			anchors.fill: parent
			
			MultiEffect {
				visible: mainItem.shadowEnabled
				enabled: mainItem.shadowEnabled
				shadowEnabled: mainItem.shadowEnabled
				anchors.fill: stackView
				source: stackView
				shadowBlur: 0.1
				shadowColor: DefaultStyle.grey_1000
				shadowOpacity: 0.1
			}
			Item {
				id: stackView
				anchors.fill: parent

				// Photo ou initiales. Un simple chargeur remplace la StackView (une par avatar, lourde pour un seul
				// element affiche et sans transition) ; il prend la taille de l'element, comme elle.
				Loader {
					id: avatarLoader
					sourceComponent: mainItem.haveAvatar ? avatar : initials
				}

				Rectangle {
					visible: mainItem.secured || mainItem.securityBreach
					anchors.fill: avatarLoader
					radius: stackView.width / 2
					z: 1
					color: "transparent"
					border {
                        width: Utils.getSizeWithScreenRatio(2)
						color: mainItem.secured ? DefaultStyle.info_500_main : DefaultStyle.danger_500_main
					}
					EffectImage {
						x: parent.width / 7
						anchors.bottom: parent.bottom
						width: parent.width / 4.5
						height: width
						imageSource: mainItem.secured ? AppIcons.trusted : AppIcons.notTrusted
						fillMode: Image.PreserveAspectFit
						
					}
				}
				
				Image {
					visible: mainItem.displayPresence
					width: stackView.width/4.5
					height: width
					sourceSize.width: Math.ceil(width)
    				sourceSize.height: Math.ceil(width)
					// width vaut stackView.width/4.5, donc fractionnaire : sans arrondi ni
					// filtrage, l'icone etait rasterisee a une taille tronquee puis mise a
					// l'echelle, d'ou une pastille pixellisee.
					smooth: true
					mipmap: true
					anchors.bottom: parent.bottom
					anchors.right: parent.right
					anchors.rightMargin: stackView.width / 15
					z: 1
					source: account?.core
							? (account.core?.registrationState !== LinphoneEnums.RegistrationState.Ok 
								? account.core?.registrationIcon 
								: account.core?.presenceIcon)
							: (contact 
								? contact.core?.presenceIcon
								: "")
					RotationAnimator on rotation {
						running: mainItem.account?.core ? mainItem.account.core.registrationState === LinphoneEnums.RegistrationState.Progress : false
						direction: RotationAnimator.Clockwise
						from: 0
						to: 360
						loops: Animation.Infinite
						duration: 10000
					}
				}
				
			}
			
			Component{
				id: initials
				Item {
					id: avatarItem
					height: stackView.height
					width: height
					Rectangle {
						id: initialItem
						property string initials: mainItem.isConference || (mainItem.displayNameVal && mainItem.displayNameVal[0] === "+") ? "" : UtilsCpp.getInitials(mainItem.displayNameVal)
						radius: width / 2
						color: DefaultStyle.main2_200
						height: stackView.height
						width: height
						Text {
							anchors.fill: parent
							anchors.centerIn: parent
							verticalAlignment: Text.AlignVCenter
							horizontalAlignment: Text.AlignHCenter
							text: initialItem.initials
							textFormat: Text.RichText
							font {
								pixelSize: initialItem.height * 36 / 120
								weight: Typography.h4.weight
								capitalization: Font.AllUppercase
							}
						}
						EffectImage {
							id: initialImg
							visible: initialItem.initials === "" || initialItem.initials[0] === "+"
							width: stackView.width/2
							height: width
							colorizationColor: DefaultStyle.main2_600
							imageSource: mainItem.isConference ? AppIcons.videoconference : AppIcons.profile
							anchors.centerIn: parent
						}
					}
					MultiEffect {
						// Suit shadowEnabled comme l'ombre exterieure : dans les listes, chaque effet
						// coutait une texture hors ecran par avatar.
						visible: mainItem.shadowEnabled
						enabled: mainItem.shadowEnabled
						source: initialItem
						anchors.fill: initialItem
						shadowEnabled: true
						shadowBlur: 0.1
						shadowColor: DefaultStyle.grey_1000
						shadowOpacity: 0.1
					}
					Connections {
						target: mainItem.call?.core ? mainItem.call.core : null
						onRemoteNameChanged: initialItem.initials = UtilsCpp.getInitials(mainItem.call.core.remoteName)
					}
				}
			}
			Component{
				id: avatar
				Item {
					id: avatarItem
					height: stackView.height
					width: height
					Image {
						id: image
						z: 200
						visible: false
						width: parent.width
						height: parent.height
						sourceSize.width: avatarItem.width
						sourceSize.height: avatarItem.height
						fillMode: Image.PreserveAspectCrop
						anchors.centerIn: parent
						// Cache memoire de Qt actif : la photo n'est plus retelechargee a chaque affichage
						// (defilement, changement d'onglet). Une photo distante changee sans que son URL
						// change reste visible grace au parametre de avatarSource, renouvele toutes les 15 min.
						source: mainItem.avatarSource
						// Relecture toutes les 15 minutes : l'ancienne photo reste affichee jusqu'a l'arrivee de la
						// nouvelle, sans passage par une image vide.
						retainWhileLoading: true
						onStatusChanged: if (status === Image.Error) {
							UtilsCpp.markMissingAvatarUrl(mainItem.avatarUri)
							mainItem.avatarLoadFailed = true
						}
						mipmap: true
						layer.enabled: true
					}
					ShaderEffect {
						id: roundEffect
						property variant src: image
						property real edge: 0.9
						property real edgeSoftness: 0.9
						property real radius: width / 2.0
						property real shadowSoftness: 0.5
						property real shadowOffset: 0.01
						anchors.fill: parent
						fragmentShader: 'qrc:/data/shaders/roundEffect.frag.qsb'
					}
				}
			}
		}
	}
}
