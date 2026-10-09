import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import QtQuick.Effects

import Linphone
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

FocusScope {
	id: mainItem
	property color searchBarColor: DefaultStyle.grey_100
	property color searchBarBorderColor: "transparent"
	property alias searchBar: searchBar
    property string startGroupButtonText
    property bool startGroupButtonVisible: true
	property NumericPadPopup numPadPopup
	signal groupCreationRequested()
	signal contactClicked(FriendGui contact)
	clip: true
    property alias topContent: topLayout.data
    property bool topLayoutVisible: topLayout.children.length > 0
    property int searchBarRightMaring: Utils.getSizeWithScreenRatio(39)
    // Liste des collegues seule (teamMode : onglet Equipe de la petite fenetre), ou section Equipe en tete
    // (showTeam), avant les favoris et contacts externes.
    property bool teamMode: false
    property bool showTeam: true
    // Relecture automatique tant que la liste est affichee (onglets de la petite fenetre).
    property bool autoRefresh: false
    // Petite fenetre : recherche de 36 (au lieu de 50) et lignes resserrees, titres de section plus petits.
    property bool dense: false
    // Message et telephone au bout des lignes, double-clic pour appeler (Equipe et Contacts de la petite fenetre).
    property bool showCallButton: false
    // Relit la liste (annuaire compris) sans changer la recherche.
    function refreshContacts() {
        contactList.refresh()
    }

	// Formulaire garde d'une ouverture a l'autre (page « Nouvel appel ») : sans recherche, sans
	// selection et en haut de la liste, comme un formulaire neuf.
	function reset() {
		searchBar.clearText()
		contactList.resetSelections()
		contactList.contentY = 0
	}

	ColumnLayout {
		anchors.fill: parent
        spacing: Utils.getSizeWithScreenRatio(22)
		ColumnLayout {
            id: topLayout
            visible: mainItem.topLayoutVisible
            spacing: Utils.getSizeWithScreenRatio(18)
		}

        ColumnLayout {
            onVisibleChanged: if (!visible && mainItem.numPadPopup) mainItem.numPadPopup.close()
            spacing: Utils.getSizeWithScreenRatio(mainItem.dense ? 16 : 38)
            SearchBar {
                id: searchBar
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                Layout.preferredHeight: mainItem.dense ? Utils.getSizeWithScreenRatio(36) : implicitHeight
                Layout.rightMargin: mainItem.searchBarRightMaring
                focus: true
                color: mainItem.searchBarColor
                borderColor: mainItem.searchBarBorderColor
                //: "Rechercher un contact"
                placeholderText: mainItem.teamMode ? "Rechercher un nom ou un poste" : qsTr("search_bar_look_for_contact_text")
                numericPadPopup: mainItem.numPadPopup
                KeyNavigation.down: groupCreationButton
            }
            ColumnLayout {
                id: content
                spacing: Utils.getSizeWithScreenRatio(32)
                Button {
                    id: groupCreationButton
                    visible: mainItem.startGroupButtonVisible
                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(320)
                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(44)
                    padding: 0
                    KeyNavigation.up: searchBar
                    KeyNavigation.down: contactList
                    onClicked: mainItem.groupCreationRequested()
                    background: Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: DefaultStyle.main2_100}
                            GradientStop { position: 1.0; color: DefaultStyle.grey_0}
                        }
                        // Black border for keyboard navigation
                        border.color: DefaultStyle.main2_900
                        border.width: groupCreationButton.keyboardFocus ? Utils.getSizeWithScreenRatio(3) : 0
                    }
                    Accessible.name: mainItem.startGroupButtonText
                    contentItem: RowLayout {
                        spacing: Utils.getSizeWithScreenRatio(16)
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: Utils.getSizeWithScreenRatio(44)
                            height: width
                            radius: width / 2
                            color: DefaultStyle.main1_500_main
                            EffectImage {
                                imageSource: AppIcons.usersThreeFilled
                                anchors.centerIn: parent
                                width: Utils.getSizeWithScreenRatio(24)
                                height: width
                                fillMode: Image.PreserveAspectFit
                                colorizationColor: DefaultStyle.grey_0
                            }
                        }
                        Text {
                            text: mainItem.startGroupButtonText
                            color: DefaultStyle.grey_1000
                            font {
                                pixelSize: Typography.h4.pixelSize
                                weight: Typography.h4.weight
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        EffectImage {
                            imageSource: AppIcons.rightArrow
                            Layout.preferredWidth: Utils.getSizeWithScreenRatio(24)
                            Layout.preferredHeight: Utils.getSizeWithScreenRatio(24)
                            colorizationColor: DefaultStyle.main2_500_main
                        }
                    }
                }
                AllContactListView{
                    id: contactList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    showContactMenu: false
                    // Comme dans Contacts : on ne se voit pas soi-meme (Nouvel appel, Nouvelle conversation).
                    showMe: false
                    // Collegues (postes internes) en tete, tries par statut ; puis favoris et contacts externes.
                    teamMode: mainItem.teamMode
                    showTeam: mainItem.showTeam || mainItem.teamMode
                    autoRefresh: mainItem.autoRefresh
                    dense: mainItem.dense
                    showCallButton: mainItem.showCallButton
                    sectionsPixelSize: mainItem.dense ? Utils.getSizeWithScreenRatio(14) : Typography.h4.pixelSize
                    externalOnly: true
                    // Formulaires avec pave numerique (appels) : un numero compose n'est pas une recherche.
                    exactNumberMatch: !!mainItem.numPadPopup
                    searchBarText: searchBar.text
                    onContactSelected: (contact) => {
                        mainItem.contactClicked(contact)
                    }
                }
            }
        }
    }
}
