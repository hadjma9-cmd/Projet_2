import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Linphone
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Ecriture du message de statut, a la place des statuts dans le menu : titre, zone de texte (avec le nombre de
// caracteres), puis Annuler / Enregistrer de meme largeur.
ColumnLayout {
	id: mainItem
	spacing: Utils.getSizeWithScreenRatio(12)
	property var accountGui
	signal isSet
	signal canceled

	onVisibleChanged: if (visible) {
		statusMessage.text = mainItem.accountGui ? mainItem.accountGui.core.presenceNote : ""
		statusMessage.forceActiveFocus()
		statusMessage.cursorPosition = statusMessage.text.length
	}

	Text {
		Layout.fillWidth: true
		text: "Message de statut"
		font.pixelSize: Utils.getSizeWithScreenRatio(14)
		font.weight: Font.DemiBold
		color: DefaultStyle.main2_800
	}

	Rectangle {
		Layout.fillWidth: true
		Layout.preferredHeight: Utils.getSizeWithScreenRatio(110)
		color: "transparent"
		border.color: statusMessage.activeFocus ? DefaultStyle.main1_500_main : DefaultStyle.main2_300
		border.width: Utils.getSizeWithScreenRatio(1)
		radius: Utils.getSizeWithScreenRatio(8)

		ColumnLayout {
			anchors.fill: parent
			anchors.margins: Utils.getSizeWithScreenRatio(10)
			TextEdit {
				id: statusMessage
				wrapMode: TextEdit.Wrap
				font.pixelSize: Utils.getSizeWithScreenRatio(14)
				color: DefaultStyle.main2_800
				Layout.fillHeight: true
				Layout.fillWidth: true
				property string previoustext: ""
				onTextChanged: {
					if (mainItem.accountGui && statusMessage.text.length > mainItem.accountGui.core.maxPresenceNoteSize) {
						statusMessage.text = previoustext
						statusMessage.cursorPosition = statusMessage.text.length
					} else {
						previoustext = statusMessage.text
					}
				}
				Text {
					visible: statusMessage.text.length === 0
					text: "Ex. : en réunion jusqu'à 15 h"
					font: statusMessage.font
					color: DefaultStyle.main2_400
				}
			}
			Text {
				Layout.fillWidth: true
				text: statusMessage.text.length + " / " + (mainItem.accountGui ? mainItem.accountGui.core.maxPresenceNoteSize : 0)
				font.pixelSize: Utils.getSizeWithScreenRatio(12)
				color: DefaultStyle.main2_400
				horizontalAlignment: Text.AlignRight
			}
		}
	}

	RowLayout {
		Layout.fillWidth: true
		spacing: Utils.getSizeWithScreenRatio(10)
		DialogButton {
			text: "Annuler"
			style: ButtonStyle.secondary
			onClicked: mainItem.canceled()
		}
		DialogButton {
			//: "Enregistrer"
			text: qsTr("contact_presence_button_save_custom_status")
			style: ButtonStyle.main
			enabled: statusMessage.text.length > 0
			onClicked: {
				mainItem.accountGui.core.presenceNote = statusMessage.text
				mainItem.isSet()
			}
		}
	}
}
