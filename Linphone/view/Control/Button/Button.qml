import QtQuick
import QtQuick.Controls.Basic as Control
import QtQuick.Effects
import QtQuick.Layouts
import QtQml
import Linphone
import CustomControls 1.0
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

Control.Button {
	id: mainItem
	property var style
    property bool asynchronous: false
	hoverEnabled: enabled
	activeFocusOnTab: true
	property color disabledFilterColor: color.hslLightness > 0.5
		? DefaultStyle.grey_0
		: DefaultStyle.grey_400
	property bool hasNavigationFocus: enabled && (activeFocus || hovered)
	property bool keyboardFocus: FocusHelper.keyboardFocus
	// Background properties
	property color color: style?.color?.normal || DefaultStyle.main1_button
	property color hoveredColor: style?.color?.hovered || Qt.darker(color, 1.05)
    property color pressedColor: style?.color?.pressed || Qt.darker(color, 1.1)
    property color checkedColor: style?.color?.checked || style?.color?.pressed || Qt.darker(color, 1.1)
	property bool shadowEnabled: false
	property int capitalization
	property color backgroundColor: mainItem.checkable && mainItem.checked
                    ? mainItem.checkedColor || mainItem.pressedColor
                    : mainItem.pressed
                        ? mainItem.pressedColor
                        : mainItem.hovered
                            ? mainItem.hoveredColor
                            : mainItem.color
	// Text properties
	property bool underline: false
    property real textSize: Utils.getSizeWithScreenRatio(18)
    property real textWeight: Typography.b1.weight
    property color textColor: style?.text?.normal || DefaultStyle.grey_0
	property color hoveredTextColor: style?.text?.hovered || Qt.darker(textColor, 1.05)
	property color pressedTextColor: style?.text?.pressed || Qt.darker(textColor, 1.1)
	property var textFormat: Text.AutoText
	property var textHAlignment: Text.AlignHCenter
	// Tooltip properties
	ToolTip.visible: false
	ToolTip.delay: 500
	// Border properties
	property color borderColor: style?.borderColor?.normal || "transparent"
	property color keyboardFocusedBorderColor: style?.borderColor?.keybaordFocused || DefaultStyle.main2_900
	property real borderWidth: Utils.getSizeWithScreenRatio(1)
	property real keyboardFocusedBorderWidth: Utils.getSizeWithScreenRatio(3)
	// Image properties
	property var contentImageColor: style?.image? style.image.normal : DefaultStyle.main2_600
	property var hoveredImageColor: style && style.image && style.image.hovered ? style.image.hovered : Qt.darker(contentImageColor, 1.05)
	property var checkedImageColor: style && style.image && style.image.checked ? style.image.checked : Qt.darker(contentImageColor, 1.1)
	property var pressedImageColor: style && style.image && style.image.pressed ? style.image.pressed : Qt.darker(contentImageColor, 1.1)
	icon.source: style?.iconSource || ""
	property var colorizationColor:  checkable && checked 
		? checkedImageColor
		: pressed 
			? pressedImageColor
			: hovered 
				? hoveredImageColor 
				: contentImageColor
	// Size properties
	spacing: Utils.getSizeWithScreenRatio(5)
    property real radius: Math.ceil(height / 2)

	// Elements construits seulement quand ils servent : chaque bouton creait d'office deux bulles d'aide, une ombre
	// et, pour une icone, une seconde icone pour l'etat desactive, la plupart jamais affichees.
	// Ombre : des sa premiere activation, puis activee et desactivee comme avant (QTBUG-124730).
	property bool _shadowUsed: false
	onShadowEnabledChanged: if (shadowEnabled) _shadowUsed = true
	Component.onCompleted: if (shadowEnabled) _shadowUsed = true

	// Bulle d'aide : seulement si un texte d'aide est donne.
	Loader {
		active: mainItem.ToolTip.text !== ""
		sourceComponent: ToolTip {
			parent: mainItem
			text: mainItem.ToolTip.text
			delay: mainItem.ToolTip.delay
			visible: mainItem.hovered && text != ""
		}
	}

	MouseArea {
		id: mouseArea
		z: stacklayout.z + 1
		anchors.fill: parent
		hoverEnabled: true
		cursorShape: containsMouse ? Qt.PointingHandCursor : Qt.ArrowCursor
		acceptedButtons: Qt.NoButton
	}
	
	background: Loader{
		asynchronous: mainItem.asynchronous
		anchors.fill: parent
		
		sourceComponent: Item {
			width: mainItem.width
			height: mainItem.height
			Rectangle {
				id: buttonBackground
				anchors.fill: parent
                color: mainItem.backgroundColor
				radius: mainItem.radius
				// Plus de contour noir de focus clavier : il apparaissait aussi apres un simple clic,
				// le code rendant souvent le focus avec une raison « clavier » (PopupButton, Dialog...).
				// La bordure propre au style (boutons secondaires) est conservee.
				border.color: mainItem.borderColor
				border.width: mainItem.borderWidth
			}
			Loader {
				anchors.fill: buttonBackground
				active: mainItem.shadowEnabled || mainItem._shadowUsed
				sourceComponent: MultiEffect {
					enabled: mainItem.shadowEnabled
					source: buttonBackground
					visible:  mainItem.shadowEnabled
					// Crash : https://bugreports.qt.io/browse/QTBUG-124730
					shadowEnabled: true
					shadowColor: DefaultStyle.grey_1000
					shadowBlur: 0.1
					shadowOpacity: mainItem.shadowEnabled ? 0.5 : 0.0
				}
			}
		}
	}

	Rectangle {
		id: disableShadow
		z: 1
		// color: buttonBackground.color == "transparent" ? "transparent" : "white"
		color: disabledFilterColor
		opacity: 0.5
		visible: !mainItem.enabled && mainItem.color.a !== 0
		radius: mainItem.radius
		width: mainItem.width
		height: mainItem.height
	}
	
	component ButtonText: Text {
		id: buttonText
		horizontalAlignment: mainItem.textHAlignment
		verticalAlignment: Text.AlignVCenter
		width: textMetrics.advanceWidth
		wrapMode: Text.WrapAnywhere
		text: mainItem.text
		textFormat: mainItem.textFormat
		maximumLineCount: 1
        color: mainItem.checkable && mainItem.checked || mainItem.pressed
			? mainItem.pressedTextColor
			: mainItem.hovered
				? mainItem.hoveredTextColor
				: mainItem.textColor
		font {
			pixelSize: mainItem.textSize
			weight: mainItem.textWeight
			family: DefaultStyle.defaultFont
			capitalization: mainItem.capitalization
			underline: mainItem.underline
			bold: (mainItem.style === ButtonStyle.noBackground || mainItem.style === ButtonStyle.noBackgroundRed) && (mainItem.hovered || mainItem.pressed)
		}
		Loader {
			active: mainItem.hovered && (buttonText.implicitWidth > buttonText.width)
			sourceComponent: ToolTip {
				parent: mainItem
				text: mainItem.text
				visible: true
				delay: 500
			}
		}
		TextMetrics {
			id: textMetrics
			text: mainItem.text
			font.bold: true
		}
	}
	
	component ButtonImage: EffectImage {
		imageSource: mainItem.icon.source
		imageWidth: mainItem.icon.width
		imageHeight: mainItem.icon.height
        colorizationColor: mainItem.colorizationColor
	}
	
	// Contenu du bouton (icone et texte, texte seul, icone seule ou rien), remplace seulement quand le texte ou
	// l'icone apparait ou disparait. Un simple chargeur : chaque bouton de l'application creait auparavant une pile
	// de pages (StackView), objet lourd, pour ne contenir que cet element. Le chargeur prend aussi de lui-meme la
	// taille naturelle de son contenu (le contournement de la pile n'est plus utile).
	contentItem: Loader {
		id: stacklayout
		anchors.centerIn: parent
		sourceComponent: mainItem.text.length != 0 && mainItem.icon.source.toString().length != 0
			? imageTextComponent
			: mainItem.text.length != 0
				? textComponent
				: mainItem.icon.source.toString().length != 0
					? imageComponent
					: emptyComponent

		Component{
			id: imageTextComponent
			// Workaround for centering the content when its
			// width is smaller than the button width
			RowLayout {
				id: content
				width: stacklayout.width
				height: stacklayout.height
				RowLayout {
					Layout.alignment: Qt.AlignCenter
					spacing: mainItem.spacing
					ButtonImage{
						id: image
						Layout.preferredWidth: mainItem.icon.width
						Layout.preferredHeight: mainItem.icon.height
					}
					ButtonText {
						Layout.maximumWidth: content.width - image.width - content.spacing
						Layout.preferredWidth: implicitWidth
					}
				}
			}
		}
		Component{
			id: textComponent
			ButtonText {
				width: stacklayout.width
				height: stacklayout.height
				// Hack for StackView binding loop
				onImplicitHeightChanged: {implicitHeight}
			}
		}
		Component{
			id: imageComponent
			Item {
				width: stacklayout.width
				height: stacklayout.height
				ButtonImage {
					id: buttonIcon
					anchors.fill: parent
				}
				Loader {
					z: buttonIcon.z + 1
					anchors.fill: parent
					active: !mainItem.enabled
					sourceComponent: ButtonImage {
						colorizationColor: DefaultStyle.grey_0
						opacity: 0.5
					}
				}
			}
		}
		Component{
			id: emptyComponent
			Item {
				width: stacklayout.width
				height: stacklayout.height
			}
		}
	}
	/*
	contentItem: StackLayout {
		id: stacklayout
		currentIndex: mainItem.text.length != 0 && mainItem.icon.source.toString().length != 0
			? 0
			: mainItem.text.length != 0
				? 1
				: mainItem.icon.source.toString().length != 0
					? 2
					: 3
					
		width: mainItem.width
		RowLayout {
			spacing: mainItem.spacing
			ButtonImage{
				Layout.preferredWidth: mainItem.icon.width
				Layout.preferredHeight: mainItem.icon.height
			}
			ButtonText{}
		}
		ButtonText {}
		ButtonImage{}
		Item {
			Layout.fillWidth: true
			Layout.fillHeight: true
		}
	}*/
}
