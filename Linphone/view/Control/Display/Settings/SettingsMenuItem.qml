import QtQuick
import QtQuick.Controls.Basic as Control
import QtQuick.Layouts
import QtQuick.Effects
import Linphone
import CustomControls 1.0
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

// Entree de la liste des rubriques (Parametres, Mon compte) : icone et nom, sur fond arrondi quand elle est choisie.
Item {
	id: mainItem
    height: visible ? Utils.getSizeWithScreenRatio(44) : 0
	anchors.right: parent.right
	anchors.left: parent.left
	property bool keyboardOtherFocus: FocusHelper.keyboardFocus || FocusHelper.otherFocus

	property string titleText
	property string iconSource
	property bool isSelected: false

	signal selected()

	//: %1 settings
	Accessible.name: qsTr("setting_tab_accessible_name").arg(titleText)
	Accessible.role: Accessible.ListItem

	Keys.onPressed: (event)=>{
		if(event.key == Qt.Key_Space || event.key == Qt.Key_Return || event.key == Qt.Key_Enter){
			mainItem.selected()
		}
	}
	MouseArea {
		id: mouseArea
		hoverEnabled: true
		anchors.fill: parent
		cursorShape: Qt.PointingHandCursor
		Rectangle {
			id: background
			anchors.fill: parent
			color: mainItem.isSelected ? DefaultStyle.main2_200 : parent.containsMouse ? DefaultStyle.main2_100 : "transparent"
			radius: Utils.getSizeWithScreenRatio(10)
			visible: parent.containsMouse || mainItem.isSelected || mainItem.keyboardOtherFocus
			border.color: DefaultStyle.main2_900
			border.width: mainItem.keyboardOtherFocus ? Utils.getSizeWithScreenRatio(3) : 0
		}
		onClicked: {
			mainItem.selected()
		}
	}
	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: Utils.getSizeWithScreenRatio(14)
		anchors.rightMargin: Utils.getSizeWithScreenRatio(14)
		spacing: Utils.getSizeWithScreenRatio(12)
		EffectImage {
			visible: mainItem.iconSource.length > 0
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(20)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(20)
			imageSource: mainItem.iconSource
			colorizationColor: mainItem.isSelected ? DefaultStyle.main1_500_main : DefaultStyle.main2_600
		}
		Text {
			Layout.fillWidth: true
			text: mainItem.titleText
			font.pixelSize: Utils.getSizeWithScreenRatio(14)
			font.weight: mainItem.isSelected ? Font.DemiBold : Font.Normal
			color: DefaultStyle.main2_700
			elide: Text.ElideRight
		}
	}
}
