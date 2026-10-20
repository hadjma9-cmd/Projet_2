import QtQuick
import QtQuick.Layouts
import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

// Envoyer la fiche d'un contact personnel a un membre de l'equipe : on choisit le membre, la fiche part dans la
// conversation avec lui comme un message (Utils.formatContactCard), et il l'ajoute a ses contacts d'un clic.
MainRightPanel {
	id: mainItem
	property FriendGui contact
	readonly property string contactName: contact ? contact.core.fullName : ""
	signal close()

	// Texte de la fiche : prenom, nom et numeros (un numero porte par une adresse SIP compte aussi).
	function cardText() {
		var phones = []
		var numbers = contact.core.phoneNumbers
		for (var i = 0; i < numbers.length; ++i)
			phones.push(numbers[i].address)
		var addresses = contact.core.addresses
		for (var j = 0; j < addresses.length; ++j) {
			var user = UtilsCpp.getUsername(addresses[j].address)
			if (/^\+?[0-9]{3,20}$/.test(user) && phones.indexOf(user) === -1)
				phones.push(user)
		}
		var given = contact.core.givenName
		var family = contact.core.familyName
		if (given.length === 0 && family.length === 0)
			given = contact.core.fullName
		return Utils.formatContactCard(given, family, phones)
	}

	// Conversation avec le membre choisi, recuperee (ou creee) par le SDK ; la fiche part des qu'elle est prete.
	property var pendingChatObj: null
	property ChatGui pendingChat: pendingChatObj ? pendingChatObj.value : null
	property string pendingTargetName
	onPendingChatChanged: if (pendingChat) {
		var chat = pendingChat
		pendingChatObj = null
		sendTimeout.stop()
		chat.core.lSendTextMessage(mainItem.cardText())
		UtilsCpp.showInformationPopup("Fiche envoyée", mainItem.contactName + " a été envoyé à " + pendingTargetName + ".", true)
		mainItem.close()
	}
	Timer {
		id: sendTimeout
		interval: 8000
		onTriggered: {
			mainItem.pendingChatObj = null
			UtilsCpp.showInformationPopup("Envoi impossible",
				"La conversation avec " + mainItem.pendingTargetName + " n'a pas pu s'ouvrir. Réessayez.", false)
		}
	}
	function sendTo(target) {
		if (!target || target.core.defaultAddress.length === 0 || pendingChatObj)
			return
		var targetName = target.core.fullName
		UtilsCpp.getMainWindow().showConfirmationLambdaPopup("Envoyer la fiche",
			"Envoyer " + mainItem.contactName + " à " + targetName + " ?", "",
			function (confirmed) {
				if (!confirmed)
					return
				mainItem.pendingTargetName = targetName
				sendTimeout.restart()
				mainItem.pendingChatObj = UtilsCpp.getChatForAddress(target.core.defaultAddress)
			}, "Annuler", "Envoyer", undefined, "info", AppIcons.addressBook)
	}

	headerContentItem: RowLayout {
		Text {
			Layout.fillWidth: true
			text: "Envoyer " + mainItem.contactName + " à…"
			elide: Text.ElideRight
			font {
				pixelSize: Utils.getSizeWithScreenRatio(20)
				weight: Typography.h4.weight
			}
		}
		Button {
			style: ButtonStyle.noBackground
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(30)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(30)
			icon.source: AppIcons.closeX
			icon.width: Utils.getSizeWithScreenRatio(24)
			icon.height: Utils.getSizeWithScreenRatio(24)
			Accessible.name: "Fermer"
			onClicked: mainItem.close()
		}
	}

	// Les membres de l'equipe (postes internes), avec la recherche par nom ou par poste.
	content: CreationFormLayout {
		teamMode: true
		showTeam: true
		startGroupButtonVisible: false
		searchBarColor: DefaultStyle.grey_0
		onContactClicked: contact => mainItem.sendTo(contact)
	}
}
