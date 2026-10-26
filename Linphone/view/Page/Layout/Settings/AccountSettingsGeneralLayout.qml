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
			// Sans titre de section : la page tient en trois cartes (identite, connexion, retrait du poste), centrees.
			title: "",
			subTitle: "",
			centered: true,
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
			spacing: 0

			// Identite : photo (changer, retirer), nom et poste. Le nom vient de l'extension dans FusionPBX : c'est a
			// l'administrateur de le regler, il n'est pas modifiable ici.
			Rectangle {
				Layout.fillWidth: true
				Layout.preferredHeight: identityColumn.implicitHeight + 2 * identityColumn.y
				radius: Utils.getSizeWithScreenRatio(14)
				color: DefaultStyle.main2_100
				ColumnLayout {
					id: identityColumn
					x: Utils.getSizeWithScreenRatio(18)
					y: Utils.getSizeWithScreenRatio(22)
					width: parent.width - 2 * x
					spacing: 0
					Avatar {
						Layout.alignment: Qt.AlignHCenter
						Layout.preferredWidth: Utils.getSizeWithScreenRatio(84)
						Layout.preferredHeight: Utils.getSizeWithScreenRatio(84)
						account: model
						displayPresence: false
						shadowEnabled: false
					}
					// « Changer la photo · Retirer » (« Ajouter une photo » s'il n'y en a pas).
					Text {
						Layout.alignment: Qt.AlignHCenter
						Layout.topMargin: Utils.getSizeWithScreenRatio(8)
						textFormat: Text.StyledText
						text: model.core.pictureUri.length === 0
							? "<a href=\"change\">Ajouter une photo</a>"
							: "<a href=\"change\">Changer la photo</a>  ·  <a href=\"remove\"><font color=\""
							  + DefaultStyle.main2_500_main + "\">Retirer</font></a>"
						linkColor: DefaultStyle.main1_500_main
						font.pixelSize: Utils.getSizeWithScreenRatio(12)
						onLinkActivated: link => {
							if (link === "change")
								fileDialog.open()
							else
								model.core.pictureUri = ""
						}
						MouseArea {
							anchors.fill: parent
							acceptedButtons: Qt.NoButton
							cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
						}
					}
					Text {
						Layout.fillWidth: true
						Layout.topMargin: Utils.getSizeWithScreenRatio(12)
						horizontalAlignment: Text.AlignHCenter
						text: model.core.displayName
						visible: text.length > 0
						font.pixelSize: Utils.getSizeWithScreenRatio(18)
						font.weight: Font.Bold
						color: DefaultStyle.main2_800
						elide: Text.ElideRight
					}
					Text {
						Layout.fillWidth: true
						Layout.topMargin: Utils.getSizeWithScreenRatio(2)
						horizontalAlignment: Text.AlignHCenter
						// Domaine : ce qui suit le « @ » de l'adresse, sans port ni parametres.
						readonly property string domain: {
							var address = model.core.identityAddress
							var at = address.indexOf("@")
							return at < 0 ? "" : address.substring(at + 1).split(";")[0].split(":")[0].replace(">", "")
						}
						text: "Poste " + UtilsCpp.getUsername(model.core.identityAddress) + (domain.length > 0 ? " · " + domain : "")
						font.pixelSize: Utils.getSizeWithScreenRatio(13)
						color: DefaultStyle.main2_500_main
						elide: Text.ElideMiddle
					}
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

			// Connexion : etat du compte et interrupteur pour le couper ou le retablir.
			Text {
				Layout.topMargin: Utils.getSizeWithScreenRatio(24)
				text: "Connexion"
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				color: DefaultStyle.main2_500_main
			}
			Rectangle {
				Layout.fillWidth: true
				Layout.topMargin: Utils.getSizeWithScreenRatio(8)
				Layout.preferredHeight: connectionRow.implicitHeight + 2 * Utils.getSizeWithScreenRatio(14)
				radius: Utils.getSizeWithScreenRatio(14)
				color: DefaultStyle.main2_100
				RowLayout {
					id: connectionRow
					anchors.fill: parent
					anchors.leftMargin: Utils.getSizeWithScreenRatio(18)
					anchors.rightMargin: Utils.getSizeWithScreenRatio(18)
					spacing: Utils.getSizeWithScreenRatio(10)
					Rectangle {
						Layout.preferredWidth: Utils.getSizeWithScreenRatio(8)
						Layout.preferredHeight: Utils.getSizeWithScreenRatio(8)
						radius: width / 2
						color: account ? account.core.registrationColor : DefaultStyle.main2_400
					}
					SwitchSetting {
						Layout.fillWidth: true
						titleText: account?.core.humaneReadableRegistrationState
						subTitleText: account?.core.humaneReadableRegistrationStateExplained
						propertyName: "registerEnabled"
						propertyOwnerGui: account
						Binding on checked {
							when: account?.core.registrationState === LinphoneEnums.RegistrationState.Failed
							value: false
						}
					}
				}
			}

			// Retrait du poste de cet ordinateur (confirmation rouge avant).
			Text {
				Layout.topMargin: Utils.getSizeWithScreenRatio(24)
				text: "Sur cet ordinateur"
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				color: DefaultStyle.main2_500_main
			}
			Rectangle {
				id: removeRow
				Layout.fillWidth: true
				Layout.topMargin: Utils.getSizeWithScreenRatio(6)
				Layout.preferredHeight: removeTexts.implicitHeight + 2 * Utils.getSizeWithScreenRatio(10)
				radius: Utils.getSizeWithScreenRatio(10)
				color: removeArea.containsMouse ? DefaultStyle.main2_100 : "transparent"
				activeFocusOnTab: true
				border.width: activeFocus ? Utils.getSizeWithScreenRatio(2) : 0
				border.color: DefaultStyle.main1_500_main
				Accessible.role: Accessible.Button
				Accessible.name: "Retirer ce poste de Gamaphone"
				function confirmRemoval() {
					UtilsCpp.getMainWindow().showConfirmationLambdaPopup("",
						"Retirer ce poste de Gamaphone ?",
						"Pour le remettre, il faudra un nouveau lien de configuration.",
						function (confirmed) {
							if (confirmed) {
								account.core.removeAccount()
							}
						}
					, undefined, undefined, undefined, "danger", AppIcons.signOut)
				}
				Keys.onPressed: event => {
					if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						removeRow.confirmRemoval()
						event.accepted = true
					}
				}
				RowLayout {
					anchors.fill: parent
					anchors.leftMargin: Utils.getSizeWithScreenRatio(6)
					anchors.rightMargin: Utils.getSizeWithScreenRatio(6)
					spacing: Utils.getSizeWithScreenRatio(14)
					EffectImage {
						Layout.preferredWidth: Utils.getSizeWithScreenRatio(24)
						Layout.preferredHeight: Utils.getSizeWithScreenRatio(24)
						imageSource: AppIcons.signOut
						colorizationColor: DefaultStyle.danger_500_main
					}
					ColumnLayout {
						id: removeTexts
						Layout.fillWidth: true
						spacing: Utils.getSizeWithScreenRatio(2)
						Text {
							Layout.fillWidth: true
							text: "Retirer ce poste de Gamaphone"
							font.pixelSize: Utils.getSizeWithScreenRatio(14)
							font.weight: Font.DemiBold
							color: DefaultStyle.danger_500_main
						}
						Text {
							Layout.fillWidth: true
							text: "Le poste reste actif sur le serveur et sur ses autres appareils."
							font.pixelSize: Utils.getSizeWithScreenRatio(12)
							color: DefaultStyle.main2_500_main
							wrapMode: Text.Wrap
						}
					}
				}
				MouseArea {
					id: removeArea
					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: removeRow.confirmRemoval()
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
										, undefined, undefined, undefined, "danger", AppIcons.trashCan)
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
