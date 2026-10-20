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
// Même dessin que les fenêtres de décision (Dialog.qml) : rond et icône en haut, titre et texte centrés, mêmes mesures.
Popup {
	id: mainItem
	// Étape en cours, voir UpdateCore : idle, available, downloading, launching, failed.
	readonly property string step: UpdateCpp.state
	readonly property bool compactWindow: AppCpp.compactMode
	readonly property bool failed: step === "failed"
	function evenSize(value) {
		return 2 * Math.round(Utils.getSizeWithScreenRatio(value) / 2)
	}

	parent: Control.Overlay.overlay
	modal: true
	closePolicy: Control.Popup.NoAutoClose
	visible: step !== "idle"
	width: Math.min(evenSize(compactWindow ? 330 : 380), 2 * Math.floor(((parent ? parent.width : 380) - evenSize(32)) / 2))
	x: parent ? Math.round((parent.width - width) / 2) : 0
	y: parent ? Math.round((parent.height - height) / 2) : 0
	padding: evenSize(compactWindow ? 20 : 24)
	underlineColor: "transparent"
	radius: Utils.getSizeWithScreenRatio(16)
	shadowBlur: 0.7
	shadowOpacity: 0.22
	shadowVerticalOffset: Utils.getSizeWithScreenRatio(4)

	contentItem: ColumnLayout {
		spacing: 0

		// Bleu pendant la mise à jour, orange si elle a échoué.
		Rectangle {
			Layout.alignment: Qt.AlignHCenter
			Layout.bottomMargin: mainItem.evenSize(mainItem.compactWindow ? 14 : 16)
			Layout.preferredWidth: mainItem.evenSize(mainItem.compactWindow ? 46 : 52)
			Layout.preferredHeight: Layout.preferredWidth
			radius: width / 2
			color: mainItem.failed ? "#FCEBD8" : DefaultStyle.main1_100
			EffectImage {
				readonly property real side: mainItem.evenSize(mainItem.compactWindow ? 22 : 26)
				x: (parent.width - side) / 2
				y: (parent.height - side) / 2
				width: side
				height: side
				imageSource: mainItem.failed ? AppIcons.warningCircle : AppIcons.download
				colorizationColor: mainItem.failed ? "#D97A1E" : DefaultStyle.main1_500_main
			}
		}
		Text {
			Layout.fillWidth: true
			Layout.bottomMargin: mainItem.evenSize(8)
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.Wrap
			color: DefaultStyle.main2_800
			font {
				pixelSize: Utils.getSizeWithScreenRatio(mainItem.compactWindow ? 16 : 18)
				weight: Typography.h3.weight
			}
			text: mainItem.step === "downloading" ? "Téléchargement en cours"
				: mainItem.step === "launching" ? "Installation"
				: mainItem.failed ? "Mise à jour impossible"
				: "Nouvelle version disponible"
		}
		Text {
			Layout.fillWidth: true
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.Wrap
			color: DefaultStyle.main2_600
			lineHeight: 1.15
			font {
				pixelSize: Utils.getSizeWithScreenRatio(mainItem.compactWindow ? 13 : 14)
				weight: Typography.p1.weight
			}
			text: mainItem.step === "downloading" ? "%1 Mo sur %2 Mo".arg(UpdateCpp.receivedMb).arg(UpdateCpp.totalMb)
				: mainItem.step === "launching" ? "Gamaphone se ferme, s'installe puis redémarre tout seul."
				: mainItem.failed ? UpdateCpp.errorText
				: "Cette mise à jour est nécessaire pour continuer. Gamaphone se fermera le temps de l'installation, puis redémarrera tout seul."
		}

		// Avancement du téléchargement.
		Rectangle {
			visible: mainItem.step === "downloading"
			Layout.fillWidth: true
			Layout.topMargin: mainItem.evenSize(16)
			Layout.preferredHeight: mainItem.evenSize(8)
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
			Layout.topMargin: mainItem.evenSize(8)
			horizontalAlignment: Text.AlignHCenter
			color: DefaultStyle.main2_500_main
			font {
				pixelSize: Utils.getSizeWithScreenRatio(mainItem.compactWindow ? 12 : 13)
				weight: Typography.p1.weight
			}
			text: "%1 %".arg(Math.round(UpdateCpp.progress * 100))
		}

		// Boutons l'un sous l'autre, sur toute la largeur : même disposition en grande fenêtre et en Combiné.
		ColumnLayout {
			Layout.fillWidth: true
			Layout.topMargin: mainItem.evenSize(mainItem.compactWindow ? 20 : 24)
			spacing: mainItem.evenSize(10)
			visible: mainItem.step !== "launching"
			DialogButton {
				visible: mainItem.step === "available" || mainItem.failed
				text: mainItem.failed ? "Réessayer" : "Mettre à jour"
				style: ButtonStyle.main
				onClicked: UpdateCpp.start()
			}
			DialogButton {
				visible: mainItem.step === "downloading"
				text: "Annuler"
				style: ButtonStyle.secondary
				onClicked: UpdateCpp.cancel()
			}
			DialogButton {
				visible: mainItem.failed
				text: "Continuer sans mettre à jour"
				style: ButtonStyle.secondary
				onClicked: UpdateCpp.dismiss()
			}
		}
	}
}
