
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

// Page de reglages : titre en haut, puis les rubriques l'une sous l'autre (titre gris, phrase d'explication, contenu
// dans une carte), le tout dans une colonne centree de largeur limitee : la page reste lisible et equilibree quelle que
// soit la largeur de la fenetre. Rubrique « plain » : pas de carte, le contenu dessine la sienne.
Rectangle {
	id: mainItem
	width: container.width
	height: container.height
	property string titleText
	property var contentModel
	property var topbarOptionalComponent
	property var model
	color: DefaultStyle.grey_0
	property var container
	// Page seule (sans liste a gauche) : son bouton de retour. Sinon, retour dans la pile s'il y a une page avant.
	property var backAction: null
	// Largeur de la colonne centree.
	property real columnWidth: Utils.getSizeWithScreenRatio(700)
	readonly property real columnShownWidth: Math.max(0, Math.min(columnWidth, width - 2 * Utils.getSizeWithScreenRatio(32)))
	readonly property real columnX: Math.round((width - columnShownWidth) / 2)
	property bool saveButtonVisible: true
	property alias saveButton: saveButton
	signal save()
	signal undo()

	Item {
		id: header
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		height: headerRow.implicitHeight + Utils.getSizeWithScreenRatio(24 + 16)
		z: 1
		Rectangle {
			anchors.fill: parent
			color: DefaultStyle.grey_0
		}
		RowLayout {
			id: headerRow
			x: mainItem.columnX
			y: Utils.getSizeWithScreenRatio(24)
			width: mainItem.columnShownWidth
			spacing: Utils.getSizeWithScreenRatio(6)
			Button {
				id: backButton
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(30)
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(30)
				Layout.leftMargin: -Utils.getSizeWithScreenRatio(6)
				icon.source: AppIcons.leftArrow
				icon.width: Utils.getSizeWithScreenRatio(24)
				icon.height: Utils.getSizeWithScreenRatio(24)
				focus: true
				visible: !!mainItem.backAction || (!!mainItem.container && mainItem.container.depth > 1)
				style: ButtonStyle.noBackground
				onClicked: {
					if (mainItem.backAction)
						mainItem.backAction()
					else
						mainItem.container.pop()
				}
				//: Return
				Accessible.name: qsTr("return_accessible_name")
			}
			Text {
				Layout.fillWidth: true
				text: titleText
				color: DefaultStyle.main2_700
				// Titre de la page entiere (page seule) un cran plus grand que celui d'une rubrique des parametres.
				font: mainItem.backAction ? Typography.h2 : Typography.h3
				elide: Text.ElideRight
			}
			Loader {
				Layout.alignment: Qt.AlignRight
				sourceComponent: mainItem.topbarOptionalComponent
				Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
			}
			MediumButton {
				id: saveButton
				style: ButtonStyle.main
				//: "Enregistrer"
				text: qsTr("save")
				visible: mainItem.saveButtonVisible
				//: Save %1 settings
				Accessible.name: qsTr("save_settings_accessible_name").arg(mainItem.titleText)
				onClicked: {
					mainItem.save()
				}
			}
		}
		// Trait sous le titre seulement quand le contenu defile dessous.
		Rectangle {
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.bottom: parent.bottom
			height: Utils.getSizeWithScreenRatio(1)
			color: DefaultStyle.main2_200
			visible: verticalBar.position > 0
		}
	}
	Control.ScrollView {
		id: scrollView
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.top: header.bottom
		contentWidth: availableWidth
		contentHeight: content.implicitHeight + Utils.getSizeWithScreenRatio(40)
		Control.ScrollBar.vertical: ScrollBar {
			id: verticalBar
			active: scrollView.contentHeight > scrollView.height
			visible: scrollView.contentHeight > scrollView.height
			interactive: true
			policy: Control.ScrollBar.AsNeeded
			anchors.top: parent.top
			anchors.bottom: parent.bottom
			anchors.right: parent.right
			anchors.rightMargin: Utils.getSizeWithScreenRatio(15)
		}
		Control.ScrollBar.horizontal: ScrollBar {
			active: false
		}
		ColumnLayout {
			id: content
			x: mainItem.columnX
			y: Utils.getSizeWithScreenRatio(4)
			width: mainItem.columnShownWidth
			spacing: Utils.getSizeWithScreenRatio(24)
			Repeater {
				model: mainItem.contentModel
				delegate: ColumnLayout {
					id: section
					// « isVisible » : fonction relue a l'affichage (la page n'est pas reconstruite quand elle change). Une
					// rubrique masquee ne cree pas son contenu.
					readonly property bool shown: modelData.isVisible ? modelData.isVisible()
						: modelData.visible === undefined || modelData.visible
					visible: shown
					Layout.fillWidth: true
					spacing: Utils.getSizeWithScreenRatio(8)
					Text {
						visible: text.length > 0
						Layout.fillWidth: true
						text: modelData.title || ""
						font.pixelSize: Utils.getSizeWithScreenRatio(13)
						font.weight: Font.DemiBold
						color: DefaultStyle.main2_600
						wrapMode: Text.WordWrap
					}
					Text {
						visible: text.length > 0
						Layout.fillWidth: true
						Layout.topMargin: -Utils.getSizeWithScreenRatio(4)
						text: modelData.subTitle || ""
						font.pixelSize: Utils.getSizeWithScreenRatio(12)
						color: DefaultStyle.main2_500_main
						wrapMode: Text.WordWrap
					}
					Rectangle {
						visible: !modelData.plain
						Layout.fillWidth: true
						Layout.preferredHeight: cardContent.implicitHeight + 2 * cardContent.y
						radius: Utils.getSizeWithScreenRatio(14)
						color: DefaultStyle.main2_100
						ColumnLayout {
							id: cardContent
							x: Utils.getSizeWithScreenRatio(20)
							y: Utils.getSizeWithScreenRatio(18)
							width: parent.width - 2 * x
							Loader {
								Layout.fillWidth: true
								active: section.shown && !modelData.plain
								sourceComponent: modelData.contentComponent
							}
						}
					}
					Loader {
						visible: !!modelData.plain
						Layout.fillWidth: true
						active: section.shown && !!modelData.plain
						sourceComponent: modelData.contentComponent
					}
				}
			}
		}

		Connections {
			target: FocusNavigator

			function onFocusChanged(item, keyboardFocus) {
				if(Utils.isDescendant(item,scrollView) && keyboardFocus){
					Utils.ensureVisibleY(item, scrollView)
				}
			}
		}
	}
}
