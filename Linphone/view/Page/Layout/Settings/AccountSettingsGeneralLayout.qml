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
			title: "Connexion",
			subTitle: "",
			contentComponent: connectionComponent
		},
		{
			title: "Mon statut",
			subTitle: "",
			contentComponent: statusComponent
		},
		{
			// Seulement pour un agent d'au moins une file (lu a l'affichage : pas de reconstruction de la page).
			isVisible: function () { return QueuesCpp.agent && QueuesCpp.queueCount > 0 },
			title: "Files d'attente",
			subTitle: "",
			contentComponent: queuesComponent
		},
		{
			title: "Informations",
			subTitle: "",
			contentComponent: informationComponent
		},
		{
			title: "Sur cet ordinateur",
			subTitle: "",
			plain: true,
			contentComponent: removeComponent
		},
		{
            visible: SettingsCpp.showAccountDevices,
            //: "Vos appareils"
            title: qsTr("manage_account_devices_title"),
            //: "La liste des appareils connectés à votre compte. Vous pouvez retirer les appareils que vous n’utilisez plus."
            subTitle: qsTr("manage_account_devices_subtitle"),
			plain: true,
			contentComponent: accountDevicesComponent
		}
	]

	property alias account: mainItem.model

	// Statut du poste en pastilles (le meme que dans le menu de la photo, partage avec ses autres appareils), et ce
	// qu'il fait des appels.
	Component {
		id: statusComponent
		ColumnLayout {
			id: statusBox
			spacing: Utils.getSizeWithScreenRatio(12)
			readonly property int current: mainItem.account ? mainItem.account.core.presence : -1
			Flow {
				Layout.fillWidth: true
				spacing: Utils.getSizeWithScreenRatio(8)
				Repeater {
					model: [LinphoneEnums.Presence.Online, LinphoneEnums.Presence.Away, LinphoneEnums.Presence.Busy,
						LinphoneEnums.Presence.DoNotDisturb, LinphoneEnums.Presence.Offline]
					delegate: Rectangle {
						id: chip
						required property int modelData
						readonly property bool selected: statusBox.current === modelData
						width: chipRow.implicitWidth + 2 * Utils.getSizeWithScreenRatio(12)
						height: Utils.getSizeWithScreenRatio(34)
						radius: height / 2
						color: selected ? DefaultStyle.main1_100 : chipArea.containsMouse ? DefaultStyle.main2_200 : DefaultStyle.grey_0
						border.width: Utils.getSizeWithScreenRatio(1)
						border.color: selected ? DefaultStyle.main1_500_main : DefaultStyle.main2_200
						Accessible.role: Accessible.RadioButton
						Accessible.name: UtilsCpp.getPresenceStatus(modelData)
						Accessible.checked: selected
						RowLayout {
							id: chipRow
							anchors.centerIn: parent
							spacing: Utils.getSizeWithScreenRatio(8)
							Image {
								readonly property real side: Utils.getSizeWithScreenRatio(11)
								Layout.preferredWidth: side
								Layout.preferredHeight: side
								sourceSize.width: side
								sourceSize.height: side
								source: UtilsCpp.getPresenceIcon(chip.modelData)
							}
							Text {
								text: UtilsCpp.getPresenceStatus(chip.modelData)
								font.pixelSize: Utils.getSizeWithScreenRatio(13)
								font.weight: chip.selected ? Font.DemiBold : Font.Normal
								color: DefaultStyle.main2_800
							}
						}
						MouseArea {
							id: chipArea
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: mainItem.account.core.presence = chip.modelData
						}
					}
				}
			}
			Text {
				Layout.fillWidth: true
				wrapMode: Text.WordWrap
				font.pixelSize: Utils.getSizeWithScreenRatio(12)
				color: DefaultStyle.main2_500_main
				text: statusBox.current === LinphoneEnums.Presence.Online ? "Tous les appels sonnent, files d'attente comprises."
					: statusBox.current === LinphoneEnums.Presence.Away || statusBox.current === LinphoneEnums.Presence.Busy
						? "Vos appels arrivent sans sonnerie ni notification, ceux des files d'attente compris."
						: "Aucun appel ne sonne et les files d'attente sont en pause."
			}
		}
	}

	// Files d'attente du poste, comme dans le menu du casque.
	Component {
		id: queuesComponent
		QueuesSection {
			headerVisible: false
			Component.onCompleted: QueuesCpp.refresh()
		}
	}

	// Poste, nom, domaine et transport : de quoi repondre au support.
	Component {
		id: informationComponent
		GridLayout {
			columns: 2
			columnSpacing: Utils.getSizeWithScreenRatio(24)
			rowSpacing: Utils.getSizeWithScreenRatio(10)
			readonly property string identity: mainItem.account ? mainItem.account.core.identityAddress : ""
			component InfoLabel: Text {
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				color: DefaultStyle.main2_500_main
			}
			component InfoValue: Text {
				Layout.fillWidth: true
				font.pixelSize: Utils.getSizeWithScreenRatio(14)
				font.weight: Font.DemiBold
				color: DefaultStyle.main2_800
				wrapMode: Text.Wrap
			}
			InfoLabel { text: "Poste" }
			InfoValue { text: UtilsCpp.getUsername(parent.identity) }
			InfoLabel { text: "Nom" }
			InfoValue { text: mainItem.account ? mainItem.account.core.displayName : "" }
			InfoLabel { text: "Domaine" }
			InfoValue {
				// Ce qui suit le « @ » de l'adresse, sans port ni parametres.
				text: parent.identity.indexOf("@") < 0 ? ""
					: parent.identity.substring(parent.identity.indexOf("@") + 1).split(";")[0].split(":")[0].replace(">", "")
			}
			InfoLabel { text: "Transport" }
			InfoValue { text: mainItem.account ? mainItem.account.core.transport.toUpperCase() : "" }
		}
	}

	// Connexion : etat du compte et interrupteur pour le couper ou le retablir.
	Component {
		id: connectionComponent
		RowLayout {
			spacing: Utils.getSizeWithScreenRatio(10)
			Rectangle {
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(8)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(8)
				radius: width / 2
				color: mainItem.account ? mainItem.account.core.registrationColor : DefaultStyle.main2_400
			}
			SwitchSetting {
				Layout.fillWidth: true
				titleText: mainItem.account?.core.humaneReadableRegistrationState
				subTitleText: mainItem.account?.core.humaneReadableRegistrationStateExplained
				propertyName: "registerEnabled"
				propertyOwnerGui: mainItem.account
				Binding on checked {
					when: mainItem.account?.core.registrationState === LinphoneEnums.RegistrationState.Failed
					value: false
				}
			}
		}
	}

	// Retrait du poste de cet ordinateur (confirmation rouge avant), dans un simple cadre : rouge au survol.
	Component {
		id: removeComponent
		Rectangle {
			id: removeRow
			Layout.fillWidth: true
			implicitHeight: removeTexts.implicitHeight + 2 * Utils.getSizeWithScreenRatio(14)
			radius: Utils.getSizeWithScreenRatio(14)
			color: removeArea.containsMouse ? "#FDF1F1" : "transparent"
			activeFocusOnTab: true
			border.width: activeFocus ? Utils.getSizeWithScreenRatio(2) : Utils.getSizeWithScreenRatio(1)
			border.color: activeFocus ? DefaultStyle.main1_500_main : DefaultStyle.main2_200
			Accessible.role: Accessible.Button
			Accessible.name: "Retirer ce poste de Gamaphone"
			function confirmRemoval() {
				UtilsCpp.getMainWindow().showConfirmationLambdaPopup("",
					"Retirer ce poste de Gamaphone ?",
					"Pour le remettre, il faudra un nouveau lien de configuration.",
					function (confirmed) {
						if (confirmed) {
							mainItem.account.core.removeAccount()
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
				anchors.leftMargin: Utils.getSizeWithScreenRatio(20)
				anchors.rightMargin: Utils.getSizeWithScreenRatio(20)
				spacing: Utils.getSizeWithScreenRatio(14)
				EffectImage {
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(22)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(22)
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


	// Account devices
	//////////////////////////

	Component {
		id: accountDevicesComponent
		RoundedPane {
			Layout.fillWidth: true
			Layout.fillHeight: true
            // Layout.minimumHeight: account.core.devices.length *Utils.getSizeWithScreenRatio(133) + (account.core.devices.length - 1) *Utils.getSizeWithScreenRatio(15) +  2 *Utils.getSizeWithScreenRatio(21)
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
