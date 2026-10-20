import QtQuick
import QtQuick.Layouts
import Linphone
import UtilsCpp
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Menu du statut, le meme dans les deux fenetres : en-tete facultatif (photo, nom, poste), statuts et message de
// statut ; l'ecriture du message prend la place des statuts. Les lignes propres a un menu (Messagerie vocale, Mon
// compte) se placent dessous, dans « extra ».
// Largeur fixe (menuWidth) portee par un simple Item : sur une mise en page (ColumnLayout), la largeur donnee etait
// recalculee d'apres le contenu et le menu se repliait (textes coupes sur plusieurs lignes).
Item {
	id: mainItem
	property var accountGui
	property bool showHeader: false
	property bool editing: false
	property real menuWidth: Utils.getSizeWithScreenRatio(270)
	property alias extra: extraLayout.data
	// Statut choisi ou message enregistre : le menu peut se fermer.
	signal done

	implicitWidth: menuWidth
	implicitHeight: column.implicitHeight
	onVisibleChanged: if (!visible) editing = false

	ColumnLayout {
		id: column
		width: parent.width
		spacing: 0

		RowLayout {
			visible: mainItem.showHeader && !mainItem.editing
			Layout.fillWidth: true
			Layout.leftMargin: Utils.getSizeWithScreenRatio(6)
			spacing: Utils.getSizeWithScreenRatio(12)
			Avatar {
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(40)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(40)
				account: mainItem.accountGui
				shadowEnabled: false
				displayPresence: false
			}
			ColumnLayout {
				Layout.fillWidth: true
				spacing: 0
				Text {
					Layout.fillWidth: true
					text: mainItem.accountGui ? mainItem.accountGui.core.displayName : ""
					font.pixelSize: Utils.getSizeWithScreenRatio(15)
					font.weight: Font.DemiBold
					color: DefaultStyle.main2_800
					elide: Text.ElideRight
				}
				Text {
					Layout.fillWidth: true
					text: mainItem.accountGui ? "Poste " + UtilsCpp.getUsername(mainItem.accountGui.core.identityAddress) : ""
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
					color: DefaultStyle.main2_500_main
					elide: Text.ElideRight
				}
			}
		}
		Rectangle {
			visible: mainItem.showHeader && !mainItem.editing
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(10)
			Layout.bottomMargin: Utils.getSizeWithScreenRatio(10)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
			color: DefaultStyle.main2_200
		}
		Presence {
			visible: !mainItem.editing
			Layout.fillWidth: true
			accountGui: mainItem.accountGui
			onSetCustomStatusClicked: mainItem.editing = true
			onIsSet: mainItem.done()
		}
		PresenceSetCustomStatus {
			visible: mainItem.editing
			Layout.fillWidth: true
			accountGui: mainItem.accountGui
			onCanceled: mainItem.editing = false
			onIsSet: {
				mainItem.editing = false
				mainItem.done()
			}
		}
		// Lignes propres au menu, sous un trait.
		Rectangle {
			visible: extraLayout.visible
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(10)
			Layout.bottomMargin: Utils.getSizeWithScreenRatio(10)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
			color: DefaultStyle.main2_200
		}
		ColumnLayout {
			id: extraLayout
			visible: !mainItem.editing && children.length > 0
			Layout.fillWidth: true
			spacing: Utils.getSizeWithScreenRatio(2)
		}
	}
}
