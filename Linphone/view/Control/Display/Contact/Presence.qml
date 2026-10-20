import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

// Choix du statut et message de statut. Statuts en texte sombre avec leur pastille ; le statut actuel est surligne et
// coche. « Ne pas deranger » et « Hors ligne » mettent les files du poste en pause (voir StatusCore) : c'est rappele
// dessous, pour un agent.
ColumnLayout {
	id: mainItem

	property var accountGui
	signal setCustomStatusClicked
	signal isSet

	spacing: Utils.getSizeWithScreenRatio(2)
	readonly property real rowPadding: Utils.getSizeWithScreenRatio(10)
	readonly property bool queuesPaused: QueuesCpp.agent && QueuesCpp.queueCount > 0
	readonly property string presenceNote: accountGui ? accountGui.core.presenceNote : ""

	function choose(presence) {
		mainItem.accountGui.core.presence = presence
		mainItem.isSet()
	}

	component StatusRow: Rectangle {
		id: row
		property int presence
		property string subtitle
		readonly property bool current: !!mainItem.accountGui && mainItem.accountGui.core.presence === presence
		Layout.fillWidth: true
		Layout.preferredHeight: Utils.getSizeWithScreenRatio(subtitle.length > 0 ? 44 : 36)
		radius: Utils.getSizeWithScreenRatio(8)
		color: current ? DefaultStyle.main1_100 : rowArea.containsMouse ? DefaultStyle.main2_100 : "transparent"
		border.width: activeFocus ? Utils.getSizeWithScreenRatio(2) : 0
		border.color: DefaultStyle.main1_500_main
		activeFocusOnTab: true
		Accessible.role: Accessible.RadioButton
		Accessible.name: UtilsCpp.getPresenceStatus(presence)
		Accessible.checked: current
		Keys.onPressed: event => {
			if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
				mainItem.choose(row.presence)
				event.accepted = true
			}
		}
		RowLayout {
			anchors.fill: parent
			anchors.leftMargin: mainItem.rowPadding
			anchors.rightMargin: mainItem.rowPadding
			spacing: Utils.getSizeWithScreenRatio(10)
			Image {
				readonly property real side: Utils.getSizeWithScreenRatio(11)
				Layout.preferredWidth: side
				Layout.preferredHeight: side
				sourceSize.width: side
				sourceSize.height: side
				source: UtilsCpp.getPresenceIcon(row.presence)
			}
			ColumnLayout {
				Layout.fillWidth: true
				spacing: 0
				Text {
					Layout.fillWidth: true
					text: UtilsCpp.getPresenceStatus(row.presence)
					font.pixelSize: Utils.getSizeWithScreenRatio(14)
					color: DefaultStyle.main2_800
					elide: Text.ElideRight
				}
				Text {
					visible: row.subtitle.length > 0
					Layout.fillWidth: true
					text: row.subtitle
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
					color: DefaultStyle.main2_500_main
					elide: Text.ElideRight
				}
			}
			EffectImage {
				visible: row.current
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(16)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(16)
				imageSource: AppIcons.check
				colorizationColor: DefaultStyle.main1_500_main
			}
		}
		MouseArea {
			id: rowArea
			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: mainItem.choose(row.presence)
		}
	}

	StatusRow { presence: LinphoneEnums.Presence.Online }
	StatusRow { presence: LinphoneEnums.Presence.Away }
	StatusRow { presence: LinphoneEnums.Presence.Busy }
	StatusRow {
		presence: LinphoneEnums.Presence.DoNotDisturb
		subtitle: mainItem.queuesPaused ? "Files mises en pause" : ""
	}
	StatusRow {
		presence: LinphoneEnums.Presence.Offline
		subtitle: mainItem.queuesPaused ? "Files mises en pause" : ""
	}

	// Statut choisi a la main : retour au statut automatique.
	MenuRow {
		accent: true
		visible: !!mainItem.accountGui && mainItem.accountGui.core.explicitPresence != LinphoneEnums.Presence.Undefined
		iconSource: AppIcons.reloadArrow
		//: "Réinitialiser le statut"
		text: qsTr("contact_presence_reset_status")
		onClicked: mainItem.accountGui.core.resetToAutomaticPresence()
	}

	// Message de statut : une ligne pour l'ajouter ; une fois ecrit, le message avec Modifier et Supprimer.
	MenuRow {
		accent: true
		visible: mainItem.presenceNote.length === 0
		Layout.topMargin: Utils.getSizeWithScreenRatio(2)
		iconSource: AppIcons.pencil
		text: "Ajouter un message de statut"
		onClicked: mainItem.setCustomStatusClicked()
	}
	RowLayout {
		visible: mainItem.presenceNote.length > 0
		Layout.fillWidth: true
		Layout.topMargin: Utils.getSizeWithScreenRatio(4)
		Layout.leftMargin: mainItem.rowPadding
		spacing: Utils.getSizeWithScreenRatio(4)
		Text {
			Layout.fillWidth: true
			text: "« " + mainItem.presenceNote + " »"
			font.pixelSize: Utils.getSizeWithScreenRatio(13)
			font.italic: true
			color: DefaultStyle.main2_700
			wrapMode: Text.Wrap
			maximumLineCount: 3
			elide: Text.ElideRight
		}
		Button {
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(30)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(30)
			style: ButtonStyle.noBackground
			icon.source: AppIcons.pencil
			icon.width: Utils.getSizeWithScreenRatio(16)
			icon.height: Utils.getSizeWithScreenRatio(16)
			ToolTip.text: "Modifier le message"
			Accessible.name: "Modifier le message"
			onClicked: mainItem.setCustomStatusClicked()
		}
		Button {
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(30)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(30)
			style: ButtonStyle.noBackground
			icon.source: AppIcons.trashCan
			icon.width: Utils.getSizeWithScreenRatio(16)
			icon.height: Utils.getSizeWithScreenRatio(16)
			ToolTip.text: "Supprimer le message"
			Accessible.name: "Supprimer le message"
			onClicked: mainItem.accountGui.core.presenceNote = ""
		}
	}
}
