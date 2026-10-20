import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as Control
import QtQuick.Effects
import QtQuick.Layouts
import Linphone
import CustomControls 1.0
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Fenetre de decision, la meme partout (grande fenetre et Combine) : carte arrondie et centree, icone dans un rond en
// haut, titre et texte centres, deux boutons de meme largeur cote a cote (Annuler a gauche, l'action a droite).
// Le genre (kind) donne la couleur du rond, de l'icone et du bouton d'action : « info » (bleu, action normale),
// « warning » (orange, attention) ou « danger » (rouge, action definitive). Chaque fenetre choisit aussi son icone.
Popup {
	id: mainItem
	modal: true
	closePolicy: Control.Popup.NoAutoClose
	readonly property bool compactWindow: AppCpp.compactMode
	// Mesures paires et arrondies au pixel : tout se centre exactement (texte net, aucun demi-pixel).
	function evenSize(value) {
		return 2 * Math.round(Utils.getSizeWithScreenRatio(value) / 2)
	}
	// Jamais plus large que l'endroit ou elle s'ouvre (Combine : 414 de large), marge comprise.
	width: Math.min(evenSize(compactWindow ? 330 : 380), 2 * Math.floor(((parent ? parent.width : 380) - evenSize(32)) / 2))
	// Centree au pixel pres (le centrage automatique pouvait tomber sur un demi-pixel).
	x: parent ? Math.round((parent.width - width) / 2) : 0
	y: parent ? Math.round((parent.height - height) / 2) : 0
	// La meme marge sur les quatre cotes.
	leftPadding: evenSize(compactWindow ? 20 : 24)
	rightPadding: leftPadding
	topPadding: leftPadding
	bottomPadding: leftPadding
	underlineColor: "transparent"
	radius: Utils.getSizeWithScreenRatio(16)
	shadowBlur: 0.7
	shadowOpacity: 0.22
	shadowVerticalOffset: Utils.getSizeWithScreenRatio(4)

	property string title
	property var titleColor: DefaultStyle.main2_800
	property string text
	// Texte brut par defaut ; Text.StyledText pour un message avec gras (<b>), dont le texte variable est echappe.
	property int textFormat: Text.PlainText
	property string details
	property string kind: "info"
	// Icone du rond ; vide : celle du genre (point d'interrogation, ou point d'exclamation pour attention et danger).
	property string iconSource: ""
	property bool showIcon: true
	readonly property string shownIcon: iconSource !== "" ? iconSource
		: kind === "info" ? AppIcons.question : AppIcons.warningCircle
	readonly property color kindColor: kind === "danger" ? DefaultStyle.danger_500_main
		: kind === "warning" ? "#D97A1E" : DefaultStyle.main1_500_main
	readonly property color kindLightColor: kind === "danger" ? "#FBE7E7"
		: kind === "warning" ? "#FCEBD8" : DefaultStyle.main1_100
	// Bouton d'action : bleu de l'application, rouge de « Raccrocher », ou orange assez fonce pour un texte blanc lisible.
	readonly property var actionStyle: kind === "danger" ? {
			"color": { "normal": DefaultStyle.danger_500_main, "hovered": DefaultStyle.danger_700,
			           "pressed": DefaultStyle.danger_900 },
			"text": { "normal": DefaultStyle.grey_0, "pressed": DefaultStyle.grey_0 },
			"image": { "normal": DefaultStyle.grey_0, "pressed": DefaultStyle.grey_0 }
		} : kind === "warning" ? {
			"color": { "normal": "#B8650F", "hovered": "#9A540C", "pressed": "#7D4409" },
			"text": { "normal": DefaultStyle.grey_0, "pressed": DefaultStyle.grey_0 },
			"image": { "normal": DefaultStyle.grey_0, "pressed": DefaultStyle.grey_0 }
		} : ButtonStyle.main

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
		Accessible.name: mainItem.title.length !== 0 ? mainItem.title : mainItem.text
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
			spacing: 0

			// Rond de couleur et son icone, de tailles paires : l'icone tombe exactement au centre.
			Rectangle {
				visible: mainItem.showIcon
				Layout.alignment: Qt.AlignHCenter
				Layout.bottomMargin: mainItem.evenSize(mainItem.compactWindow ? 14 : 16)
				Layout.preferredWidth: mainItem.evenSize(mainItem.compactWindow ? 46 : 52)
				Layout.preferredHeight: Layout.preferredWidth
				radius: width / 2
				color: mainItem.kindLightColor
				EffectImage {
					readonly property real side: mainItem.evenSize(mainItem.compactWindow ? 22 : 26)
					x: (parent.width - side) / 2
					y: (parent.height - side) / 2
					width: side
					height: side
					imageSource: mainItem.shownIcon
					colorizationColor: mainItem.kindColor
				}
			}
			Text {
				id: titleText
				Layout.fillWidth: true
				// Ecart sous le titre seulement si un texte suit (sinon il s'ajoutait a celui des boutons).
				Layout.bottomMargin: defaultText.visible ? mainItem.evenSize(8) : 0
				visible: text.length != 0
				text: mainItem.title
				// Un titre peut etre un nom de contact : jamais lu comme du HTML.
				textFormat: Text.PlainText
				color: mainItem.titleColor
				font {
					pixelSize: Utils.getSizeWithScreenRatio(mainItem.compactWindow ? 16 : 18)
					weight: Typography.h3.weight
				}
				wrapMode: Text.Wrap
				horizontalAlignment: Text.AlignHCenter
			}
			// Sans titre, la question elle-meme tient lieu de titre (« Quitter Gamaphone ? »).
			Text {
				id: defaultText
				visible: text.length != 0
				Layout.fillWidth: true
				text: mainItem.text
				textFormat: mainItem.textFormat
				color: titleText.visible ? DefaultStyle.main2_600 : mainItem.titleColor
				font {
					pixelSize: titleText.visible
						? Utils.getSizeWithScreenRatio(mainItem.compactWindow ? 13 : 14)
						: Utils.getSizeWithScreenRatio(mainItem.compactWindow ? 15 : 16)
					weight: titleText.visible ? Typography.p1.weight : Typography.h3.weight
				}
				lineHeight: 1.15
				wrapMode: Text.Wrap
				horizontalAlignment: Text.AlignHCenter
			}
			Text {
				id: detailsText
				visible: text.length != 0
				Layout.fillWidth: true
				Layout.topMargin: mainItem.evenSize(8)
				text: mainItem.details
				color: DefaultStyle.main2_500_main
				font {
					pixelSize: Utils.getSizeWithScreenRatio(mainItem.compactWindow ? 12 : 13)
					weight: Typography.p1.weight
				}
				wrapMode: Text.Wrap
				horizontalAlignment: Text.AlignHCenter
			}

			// Contenu propre a une fenetre (champ, liste...) : toute la largeur, chaque element choisit son alignement.
			ColumnLayout {
				id: contentLayout
				Layout.fillWidth: true
				// Ecart seulement s'il y a quelque chose au-dessus (la fenetre ZRTP n'a ni rond, ni titre, ni texte).
				Layout.topMargin: children.length > 0 && (mainItem.showIcon || titleText.visible || defaultText.visible
				                                          || detailsText.visible) ? mainItem.evenSize(16) : 0
				Layout.fillHeight: false
			}

			// Annuler a gauche, l'action a droite, de meme largeur. Les boutons par defaut sont dans l'ordre
			// premier/second ; quand le premier est l'action, la rangee s'inverse pour la garder a droite.
			RowLayout {
				id: buttonsLayout
				Layout.fillWidth: true
				Layout.topMargin: mainItem.evenSize(mainItem.compactWindow ? 20 : 24)
				Layout.alignment: Qt.AlignHCenter
				spacing: mainItem.evenSize(10)
				layoutDirection: mainItem.buttons.length === 2 && mainItem.firstButtonAccept ? Qt.RightToLeft
				                                                                             : Qt.LeftToRight
				onVisibleChanged: if (visible) {
					if (mainItem.firstButtonAccept) firstButtonId.forceActiveFocus()
					else secondButtonId.forceActiveFocus()
				}

				// Default buttons only visible if no other children
				// have been set
				DialogButton {
					id:firstButtonId
					visible: mainItem.buttons.length === 2
					text: mainItem.firstButtonText
					style: mainItem.firstButtonAccept ? mainItem.actionStyle : ButtonStyle.secondary
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
				DialogButton {
					id: secondButtonId
					visible: mainItem.buttons.length === 2
					text: mainItem.secondButtonText
					style: mainItem.secondButtonAccept ? mainItem.actionStyle : ButtonStyle.secondary
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
