import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control

import Linphone
import UtilsCpp
import ConstantsCpp
import SettingsCpp
import CustomControls 1.0
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

FocusScope {
    id: mainItem
    // Petite fenetre (Combiné) : photo de 45, la taille de l'onglet Appels, commune a tous ses menus (Equipe,
    // Contacts, Appels, Messages, suggestions du clavier), et texte de 14 / 12.
    property bool dense: false
    implicitHeight: visible ? Utils.getSizeWithScreenRatio(56) : 0
    property var searchResultItem
    property bool showInitials: true // Display Initials of Display name.
    property bool showDefaultAddress: true // Display address below display name.
    property bool showDisplayName: true // Display name above address.
    // Onglet Equipe : numero du poste et statut sous le nom (« 1001 · Disponible »).
    property bool showTeamStatus: false
    // Onglet Equipe : petit telephone gris toujours visible au bout de la ligne (vert seulement quand la souris est
    // dessus), et double-clic sur la ligne pour appeler. Un simple clic ouvre toujours la fiche.
    property bool showCallButton: false
    function callContact() {
        if (mainItem.searchResultItem)
            UtilsCpp.getMainWindow().startCallWithContact(mainItem.searchResultItem, false, mainItem, false)
    }
    function messageContact() {
        if (mainItem.searchResultItem)
            UtilsCpp.getMainWindow().sendMessageToContact(mainItem.searchResultItem, mainItem)
    }
    // Petite fenetre : le simple clic (choix d'action ou confirmation d'appel) attend un instant pour laisser passer un
    // eventuel double-clic, qui appelle directement. Dans la grande fenetre, le simple clic ouvre la fiche tout de suite.
    readonly property bool waitForDoubleClick: dense && showCallButton
    Timer {
        id: singleClickDelay
        interval: 250
        onTriggered: mainItem.clicked(undefined)
    }
    property bool showActions: false // Display actions layout (call buttons)
    property bool showContactMenu: true // Display the dot menu for contacts.
    property string highlightText
    // Le contact peut etre momentanement absent pendant une mise a jour de la liste : pas d'erreur dans ce cas.
    property string addressFromFilter: searchResultItem ? UtilsCpp.getAddressToDisplay(searchResultItem.core.addresses, highlightText, searchResultItem.core.defaultAddress) : ""

    // Bold characters in Display name.
    property bool displayNameCapitalization: true // Capitalize display name.

    property bool selectionEnabled: true // Contact can be selected
    property bool multiSelectionEnabled: false //Multiple items can be selected.
    property list<string> selectedContacts
    // List of default address on selected contacts.
    property bool isSelected: false // selected in list => currentIndex == index
    property bool isLastHovered: false

    property var previousInitial
    // Use directly previous initial
    property real itemsRightMargin: Utils.getSizeWithScreenRatio(39)

    property var displayName: searchResultItem? searchResultItem.core.fullName : ""
    property var initial: displayName.length > 0 ? UtilsCpp.getInitials(displayName, 1).toLocaleLowerCase(AppCpp.localeAsString) : ''

    signal clicked(var mouse)
    signal contactDeletionRequested(FriendGui contact)
    signal containsMouseChanged(bool containsMouse)
    // Clic droit sur la ligne (ContactListView) : menu du contact. friendPopup n'est pas visible depuis la liste,
    // d'ou cette fonction (le clic droit levait « friendPopup is not defined »).
    function openContactMenu() {
        if (mainItem.showContactMenu) friendPopup.open()
    }
    Accessible.name: displayName
    Accessible.role: Accessible.ListItem

    MouseArea {
        Text {
            id: initialText
            anchors.left: parent.left
            visible: mainItem.showInitials
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Utils.getSizeWithScreenRatio(15)
            verticalAlignment: Text.AlignVCenter
            width: Utils.getSizeWithScreenRatio(mainItem.dense ? 16 : 20)
            opacity: previousInitial != mainItem.initial ? 1 : 0
            text: mainItem.initial
            textFormat: Text.RichText
            color: DefaultStyle.main2_400
            font {
                pixelSize: Utils.getSizeWithScreenRatio(mainItem.dense ? 16 : 20)
                weight: Utils.getSizeWithScreenRatio(500)
                capitalization: Font.AllUppercase
            }
        }
        RowLayout {
            id: contactDelegate
            anchors.left: initialText.visible ? initialText.right : parent.left
            anchors.right: parent.right
            anchors.rightMargin: mainItem.itemsRightMargin
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: Utils.getSizeWithScreenRatio(16)
            z: contactArea.z + 1
            Avatar {
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(45)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                Layout.leftMargin: Utils.getSizeWithScreenRatio(5)
                contact: searchResultItem || null
                shadowEnabled: false
            }
            ColumnLayout {
                spacing: 0
                Text {
                    id: displayNameText
                    visible: mainItem.showDisplayName
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? implicitHeight: 0
                    text: UtilsCpp.boldTextPart(UtilsCpp.encodeEmojiToQmlRichFormat((mainItem.displayName)),
                                                mainItem.highlightText)
                    textFormat: Text.RichText
                    // Equipe : nom en 14 normal, comme Contacts et Appels (pas de gras).
                    font {
                        pixelSize: mainItem.dense ? Utils.getSizeWithScreenRatio(14)
                                   : mainItem.showDefaultAddress ? Typography.h4.pixelSize : Typography.p1.pixelSize
                        capitalization: mainItem.displayNameCapitalization ? Font.Capitalize : Font.MixedCase
                        weight: mainItem.showDefaultAddress ? Typography.h4.weight : Typography.p1.weight
                    }
                    maximumLineCount: 1
                }
                Text {
                    Layout.topMargin: Utils.getSizeWithScreenRatio(2)
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? implicitHeight: 0
                    visible: mainItem.showDefaultAddress
                    property string address: SettingsCpp.hideSipAddresses
                        ? UtilsCpp.getUsername(mainItem.addressFromFilter)
                        : mainItem.addressFromFilter
                    text: UtilsCpp.boldTextPart(address, mainItem.highlightText)
                    textFormat: Text.RichText
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    font {
                        weight: Utils.getSizeWithScreenRatio(300)
                        pixelSize: Utils.getSizeWithScreenRatio(12)
                    }
                }
                // Onglet Equipe : numero du poste en fin, puis le statut en demi-gras dans la couleur de sa pastille
                // (« 1001 · Disponible » en vert, « En communication » en bleu...) : la liste se lit d'un coup d'oeil.
                RowLayout {
                    id: teamStatusRow
                    Layout.topMargin: Utils.getSizeWithScreenRatio(2)
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? implicitHeight : 0
                    visible: mainItem.showTeamStatus && !!mainItem.searchResultItem
                    spacing: 0
                    readonly property var core: mainItem.searchResultItem ? mainItem.searchResultItem.core : null
                    readonly property string number: core ? UtilsCpp.getUsername(core.defaultAddress) : ""
                    readonly property string status: core ? core.presenceStatus : ""
                    // Couleurs lisibles sur fond blanc (le jaune de la pastille « Absent » serait trop pale).
                    readonly property color statusColor: !core ? DefaultStyle.main2_600
                        : core.inCall ? DefaultStyle.info_800_main
                        : core.presence === LinphoneEnums.Presence.Online ? DefaultStyle.success_700
                        : core.presence === LinphoneEnums.Presence.Away ? DefaultStyle.warning_700
                        : core.presence === LinphoneEnums.Presence.Busy || core.presence === LinphoneEnums.Presence.DoNotDisturb
                            ? DefaultStyle.danger_500_main
                        : DefaultStyle.main2_500_main
                    Text {
                        text: teamStatusRow.number + (teamStatusRow.status.length > 0 ? " · " : "")
                        color: DefaultStyle.main2_600
                        maximumLineCount: 1
                        font {
                            weight: Utils.getSizeWithScreenRatio(300)
                            pixelSize: Utils.getSizeWithScreenRatio(12)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: teamStatusRow.status
                        color: teamStatusRow.statusColor
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        font {
                            weight: Font.DemiBold
                            pixelSize: Utils.getSizeWithScreenRatio(12)
                        }
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
            RowLayout {
                id: actionsRow
                z: contactArea.z + 1
                visible: mainItem.showActions || actionButtons.visible || mainItem.showContactMenu || mainItem.multiSelectionEnabled
                         || mainItem.showCallButton
                spacing: visible ? Utils.getSizeWithScreenRatio(16) : 0
                enabled: visible
                Layout.rightMargin: Utils.getSizeWithScreenRatio(5)
                EffectImage {
                    id: isSelectedCheck
                    visible: mainItem.multiSelectionEnabled
                                && (mainItem.selectedContacts.indexOf(mainItem.addressFromFilter) != -1)
                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(24)
                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(24)
                    imageSource: AppIcons.check
                    colorizationColor: DefaultStyle.main1_500_main
                }
                RowLayout {
                    id: actionButtons
                    visible: mainItem.showActions
                    spacing: visible ? Utils.getSizeWithScreenRatio(10) : 0
                    IconButton {
                        id: callButton
                        Layout.preferredWidth: Utils.getSizeWithScreenRatio(45)
                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                        icon.width: Utils.getSizeWithScreenRatio(24)
                        icon.height: Utils.getSizeWithScreenRatio(24)
                        icon.source: AppIcons.phone
                        focus: visible
                        radius: Utils.getSizeWithScreenRatio(40)
                        style: ButtonStyle.grey
                        onClicked: UtilsCpp.createCall(mainItem.addressFromFilter)
                        KeyNavigation.left: chatButton
                        KeyNavigation.right: videoCallButton
                        //: "Call %1"
                        Accessible.name: qsTr("call_with_contact_name_accessible_button").arg(mainItem.displayName)
                        keyboardFocus: FocusHelper.keyboardFocus || FocusHelper.otherFocus
                    }
                    IconButton {
                        id: videoCallButton
                        visible: SettingsCpp.videoEnabled
                        Layout.preferredWidth: Utils.getSizeWithScreenRatio(45)
                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                        icon.width: Utils.getSizeWithScreenRatio(24)
                        icon.height: Utils.getSizeWithScreenRatio(24)
                        icon.source: AppIcons.videoCamera
                        focus: visible && !callButton.visible
                        radius: Utils.getSizeWithScreenRatio(40)
                        style: ButtonStyle.grey
                        onClicked: UtilsCpp.createCall(mainItem.addressFromFilter, {"localVideoEnabled": true})
                        KeyNavigation.left: callButton
                        KeyNavigation.right: chatButton
                        //: "Video call %1"
                        Accessible.name: qsTr("video_call_with_contact_name_accessible_button").arg(mainItem.displayName)
                        keyboardFocus: FocusHelper.keyboardFocus || FocusHelper.otherFocus
                    }
                    IconButton {
                        id: chatButton
                        visible: actionButtons.visible
                                    && !SettingsCpp.disableChatFeature
                        Layout.preferredWidth: Utils.getSizeWithScreenRatio(45)
                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                        icon.width: Utils.getSizeWithScreenRatio(24)
                        icon.height: Utils.getSizeWithScreenRatio(24)
                        icon.source: AppIcons.chatTeardropText
                        focus: visible && !callButton.visible
                                && !videoCallButton.visible
                        radius: Utils.getSizeWithScreenRatio(40)
                        style: ButtonStyle.grey
                        KeyNavigation.left: videoCallButton
                        KeyNavigation.right: callButton
                        onClicked: {
                            console.debug("[ContactListItem.qml] Open conversation")
                            mainWindow.displayChatPage(mainItem.addressFromFilter)
                        }
                        //: "Message %1"
                        Accessible.name: qsTr("message_with_contact_name_accessible_button").arg(mainItem.displayName)
                        keyboardFocus: FocusHelper.keyboardFocus || FocusHelper.otherFocus
                    }
                }
                // Message et appel (Equipe et Contacts) : gris au repos, pastille de couleur seulement quand la souris est sur
                // l'icone elle-meme (pas sur le reste de la ligne) : bleue pour le message, verte pour l'appel. Pas de
                // message pour un externe (numero de telephone), qui ne peut pas en recevoir.
                component RowActionButton: Item {
                    id: rowAction
                    property url iconSource
                    property color hoverColor
                    signal triggered()
                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(32)
                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(32)
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: rowActionArea.containsMouse ? rowAction.hoverColor : "transparent"
                    }
                    EffectImage {
                        anchors.centerIn: parent
                        width: Utils.getSizeWithScreenRatio(19)
                        height: width
                        imageSource: rowAction.iconSource
                        colorizationColor: rowActionArea.containsMouse ? DefaultStyle.grey_0 : DefaultStyle.main2_400
                    }
                    MouseArea {
                        id: rowActionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: rowAction.triggered()
                    }
                    Accessible.role: Accessible.Button
                }
                RowLayout {
                    id: rowActions
                    visible: mainItem.showCallButton
                    spacing: Utils.getSizeWithScreenRatio(8)
                    RowActionButton {
                        visible: !SettingsCpp.disableChatFeature && !!mainItem.searchResultItem
                                 && mainItem.searchResultItem.core.internalExtension
                        iconSource: AppIcons.chatTeardropText
                        hoverColor: DefaultStyle.main1_500_main
                        onTriggered: mainItem.messageContact()
                        //: "Message %1"
                        Accessible.name: qsTr("message_with_contact_name_accessible_button").arg(mainItem.displayName)
                    }
                    RowActionButton {
                        iconSource: AppIcons.phone
                        hoverColor: DefaultStyle.success_500_main
                        onTriggered: mainItem.callContact()
                        //: "Call %1"
                        Accessible.name: qsTr("call_with_contact_name_accessible_button").arg(mainItem.displayName)
                    }
                }
                PopupButton {
                    id: friendPopup
                    z: contactArea.z + 1
                    popup.x: 0
                    popup.padding: Utils.getSizeWithScreenRatio(10)
                    visible: mainItem.showContactMenu && (contactArea.containsMouse || mainItem.isLastHovered || hovered || popup.opened)
                    enabled: visible

                    // Menu construit a sa premiere ouverture : une ligne de contact en construisait un d'office (3 boutons)
                    // pour rien, ce qui alourdissait l'affichage et le defilement de la liste.
                    popup.onAboutToShow: contactMenuLoader.active = true
                    popup.contentItem: Loader {
                        id: contactMenuLoader
                        active: false
                        sourceComponent: ColumnLayout {
                            IconLabelButton {
                                Layout.fillWidth: true
                                visible: !!searchResultItem && searchResultItem.core.isStored
                                            && !searchResultItem.core.readOnly
                                //: "Enlever des favoris"
                                text: searchResultItem?.core.starred ? qsTr("contact_details_remove_from_favourites")
                                                                        //: "Ajouter aux favoris"
                                                                    : qsTr("contact_details_add_to_favourites")
                                icon.source: searchResultItem?.core.starred ? AppIcons.heartFill : AppIcons.heart
                                spacing: Utils.getSizeWithScreenRatio(10)
                                textColor: DefaultStyle.main2_500_main
                                hoveredImageColor: searchResultItem?.core.starred ? DefaultStyle.main1_700 : DefaultStyle.danger_700
                                contentImageColor: searchResultItem?.core.starred ? DefaultStyle.danger_500_main : DefaultStyle.main2_600
                                onClicked: {
                                    searchResultItem.core.lSetStarred(
                                                !searchResultItem.core.starred)
                                    friendPopup.close()
                                }
                                style: ButtonStyle.noBackground
                            }
                            IconLabelButton {
                                text: qsTr("Partager")
                                Layout.fillWidth: true
                                icon.source: AppIcons.shareNetwork
                                spacing: Utils.getSizeWithScreenRatio(10)
                                textColor: DefaultStyle.main2_500_main
                                onClicked: {
                                    var vcard = searchResultItem.core.getVCard()
                                    var username = searchResultItem.core.givenName
                                            + searchResultItem.core.familyName
                                    var filepath = UtilsCpp.createVCardFile(
                                                username, vcard)
                                    if (filepath == "")
                                        UtilsCpp.showInformationPopup(
                                                    qsTr("information_popup_error_title"),
                                                    //: La création du fichier vcard a échoué
                                                    qsTr("information_popup_vcard_creation_error"),
                                                    false)
                                    else
                                        //: VCard créée
                                        mainWindow.showInformationPopup(qsTr("information_popup_vcard_creation_title"),
                                                                        //: "VCard du contact enregistrée dans %1"
                                                                        qsTr("information_popup_vcard_creation_success").arg(filepath))
                                    //: Partage de contact
                                    UtilsCpp.shareByEmail(qsTr("contact_sharing_email_title"),vcard, filepath)
                                }
                                style: ButtonStyle.noBackground
                            }
                            IconLabelButton {
                                //: "Supprimer"
                                text: qsTr("contact_details_delete")
                                icon.source: AppIcons.trashCan
                                spacing: Utils.getSizeWithScreenRatio(10)
                                visible: !!searchResultItem && searchResultItem.core.isStored && !searchResultItem.core.readOnly
                                Layout.fillWidth: true
                                onClicked: {
                                    mainItem.contactDeletionRequested(searchResultItem)
                                    friendPopup.close()
                                }
                                style: ButtonStyle.noBackgroundRed
                            }
                        }
                    }
                }
            }
        }

        id: contactArea
        enabled: mainItem.selectionEnabled
        anchors.fill: parent
        //height: mainItem.height
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        focus: !actionButtons.visible
        onContainsMouseChanged: {
            mainItem.containsMouseChanged(containsMouse)
        }
        Rectangle {
            anchors.fill: contactArea
            radius: Utils.getSizeWithScreenRatio(8)
            opacity: 0.7
            color: mainItem.isSelected ? DefaultStyle.main2_200 : DefaultStyle.main2_100
            visible: mainItem.isLastHovered || mainItem.isSelected || friendPopup.hovered
        }
        Keys.onPressed: event => {
            if (event.key == Qt.Key_Space
                || event.key == Qt.Key_Enter
                || event.key == Qt.Key_Return) {
                contactArea.clicked(undefined)
                event.accepted = true
            }
        }
        onClicked: mouse => {
            forceActiveFocus()
            if (mouse && mouse.button == Qt.RightButton
                && mainItem.showContactMenu) {
                if (friendPopup) friendPopup.open()
            } else if (mainItem.waitForDoubleClick && mouse) {
                singleClickDelay.restart()
            } else {
                mainItem.clicked(mouse)
            }
        }
        // Double-clic sur la ligne = appel direct (grande fenetre : le premier clic a deja ouvert la fiche ; petite
        // fenetre : le simple clic en attente est annule).
        onDoubleClicked: mouse => {
            if (mainItem.showCallButton && (!mouse || mouse.button === Qt.LeftButton)) {
                singleClickDelay.stop()
                mainItem.callContact()
            }
        }
    }
}
