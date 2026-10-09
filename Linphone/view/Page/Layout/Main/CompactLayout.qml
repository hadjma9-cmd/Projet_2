import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import SettingsCpp
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle

// Petite fenetre (format telephone, comme 3CX), appels audio seulement. Bande a gauche, dans l'ordre : compte et
// statut, Contacts, Clavier (accueil), Appels, Messages, Boite vocale, retour a la grande fenetre ; parametres en bas.
// A droite, la page de l'onglet. Un appel occupe toute la fenetre (CompactCallView).
Item {
	id: mainItem
	property int currentIndex: 1
	readonly property bool callVisible: callLoader.active

	signal openSettingsRequested()
	signal openHelpRequested()

	function openChat(chat) {
		mainItem.currentIndex = 3
		messagesPage.openChat(chat)
	}

	AccountProxy {
		id: accountProxy
	}
	readonly property AccountGui account: accountProxy.defaultAccount
	readonly property bool voicemailAvailable: !!account && (account.core.showMwi || account.core.voicemailAddress.length > 0)

	CallProxy {
		id: callsModel
		sourceModel: AppCpp.calls
	}

	// Appels manques vus en ouvrant l'onglet Appels.
	onCurrentIndexChanged: if (currentIndex === 2 && account) account.core.lResetMissedCalls()

	function openVoicemail() {
		if (account && account.core.voicemailAddress.length > 0)
			UtilsCpp.createCall(account.core.voicemailAddress)
	}

	// Pastille rouge en haut a droite d'une icone, contour de la couleur de la bande.
	component BandBadge: Rectangle {
		property int count: 0
		visible: count > 0
		height: Utils.getSizeWithScreenRatio(17)
		width: Math.max(height, badgeText.implicitWidth + Utils.getSizeWithScreenRatio(8))
		radius: height / 2
		color: DefaultStyle.danger_500_main
		border.width: Utils.getSizeWithScreenRatio(2)
		border.color: DefaultStyle.main1_gradient_top
		Text {
			id: badgeText
			anchors.centerIn: parent
			text: parent.count > 99 ? "99+" : parent.count
			color: DefaultStyle.grey_0
			font {
				pixelSize: Utils.getSizeWithScreenRatio(10)
				weight: Font.DemiBold
			}
		}
	}

	// Entree de la bande : icone seule, nom au survol.
	component BandButton: Item {
		id: bandButton
		property url iconSource
		property string label
		property int pageIndex: -1
		property int badgeCount: 0
		readonly property bool selected: pageIndex >= 0 && mainItem.currentIndex === pageIndex
		signal triggered()
		function activate() {
			if (bandButton.pageIndex >= 0)
				mainItem.currentIndex = bandButton.pageIndex
			bandButton.triggered()
		}
		// 38 et icone de 22 (42 et 24 auparavant) : bande plus fine, accordee aux listes resserrees du Combiné.
		Layout.alignment: Qt.AlignHCenter
		Layout.preferredWidth: Utils.getSizeWithScreenRatio(38)
		Layout.preferredHeight: Utils.getSizeWithScreenRatio(38)
		activeFocusOnTab: true
		Accessible.role: Accessible.Button
		Accessible.name: label
		Keys.onPressed: event => {
			if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
				bandButton.activate()
				event.accepted = true
			}
		}
		Rectangle {
			anchors.fill: parent
			radius: Utils.getSizeWithScreenRatio(9)
			color: bandButton.selected
				? Qt.rgba(1, 1, 1, 0.2)
				: bandArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
			border.width: bandButton.activeFocus ? Utils.getSizeWithScreenRatio(2) : 0
			border.color: DefaultStyle.grey_0
		}
		Item {
			anchors.centerIn: parent
			width: Utils.getSizeWithScreenRatio(22)
			height: width
			EffectImage {
				anchors.fill: parent
				imageSource: bandButton.iconSource
				colorizationColor: bandButton.selected || bandArea.containsMouse ? DefaultStyle.grey_0 : DefaultStyle.main1_100
			}
			BandBadge {
				count: bandButton.badgeCount
				x: parent.width - Utils.getSizeWithScreenRatio(8)
				y: -Utils.getSizeWithScreenRatio(7)
			}
		}
		MouseArea {
			id: bandArea
			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: bandButton.activate()
		}
		ToolTip {
			text: bandButton.label
			visible: bandArea.containsMouse
			delay: 300
		}
	}

	// Clic sur une personne (Equipe, Contacts) : appeler ou lui ecrire, au choix.
	function chooseContactAction(contact) {
		if (!contact)
			return
		var address = contact.core.defaultAddress
		var username = UtilsCpp.getUsername(address)
		// Meme ecriture que la confirmation d'appel : un poste seul, sinon l'adresse (ou le numero si les adresses
		// SIP sont masquees) ; le nom d'abord.
		var number = (/^[0-9]{1,5}$/.test(username) || SettingsCpp.hideSipAddresses) ? username : address
		var name = contact.core.fullName
		contactActionDialog.contact = contact
		contactActionDialog.target = (name.length !== 0 && name !== username) ? name + " (" + number + ")" : number
		contactActionDialog.open()
	}
	// « Message » : conversation recuperee (ou creee) par le SDK, puis ouverte dans l'onglet Messages.
	property var pendingChatObj: null
	property ChatGui pendingContactChat: pendingChatObj ? pendingChatObj.value : null
	onPendingContactChatChanged: if (pendingContactChat) {
		var chat = pendingContactChat
		pendingChatObj = null
		mainItem.openChat(chat)
	}
	function messageContact(contact) {
		if (!contact || contact.core.defaultAddress.length === 0)
			return
		messageAddress(contact.core.defaultAddress)
	}
	function messageAddress(address) {
		if (address.length === 0)
			return
		pendingChatObj = UtilsCpp.getChatForAddress(address)
	}
	Dialog {
		id: contactActionDialog
		property FriendGui contact: null
		property string target
		// Nom en gras ; echappe pour qu'un « & » ou un « < » dans un nom ne casse pas le texte.
		textFormat: Text.StyledText
		text: "Que souhaitez-vous faire avec <b>" + target.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") + "</b> ?"
		onOpened: callChoiceButton.forceActiveFocus()
		buttons: [
			MediumButton {
				id: callChoiceButton
				text: "Appeler"
				style: ButtonStyle.main
				leftPadding: Utils.getSizeWithScreenRatio(14)
				rightPadding: Utils.getSizeWithScreenRatio(14)
				topPadding: Utils.getSizeWithScreenRatio(8)
				bottomPadding: Utils.getSizeWithScreenRatio(8)
				KeyNavigation.right: messageChoiceButton
				onClicked: {
					var contact = contactActionDialog.contact
					contactActionDialog.close()
					// Choix explicite : pas de seconde confirmation.
					UtilsCpp.getMainWindow().startCallWithContact(contact, false, mainItem, false)
				}
			},
			MediumButton {
				id: messageChoiceButton
				visible: !SettingsCpp.disableChatFeature
				text: "Message"
				style: ButtonStyle.secondary
				leftPadding: Utils.getSizeWithScreenRatio(14)
				rightPadding: Utils.getSizeWithScreenRatio(14)
				topPadding: Utils.getSizeWithScreenRatio(8)
				bottomPadding: Utils.getSizeWithScreenRatio(8)
				KeyNavigation.left: callChoiceButton
				KeyNavigation.right: cancelChoiceButton
				onClicked: {
					var contact = contactActionDialog.contact
					contactActionDialog.close()
					mainItem.messageContact(contact)
				}
			},
			MediumButton {
				id: cancelChoiceButton
				text: "Annuler"
				style: ButtonStyle.secondary
				leftPadding: Utils.getSizeWithScreenRatio(14)
				rightPadding: Utils.getSizeWithScreenRatio(14)
				topPadding: Utils.getSizeWithScreenRatio(8)
				bottomPadding: Utils.getSizeWithScreenRatio(8)
				KeyNavigation.left: messageChoiceButton
				onClicked: contactActionDialog.close()
			}
		]
	}

	// Page chargee a sa premiere ouverture, puis gardee : on retrouve l'onglet tel qu'on l'a laisse.
	component LazyPage: Loader {
		property int pageIndex
		property bool keptAlive: false
		active: keptAlive || mainItem.currentIndex === pageIndex
		onLoaded: Qt.callLater(function () {
			keptAlive = true
		})
		// Preparation en arriere-plan, construite par petits morceaux pour ne rien figer.
		function preload() {
			if (active)
				return
			asynchronous = true
			keptAlive = true
		}
	}
	// Equipe et Contacts prepares juste apres l'ouverture de la petite fenetre : prets avant le premier clic (leur
	// liste et la recherche dans l'annuaire prenaient un temps visible).
	Timer {
		interval: 400
		running: true
		onTriggered: {
			teamLazyPage.preload()
			contactsLazyPage.preload()
		}
	}

	RowLayout {
		anchors.fill: parent
		spacing: 0

		// ---------------------------------------------------------------------------------------------------------
		//  Bande
		// ---------------------------------------------------------------------------------------------------------
		Rectangle {
			Layout.fillHeight: true
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(54)
			gradient: Gradient {
				GradientStop {
					position: 0.0
					color: DefaultStyle.main1_gradient_top
				}
				GradientStop {
					position: 1.0
					color: DefaultStyle.main1_gradient_bottom
				}
			}
			ColumnLayout {
				anchors.fill: parent
				anchors.topMargin: Utils.getSizeWithScreenRatio(12)
				anchors.bottomMargin: Utils.getSizeWithScreenRatio(10)
				spacing: Utils.getSizeWithScreenRatio(6)

				// Compte : photo et pastille de statut ; un clic pour changer de statut.
				PopupButton {
					id: accountButton
					Layout.alignment: Qt.AlignHCenter
					Layout.bottomMargin: Utils.getSizeWithScreenRatio(6)
					// Sa propre photo : 42 et pastille d'environ 13, lisibles dans une bande fine (les listes, elles, sont en 45).
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(42)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(42)
					style: ButtonStyle.noBackground
					shadowEnabled: false
					enabled: !!mainItem.account && mainItem.account.core.registrationState === LinphoneEnums.RegistrationState.Ok
					popUpTitle: "Statut"
					contentItem: Item {
						Avatar {
							anchors.fill: parent
							account: mainItem.account
							shadowEnabled: false
							presenceScale: 0.3
						}
					}
					popup.contentItem: FocusScope {
						implicitWidth: Utils.getSizeWithScreenRatio(260)
						implicitHeight: statusChoice.implicitHeight + Utils.getSizeWithScreenRatio(20)
						Presence {
							id: statusChoice
							anchors.fill: parent
							anchors.margins: Utils.getSizeWithScreenRatio(10)
							accountGui: mainItem.account
							onIsSet: accountButton.popup.close()
						}
					}
				}
				// Equipe en premier, comme dans la grande fenetre (page 4, ajoutee apres les autres).
				BandButton {
					iconSource: AppIcons.usersThree
					label: "Équipe"
					pageIndex: 4
				}
				BandButton {
					iconSource: AppIcons.adressBook
					label: "Contacts"
					pageIndex: 0
				}
				BandButton {
					iconSource: AppIcons.dialer
					label: "Clavier"
					pageIndex: 1
				}
				// Historique des appels : horloge, comme dans la grande fenetre.
				BandButton {
					iconSource: AppIcons.callHistory
					label: "Appels"
					pageIndex: 2
					badgeCount: mainItem.account ? Math.max(0, mainItem.account.core.unreadCallNotifications) : 0
				}
				BandButton {
					visible: !SettingsCpp.disableChatFeature
					iconSource: AppIcons.chatTeardropText
					label: "Messages"
					pageIndex: 3
					badgeCount: mainItem.account ? Math.max(0, mainItem.account.core.unreadMessageNotifications) : 0
				}
				BandButton {
					visible: mainItem.voicemailAvailable
					iconSource: AppIcons.voicemail
					label: "Boîte vocale"
					badgeCount: mainItem.account && mainItem.account.core.showMwi ? mainItem.account.core.voicemailCount : 0
					onTriggered: mainItem.openVoicemail()
				}
				Item {
					Layout.fillHeight: true
				}
				// Retour en mode bureau : en bas de la bande, a part, au meme endroit que le bouton de la grande fenetre.
				Rectangle {
					Layout.alignment: Qt.AlignHCenter
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(30)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
					color: Qt.rgba(1, 1, 1, 0.3)
				}
				BandButton {
					iconSource: AppIcons.modeDesktop
					label: "Revenir en mode bureau"
					onTriggered: AppCpp.compactMode = false
				}
				// Parametres : petit menu (parametres et aide dans la grande fenetre, notifications, quitter).
				PopupButton {
					id: settingsButton
					Layout.alignment: Qt.AlignHCenter
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(38)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(38)
					style: ButtonStyle.noBackground
					shadowEnabled: false
					hoveredColor: Qt.rgba(1, 1, 1, 0.1)
					pressedColor: Qt.rgba(1, 1, 1, 0.2)
					backgroundColor: checked ? pressedColor : hovered ? hoveredColor : color
					icon.source: AppIcons.settings
					icon.width: Utils.getSizeWithScreenRatio(22)
					icon.height: Utils.getSizeWithScreenRatio(22)
					contentImageColor: DefaultStyle.main1_100
					hoveredImageColor: DefaultStyle.grey_0
					pressedImageColor: DefaultStyle.grey_0
					popUpTitle: "Paramètres"
					popup.contentItem: ColumnLayout {
						spacing: Utils.getSizeWithScreenRatio(10)
						IconLabelButton {
							Layout.fillWidth: true
							visible: !SettingsCpp.hideSettings
							icon.width: Utils.getSizeWithScreenRatio(28)
							icon.height: Utils.getSizeWithScreenRatio(28)
							icon.source: AppIcons.settings
							text: "Paramètres"
							onClicked: {
								settingsButton.close()
								mainItem.openSettingsRequested()
							}
						}
						IconLabelButton {
							Layout.fillWidth: true
							icon.width: Utils.getSizeWithScreenRatio(28)
							icon.height: Utils.getSizeWithScreenRatio(28)
							icon.source: SettingsCpp.dnd ? AppIcons.bell : AppIcons.bellSlash
							overlayIconSource: SettingsCpp.dnd ? "" : AppIcons.bellSlashBar
							overlayIconColor: DefaultStyle.danger_500_main
							text: SettingsCpp.dnd ? "Activer les notifications" : "Désactiver les notifications"
							onClicked: {
								settingsButton.close()
								SettingsCpp.dnd = !SettingsCpp.dnd
							}
						}
						IconLabelButton {
							Layout.fillWidth: true
							icon.width: Utils.getSizeWithScreenRatio(28)
							icon.height: Utils.getSizeWithScreenRatio(28)
							icon.source: AppIcons.question
							text: "Aide"
							onClicked: {
								settingsButton.close()
								mainItem.openHelpRequested()
							}
						}
						IconLabelButton {
							Layout.fillWidth: true
							icon.width: Utils.getSizeWithScreenRatio(28)
							icon.height: Utils.getSizeWithScreenRatio(28)
							icon.source: AppIcons.power
							text: "Quitter"
							onClicked: {
								settingsButton.close()
								UtilsCpp.getMainWindow().showConfirmationLambdaPopup("", "Quitter " + applicationName + " ?", "",
									function (confirmed) {
										if (confirmed) Qt.quit()
									})
							}
						}
					}
				}
			}
		}

		// ---------------------------------------------------------------------------------------------------------
		//  Pages
		// ---------------------------------------------------------------------------------------------------------
		StackLayout {
			id: pages
			Layout.fillWidth: true
			Layout.fillHeight: true
			currentIndex: mainItem.currentIndex

			// Contacts : recherche, favoris et annuaire, sans les postes internes (onglet Equipe) ; un clic appelle.
			LazyPage {
				id: contactsLazyPage
				pageIndex: 0
				sourceComponent: Item {
					// Petite fenetre gardee en memoire : la liste est relue quand on l'affiche (onglet ou retour en
					// Combiné), au plus toutes les 10 minutes, comme dans la grande fenetre. Une extension creee entre-temps
					// apparait ainsi.
					property double lastRefresh: Date.now()
					onVisibleChanged: if (visible && Date.now() - lastRefresh >= 10 * 60 * 1000) {
						lastRefresh = Date.now()
						contactsForm.refreshContacts()
					}
					CreationFormLayout {
						id: contactsForm
						autoRefresh: true
						dense: true
						showCallButton: true
						anchors.fill: parent
						anchors.topMargin: Utils.getSizeWithScreenRatio(14)
						anchors.leftMargin: Utils.getSizeWithScreenRatio(12)
						anchors.rightMargin: Utils.getSizeWithScreenRatio(4)
						showTeam: false
						startGroupButtonVisible: false
						searchBarRightMaring: Utils.getSizeWithScreenRatio(8)
						onContactClicked: contact => UtilsCpp.getMainWindow().startCallWithContact(contact, false, mainItem)
					}
				}
			}
			// Clavier : on compose et on appelle.
			LazyPage {
				pageIndex: 1
				sourceComponent: DialerForm {
					// Fenetre basse : deux suggestions, le pave reste entier.
					maxSuggestions: 2
					suggestionAvatarSize: Utils.getSizeWithScreenRatio(45)
					onCallRequested: number => UtilsCpp.createCall(number)
				}
			}
			// Appels : historique, un clic sur le combine rappelle.
			LazyPage {
				pageIndex: 2
				sourceComponent: ColumnLayout {
					spacing: Utils.getSizeWithScreenRatio(10)
					SearchBar {
						id: historySearchBar
						Layout.fillWidth: true
						Layout.topMargin: Utils.getSizeWithScreenRatio(14)
						Layout.leftMargin: Utils.getSizeWithScreenRatio(12)
						Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
						placeholderText: "Rechercher un appel"
					}
					CallHistoryListView {
						Layout.fillWidth: true
						Layout.fillHeight: true
						avatarSize: Utils.getSizeWithScreenRatio(45)
						Layout.leftMargin: Utils.getSizeWithScreenRatio(6)
						Layout.rightMargin: Utils.getSizeWithScreenRatio(6)
						searchBar: historySearchBar
					}
				}
			}
			// Messages : la liste, puis la conversation ouverte (fleche pour revenir).
			Item {
				id: messagesPage
				property ChatGui pendingChat: null
				function openChat(chat) {
					messagesPage.pendingChat = chat
					if (messagesLoader.item)
						messagesLoader.item.openChat(chat)
				}
				LazyPage {
					id: messagesLoader
					anchors.fill: parent
					pageIndex: 3
					onLoaded: if (messagesPage.pendingChat) item.openChat(messagesPage.pendingChat)
					sourceComponent: Item {
						id: messagesContent
						property ChatGui currentChat: null
						function openChat(chat) {
							chatListView.chatToSelect = chat
							messagesContent.currentChat = chat
							messagesPage.pendingChat = null
						}
						ColumnLayout {
							anchors.fill: parent
							visible: !messagesContent.currentChat
							spacing: Utils.getSizeWithScreenRatio(10)
							SearchBar {
								id: chatSearchBar
								Layout.fillWidth: true
								Layout.topMargin: Utils.getSizeWithScreenRatio(14)
								Layout.leftMargin: Utils.getSizeWithScreenRatio(12)
								Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
								placeholderText: "Rechercher une conversation"
							}
							ChatListView {
								id: chatListView
								avatarSize: Utils.getSizeWithScreenRatio(45)
								Layout.fillWidth: true
								Layout.fillHeight: true
								chatProxy.model: AppCpp.chats
								currentIndex: -1
								searchBar: chatSearchBar
								onCurrentChatGuiChanged: if (currentChatGui) messagesContent.currentChat = currentChatGui
							}
						}
						SelectedChatView {
							anchors.fill: parent
							visible: !!messagesContent.currentChat
							chat: messagesContent.currentChat
							backButtonVisible: true
							videoCallEnabled: false
							onBackButtonPressed: {
								chatListView.currentIndex = -1
								chatListView.currentChatGui = null
								messagesContent.currentChat = null
							}
						}
					}
				}
			}
			// Equipe : les collegues (postes internes) tries par statut ; un clic appelle.
			LazyPage {
				id: teamLazyPage
				pageIndex: 4
				sourceComponent: Item {
					// Relue quand on l'affiche, au plus toutes les 10 minutes (voir Contacts).
					property double lastRefresh: Date.now()
					onVisibleChanged: if (visible && Date.now() - lastRefresh >= 10 * 60 * 1000) {
						lastRefresh = Date.now()
						teamForm.refreshContacts()
					}
					CreationFormLayout {
						id: teamForm
						autoRefresh: true
						dense: true
						showCallButton: true
						anchors.fill: parent
						anchors.topMargin: Utils.getSizeWithScreenRatio(14)
						anchors.leftMargin: Utils.getSizeWithScreenRatio(12)
						anchors.rightMargin: Utils.getSizeWithScreenRatio(4)
						teamMode: true
						startGroupButtonVisible: false
						searchBarRightMaring: Utils.getSizeWithScreenRatio(8)
						onContactClicked: contact => mainItem.chooseContactAction(contact)
					}
				}
			}
		}
	}

	// Appel en cours ou entrant : il occupe toute la fenetre.
	Loader {
		id: callLoader
		anchors.fill: parent
		z: 10
		// Seulement en Combiné : gardee en memoire pendant la grande fenetre, elle ne doit pas y construire un
		// ecran d'appel cache.
		active: AppCpp.compactMode && !!callsModel.currentCall
		sourceComponent: CompactCallView {
			call: callsModel.currentCall
		}
	}
}
