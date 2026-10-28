
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import SettingsCpp 1.0
import Linphone
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

// Général : réglages de l'application utiles à tous (le reste, technique, est dans Paramètres avancés, réservé à
// l'administrateur).
AbstractSettingsLayout {
	width: parent?.width
	contentModel: [
		{
			title: "",
			subTitle: "",
			contentComponent: startComponent
		}
	]

	onSave: {
		SettingsCpp.save()
	}
	onUndo: SettingsCpp.undo()

	Component {
		id: startComponent
		SwitchSetting {
			Layout.fillWidth: true
			titleText: "Lancer Gamaphone au démarrage de Windows"
			subTitleText: "Gamaphone s'ouvre tout seul quand vous allumez le PC : vous ne manquez aucun appel."
			propertyName: "autoStart"
			propertyOwner: SettingsCpp
		}
	}
}
