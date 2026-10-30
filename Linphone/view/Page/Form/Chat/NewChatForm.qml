import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import QtQuick.Effects

import Linphone
import UtilsCpp
import SettingsCpp

CreationFormLayout {
	id: mainItem
	// Messages : seulement l'equipe (les postes internes). Les contacts sont des numeros de telephone, sans
	// messagerie : on ne peut discuter qu'avec un membre de l'equipe.
	teamMode: true

    //: Nouveau groupe
    startGroupButtonText: qsTr("chat_start_group_chat_title")
}
