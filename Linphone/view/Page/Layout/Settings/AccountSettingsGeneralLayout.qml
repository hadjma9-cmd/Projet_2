import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import QtQuick.Dialogs
import Linphone
import SettingsCpp
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

AbstractSettingsLayout {
	id: mainItem
	saveButtonVisible: false

	width: parent?.width
	contentModel: [
		{
            //: "Détails"
            title: qsTr("manage_account_details_title"),
            //: Éditer les informations de votre compte.
            subTitle: qsTr("manage_account_details_subtitle"),
			contentComponent: accountParametersComponent
		},
		{
            visible: SettingsCpp.showAccountDevices,
            //: "Vos appareils"
            title: qsTr("manage_account_devices_title"),
            //: "La liste des appareils connectés à votre compte. Vous pouvez retirer les appareils que vous n’utilisez plus."
            subTitle: qsTr("manage_account_devices_subtitle"),
			contentComponent: accountDevicesComponent
		}
	]

	property alias account: mainItem.model

	// Account parameters
	//////////////////////////

	Component {
		id: accountParametersComponent
		ColumnLayout {
			Layout.fillWidth: true
            spacing: Utils.getSizeWithScreenRatio(20)
			Avatar {
				id: avatar
				account: model
				displayPresence: false
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(100)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(100)
				Layout.alignment: Qt.AlignHCenter
			}
			IconLabelButton {
				visible: model.core.pictureUri.length === 0
				Layout.preferredWidth: width
				icon.source: AppIcons.camera
                icon.width: Utils.getSizeWithScreenRatio(17)
                icon.height: Utils.getSizeWithScreenRatio(17)
                //: "Ajouter une image"
                text: qsTr("manage_account_add_picture")
				style: ButtonStyle.noBackground
				onClicked: fileDialog.open()
				Layout.alignment: Qt.AlignHCenter
			}
			RowLayout {
				visible: model.core.pictureUri.length > 0
				Layout.alignment: Qt.AlignHCenter
                spacing: Utils.getSizeWithScreenRatio(5)
				IconLabelButton {
					Layout.preferredWidth: width
					icon.source: AppIcons.pencil
                    icon.width: Utils.getSizeWithScreenRatio(17)
                    icon.height: Utils.getSizeWithScreenRatio(17)
                    //: "Modifier l'image"
                    text: qsTr("manage_account_edit_picture")
					style: ButtonStyle.noBackground
					onClicked: fileDialog.open()
				}
				IconLabelButton {
					Layout.preferredWidth: width
					icon.source: AppIcons.trashCan
                    icon.width: Utils.getSizeWithScreenRatio(17)
                    icon.height: Utils.getSizeWithScreenRatio(17)
                    //: "Supprimer l'image"
                    text: qsTr("manage_account_remove_picture")
					style: ButtonStyle.noBackground
					onClicked: model.core.pictureUri = ""
				}
			}
			FileDialog {
				id: fileDialog
				currentFolder: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
				onAccepted: {
					var avatarPath = UtilsCpp.createAvatar( selectedFile )
					if(avatarPath){
						model.core.pictureUri = avatarPath
					}
				}
			}
			// Identité du poste, en lecture seule. Le nom présenté aux autres est celui de l'extension dans FusionPBX :
			// le modifier ici ne changeait que l'affichage local, c'est à l'administrateur de le régler. L'indicatif
			// international n'est plus proposé non plus (la valeur en place reste active).
			ColumnLayout {
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(2)
				Text {
					Layout.fillWidth: true
					horizontalAlignment: Text.AlignHCenter
					text: model.core.displayName
					visible: text.length > 0
					color: DefaultStyle.main2_700
					font: Typography.h4
					elide: Text.ElideRight
				}
				Text {
					Layout.fillWidth: true
					horizontalAlignment: Text.AlignHCenter
					text: "Poste " + UtilsCpp.getUsername(model.core.identityAddress)
					color: DefaultStyle.main2_600
					font: Typography.p2l
				}
				Text {
					Layout.fillWidth: true
					horizontalAlignment: Text.AlignHCenter
					// Domaine : ce qui suit le « @ » de l'adresse, sans port ni paramètres.
					text: {
						var address = model.core.identityAddress
						var at = address.indexOf("@")
						return at < 0 ? "" : address.substring(at + 1).split(";")[0].split(":")[0]
					}
					visible: text.length > 0
					color: DefaultStyle.main2_500_main
					font: Typography.p1
					elide: Text.ElideMiddle
				}
			}
			SwitchSetting {
				titleText: account?.core.humaneReadableRegistrationState
				subTitleText: account?.core.humaneReadableRegistrationStateExplained
				propertyName: "registerEnabled"
				propertyOwnerGui: account
				Binding on checked {
					when: account?.core.registrationState === LinphoneEnums.RegistrationState.Failed
					value: false
				}
			}
			RowLayout {
				id:mainItem
                spacing : Utils.getSizeWithScreenRatio(20)
				ColumnLayout {
                    spacing : Utils.getSizeWithScreenRatio(5)
					Text {
                        //: "Supprimer mon compte"
                        text: qsTr("manage_account_delete")
						font: Typography.p2l
						wrapMode: Text.WordWrap
						color: DefaultStyle.danger_500_main
						Layout.fillWidth: true
					}
					Text {
                        text: "Retire ce poste de Gamaphone sur cet ordinateur."
						font: Typography.p1
						wrapMode: Text.WordWrap
						color: DefaultStyle.main2_500_main
						Layout.fillWidth: true
					}
				}
				Item {
					Layout.fillWidth: true
				}
				BigButton {
					style: ButtonStyle.noBackgroundRed
					Layout.alignment: Qt.AlignRight
                    Layout.rightMargin: Utils.getSizeWithScreenRatio(5)
					icon.source: AppIcons.trashCan
					onClicked: {
						var mainWin = UtilsCpp.getMainWindow()
						mainWin.showConfirmationLambdaPopup("",
                            "Retirer ce poste de Gamaphone ?",
                            "Pour le remettre, il faudra un nouveau lien de configuration.",
							function (confirmed) {
								if (confirmed) {
									account.core.removeAccount()
								}
							}
						)
					}
				}
			}
		}
	}


	// Account devices
	//////////////////////////

	Component {
		id: accountDevicesComponent
		RoundedPane {
			Layout.fillWidth: true
			Layout.fillHeight: true
            // Layout.minimumHeight: account.core.devices.length *Utils.getSizeWithScreenRatio(133) + (account.core.devices.length - 1) *Utils.getSizeWithScreenRatio(15) +  2 *Utils.getSizeWithScreenRatio(21)
            Layout.rightMargin: Utils.getSizeWithScreenRatio(30)
            Layout.topMargin: Utils.getSizeWithScreenRatio(20)
            Layout.bottomMargin: Utils.getSizeWithScreenRatio(4)
            Layout.leftMargin: Utils.getSizeWithScreenRatio(44)
            topPadding: Utils.getSizeWithScreenRatio(21)
            bottomPadding: Utils.getSizeWithScreenRatio(21)
            leftPadding: Utils.getSizeWithScreenRatio(17)
            rightPadding: Utils.getSizeWithScreenRatio(17)
			background: Rectangle {
				anchors.fill: parent
				color: DefaultStyle.grey_100
                radius: Utils.getSizeWithScreenRatio(15)
			}
			contentItem: ColumnLayout {
                spacing: Utils.getSizeWithScreenRatio(15)
                BusyIndicator {
                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(60)
                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(60)
                    Layout.alignment: Qt.AlignHCenter
                    visible: devices.loading
                }

				Text {
					visible: devices.count === 0
					font: Typography.h3m
					//: No device fetched
					text: qsTr("no_device_message")
				}

				Repeater {
					id: devices
                    visible: !loading
                    property bool loading
                    Component.onCompleted: loading = true
					model: AccountDeviceProxy {
						id: accountDeviceProxy
						account: mainItem.model
                        onDevicesSet: devices.loading = false;
                        onRequestError: (errorMessage) => {
                            devices.loading = false;
                            //: Erreur
                            mainWindow.showInformationPopup(qsTr("error"), errorMessage, false)
                        }
					}
                    Control.Control {
						Layout.fillWidth: true
                        height: Utils.getSizeWithScreenRatio(133)
                        topPadding: Utils.getSizeWithScreenRatio(26)
                        bottomPadding: Utils.getSizeWithScreenRatio(26)
                        rightPadding: Utils.getSizeWithScreenRatio(36)
                        leftPadding: Utils.getSizeWithScreenRatio(33)
						background: Rectangle {
							anchors.fill: parent
							color: DefaultStyle.grey_0
                            radius: Utils.getSizeWithScreenRatio(10)
						}
						contentItem: ColumnLayout {
							width: parent.width
                            spacing: Utils.getSizeWithScreenRatio(20)
							RowLayout {
                                spacing: Utils.getSizeWithScreenRatio(5)
								EffectImage {
                                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(24)
                                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(24)
									fillMode: Image.PreserveAspectFit
									colorizationColor: DefaultStyle.main2_600
									imageSource: modelData.core.userAgent.toLowerCase().includes('ios') | modelData.core.userAgent.toLowerCase().includes('android') ? AppIcons.mobile : AppIcons.desktop
								}
								Text {
									text: modelData.core.deviceName
									color: DefaultStyle.main2_600
									font: Typography.p2
								}
								Item {
									Layout.fillWidth: true
								}
								MediumButton {
									Layout.alignment: Qt.AlignRight
                                    //: "Supprimer"
                                    text: qsTr("manage_account_device_remove")
									icon.source: AppIcons.trashCan
                                    icon.width: Utils.getSizeWithScreenRatio(16)
                                    icon.height: Utils.getSizeWithScreenRatio(16)
									style: ButtonStyle.tertiary
									onClicked: {
										var mainWin = UtilsCpp.getMainWindow()
										mainWin.showConfirmationLambdaPopup("",
                                            //:"Supprimer %1 ?"
                                            qsTr("manage_account_device_remove_confirm_dialog").arg(modelData.core.deviceName), "",
											function (confirmed) {
												if (confirmed) {
													accountDeviceProxy.deleteDevice(modelData)
												}
											}
										)
									}
								}
							}
							RowLayout {
                                spacing: Utils.getSizeWithScreenRatio(5)
								Text {
                                    //: "Dernière connexion:"
                                    text: qsTr("manage_account_device_last_connection")
									color: DefaultStyle.main2_600
									font: Typography.p2
								}
								EffectImage {
									visible: dateText.lastDate != ""
                                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(20)
                                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(20)
									imageSource: AppIcons.calendarBlank
									colorizationColor: DefaultStyle.main2_600
									fillMode: Image.PreserveAspectFit
								}
								Text {
									id: dateText
									property string lastDate: UtilsCpp.formatDate(modelData.core.lastUpdateTimestamp,false)
									text: lastDate != ""
										? lastDate
										//: "No information"
										: qsTr("device_last_updated_time_no_info")
									color: DefaultStyle.main2_600
									font: Typography.p1
								}
								EffectImage {
									visible: dateText.lastDate != ""
                                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(20)
                                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(20)
									imageSource: AppIcons.clock
									colorizationColor: DefaultStyle.main2_600
									fillMode: Image.PreserveAspectFit
								}
								Text {
									visible: dateText.lastDate != ""
									text: UtilsCpp.formatTime(modelData.core.lastUpdateTimestamp)
									color: DefaultStyle.main2_600
									font: Typography.p1
								}
							}
						}
					}
				}
			}
		}
	}
}
