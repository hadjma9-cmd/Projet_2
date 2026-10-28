import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

AbstractMainPage {

	id: mainItem
	showDefaultItem: false

	property var layoutsPath
	property var titleText

	signal goBack()
	signal goBackRequested()

	function layoutUrl(name) {
		return layoutsPath+"/"+name+".qml"
	}

	property var families
	property var defaultIndex: -1
	// Sous le titre, avant la liste : contenu propre a la page (la carte d'identite de Mon compte).
	property Component leftHeaderComponent
	leftPanelWidth: Utils.getSizeWithScreenRatio(340)

	function openFamily(family) {
		rightPanelStackView.clear()
		rightPanelStackView.push(layoutUrl(family.layout), { titleText: family.title, model: family.model, container: rightPanelStackView})
	}

	leftPanelContent: ColumnLayout {
		id: leftPanel
		Layout.fillWidth: true
		Layout.fillHeight: true
        property real sideMargin: Utils.getSizeWithScreenRatio(24)
        spacing: Utils.getSizeWithScreenRatio(5)
		RowLayout {
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(14)
			Layout.leftMargin: leftPanel.sideMargin
			Layout.rightMargin: leftPanel.sideMargin
            spacing: Utils.getSizeWithScreenRatio(6)
			Button {
				id: backButton
				icon.width: Utils.getSizeWithScreenRatio(24)
				icon.height: Utils.getSizeWithScreenRatio(24)
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(30)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(30)
				icon.source: AppIcons.leftArrow
				style: ButtonStyle.noBackground
				focus: true
				onClicked: {
					mainItem.goBackRequested()
				}
				//: Back to previous menu
				Accessible.name: qsTr("back_previous_menu_accessible_name")
			}
			Text {
				Layout.fillWidth: true
				text: titleText
				color: DefaultStyle.main2_700
				font: Typography.h2
				elide: Text.ElideRight
			}
		}

		Loader {
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(20)
			Layout.leftMargin: leftPanel.sideMargin
			Layout.rightMargin: leftPanel.sideMargin
			active: !!mainItem.leftHeaderComponent
			visible: active
			sourceComponent: mainItem.leftHeaderComponent
		}
		ListView {
			id: familiesList
			// Un seul onglet visible (Mon compte sans les menus techniques) : pas de liste.
			visible: mainItem.families.filter(function (family) {
				return family.visible === undefined || family.visible
			}).length > 1
			Layout.fillWidth: true
			Layout.fillHeight: true
			model: mainItem.families
            Layout.topMargin: Utils.getSizeWithScreenRatio(24)
			Layout.leftMargin: leftPanel.sideMargin
			Layout.rightMargin: leftPanel.sideMargin
			property int selectedIndex: mainItem.defaultIndex != -1 ? mainItem.defaultIndex : 0
			activeFocusOnTab: true
			spacing: Utils.getSizeWithScreenRatio(4)
			Accessible.role: Accessible.List
			//: Settings page selection
			Accessible.name: qsTr("settings_page_selection_accessible_name")
			keyNavigationEnabled: false

			delegate: SettingsMenuItem {
				titleText: modelData.title
				iconSource: modelData.icon || ""
				visible: modelData.visible != undefined ? modelData.visible : true
				enabled: visible
				isSelected: familiesList.selectedIndex == index
				focus: index == 0
				focusPolicy: visible ? Qt.StrongFocus : Qt.NoFocus
				onSelected: {
					familiesList.selectedIndex = index
					mainItem.openFamily(modelData)
				}
			}
		}
		// Sans liste : le haut de la colonne reste en haut (sinon la colonne le centre verticalement).
		Item {
			visible: !familiesList.visible
			Layout.fillHeight: true
		}
		Component.onCompleted: {
			mainItem.openFamily(mainItem.families[familiesList.selectedIndex])
			familiesList.currentIndex = familiesList.selectedIndex
		}
	}
	Control.StackView.onActivated: {
	    familiesList.forceActiveFocus(FocusNavigator.doesLastFocusWasKeyboard() ? Qt.TabFocusReason : Qt.MouseFocusReason)
    }
}
