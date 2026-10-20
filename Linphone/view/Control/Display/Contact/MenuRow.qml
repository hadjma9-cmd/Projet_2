import QtQuick
import QtQuick.Layouts
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Ligne de menu (statut, profil) : icone, texte, nombre facultatif a droite (messages en attente). Bleue pour une
// action (« Ajouter un message de statut »), sombre pour une entree ordinaire (« Mon compte »).
Rectangle {
	id: mainItem
	property url iconSource
	property string text
	property int count: 0
	property bool accent: false
	signal clicked

	Layout.fillWidth: true
	Layout.preferredHeight: Utils.getSizeWithScreenRatio(36)
	radius: Utils.getSizeWithScreenRatio(8)
	color: rowArea.containsMouse ? DefaultStyle.main2_100 : "transparent"
	border.width: activeFocus ? Utils.getSizeWithScreenRatio(2) : 0
	border.color: DefaultStyle.main1_500_main
	activeFocusOnTab: true
	Accessible.role: Accessible.Button
	Accessible.name: text
	Keys.onPressed: event => {
		if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			mainItem.clicked()
			event.accepted = true
		}
	}
	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: Utils.getSizeWithScreenRatio(10)
		anchors.rightMargin: Utils.getSizeWithScreenRatio(10)
		spacing: Utils.getSizeWithScreenRatio(10)
		EffectImage {
			readonly property real side: Utils.getSizeWithScreenRatio(mainItem.accent ? 16 : 18)
			Layout.preferredWidth: side
			Layout.preferredHeight: side
			imageSource: mainItem.iconSource
			colorizationColor: mainItem.accent ? DefaultStyle.main1_500_main : DefaultStyle.main2_600
		}
		Text {
			Layout.fillWidth: true
			text: mainItem.text
			font.pixelSize: Utils.getSizeWithScreenRatio(14)
			color: mainItem.accent ? DefaultStyle.main1_500_main : DefaultStyle.main2_800
			elide: Text.ElideRight
		}
		Rectangle {
			visible: mainItem.count > 0
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(18)
			Layout.preferredWidth: Math.max(height, countText.implicitWidth + Utils.getSizeWithScreenRatio(10))
			radius: height / 2
			color: DefaultStyle.danger_500_main
			Text {
				id: countText
				anchors.centerIn: parent
				text: mainItem.count > 99 ? "99+" : mainItem.count
				font.pixelSize: Utils.getSizeWithScreenRatio(11)
				font.weight: Font.DemiBold
				color: DefaultStyle.grey_0
			}
		}
	}
	MouseArea {
		id: rowArea
		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: mainItem.clicked()
	}
}
