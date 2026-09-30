import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control

import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Clavier de « Nouvel appel » : on compose un numero et on appelle, comme sur un telephone.
// Aucune liste de contacts : seul le contact dont c'est exactement le numero est rappele sous le
// numero compose, et c'est lui qui est appele.
FocusScope {
	id: mainItem

	// Numero compose, sans ses separateurs (espaces, points, tirets, parentheses).
	readonly property string number: numberField.text.replace(/[\s.()\/-]/g, "")
	signal callRequested(string number)

	function focusNumber() {
		numberField.forceActiveFocus()
	}
	function launchCall() {
		if (mainItem.number.length > 0)
			mainItem.callRequested(mainItem.number)
	}
	// Touche du pave : saisie au curseur, puis le focus revient au numero pour que le clavier
	// de l'ordinateur continue d'y ecrire.
	function insertText(text) {
		if (numberField.selectedText.length > 0)
			numberField.remove(numberField.selectionStart, numberField.selectionEnd)
		numberField.insert(numberField.cursorPosition, text)
		numberField.forceActiveFocus()
	}
	function eraseText() {
		if (numberField.selectedText.length > 0)
			numberField.remove(numberField.selectionStart, numberField.selectionEnd)
		else if (numberField.cursorPosition > 0)
			numberField.remove(numberField.cursorPosition - 1, numberField.cursorPosition)
		numberField.forceActiveFocus()
	}

	// Recherche du contact correspondant, lancee une fois la saisie posee.
	property string searchedNumber: ""
	onNumberChanged: searchDelay.restart()
	Timer {
		id: searchDelay
		interval: 300
		onTriggered: mainItem.searchedNumber = mainItem.number
	}
	property MagicSearchProxy matchProxy: MagicSearchProxy {
		searchText: mainItem.searchedNumber
		exactNumberMatch: true
		showMe: false
		sourceFlags: LinphoneEnums.MagicSearchSource.All
		aggregationFlag: LinphoneEnums.MagicSearchAggregation.Friend
		filterType: MagicSearchProxy.FilteringTypes.App
		            | MagicSearchProxy.FilteringTypes.Ldap
		            | MagicSearchProxy.FilteringTypes.CardDAV
		initialDisplayItems: 1
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Numero compose
		Item {
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(26)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(56)
			TextInput {
				id: numberField
				anchors.fill: parent
				focus: true
				clip: true
				horizontalAlignment: TextInput.AlignHCenter
				verticalAlignment: TextInput.AlignVCenter
				color: DefaultStyle.main2_700
				font.family: DefaultStyle.defaultFont
				font.pixelSize: Utils.getSizeWithScreenRatio(36)
				font.weight: Font.Bold
				font.letterSpacing: Utils.getSizeWithScreenRatio(2)
				selectByMouse: true
				inputMethodHints: Qt.ImhDialableCharactersOnly
				validator: RegularExpressionValidator {
					regularExpression: /[0-9+*#\s.()\/-]{0,32}/
				}
				//: "Numéro à appeler"
				Accessible.name: qsTr("dialer_number_accessible_name")
				Keys.onPressed: event => {
					if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						mainItem.launchCall()
						event.accepted = true
					} else if ((event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
							   || event.key === Qt.Key_Asterisk || event.key === Qt.Key_Plus) {
						// Meme effet qu'un appui sur la touche du pave (animation et tonalite) ;
						// le caractere arrive par buttonPressed.
						numPad.handleKeyPadEvent(event)
					}
				}
			}
			Text {
				anchors.centerIn: parent
				visible: numberField.text.length === 0
				//: "Saisissez un numéro"
				text: qsTr("dialer_number_placeholder")
				color: DefaultStyle.main2_400
				font.pixelSize: Utils.getSizeWithScreenRatio(20)
			}
		}

		// Contact dont c'est exactement le numero ; place reservee pour que le pave ne bouge pas.
		Item {
			Layout.fillWidth: true
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(48)
			Row {
				anchors.centerIn: parent
				Repeater {
					model: mainItem.number.length > 0 ? mainItem.matchProxy : null
					delegate: Rectangle {
						id: matchChip
						property var friendGui: $modelData
						height: Utils.getSizeWithScreenRatio(36)
						width: chipContent.implicitWidth + Utils.getSizeWithScreenRatio(24)
						radius: height / 2
						color: DefaultStyle.main2_100
						Row {
							id: chipContent
							anchors.centerIn: parent
							spacing: Utils.getSizeWithScreenRatio(8)
							Avatar {
								anchors.verticalCenter: parent.verticalCenter
								width: Utils.getSizeWithScreenRatio(26)
								height: width
								shadowEnabled: false
								contact: matchChip.friendGui
							}
							Text {
								anchors.verticalCenter: parent.verticalCenter
								text: matchChip.friendGui ? matchChip.friendGui.core.fullName : ""
								color: DefaultStyle.main2_700
								font.pixelSize: Typography.b2.pixelSize
								font.weight: Font.Bold
							}
							Text {
								anchors.verticalCenter: parent.verticalCenter
								//: "Poste %1"
								text: "· " + (/^[0-9]{1,5}$/.test(mainItem.number)
											  ? qsTr("dialer_contact_extension").arg(mainItem.number)
											  : mainItem.number)
								color: DefaultStyle.main2_500_main
								font.pixelSize: Typography.p1.pixelSize
							}
						}
					}
				}
			}
		}

		NumericPad {
			id: numPad
			Layout.alignment: Qt.AlignHCenter
			Layout.topMargin: Utils.getSizeWithScreenRatio(12)
			// Touches teintees : la page est blanche, les touches par defaut le sont aussi.
			keyStyle: ButtonStyle.numericPadLight
			keySize: Utils.getSizeWithScreenRatio(64)
			keyColumnSpacing: Utils.getSizeWithScreenRatio(30)
			keyRowSpacing: Utils.getSizeWithScreenRatio(14)
			onButtonPressed: text => mainItem.insertText(text)
			onWipe: mainItem.eraseText()
			onLaunchCall: mainItem.launchCall()
		}

		Item {
			Layout.fillHeight: true
		}
	}
}
