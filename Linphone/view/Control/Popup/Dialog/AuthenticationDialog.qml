import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import QtQuick.Dialogs

import Linphone
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

Dialog {
	id: mainItem
	
	property string identity
	property string domain
	readonly property string password: passwordEdit.text
	property var callback// Define cb(var) function
		
	kind: "warning"
	iconSource: AppIcons.lockKey
	//: "Authentification requise"
	title: qsTr("account_settings_dialog_invalid_password_title")
	//: La connexion a échoué pour le compte %1. Vous pouvez renseigner votre mot de passe à nouveau ou bien vérifier les options de configuration de votre compte.
	text: qsTr("account_settings_dialog_invalid_password_message").arg(mainItem.identity)
	modal: true
	closePolicy: Popup.NoAutoClose
	
	onAccepted: {
		if( callback) callback.cb(password)
		close()
	}
	onRejected: close()
	Component.onDestruction: if(callback) callback.destroy()
	
	// Titre et message dans l'en-tete commun ; ici seulement le champ du mot de passe, sur toute la largeur.
	content: ColumnLayout {
		id: contentLayout
		Layout.fillWidth: true
		spacing: 0
        FormItemLayout {
            id: passwordItem
            Layout.fillWidth: true
            label: qsTr("password")
            enableErrorText: true
            mandatory: true
            contentItem: TextField {
                id: passwordEdit
                hidden: true
                width: parent.width
                isError: passwordItem.errorTextVisible
                KeyNavigation.down: cancelButton
                //: %1 mandatory
			    Accessible.name: qsTr("mandatory_field_accessible_name").arg(qsTr("password"))
            }
        }
	}

	buttons: [
		DialogButton {
			id: cancelButton
            //: "Annuler
            text: qsTr("cancel")
			style: ButtonStyle.secondary
			onClicked: mainItem.rejected()
			KeyNavigation.up: passwordEdit
			KeyNavigation.right: connectButton
		},
		DialogButton {
			id: connectButton
            //: Connexion
            text: qsTr("assistant_account_login")
			style: mainItem.actionStyle
			KeyNavigation.up: passwordEdit
			KeyNavigation.right: cancelButton
			onClicked: {
				passwordItem.errorMessage = ""
                if (passwordEdit.text.length == 0) {
                    //: Veuillez saisir un mot de passe
                    passwordItem.errorMessage = qsTr("assistant_account_login_missing_password")
					return
				}
				mainItem.accepted()
			}
		}
	]
}
