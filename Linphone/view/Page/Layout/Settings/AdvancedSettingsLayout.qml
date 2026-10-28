
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import SettingsCpp 1.0
import UtilsCpp 1.0
import Linphone
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

AbstractSettingsLayout {
	width: parent?.width
	// Lancement au demarrage : dans General (visible par tous). Le reste ici, reserve a l'administrateur
	// (Ctrl+Maj+M) : un changement de chiffrement ou de codec peut casser les appels.
	contentModel: [
		{
            //: Security / Encryption
            title: qsTr("settings_security_title"),
			subTitle: "",
			contentComponent: securityComponent,
		},
		{
            //: Audio codecs
            title: qsTr("settings_advanced_audio_codecs_title"),
			subTitle: "",
			contentComponent: audioCodecsComponent,
		},
		{
            //: Video codecs
            title: qsTr("settings_advanced_video_codecs_title"),
			subTitle: "",
			contentComponent: videoCodecsComponent
		},
		{
			title: "",
			subTitle: "",
			contentComponent: hideFpsComponent
		}
	]

	onSave: {
		SettingsCpp.save()
	}
	onUndo: SettingsCpp.undo()

	Component {
		id: securityComponent
		ColumnLayout {
            spacing: Utils.getSizeWithScreenRatio(20)
			ColumnLayout {
                spacing: Utils.getSizeWithScreenRatio(5)
				Text {
                    //: Media encryption
                    text: qsTr("settings_advanced_media_encryption_title")
					font {
                        pixelSize: Typography.p2l.pixelSize
                        weight: Typography.p2l.weight
					}
				}
				ComboSetting {
					Layout.fillWidth: true
					Layout.preferredWidth: parent.width
					entries: SettingsCpp.mediaEncryptions
					propertyName: "mediaEncryption"
					textRole: 'display_name'
                    propertyOwner: SettingsCpp
					accessibleLabel: qsTr("settings_advanced_media_encryption_title")
				}
			}
			SwitchSetting {
				Layout.fillWidth: true
                //: Media encryption mandatory
                titleText: qsTr("settings_advanced_media_encryption_mandatory_title")
				propertyName: "mediaEncryptionMandatory"
				propertyOwner: SettingsCpp
			}
			SwitchSetting {
				visible: false
				Layout.fillWidth: true
                //: Create end to end encrypted meetings and group calls
                titleText: qsTr("settings_advanced_create_endtoend_encrypted_meetings_title")
				propertyName: "createEndToEndEncryptedMeetingsAndGroupCalls"
				propertyOwner: SettingsCpp
			}
		}
	}

	// Audio codecs
	//////////////

	Component {
		id: audioCodecsComponent
		ColumnLayout {
			ListView {
				id: audioCodecsList
				Layout.preferredHeight: contentHeight
				Layout.fillWidth: true
                spacing: Utils.getSizeWithScreenRatio(20)
				model: PayloadTypeProxy {
					filterType: PayloadTypeProxy.Audio | PayloadTypeProxy.NotDownloadable
				}
				delegate: SwitchSetting {
					width: audioCodecsList ? audioCodecsList.width : 0
                    height: Utils.getSizeWithScreenRatio(32)
					titleText: Utils.capitalizeFirstLetter(modelData.core.mimeType)
					subTitleText: modelData.core.clockRate + " Hz"
					propertyName: "enabled"
					propertyOwnerGui: modelData
					Connections {
						target: modelData.core
						function onChanged() { SettingsCpp.isSaved = false }
					}
					Connections {
						target: SettingsCpp
						function onIsSavedChanged(saved) {
							if (saved)
								modelData.core.save()
						}
					}
				}
			}
		}
	}

	// Video codecs
	//////////////

	Component {
		id: videoCodecsComponent
		ColumnLayout {
            spacing: Utils.getSizeWithScreenRatio(20)
			ListView {
				id: videoCodecList
				Layout.preferredHeight: contentHeight
				Layout.fillWidth: true
                spacing: Utils.getSizeWithScreenRatio(20)
				model: PayloadTypeProxy {
					id: videoPayloadTypeProxy
					filterType: PayloadTypeProxy.Video | PayloadTypeProxy.NotDownloadable
				}
				delegate: SwitchSetting {
					width: videoCodecList.width
                    height: Utils.getSizeWithScreenRatio(32)
					titleText: Utils.capitalizeFirstLetter(modelData.core.mimeType)
					subTitleText: modelData.core.encoderDescription
					propertyName: "enabled"
					propertyOwnerGui: modelData
					Connections {
						target: modelData.core
						function onChanged() { SettingsCpp.isSaved = false }
					}
					Connections {
						target: SettingsCpp
						function onIsSavedChanged(saved) {
							if (saved)
								modelData.core.save()
						}
					}
				}
			}
			ListView {
				id: payloadList
				Layout.preferredHeight: contentHeight
				Layout.fillWidth: true
                spacing: Utils.getSizeWithScreenRatio(20)
				model: PayloadTypeProxy {
					id: downloadableVideoPayloadTypeProxy
					filterType: PayloadTypeProxy.Video | PayloadTypeProxy.Downloadable
				}
				delegate: SwitchSetting {
					width: payloadList.width
                    height: Utils.getSizeWithScreenRatio(32)
					titleText: Utils.capitalizeFirstLetter(modelData.core.mimeType)
					subTitleText: modelData.core.encoderDescription
					onToggled: Utils.openCodecOnlineInstallerDialog(
						UtilsCpp.getMainWindow(),
						modelData.core,
						function cancelCallBack() {
							checked = false
						},
						function successCallBack() {
							videoPayloadTypeProxy.reload()
							downloadableVideoPayloadTypeProxy.reload()
						},
						function errorCallBack() {
							checked = false
						})
				}
			}
		}
	}

	//Hide fps
	//////////

	Component {
		id: hideFpsComponent
		ColumnLayout {
            spacing: Utils.getSizeWithScreenRatio(40)
			SwitchSetting {
                //:"Cacher les FPS"
                titleText:qsTr("settings_advanced_hide_fps_title")
				propertyName: "hideFps"
				propertyOwner: SettingsCpp
			}
		}
	}
}
