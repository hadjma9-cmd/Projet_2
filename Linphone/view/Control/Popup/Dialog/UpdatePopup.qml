import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Mise à jour obligatoire de Gamaphone. La fenêtre s'ouvre dès que le serveur propose un installeur plus récent et ne se
// ferme pas tant qu'il n'est pas installé : ni clic à côté, ni Échap, pas de « plus tard ». Seul un échec (téléchargement
// impossible, installation refusée) laisse continuer avec la version actuelle, pour que personne ne reste sans
// téléphone ; la mise à jour est alors redemandée au lancement suivant.
Popup {
	id: mainItem
	// Étape en cours, voir UpdateCore : idle, available, downloading, launching, failed.
	readonly property string step: UpdateCpp.state
	readonly property bool compactWindow: AppCpp.compactMode

	parent: Control.Overlay.overlay
	anchors.centerIn: parent
	modal: true
	closePolicy: Control.Popup.NoAutoClose
	visible: step !== "idle"
	width: Utils.getSizeWithScreenRatio(compactWindow ? 320 : 380)
	padding: Utils.getSizeWithScreenRatio(compactWindow ? 18 : 24)
	underlineColor: "transparent"
	radius: Utils.getSizeWithScreenRatio(14)
	shadowBlur: 0.7
	shadowOpacity: 0.22
	shadowVerticalOffset: Utils.getSizeWithScreenRatio(4)

	contentItem: ColumnLayout {
		spacing: Utils.getSizeWithScreenRatio(14)

		Text {
			Layout.fillWidth: true
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.Wrap
			color: DefaultStyle.main2_700
			font: Typography.h4
			text: mainItem.step === "downloading" ? "Téléchargement en cours"
				: mainItem.step === "launching" ? "Installation"
				: mainItem.step === "failed" ? "Mise à jour impossible"
				: "Nouvelle version disponible"
		}
		Text {
			Layout.fillWidth: true
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.Wrap
			color: DefaultStyle.main2_600
			font: Typography.p1
			text: mainItem.step === "downloading" ? "%1 Mo sur %2 Mo".arg(UpdateCpp.receivedMb).arg(UpdateCpp.totalMb)
				: mainItem.step === "launching" ? "L'installeur démarre, Gamaphone va se fermer."
				: mainItem.step === "failed" ? UpdateCpp.errorText
				: "Cette mise à jour est nécessaire pour continuer. Gamaphone se fermera le temps de l'installation."
		}

		// Avancement du téléchargement.
		Rectangle {
			visible: mainItem.step === "downloading"
			Layout.fillWidth: true
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(8)
			radius: height / 2
			color: DefaultStyle.grey_200
			Rectangle {
				width: parent.width * UpdateCpp.progress
				height: parent.height
				radius: height / 2
				color: DefaultStyle.main1_500_main
			}
		}
		Text {
			visible: mainItem.step === "downloading"
			Layout.fillWidth: true
			horizontalAlignment: Text.AlignHCenter
			color: DefaultStyle.main2_500_main
			font: Typography.p1
			text: "%1 %".arg(Math.round(UpdateCpp.progress * 100))
		}

		// Boutons l'un sous l'autre, sur toute la largeur : même disposition en grande fenêtre et en Combiné.
		ColumnLayout {
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(4)
			spacing: Utils.getSizeWithScreenRatio(8)
			visible: mainItem.step !== "launching"
			MediumButton {
				visible: mainItem.step === "available" || mainItem.step === "failed"
				Layout.fillWidth: true
				text: mainItem.step === "failed" ? "Réessayer" : "Mettre à jour"
				style: ButtonStyle.main
				onClicked: UpdateCpp.start()
			}
			MediumButton {
				visible: mainItem.step === "downloading"
				Layout.fillWidth: true
				text: "Annuler"
				style: ButtonStyle.secondary
				onClicked: UpdateCpp.cancel()
			}
			MediumButton {
				visible: mainItem.step === "failed"
				Layout.fillWidth: true
				text: "Continuer sans mettre à jour"
				style: ButtonStyle.secondary
				onClicked: UpdateCpp.dismiss()
			}
		}
	}
}
