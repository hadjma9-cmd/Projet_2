import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Linphone
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

// Files d'attente du Centre d'appels, menu du casque : un interrupteur par file (activee = le poste recoit ses appels).
// L'interrupteur ne change qu'une fois le serveur d'accord ; il palit en attendant sa reponse. Memes lignes que les
// statuts du menu de la photo (hauteur, marges, survol).
ColumnLayout {
	id: mainItem
	spacing: 0

	readonly property bool available: QueuesCpp.agentStatus === "Available"
		|| QueuesCpp.agentStatus === "Available (On Demand)"
	readonly property real rowPadding: Utils.getSizeWithScreenRatio(10)
	// Titre « Files d'attente » et compte des files activees (cache dans Mon compte, ou la rubrique a deja son titre).
	property bool headerVisible: true

	RowLayout {
		visible: mainItem.headerVisible
		Layout.fillWidth: true
		Layout.leftMargin: mainItem.rowPadding
		Layout.rightMargin: mainItem.rowPadding
		Layout.bottomMargin: Utils.getSizeWithScreenRatio(4)
		Text {
			Layout.fillWidth: true
			text: "Files d'attente"
			font.pixelSize: Utils.getSizeWithScreenRatio(13)
			font.weight: Font.DemiBold
			color: DefaultStyle.main2_800
		}
		Text {
			text: QueuesCpp.connectedCount + " sur " + QueuesCpp.queueCount
			font.pixelSize: Utils.getSizeWithScreenRatio(12)
			color: DefaultStyle.main2_500_main
		}
	}
	// En pause ou deconnecte du Centre d'appels (par *22, un administrateur ou Ne pas deranger) : inscrit aux files
	// mais sans appel. Activer une file remet disponible.
	Text {
		visible: QueuesCpp.agentStatus.length > 0 && !mainItem.available
		Layout.fillWidth: true
		Layout.leftMargin: mainItem.rowPadding
		Layout.rightMargin: mainItem.rowPadding
		Layout.bottomMargin: Utils.getSizeWithScreenRatio(4)
		text: QueuesCpp.agentStatus === "On Break" ? "En pause : aucun appel des files" : "Déconnecté : aucun appel des files"
		font.pixelSize: Utils.getSizeWithScreenRatio(12)
		color: DefaultStyle.warning_700
		wrapMode: Text.WordWrap
	}
	Repeater {
		model: QueuesCpp.queues
		delegate: Rectangle {
			id: queueRow
			required property var modelData
			readonly property bool pending: QueuesCpp.pendingQueues.indexOf(modelData.id) !== -1
			Layout.fillWidth: true
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(36)
			radius: Utils.getSizeWithScreenRatio(8)
			color: rowArea.containsMouse ? DefaultStyle.main2_100 : "transparent"

			RowLayout {
				anchors.fill: parent
				anchors.leftMargin: mainItem.rowPadding
				anchors.rightMargin: mainItem.rowPadding
				spacing: Utils.getSizeWithScreenRatio(6)
				Text {
					Layout.maximumWidth: parent.width - toggle.width - numberText.implicitWidth - 2 * parent.spacing
					text: queueRow.modelData.name
					font.pixelSize: Utils.getSizeWithScreenRatio(14)
					color: DefaultStyle.main2_800
					elide: Text.ElideRight
				}
				Text {
					id: numberText
					text: queueRow.modelData.number
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
					color: DefaultStyle.main2_400
				}
				Item {
					Layout.fillWidth: true
				}
				Rectangle {
					id: toggle
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(36)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(20)
					radius: height / 2
					color: queueRow.modelData.connected ? DefaultStyle.main1_500_main : DefaultStyle.main2_300
					opacity: queueRow.pending ? 0.5 : 1
					Rectangle {
						readonly property real inset: Utils.getSizeWithScreenRatio(2)
						width: parent.height - 2 * inset
						height: width
						radius: width / 2
						y: inset
						x: queueRow.modelData.connected ? parent.width - width - inset : inset
						color: DefaultStyle.grey_0
					}
				}
			}
			// Toute la ligne est cliquable, pas seulement l'interrupteur.
			MouseArea {
				id: rowArea
				anchors.fill: parent
				hoverEnabled: true
				enabled: !queueRow.pending
				cursorShape: Qt.PointingHandCursor
				onClicked: QueuesCpp.setQueueConnected(queueRow.modelData.id, !queueRow.modelData.connected)
			}
			Accessible.role: Accessible.CheckBox
			Accessible.name: "File " + modelData.name
			Accessible.checked: modelData.connected
		}
	}
	Text {
		visible: QueuesCpp.errorText.length > 0
		Layout.fillWidth: true
		Layout.leftMargin: mainItem.rowPadding
		Layout.rightMargin: mainItem.rowPadding
		Layout.topMargin: Utils.getSizeWithScreenRatio(4)
		text: QueuesCpp.errorText
		font.pixelSize: Utils.getSizeWithScreenRatio(12)
		color: DefaultStyle.danger_500_main
		wrapMode: Text.WordWrap
	}
}
