
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control

import Linphone
import SettingsCpp 1.0
import UtilsCpp 1.0
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Depannage, a droite de l'Aide : versions a donner au support, journaux (appliques tout de suite, sans bouton
// Enregistrer), puis l'assistance : appeler ou ecrire au support, ou lui envoyer les journaux.
AbstractSettingsLayout {
	Layout.fillWidth: true
	Layout.fillHeight: true
	id: mainItem
	saveButtonVisible: false
	contentModel: [
		{
			title: "Versions",
			subTitle: "",
			contentComponent: versionContent
		},
		{
			title: "Journaux",
			subTitle: "Activez-les, refaites ce qui ne va pas, puis envoyez-les au support (plus bas).",
			contentComponent: logContent
		},
		{
			title: "Assistance",
			subTitle: "",
			contentComponent: supportContent
		}
	]

	Dialog {
		id: deleteLogs
		kind: "danger"
		iconSource: AppIcons.trashCan
        //: "Les traces de débogage seront supprimées. Souhaitez-vous continuer ?"
        text: qsTr("settings_debug_clean_logs_message")
		onAccepted: SettingsCpp.cleanLogs()
	}

	// Une version par ligne, copiee d'un clic.
	component VersionRow: RowLayout {
		id: versionRow
		property string iconSource
		property string title
		property string value
		Layout.fillWidth: true
		spacing: Utils.getSizeWithScreenRatio(12)
		EffectImage {
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(22)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(22)
			imageSource: versionRow.iconSource
			colorizationColor: DefaultStyle.main1_500_main
		}
		Text {
			text: versionRow.title
			font.pixelSize: Utils.getSizeWithScreenRatio(14)
			font.weight: Font.DemiBold
			color: DefaultStyle.main2_800
		}
		Text {
			Layout.fillWidth: true
			text: versionRow.value
			font.pixelSize: Utils.getSizeWithScreenRatio(13)
			color: DefaultStyle.main2_500_main
			elide: Text.ElideRight
		}
		SmallButton {
			style: ButtonStyle.noBackground
			icon.source: AppIcons.copy
			text: copiedTimer.running ? "Copié" : "Copier"
			onClicked: {
				UtilsCpp.copyToClipboard(versionRow.value)
				copiedTimer.restart()
			}
			Timer {
				id: copiedTimer
				interval: 2000
			}
		}
	}

	Component {
		id: versionContent
		ColumnLayout {
			spacing: Utils.getSizeWithScreenRatio(10)
			VersionRow {
				iconSource: AppIcons.appWindow
				title: "Application"
				value: AppCpp.applicationVersion + " (" + AppCpp.gitBranchName + ")"
			}
			VersionRow {
				iconSource: AppIcons.resourcePackage
				title: "SDK"
				value: AppCpp.sdkVersion
			}
			VersionRow {
				iconSource: AppIcons.qtLogo
				title: "Qt"
				value: AppCpp.qtVersion
			}
		}
	}

	Component {
		id: logContent
		ColumnLayout {
            spacing: Utils.getSizeWithScreenRatio(16)
			SwitchSetting {
				Layout.fillWidth: true
                //: "Activer les traces de débogage"
                titleText: qsTr("settings_debug_enable_logs_title")
				propertyName: "logsEnabled"
				propertyOwner: SettingsCpp
				onToggled: SettingsCpp.save()
			}
			SwitchSetting {
				Layout.fillWidth: true
                //: "Activer les traces de débogage intégrales"
                titleText: qsTr("settings_debug_enable_full_logs_title")
				propertyName: "fullLogsEnabled"
				propertyOwner: SettingsCpp
				onToggled: SettingsCpp.save()
			}
			SmallButton {
				Layout.alignment: Qt.AlignRight
				style: ButtonStyle.noBackground
				icon.source: AppIcons.trashCan
                //: "Supprimer les traces"
                text: qsTr("settings_debug_delete_logs_title")
				onClicked: deleteLogs.open()
			}
		}
	}

	// Appeler ou ecrire au support, ou lui envoyer les journaux : ils partent vers le serveur du compte, qui previent
	// le support par e-mail (plus rien vers les serveurs de Linphone). Le resultat s'affiche a cote du bouton.
	Component {
		id: supportContent
		ColumnLayout {
			spacing: Utils.getSizeWithScreenRatio(14)
			Text {
				Layout.fillWidth: true
				text: "Un souci ? Appelez ou écrivez au support, ou envoyez-lui vos journaux : il les reçoit avec une référence à lui donner."
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				color: DefaultStyle.main2_600
				wrapMode: Text.WordWrap
			}
			Flow {
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(10)
				MediumButton {
					style: ButtonStyle.secondary
					icon.source: AppIcons.phone
					text: "Appeler le support · 05 61 83 28 32"
					onClicked: UtilsCpp.createCall("0561832832")
				}
				MediumButton {
					style: ButtonStyle.secondary
					icon.source: AppIcons.envelope
					text: "support@gama-it.fr"
					onClicked: Qt.openUrlExternally("mailto:support@gama-it.fr")
				}
			}
			RowLayout {
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(14)
				MediumButton {
					style: ButtonStyle.main
					icon.source: AppIcons.paperPlaneRight
					text: "Envoyer les journaux"
					enabled: (SettingsCpp.logsEnabled || SettingsCpp.fullLogsEnabled) && !SupportCpp.sending
					onClicked: {
						sendAnswer.text = ""
						UtilsCpp.getMainWindow().showLoadingPopup("Envoi des journaux au support…")
						SupportCpp.sendLogs()
					}
				}
				Text {
					visible: !SettingsCpp.logsEnabled && !SettingsCpp.fullLogsEnabled && sendAnswer.text.length === 0
					Layout.fillWidth: true
					text: "Activez d'abord les journaux, plus haut."
					wrapMode: Text.WordWrap
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
					color: DefaultStyle.main2_500_main
				}
				Text {
					id: sendAnswer
					property bool ok: true
					visible: text.length > 0
					Layout.fillWidth: true
					wrapMode: Text.WordWrap
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
					font.weight: Font.DemiBold
					color: ok ? "#2F7D4F" : "#8A4B0B"
				}
			}
			Connections {
				target: SupportCpp
				function onLogsSent(reference, emailed) {
					UtilsCpp.getMainWindow().closeLoadingPopup()
					sendAnswer.ok = true
					sendAnswer.text = emailed ? "Journaux envoyés au support (référence " + reference + ")."
						: "Journaux enregistrés sur le serveur (référence " + reference + ") : donnez cette référence au support."
				}
				function onLogsFailed(message) {
					UtilsCpp.getMainWindow().closeLoadingPopup()
					sendAnswer.ok = false
					sendAnswer.text = message + " Les journaux sont aussi dans le dossier : " + SettingsCpp.logsFolder
				}
			}
		}
	}
}
