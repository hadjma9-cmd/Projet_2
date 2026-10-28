import QtCore
import QtQuick
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

AbstractSettingsMenu {
	id: mainItem
	layoutsPath: "qrc:/qt/qml/Linphone/view/Page/Layout/Settings"
    //: "Mon compte"
    titleText: qsTr("drawer_menu_manage_account")
	property AccountGui account
	signal accountRemoved()
	families: [
        {title: "Mon poste", layout: "AccountSettingsGeneralLayout", model: account, icon: AppIcons.manageProfile},
        // Paramètres de compte (registrar, proxy, STUN...) : réservé à l'administrateur (Ctrl+Maj+M), ces réglages
        // viennent du lien de configuration et un changement casse le compte.
        //: "Paramètres de compte"
        {title: qsTr("settings_account_title"), layout: "AccountSettingsParametersLayout", model: account,
         icon: AppIcons.settings, visible: AppCpp.adminMenus}
	]
	// Identite, en haut de la colonne de gauche : photo (changer, retirer), nom et poste. Le nom vient de l'extension
	// dans FusionPBX : c'est a l'administrateur de le regler, il n'est pas modifiable ici.
	leftHeaderComponent: Rectangle {
		implicitHeight: identityColumn.implicitHeight + 2 * identityColumn.y
		radius: Utils.getSizeWithScreenRatio(14)
		color: DefaultStyle.main2_100
		ColumnLayout {
			id: identityColumn
			x: Utils.getSizeWithScreenRatio(16)
			y: Utils.getSizeWithScreenRatio(22)
			width: parent.width - 2 * x
			spacing: 0
			Avatar {
				Layout.alignment: Qt.AlignHCenter
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(96)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(96)
				account: mainItem.account
				displayPresence: false
				shadowEnabled: false
			}
			Text {
				Layout.fillWidth: true
				Layout.topMargin: Utils.getSizeWithScreenRatio(12)
				horizontalAlignment: Text.AlignHCenter
				text: mainItem.account ? mainItem.account.core.displayName : ""
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
				text: mainItem.account ? "Poste " + UtilsCpp.getUsername(mainItem.account.core.identityAddress) : ""
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				color: DefaultStyle.main2_500_main
				elide: Text.ElideRight
			}
			SmallButton {
				Layout.alignment: Qt.AlignHCenter
				Layout.topMargin: Utils.getSizeWithScreenRatio(14)
				style: ButtonStyle.secondary
				icon.source: AppIcons.camera
				text: mainItem.account && mainItem.account.core.pictureUri.length > 0 ? "Changer la photo" : "Ajouter une photo"
				onClicked: pictureDialog.open()
			}
			SmallButton {
				Layout.alignment: Qt.AlignHCenter
				Layout.topMargin: Utils.getSizeWithScreenRatio(2)
				visible: !!mainItem.account && mainItem.account.core.pictureUri.length > 0
				style: ButtonStyle.noBackground
				text: "Retirer la photo"
				onClicked: mainItem.account.core.pictureUri = ""
			}
		}
	}
	FileDialog {
		id: pictureDialog
		currentFolder: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
		onAccepted: {
			var avatarPath = UtilsCpp.createAvatar(selectedFile)
			if (avatarPath)
				mainItem.account.core.pictureUri = avatarPath
		}
	}
	Connections {
		target: account ? account.core : null
		function onRemoved() { accountRemoved() }
	}
	onGoBackRequested: if (!account.core.isSaved) {
                           //: "Modifications non enregistrées"
        UtilsCpp.getMainWindow().showConfirmationLambdaPopup(qsTr("contact_editor_popup_abort_confirmation_title"),
                                                             //: "Vous avez des modifications non enregistrées. Si vous quittez cette page, vos changements seront perdus. Voulez-vous enregistrer vos modifications avant de continuer ?"
            qsTr("contact_editor_popup_abort_confirmation_message"),
			"",
			function (confirmed) {
				if (confirmed) {
					account.core.save()
				} else {
					account.core.undo()
				}
				mainItem.goBack()
                //: "Ne pas enregistrer"
                //: "Enregistrer"
            }, qsTr("contact_editor_dialog_abort_confirmation_do_not_save"), qsTr("contact_editor_dialog_abort_confirmation_save")
		, undefined, "warning", AppIcons.warningCircle)
	} else {mainItem.goBack()}
}
