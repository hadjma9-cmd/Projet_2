
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
		} else {
			mainItem.target = 0
			mainItem.number = destination
		}
		mainItem.edited = false
	}
	// Postes internes de l'équipe, triés par nom (sans le sien) ; en tête, « Choisir… » tant qu'aucun n'est choisi.
	readonly property string ownNumber: accounts.defaultAccount
		? UtilsCpp.getUsername(accounts.defaultAccount.core.identityAddress) : ""
	readonly property var members: {
		var list = []
		var count = teamList.count // relu quand la liste arrive
		var all = teamList.getAll()
		for (var i = 0; i < all.length; ++i) {
			var number = all[i] ? UtilsCpp.getUsername(all[i].core.defaultAddress) : ""
			if (number.length > 0 && number !== mainItem.ownNumber)
				list.push({text: all[i].core.fullName + " · " + number, number: number})
		}
		list.sort(function (a, b) { return a.text.localeCompare(b.text) })
		return [{text: "Choisir un membre de l'équipe", number: ""}].concat(list)
	}
	readonly property int memberIndex: Math.max(0, members.findIndex(function (member) {
		return member.number === mainItem.memberNumber
	}))
	AccountProxy {
		id: accounts
	}
	MagicSearchProxy {
		id: teamList
		aggregationFlag: LinphoneEnums.MagicSearchAggregation.Friend
		sourceFlags: LinphoneEnums.MagicSearchSource.All
		filterType: MagicSearchProxy.FilteringTypes.App | MagicSearchProxy.FilteringTypes.Ldap
			| MagicSearchProxy.FilteringTypes.Extensions
		initialDisplayItems: 1000
		onInitialized: forceUpdate()
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
				subTitleText: "Absent ou en réunion ? Vos appels directs vont à un collègue, à votre messagerie ou à un autre numéro."
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
			// Un membre de l'équipe : choisi dans la liste des postes internes (celle de l'onglet Équipe), par nom.
			ColumnLayout {
				visible: mainItem.forwardEnabled && mainItem.target === 1
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(6)
				Text {
					text: "Membre de l'équipe"
					font: Typography.p2l
					color: DefaultStyle.main2_600
				}
				ComboBox {
					Layout.fillWidth: true
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(49)
					model: mainItem.members
					currentIndex: mainItem.memberIndex
					onCurrentIndexChanged: {
						var member = mainItem.members[currentIndex]
						// La liste qui arrive ou se recharge suit le membre choisi : seul un choix dans la liste change
						// la destination.
						if (!member || currentIndex === mainItem.memberIndex) return
						mainItem.memberNumber = member.number
						mainItem.edited = true
					}
					accessibleLabel: "Membre de l'équipe"
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
