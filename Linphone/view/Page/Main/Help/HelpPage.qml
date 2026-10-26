import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils


AbstractMainPage {

	id: mainItem
	showDefaultItem: false
	
	signal goBack()
	
	leftPanelContent: ColumnLayout {
		id: leftPanel
		Layout.fillWidth: true
		Layout.fillHeight: true
        property real leftMargin: Utils.getSizeWithScreenRatio(45)
        property real rightMargin: Utils.getSizeWithScreenRatio(29)
        spacing: Utils.getSizeWithScreenRatio(5)
		RowLayout {
			Layout.fillWidth: true
			Layout.leftMargin: leftPanel.leftMargin
			Layout.rightMargin: leftPanel.rightMargin
            spacing: Utils.getSizeWithScreenRatio(8)
			RoundButton {
				icon.source: AppIcons.leftArrow
				style: ButtonStyle.noBackground
                icon.width: Utils.getSizeWithScreenRatio(24)
                icon.height: Utils.getSizeWithScreenRatio(24)
				onClicked: {
					mainItem.goBack()
				}
			}
			Text {
                //: "Aide"
                text: qsTr("help_title")
				color: DefaultStyle.main2_700
				font: Typography.h2
			}
			Item {
				Layout.fillWidth: true
			}
		}
		// Logo de l'entreprise, version et mise a jour.
		Rectangle {
			Layout.fillWidth: true
			Layout.leftMargin: leftPanel.leftMargin
			Layout.rightMargin: leftPanel.rightMargin
			Layout.topMargin: Utils.getSizeWithScreenRatio(24)
			Layout.preferredHeight: aboutColumn.implicitHeight + 2 * aboutColumn.y
			radius: Utils.getSizeWithScreenRatio(14)
			color: DefaultStyle.main2_100
			ColumnLayout {
				id: aboutColumn
				x: Utils.getSizeWithScreenRatio(18)
				y: Utils.getSizeWithScreenRatio(20)
				width: parent.width - 2 * x
				spacing: 0
				Image {
					Layout.alignment: Qt.AlignHCenter
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(170)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(43)
					source: AppIcons.companyLogo
					fillMode: Image.PreserveAspectFit
					smooth: true
					mipmap: true
				}
				Text {
					Layout.alignment: Qt.AlignHCenter
					Layout.topMargin: Utils.getSizeWithScreenRatio(12)
					// « 6.2.1-pre.21+44eb08bf5 » : la version, et le numero de build (commits depuis l'etiquette).
					readonly property var build: Qt.application.version.match(/pre\.(\d+)/)
					text: "Version " + AppCpp.shortApplicationVersion + (build ? " · build " + build[1] : "")
					font.pixelSize: Utils.getSizeWithScreenRatio(13)
					color: DefaultStyle.main2_500_main
				}
				MediumButton {
					Layout.fillWidth: true
					Layout.topMargin: Utils.getSizeWithScreenRatio(16)
					style: ButtonStyle.secondary
					//: Check update
					text: qsTr("help_check_for_update_button_label")
					// Reponse affichee par la verification elle-meme (a jour, ou fenetre de mise a jour).
					onClicked: AppCpp.checkForUpdate(true)
				}
			}
		}

		// Poste, domaine et etat de la connexion : ce qu'on demande en premier au telephone pour un depannage.
		Text {
			Layout.leftMargin: leftPanel.leftMargin
			Layout.topMargin: Utils.getSizeWithScreenRatio(24)
			text: "Mon poste"
			font.pixelSize: Utils.getSizeWithScreenRatio(13)
			color: DefaultStyle.main2_500_main
		}
		Rectangle {
			id: posteCard
			readonly property var account: accountProxy.defaultAccount
			readonly property string identity: account ? account.core.identityAddress : ""
			readonly property bool connected: !!account && account.core.registrationState === LinphoneEnums.RegistrationState.Ok
			Layout.fillWidth: true
			Layout.leftMargin: leftPanel.leftMargin
			Layout.rightMargin: leftPanel.rightMargin
			Layout.topMargin: Utils.getSizeWithScreenRatio(8)
			Layout.preferredHeight: posteGrid.implicitHeight + 2 * posteGrid.y
			radius: Utils.getSizeWithScreenRatio(14)
			color: DefaultStyle.main2_100
			GridLayout {
				id: posteGrid
				x: Utils.getSizeWithScreenRatio(18)
				y: Utils.getSizeWithScreenRatio(16)
				width: parent.width - 2 * x
				columns: 2
				columnSpacing: Utils.getSizeWithScreenRatio(16)
				rowSpacing: Utils.getSizeWithScreenRatio(8)
				component InfoLabel: Text {
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
					color: DefaultStyle.main2_500_main
				}
				component InfoValue: Text {
					Layout.fillWidth: true
					font.pixelSize: Utils.getSizeWithScreenRatio(13)
					font.weight: Font.DemiBold
					color: DefaultStyle.main2_800
					elide: Text.ElideRight
				}
				InfoLabel {
					text: "Poste"
				}
				InfoValue {
					readonly property string poste: UtilsCpp.getUsername(posteCard.identity)
					readonly property string name: posteCard.account ? posteCard.account.core.displayName : ""
					text: name.length > 0 && name !== poste ? poste + " · " + name : poste
				}
				InfoLabel {
					text: "Domaine"
				}
				InfoValue {
					// « sip:1000@domaine;transport=tcp » : la partie apres @, sans les parametres.
					text: posteCard.identity.indexOf("@") >= 0
						? posteCard.identity.split("@")[1].split(";")[0].replace(">", "")
						: ""
				}
				InfoLabel {
					text: "Connexion"
				}
				RowLayout {
					Layout.fillWidth: true
					spacing: Utils.getSizeWithScreenRatio(6)
					Rectangle {
						Layout.preferredWidth: Utils.getSizeWithScreenRatio(8)
						Layout.preferredHeight: Utils.getSizeWithScreenRatio(8)
						radius: width / 2
						color: posteCard.account ? posteCard.account.core.registrationColor : DefaultStyle.main2_400
					}
					InfoValue {
						color: posteCard.account ? posteCard.account.core.registrationColor : DefaultStyle.main2_500_main
						text: !posteCard.account ? "Aucun compte"
							: posteCard.connected
								? "Connecté" + (posteCard.account.core.transport.length > 0
									? " (" + posteCard.account.core.transport.toUpperCase() + ")" : "")
								: posteCard.account.core.humaneReadableRegistrationState
					}
				}
			}
		}

		Text {
			Layout.leftMargin: leftPanel.leftMargin
			Layout.topMargin: Utils.getSizeWithScreenRatio(24)
			text: "Assistance"
			font.pixelSize: Utils.getSizeWithScreenRatio(13)
			color: DefaultStyle.main2_500_main
		}
		HelpIconLabelButton {
			id: troubleShooting
			Layout.fillWidth: true
			Layout.leftMargin: leftPanel.leftMargin
			Layout.rightMargin: leftPanel.rightMargin
			Layout.topMargin: Utils.getSizeWithScreenRatio(12)
			iconSource: AppIcons.debug
			arrowImageVisible: true
			//: "Dépannage"
			title: qsTr("help_troubleshooting_title")
			subTitle: "Journaux, envoi au support"
			onClicked: {
				rightPanelStackView.clear()
				rightPanelStackView.push("qrc:/qt/qml/Linphone/view/Page/Layout/Settings/DebugSettingsLayout.qml", { titleText: troubleShooting.title, container: rightPanelStackView })
			}
		}
		Item {
			Layout.fillHeight: true
		}
		// Mention obligatoire de la licence de Linphone, discrete, en bas.
		Text {
			Layout.fillWidth: true
			Layout.leftMargin: leftPanel.leftMargin
			Layout.rightMargin: leftPanel.rightMargin
			Layout.bottomMargin: Utils.getSizeWithScreenRatio(16)
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.Wrap
			textFormat: Text.StyledText
			text: "Basé sur Linphone · licence <a href=\"" + applicationLicenceUrl + "\">GPLv3</a><br>"
				+ (copyrightRangeDate || applicationVendor ? "© " : "") + (copyrightRangeDate ? copyrightRangeDate : "")
				+ (applicationVendor ? " " + applicationVendor : "")
			linkColor: DefaultStyle.main1_500_main
			font.pixelSize: Utils.getSizeWithScreenRatio(11)
			lineHeight: 1.3
			color: DefaultStyle.main2_400
			onLinkActivated: link => Qt.openUrlExternally(link)
			MouseArea {
				anchors.fill: parent
				acceptedButtons: Qt.NoButton
				cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
			}
		}
	}

	// Compte du poste (carte « Mon poste »).
	AccountProxy {
		id: accountProxy
	}
}
