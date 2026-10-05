import QtQuick
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Bouton rond des appels (fond bleu nuit) : icone blanche, nom en dessous en appel audio, ou au survol dans la barre
// translucide de la video, ou l'icone survolee grossit. Allume en bleu Gama quand il est actif (micro coupe, son
// coupe, attente...), rouge pour raccrocher ou refuser, vert pour repondre.
Item {
	id: mainItem
	property url iconSource
	property string label
	property string toolTipText: label
	property bool active: false
	property bool danger: false
	property bool success: false
	// Barre video translucide : fond clair transparent, nom au survol seulement, icone qui grossit au survol.
	property bool translucent: false
	property bool showLabel: !translucent
	property real size: Utils.getSizeWithScreenRatio(translucent ? 44 : 52)
	readonly property bool hovered: buttonArea.containsMouse
	signal clicked()

	implicitWidth: Math.max(circle.width, labelText.visible ? labelText.implicitWidth : 0)
	implicitHeight: circle.height + (labelText.visible ? labelText.implicitHeight + Utils.getSizeWithScreenRatio(6) : 0)
	z: hovered ? 1 : 0
	opacity: enabled ? 1 : 0.45
	activeFocusOnTab: visible && enabled
	Accessible.role: Accessible.Button
	Accessible.name: mainItem.toolTipText
	Keys.onPressed: event => {
		if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			mainItem.clicked()
			event.accepted = true
		}
	}

	Rectangle {
		id: circle
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.top: parent.top
		width: mainItem.danger || mainItem.success ? Math.round(mainItem.size * 1.4) : mainItem.size
		height: mainItem.size
		radius: height / 2
		color: mainItem.danger
			? (buttonArea.pressed ? DefaultStyle.danger_700
				: mainItem.hovered ? Qt.darker(DefaultStyle.danger_500_main, 1.1) : DefaultStyle.danger_500_main)
			: mainItem.success
				? (buttonArea.pressed ? DefaultStyle.success_700
					: mainItem.hovered ? Qt.darker(DefaultStyle.success_500_main, 1.1) : DefaultStyle.success_500_main)
				: mainItem.active
					? (mainItem.hovered ? Qt.lighter(DefaultStyle.main1_button, 1.15) : DefaultStyle.main1_button)
					: mainItem.translucent
						? Qt.rgba(1, 1, 1, mainItem.hovered ? 0.2 : 0.1)
						: (mainItem.hovered ? DefaultStyle.callButtonHovered : DefaultStyle.callButton)
		border.width: mainItem.activeFocus ? Utils.getSizeWithScreenRatio(2) : 0
		border.color: DefaultStyle.grey_0
		scale: mainItem.translucent && mainItem.hovered ? 1.35 : 1
		Behavior on scale {
			NumberAnimation {
				duration: 140
				easing.type: Easing.OutQuad
			}
		}
		EffectImage {
			anchors.centerIn: parent
			width: Math.round(mainItem.size * 0.48)
			height: width
			imageSource: mainItem.iconSource
			colorizationColor: DefaultStyle.grey_0
		}
	}
	Text {
		id: labelText
		visible: mainItem.showLabel && mainItem.label.length > 0
		anchors.top: circle.bottom
		anchors.topMargin: Utils.getSizeWithScreenRatio(6)
		anchors.horizontalCenter: parent.horizontalCenter
		text: mainItem.label
		color: DefaultStyle.main2_300
		font {
			pixelSize: Utils.getSizeWithScreenRatio(12)
			weight: Typography.p2.weight
		}
	}
	MouseArea {
		id: buttonArea
		anchors.fill: circle
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: mainItem.clicked()
	}
	ToolTip {
		text: mainItem.toolTipText
		visible: mainItem.hovered && !labelText.visible && text.length > 0
		delay: 300
	}
}
