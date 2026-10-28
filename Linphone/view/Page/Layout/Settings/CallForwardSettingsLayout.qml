
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Transfert d'appel : renvoi de tous les appels du poste, appliqué par le serveur (ForwardCpp), vers un numéro, un
// membre de l'équipe ou la messagerie du poste. Les choix restent sur la page jusqu'à « Enregistrer ».
AbstractSettingsLayout {
	id: mainItem
	width: parent?.width

	// Choix en cours sur la page, repris du serveur tant qu'on n'y a pas touché.
	property bool forwardEnabled: false
	property int target: 0 // 0 : un numéro, 1 : un membre de l'équipe, 2 : ma messagerie
	property string number
	property string memberNumber
	property string memberName
	property bool edited: false
	property string pageError
	property bool savedNow: false

	function load() {
		mainItem.forwardEnabled = ForwardCpp.enabled
		var destination = ForwardCpp.destination
		if (destination.length > 0 && destination === ForwardCpp.voicemail) {
			mainItem.target = 2
		} else if (/^[0-9]{2,6}$/.test(destination)) {
			// Numéro court : un poste interne.
			mainItem.target = 1
			mainItem.memberNumber = destination
			mainItem.memberName = ""
		} else {
			mainItem.target = 0
			mainItem.number = destination
		}
		mainItem.edited = false
	}
	Component.onCompleted: {
		load()
		ForwardCpp.refresh()
	}
	Connections {
		target: ForwardCpp
		function onChanged() {
			if (!mainItem.edited) mainItem.load()
		}
		function onSaved() {
			mainItem.edited = false
			mainItem.savedNow = true
			savedTimer.restart()
		}
	}
	Timer {
		id: savedTimer
		interval: 3000
		onTriggered: mainItem.savedNow = false
	}
	onForwardEnabledChanged: mainItem.edited = true

	onSave: {
		mainItem.pageError = ""
		var destination = mainItem.target === 2 ? ForwardCpp.voicemail
			: mainItem.target === 1 ? mainItem.memberNumber : mainItem.number
		if (mainItem.forwardEnabled && mainItem.target === 0 && destination.trim().length === 0) {
			mainItem.pageError = "Indiquez le numéro vers lequel renvoyer vos appels."
			return
		}
		if (mainItem.forwardEnabled && mainItem.target === 1 && destination.length === 0) {
			mainItem.pageError = "Choisissez le membre de l'équipe qui recevra vos appels."
			return
		}
		ForwardCpp.save(mainItem.forwardEnabled, destination)
	}

	contentModel: [
		{
			title: "",
			subTitle: "",
			contentComponent: forwardComponent
		}
	]

	Component {
		id: forwardComponent
		ColumnLayout {
			spacing: Utils.getSizeWithScreenRatio(16)
			SwitchSetting {
				Layout.fillWidth: true
				titleText: "Renvoyer mes appels"
				subTitleText: "Vos appels arrivent sur un autre numéro, même PC éteint."
				propertyName: "forwardEnabled"
				propertyOwner: mainItem
			}
			ColumnLayout {
				visible: mainItem.forwardEnabled
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(6)
				Text {
					text: "Vers"
					font: Typography.p2l
					color: DefaultStyle.main2_600
				}
				ComboBox {
					id: targetBox
					Layout.fillWidth: true
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(49)
					model: [{text: "Un numéro"}, {text: "Un membre de l'équipe"}, {text: "Ma messagerie"}]
					currentIndex: mainItem.target
					onCurrentIndexChanged: if (currentIndex !== mainItem.target) {
						mainItem.target = currentIndex
						mainItem.edited = true
					}
					accessibleLabel: "Vers"
				}
			}
			// Un numéro.
			ColumnLayout {
				visible: mainItem.forwardEnabled && mainItem.target === 0
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(6)
				Text {
					text: "Numéro"
					font: Typography.p2l
					color: DefaultStyle.main2_600
				}
				TextField {
					Layout.fillWidth: true
					placeholderText: "06 12 34 56 78"
					text: mainItem.number
					onTextEdited: {
						mainItem.number = text
						mainItem.edited = true
					}
				}
			}
			// Un membre de l'équipe : recherche par nom ou numéro parmi les postes internes.
			ColumnLayout {
				visible: mainItem.forwardEnabled && mainItem.target === 1
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(6)
				Text {
					text: "Membre de l'équipe"
					font: Typography.p2l
					color: DefaultStyle.main2_600
				}
				TextField {
					id: memberSearch
					Layout.fillWidth: true
					placeholderText: "Rechercher un nom ou un poste"
					text: mainItem.memberNumber.length === 0 ? ""
						: mainItem.memberName.length > 0 ? mainItem.memberName + " · " + mainItem.memberNumber
						: "Poste " + mainItem.memberNumber
					onTextEdited: {
						mainItem.memberNumber = ""
						mainItem.memberName = ""
						mainItem.edited = true
					}
				}
				Repeater {
					// Propositions tant qu'aucun membre n'est choisi (cinq au plus).
					model: mainItem.memberNumber.length === 0 && memberSearch.text.length > 0 ? teamSearch : []
					delegate: Rectangle {
						id: memberRow
						readonly property var member: $modelData
						readonly property string extension: member ? UtilsCpp.getUsername(member.core.defaultAddress) : ""
						visible: index < 5
						Layout.fillWidth: true
						Layout.preferredHeight: visible ? Utils.getSizeWithScreenRatio(36) : 0
						radius: Utils.getSizeWithScreenRatio(8)
						color: memberArea.containsMouse ? DefaultStyle.main2_200 : DefaultStyle.grey_0
						RowLayout {
							anchors.fill: parent
							anchors.leftMargin: Utils.getSizeWithScreenRatio(12)
							anchors.rightMargin: Utils.getSizeWithScreenRatio(12)
							Text {
								Layout.fillWidth: true
								text: memberRow.member ? memberRow.member.core.fullName : ""
								font.pixelSize: Utils.getSizeWithScreenRatio(14)
								color: DefaultStyle.main2_800
								elide: Text.ElideRight
							}
							Text {
								text: memberRow.extension
								font.pixelSize: Utils.getSizeWithScreenRatio(12)
								color: DefaultStyle.main2_500_main
							}
						}
						MouseArea {
							id: memberArea
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: {
								mainItem.memberName = memberRow.member.core.fullName
								mainItem.memberNumber = memberRow.extension
								mainItem.edited = true
							}
						}
					}
				}
				MagicSearchProxy {
					id: teamSearch
					searchText: mainItem.memberNumber.length === 0 ? memberSearch.text : ""
					aggregationFlag: LinphoneEnums.MagicSearchAggregation.Friend
					sourceFlags: LinphoneEnums.MagicSearchSource.All
					filterType: MagicSearchProxy.FilteringTypes.App | MagicSearchProxy.FilteringTypes.Ldap
						| MagicSearchProxy.FilteringTypes.Extensions
				}
			}
			Text {
				visible: mainItem.forwardEnabled && mainItem.target === 2
				Layout.fillWidth: true
				text: "Les appelants pourront vous laisser un message."
				font: Typography.p1
				color: DefaultStyle.main2_600
				wrapMode: Text.WordWrap
			}
			// Files d'attente : le renvoi y met le poste en pause, les appels des files vont aux autres agents.
			Text {
				visible: mainItem.forwardEnabled && QueuesCpp.agent && QueuesCpp.queueCount > 0
				Layout.fillWidth: true
				text: "Pendant le renvoi, vous êtes en pause dans vos files d'attente : leurs appels vont à vos collègues."
				font.pixelSize: Utils.getSizeWithScreenRatio(12)
				color: DefaultStyle.main2_500_main
				wrapMode: Text.WordWrap
			}
			Text {
				visible: text.length > 0
				Layout.fillWidth: true
				text: mainItem.pageError.length > 0 ? mainItem.pageError : ForwardCpp.errorText
				font.pixelSize: Utils.getSizeWithScreenRatio(12)
				font.weight: Font.DemiBold
				color: DefaultStyle.danger_500_main
				wrapMode: Text.WordWrap
			}
			Text {
				visible: mainItem.savedNow
				Layout.fillWidth: true
				text: ForwardCpp.enabled ? "Renvoi enregistré." : "Renvoi arrêté."
				font.pixelSize: Utils.getSizeWithScreenRatio(12)
				font.weight: Font.DemiBold
				color: "#2F7D4F"
			}
		}
	}
}
