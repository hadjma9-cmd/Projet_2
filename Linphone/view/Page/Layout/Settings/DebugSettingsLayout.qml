
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control

import Linphone
import SettingsCpp 1.0
import UtilsCpp 1.0
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

AbstractSettingsLayout {
	Layout.fillWidth: true
	Layout.fillHeight: true
	id: mainItem
	contentModel: [
		{
			title: "",
			subTitle: "",
			contentComponent: versionContent
		},
		{
			title: "",
			subTitle: "",
			contentComponent: logContent
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
	
	onSave: {
		SettingsCpp.save()
	}
	
	Component {
		id: logContent
		ColumnLayout {
            spacing: Utils.getSizeWithScreenRatio(20)
			SwitchSetting {
                //: "Activer les traces de débogage"
                titleText: qsTr("settings_debug_enable_logs_title")
				propertyName: "logsEnabled"
				propertyOwner: SettingsCpp
			}
			SwitchSetting {
                //: "Activer les traces de débogage intégrales"
                titleText: qsTr("settings_debug_enable_full_logs_title")
				propertyName: "fullLogsEnabled"
				propertyOwner: SettingsCpp
			}
			RowLayout {
                spacing: Utils.getSizeWithScreenRatio(20)
				Layout.alignment: Qt.AlignRight
				MediumButton {
					style: ButtonStyle.tertiary
                    //: "Supprimer les traces"
                    text: qsTr("settings_debug_delete_logs_title")
					onClicked: {
						deleteLogs.open()
					}
				}
				// Envoi au support : les journaux partent vers le serveur du compte, qui previent le support par
				// e-mail (plus rien vers les serveurs de Linphone).
				MediumButton {
					style: ButtonStyle.tertiary
					text: "Envoyer au support"
					enabled: (SettingsCpp.logsEnabled || SettingsCpp.fullLogsEnabled) && !SupportCpp.sending
					onClicked: {
						UtilsCpp.getMainWindow().showLoadingPopup("Envoi des journaux au support…")
						SupportCpp.sendLogs()
					}
				}
			}
		}
	}
	
	Component {
	id: versionContent
		ColumnLayout {
            spacing: Utils.getSizeWithScreenRatio(20)
			HelpIconLabelButton {
				enabled: false
				// Layout.preferredWidth: width
				// Layout.minimumWidth: width
				iconSize: Utils.getSizeWithScreenRatio(24)
				//: "Version de l'application"
				title: qsTr("settings_debug_app_version_title")
				iconSource: AppIcons.appWindow
				subTitle: AppCpp.applicationVersion + ' ('+ AppCpp.gitBranchName + ')'
				onClicked: {
					var text = UtilsCpp.copyToClipboard(AppCpp.applicationVersion)
					if (text.length !== "") {
						//: Copied
						UtilsCpp.showInformationPopup(qsTr("copied"),
						//: App version has been copied to clipboard
						qsTr("settings_debug_app_version_copied_message"))
					}
				}
				ToolTip {
					visible: parent.containsMouse || parent.activeFocus
					//: Copy text
					text: qsTr("settings_debug_copy_tooltip")
				}
			}
			HelpIconLabelButton {
				enabled: false
				// Layout.preferredWidth: width
				// Layout.minimumWidth: width
				iconSize: Utils.getSizeWithScreenRatio(24)
				//: "Version du SDK"
				title: qsTr("settings_debug_sdk_version_title")
				iconSource: AppIcons.resourcePackage
				subTitle: AppCpp.sdkVersion
				onClicked: {
					var text = UtilsCpp.copyToClipboard(AppCpp.sdkVersion)
					if (text.length !== "") {
						//: Copied
						UtilsCpp.showInformationPopup(qsTr("copied"),
						//: SDK version has been copied to clipboard
						qsTr("settings_debug_sdk_version_copied_message"))
					}
				}
				ToolTip {
					visible: parent.containsMouse || parent.activeFocus
					//: Copy text
					text: qsTr("settings_debug_copy_tooltip")
				}
			}
			HelpIconLabelButton {
				enabled: false
				// Layout.preferredWidth: width
				// Layout.minimumWidth: width
				iconSize: Utils.getSizeWithScreenRatio(24)
				iconSource: AppIcons.qtLogo
				//: "Qt Version"
				title: qsTr("settings_debug_qt_version_title")
				subTitle: AppCpp.qtVersion
				onClicked: {
					var text = UtilsCpp.copyToClipboard(AppCpp.qtVersion)
					if (text.length !== "") {
						//: Copied
						UtilsCpp.showInformationPopup(qsTr("copied"),
						//: Qt version has been copied to clipboard
						qsTr("settings_debug_qt_version_copied_message"))
					}
				}
				ToolTip {
					visible: parent.containsMouse || parent.activeFocus
					//: Copy text
					text: qsTr("settings_debug_copy_tooltip")
				}
			}
		}
	}
	
	Connections {
		target: SupportCpp
		function onLogsSent(reference, emailed) {
			UtilsCpp.getMainWindow().closeLoadingPopup()
			UtilsCpp.showInformationPopup("Journaux envoyés",
				emailed ? "Vos journaux ont été envoyés au support (référence " + reference + ")."
				        : "Vos journaux sont enregistrés sur le serveur (référence " + reference + "). Donnez cette référence au support.",
				true)
		}
		function onLogsFailed(message) {
			UtilsCpp.getMainWindow().closeLoadingPopup()
			UtilsCpp.showInformationPopup("Envoi impossible",
				message + " Les journaux se trouvent aussi dans le dossier : " + SettingsCpp.logsFolder, false)
		}
	}
}
