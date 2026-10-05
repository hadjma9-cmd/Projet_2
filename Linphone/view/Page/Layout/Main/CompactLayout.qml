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
		Layout.alignment: Qt.AlignHCenter
		Layout.preferredWidth: Utils.getSizeWithScreenRatio(42)
		Layout.preferredHeight: Utils.getSizeWithScreenRatio(42)
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
			radius: Utils.getSizeWithScreenRatio(10)
			color: bandButton.selected
				? Qt.rgba(1, 1, 1, 0.2)
				: bandArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
			border.width: bandButton.activeFocus ? Utils.getSizeWithScreenRatio(2) : 0
			border.color: DefaultStyle.grey_0
		}
		Item {
			anchors.centerIn: parent
			width: Utils.getSizeWithScreenRatio(24)
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
			delay: 400
		}
	}

	// Page chargee a sa premiere ouverture, puis gardee : on retrouve l'onglet tel qu'on l'a laisse.
	component LazyPage: Loader {
		property int pageIndex
		property bool keptAlive: false
		active: keptAlive || mainItem.currentIndex === pageIndex
		onLoaded: Qt.callLater(function () {
			keptAlive = true
		})
	}

	RowLayout {
		anchors.fill: parent
		spacing: 0

		// ---------------------------------------------------------------------------------------------------------
		//  Bande
		// ---------------------------------------------------------------------------------------------------------
		Rectangle {
			Layout.fillHeight: true
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(58)
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
				spacing: Utils.getSizeWithScreenRatio(8)

				// Compte : photo et pastille de statut ; un clic pour changer de statut.
				PopupButton {
					id: accountButton
					Layout.alignment: Qt.AlignHCenter
					Layout.bottomMargin: Utils.getSizeWithScreenRatio(6)
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(40)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(40)
					style: ButtonStyle.noBackground
					shadowEnabled: false
					enabled: !!mainItem.account && mainItem.account.core.registrationState === LinphoneEnums.RegistrationState.Ok
					popUpTitle: "Statut"
					contentItem: Item {
						Avatar {
							anchors.fill: parent
							account: mainItem.account
							shadowEnabled: false
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
				BandButton {
					iconSource: AppIcons.phone
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
				BandButton {
					iconSource: AppIcons.windowLarge
					label: "Grande fenêtre"
					onTriggered: AppCpp.compactMode = false
				}
				Item {
					Layout.fillHeight: true
				}
				// Parametres : petit menu (parametres et aide dans la grande fenetre, notifications, quitter).
				PopupButton {
					id: settingsButton
					Layout.alignment: Qt.AlignHCenter
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(42)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(42)
					style: ButtonStyle.noBackground
					shadowEnabled: false
					hoveredColor: Qt.rgba(1, 1, 1, 0.1)
					pressedColor: Qt.rgba(1, 1, 1, 0.2)
					backgroundColor: checked ? pressedColor : hovered ? hoveredColor : color
					icon.source: AppIcons.settings
					icon.width: Utils.getSizeWithScreenRatio(24)
					icon.height: Utils.getSizeWithScreenRatio(24)
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

			// Contacts : recherche, favoris et annuaire ; un clic appelle.
			LazyPage {
				pageIndex: 0
				sourceComponent: Item {
					CreationFormLayout {
						anchors.fill: parent
						anchors.topMargin: Utils.getSizeWithScreenRatio(14)
						anchors.leftMargin: Utils.getSizeWithScreenRatio(12)
						anchors.rightMargin: Utils.getSizeWithScreenRatio(4)
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
		}
	}

	// Appel en cours ou entrant : il occupe toute la fenetre.
	Loader {
		id: callLoader
		anchors.fill: parent
		z: 10
		active: !!callsModel.currentCall
		sourceComponent: CompactCallView {
			call: callsModel.currentCall
		}
	}
}
