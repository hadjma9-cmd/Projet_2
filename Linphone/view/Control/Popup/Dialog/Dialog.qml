import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as Control
import QtQuick.Effects
import QtQuick.Layouts
import Linphone
import CustomControls 1.0
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

Popup {
	id: mainItem
	modal: true
	anchors.centerIn: parent
	closePolicy: Control.Popup.NoAutoClose
	// Confirmation simple (sans titre, ex. « Souhaitez-vous appeler… ? ») : plus aeree, une ombre douce au lieu
	// du filet bleu. Un peu plus serree dans la petite fenetre (Combiné), pour ne pas l'encombrer.
	readonly property bool simple: title.length === 0
	readonly property bool compactWindow: AppCpp.compactMode
    leftPadding: Utils.getSizeWithScreenRatio(simple ? (compactWindow ? 16 : 20) : 33)
    rightPadding: Utils.getSizeWithScreenRatio(simple ? (compactWindow ? 16 : 20) : 33)
    topPadding: Utils.getSizeWithScreenRatio(simple ? (compactWindow ? 16 : 20) : 37)
    bottomPadding: Utils.getSizeWithScreenRatio(simple ? (compactWindow ? 14 : 18) : 37)
	underlineColor: simple ? "transparent" : DefaultStyle.main1_500_main
    radius: simple ? Utils.getSizeWithScreenRatio(14) : 0
	shadowBlur: simple ? 0.7 : 0.1
	shadowOpacity: simple ? 0.22 : 0.1
	shadowVerticalOffset: simple ? Utils.getSizeWithScreenRatio(4) : 0
	property string title
	property var titleColor: DefaultStyle.main1_500_main
	property string text
	// Texte brut par defaut ; Text.StyledText pour un message avec gras (<b>), dont le texte variable est echappe.
	property int textFormat: Text.PlainText
	property string details
    //: "Confirmer"
    property string firstButtonText: firstButtonAccept ? qsTr("dialog_confirm")
                                                         //: "Annuler"
                                                       : qsTr("dialog_cancel")
    property string secondButtonText: secondButtonAccept ? qsTr("dialog_confirm")
                                                         : qsTr("dialog_cancel")
  	property alias content: contentLayout.data
  	property alias buttons: buttonsLayout.data
	property alias firstButton: firstButtonId
	property alias secondButton: secondButtonId
	property bool firstButtonAccept: true
	property bool secondButtonAccept: false

	signal accepted()
	signal rejected()

	property Item itemToFocusOnClose: null
	property bool quitWithKeyboard : false

	function updateQuitWithKeyboardPress (event) {
		if(visible && (event.key == Qt.Key_Escape || event.key == Qt.Key_Enter || event.key == Qt.Key_Space || event.key == Qt.Key_Return)){
			mainItem.quitWithKeyboard = true
		}
	}

	onAboutToHide: {
		if(mainItem.itemToFocusOnClose && mainItem.itemToFocusOnClose.visible && mainItem.quitWithKeyboard){
			// Focus last element that was focused before Dialog was opened
			mainItem.itemToFocusOnClose.forceActiveFocus(Qt.TabFocusReason)
		}
		mainItem.itemToFocusOnClose = null
	}

	contentItem: FocusScope {
		Accessible.role: Accessible.Dialog
		Accessible.name: mainItem.title
		Accessible.description: mainItem.details
		implicitWidth: child.implicitWidth
		implicitHeight: child.implicitHeight
		onVisibleChanged: {
			if(visible){
				mainItem.itemToFocusOnClose = FocusNavigator.lastFocusItem
				const focusReason = FocusNavigator.doesLastFocusWasKeyboard() ? Qt.TabFocusReason : Qt.OtherFocusReason
				forceActiveFocus(focusReason)
			}
		}
		Keys.onPressed: (event) => {
			mainItem.updateQuitWithKeyboardPress(event)
			if(visible && event.key == Qt.Key_Escape){
				mainItem.close()
				event.accepted = true
			} else if (visible && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
				// Entree declenche le bouton selectionne (« Appeler » par defaut) : les boutons ne repondent
				// d'eux-memes qu'a la barre d'espace.
				var focused = Window.activeFocusItem
				if (focused && focused.clicked && Utils.isDescendant(focused, mainItem.contentItem)) {
					focused.clicked()
					event.accepted = true
				}
			}
		}
		ColumnLayout {
			id: child
			anchors.fill: parent
            spacing: Utils.getSizeWithScreenRatio(mainItem.simple ? (mainItem.compactWindow ? 14 : 18) : 15)
			
			Text{
				id: titleText
				Layout.fillWidth: true
				visible: text.length != 0
				text: mainItem.title
				color: mainItem.titleColor
				font {
                    pixelSize: Typography.h3.pixelSize
                    weight: Typography.h3.weight
				}
				wrapMode: Text.Wrap
				horizontalAlignment: Text.AlignLeft
			}
			Rectangle{
				Layout.fillWidth: true
				Layout.preferredHeight: 1
				color: DefaultStyle.main2_400
				visible: titleText.visible
			}
	
			Text {
				id: defaultText
				visible: text.length != 0
				Layout.fillWidth: true
				Layout.alignment: Qt.AlignCenter
				text: mainItem.text
				textFormat: mainItem.textFormat
				font {
                    pixelSize: mainItem.simple && mainItem.compactWindow ? Utils.getSizeWithScreenRatio(13) : Typography.p1.pixelSize
                    weight: Typography.p1.weight
				}
				wrapMode: Text.Wrap
				horizontalAlignment: titleText.visible ?  Text.AlignLeft : Text.AlignHCenter
			}
			Text {
				id: detailsText
				visible: text.length != 0
				Layout.fillWidth: true
                //Layout.preferredWidth: Utils.getSizeWithScreenRatio(278)
				Layout.alignment: Qt.AlignCenter
				text: mainItem.details
				font {
                    pixelSize: Typography.p1.pixelSize
                    weight: Typography.p1.weight
					italic: true
				}
				wrapMode: Text.Wrap
				horizontalAlignment: Text.AlignHCenter
			}
	
			ColumnLayout {
				id: contentLayout
				Layout.alignment: Qt.AlignHCenter
				Layout.fillHeight: false
			}
			
			RowLayout {
				id: buttonsLayout
				Layout.alignment: Qt.AlignBottom | ( titleText.visible ? Qt.AlignRight : Qt.AlignHCenter)
                spacing: Utils.getSizeWithScreenRatio(titleText.visible ? 20 : 10)
				onVisibleChanged: if (visible) {
					if (mainItem.firstButtonAccept) firstButtonId.forceActiveFocus()
					else secondButtonId.forceActiveFocus()
				}

				// Default buttons only visible if no other children
				// have been set
				MediumButton {
					id:firstButtonId
					visible: mainItem.buttons.length === 2
					leftPadding: Utils.getSizeWithScreenRatio(mainItem.simple ? (mainItem.compactWindow ? 14 : 20) : 16)
					rightPadding: leftPadding
					topPadding: Utils.getSizeWithScreenRatio(mainItem.simple && mainItem.compactWindow ? 8 : 10)
					bottomPadding: topPadding
					text: mainItem.firstButtonText
					style: mainItem.firstButtonAccept ? ButtonStyle.main : ButtonStyle.secondary
					focus: !mainItem.firstButtonAccept
					focusPolicy: Qt.StrongFocus
					activeFocusOnTab:true
					keyboardFocus: FocusHelper.keyboardFocus || FocusHelper.otherFocus
					onClicked: {
						if(mainItem.firstButtonAccept)
							mainItem.accepted()
						else
							mainItem.rejected()
						mainItem.close()
					}
					Keys.onPressed: (event) => {
						mainItem.updateQuitWithKeyboardPress(event)
					}
					KeyNavigation.left: secondButtonId
					KeyNavigation.right: secondButtonId
				}
				MediumButton {
					id: secondButtonId
					visible: mainItem.buttons.length === 2
					leftPadding: firstButtonId.leftPadding
					rightPadding: firstButtonId.rightPadding
					topPadding: firstButtonId.topPadding
					bottomPadding: firstButtonId.bottomPadding
					text: mainItem.secondButtonText
					style: mainItem.firstButtonAccept ? ButtonStyle.secondary : ButtonStyle.main
					focus: !mainItem.secondButtonAccept
					focusPolicy: Qt.StrongFocus
					activeFocusOnTab:true
					keyboardFocus: FocusHelper.keyboardFocus || FocusHelper.otherFocus
					onClicked: {
						if(mainItem.secondButtonAccept)
							mainItem.accepted()
						else
							mainItem.rejected()
						mainItem.close()
					}
					Keys.onPressed: (event) => {
						mainItem.updateQuitWithKeyboardPress(event)
					}
					KeyNavigation.left: firstButtonId
					KeyNavigation.right: firstButtonId
				}
			}
		}
	}
}
