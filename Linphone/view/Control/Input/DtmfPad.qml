import QtQuick
import QtQuick.Layouts
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle

// Clavier de l'appel en cours : chaque touche envoie sa tonalite (DTMF) au correspondant, quand un serveur vocal ou
// une messagerie demande de taper. Chiffres tapes en grand en haut, pave juste dessous. Pas d'effacement : une
// tonalite envoyee est deja prise en compte par le serveur. Clavier de l'ordinateur : pave numerique seulement
// (handleKeyPadEvent, a appeler par la fenetre qui recoit les touches).
FocusScope {
	id: mainItem
	property var call: null
	property string typedDigits: ""
	property var keyStyle: ButtonStyle.numericPad
	property real keySize: Utils.getSizeWithScreenRatio(64)
	property real keyColumnSpacing: Utils.getSizeWithScreenRatio(28)
	property real keyRowSpacing: Utils.getSizeWithScreenRatio(14)

	implicitWidth: column.implicitWidth
	implicitHeight: column.implicitHeight

	// Touche du clavier de l'ordinateur : chiffres et * du pave numerique.
	function handleKeyPadEvent(event) {
		if (event.modifiers & Qt.KeypadModifier)
			numPad.handleKeyPadEvent(event)
	}
	// Autre appel : affichage remis a zero.
	onCallChanged: mainItem.typedDigits = ""

	ColumnLayout {
		id: column
		anchors.fill: parent
		spacing: 0

		// Chiffres tapes, centres. Hauteur fixe : le pave ne bouge pas.
		Item {
			Layout.fillWidth: true
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(110)
			Text {
				anchors.centerIn: parent
				// Les derniers chiffres restent visibles quand la saisie est longue.
				width: Math.min(implicitWidth, mainItem.width - Utils.getSizeWithScreenRatio(40))
				elide: Text.ElideLeft
				text: mainItem.typedDigits
				color: DefaultStyle.main2_700
				font.family: DefaultStyle.defaultFont
				font.pixelSize: Utils.getSizeWithScreenRatio(34)
				font.weight: Font.Medium
				font.letterSpacing: Utils.getSizeWithScreenRatio(3)
			}
		}

		NumericPad {
			id: numPad
			Layout.alignment: Qt.AlignHCenter
			currentCall: mainItem.call
			lastRowVisible: false
			keyStyle: mainItem.keyStyle
			keySize: mainItem.keySize
			keyColumnSpacing: mainItem.keyColumnSpacing
			keyRowSpacing: mainItem.keyRowSpacing
			// La tonalite est envoyee par NumericPad lui-meme ; ici, seulement l'affichage.
			onButtonPressed: text => mainItem.typedDigits += text
		}

		Text {
			Layout.alignment: Qt.AlignHCenter
			Layout.topMargin: Utils.getSizeWithScreenRatio(22)
			text: "Vous pouvez aussi taper sur le pavé numérique du clavier"
			color: DefaultStyle.main2_400
			font.pixelSize: Utils.getSizeWithScreenRatio(12)
		}

		Item {
			Layout.fillHeight: true
		}
	}
}
