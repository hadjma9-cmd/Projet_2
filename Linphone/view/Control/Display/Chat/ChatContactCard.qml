import QtQuick
import QtQuick.Layouts
import Linphone
import UtilsCpp
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Fiche de contact dans une conversation (message texte reconnu par Utils.parseContactCard) : nom et numeros, et, pour
// celui qui la recoit, « Ajouter a mes contacts » : un clic cree le contact personnel, sans formulaire.
ColumnLayout {
	id: mainItem
	// { name, given, family, phones }
	property var card
	property bool isRemoteMessage: false
	property bool added: false
	// Numero deja dans les contacts (personnels ou de l'equipe) : rien a ajouter. La recherche rend aussi des fiches
	// temporaires (numero vu dans l'historique ou une recherche) : celles-la ne comptent pas, sinon le bouton
	// disparaissait au profit de « Deja dans vos contacts » pour quelqu'un qui n'y etait pas.
	property var existingObj: card ? UtilsCpp.findFriendByAddress(card.phones[0]) : null
	readonly property var existing: existingObj ? existingObj.value : null
	readonly property bool known: !!existing && (existing.core.isAppFriend || existing.core.isLdap)

	spacing: Utils.getSizeWithScreenRatio(10)

	// Un numero francais se lit par paires, comme sur la fiche d'un contact.
	function formatNumber(value) {
		var digits = String(value).replace(/[^0-9]/g, "")
		return /^0[0-9]{9}$/.test(digits) ? digits.replace(/([0-9]{2})(?=[0-9])/g, "$1 ") : value
	}
	function addToContacts() {
		var friendGui = Qt.createQmlObject('import Linphone; FriendGui {}', mainItem)
		friendGui.core.givenName = card.given
		friendGui.core.familyName = card.family
		for (var i = 0; i < card.phones.length; ++i)
			friendGui.core.appendPhoneNumber(qsTr("phone"), card.phones[i])
		friendGui.core.save()
		added = true
	}

	RowLayout {
		spacing: Utils.getSizeWithScreenRatio(12)
		Rectangle {
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(40)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(40)
			radius: width / 2
			color: DefaultStyle.main2_200
			Text {
				anchors.centerIn: parent
				text: mainItem.card ? UtilsCpp.getInitials(mainItem.card.name) : ""
				color: DefaultStyle.main2_700
				font.pixelSize: Utils.getSizeWithScreenRatio(14)
				font.weight: Font.Bold
				font.capitalization: Font.AllUppercase
			}
		}
		ColumnLayout {
			spacing: 0
			Text {
				text: mainItem.card ? mainItem.card.name : ""
				textFormat: Text.PlainText
				color: DefaultStyle.main2_800
				font.pixelSize: Utils.getSizeWithScreenRatio(14)
				font.weight: Font.DemiBold
			}
			Repeater {
				model: mainItem.card ? mainItem.card.phones : []
				Text {
					required property string modelData
					text: mainItem.formatNumber(modelData)
					textFormat: Text.PlainText
					color: DefaultStyle.main2_600
					font.pixelSize: Utils.getSizeWithScreenRatio(13)
				}
			}
		}
	}

	// Celui qui recoit : le bouton, puis ce qu'il en est (ajoute a l'instant, ou deja present).
	Rectangle {
		id: stateBar
		readonly property bool done: mainItem.added || mainItem.known
		visible: mainItem.isRemoteMessage
		Layout.preferredWidth: stateRow.implicitWidth + Utils.getSizeWithScreenRatio(28)
		Layout.preferredHeight: Utils.getSizeWithScreenRatio(32)
		radius: height / 2
		color: done
			? DefaultStyle.account_status_background_green
			: addArea.containsMouse ? Qt.lighter(DefaultStyle.main1_button, 1.15) : DefaultStyle.main1_button
		RowLayout {
			id: stateRow
			anchors.centerIn: parent
			spacing: Utils.getSizeWithScreenRatio(6)
			EffectImage {
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(15)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(15)
				imageSource: stateBar.done ? AppIcons.check : AppIcons.userPlus
				colorizationColor: stateBar.done ? DefaultStyle.account_status_green : DefaultStyle.grey_0
			}
			Text {
				text: mainItem.added
					? "Ajouté à vos contacts"
					: mainItem.known ? "Déjà dans vos contacts" : "Ajouter à mes contacts"
				color: stateBar.done ? DefaultStyle.account_status_green : DefaultStyle.grey_0
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
			}
		}
		MouseArea {
			id: addArea
			anchors.fill: parent
			enabled: !stateBar.done
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: mainItem.addToContacts()
		}
		Accessible.role: Accessible.Button
		Accessible.name: "Ajouter " + (mainItem.card ? mainItem.card.name : "") + " à mes contacts"
	}
}
