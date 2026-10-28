import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import SettingsCpp
import UtilsCpp

AbstractSettingsMenu {
	id: mainItem
	layoutsPath: "qrc:/qt/qml/Linphone/view/Page/Layout/Settings"
    //: "Paramètres"
    titleText: qsTr("settings_title")
	families: [
        //: "Appels"
        {title: qsTr("settings_calls_title"), layout: "CallSettingsLayout", icon: AppIcons.phone},
		// Transfert d'appel : masque, Linphone enregistre le reglage mais ne l'applique pas (« TODO implement BL » dans
		// SettingsModel::setCallForwardToAddress). Les renvois se reglent dans FusionPBX.
		//: "Transfert d'appel"
        {title: qsTr("settings_call_forward"), layout: "CallForwardSettingsLayout", icon: AppIcons.transferCall,
         visible: false},
        //: "Conversations"
        {title: qsTr("settings_conversations_title"), layout: "ChatSettingsLayout", icon: AppIcons.chatTeardropText,
         visible: !SettingsCpp.disableChatFeature},
        //: "Réunions"
        // Reunions : masquees comme l'onglet de la barre laterale (les reunions Linphone demandent un serveur de
        // conference, absent avec FusionPBX).
        {title: qsTr("settings_meetings_title"), layout: "MeetingsSettingsLayout", icon: AppIcons.videoconference,
         visible: false},
        //: "Affichage"
        //{title: qsTr("settings_user_interface_title"), layout: "DisplaySettingsLayout"},
        //: "Security"
        // {title: qsTr("settings_security_title"), layout: "SecuritySettingsLayout"},
        // Réseau : la section ne contenait que « Autoriser l'IPv6 », désormais coupé pour de bon
        // (linphonerc-factory) : il empêche l'annuaire de répondre.
        // {title: qsTr("settings_network_title"), layout: "NetworkSettingsLayout"},
        //: "Paramètres avancés"
        {title: qsTr("settings_advanced_title"), layout: "AdvancedSettingsLayout", icon: AppIcons.settings},
        // Contacts (annuaires LDAP et CardDAV) : réservé à l'administrateur (Ctrl+Maj+M), l'annuaire est réglé par
        // le lien de configuration. En fin de liste : cachée, l'entrée ne laisse pas d'écart entre les autres.
        //: "Contacts"
        {title: qsTr("settings_contacts_title"), layout: "ContactsSettingsLayout", icon: AppIcons.adressBook,
         visible: AppCpp.adminMenus}
	]

	onGoBackRequested: mainItem.goBack()
	
	Component.onCompleted: {
		SettingsCpp.isSaved = true
	}
}
