import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import EnumsToStringCpp
import SettingsCpp
import ConstantsCpp
import CustomControls 1.0
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

AbstractMainPage {
    id: mainItem
    // Onglet Equipe : meme page, limitee aux postes internes (1 a 5 chiffres) tries par statut. Sinon, page
    // Contacts : tous les autres (portables, numeros externes).
    property bool teamMode: false
    // Vide quand la creation est desactivee : AbstractMainPage masque alors le bouton.
    //: "Ajouter un contact"
    noItemButtonText: ConstantsCpp.contactCreationEnabled && !teamMode ? qsTr("contacts_add") : ""
    //: "Aucun contact pour le moment"
    emptyListText: teamMode ? "Personne dans l'équipe pour le moment" : qsTr("contacts_list_empty")
    newItemIconSource: AppIcons.plusCircle

    /**
     * Focus on the first pertinent element in the page (LINQT-2202)
     * @override
     */
    function forceActiveFocus(reason = undefined){
        if (createContactButton.visible)
            createContactButton.forceActiveFocus(reason)
        else
            searchBar.forceActiveFocus(reason)
    }

    // disable left panel contact list interaction while a contact is being edited
    property bool leftPanelEnabled: !rightPanelStackView.currentItem
                                    || rightPanelStackView.currentItem.objectName
                                    != "contactEdition"
    property FriendGui selectedContact
    // Un contact d'annuaire (LDAP) est en lecture seule : ni edition, ni favori, ni suppression.
    property bool contactEditable: selectedContact && selectedContact.core.isStored
                                   && !selectedContact.core.readOnly
    property string initialFriendToDisplay
    onInitialFriendToDisplayChanged: {
        if (initialFriendToDisplay != '' && contactList.selectContact(initialFriendToDisplay) != -1)
            initialFriendToDisplay = ""
        else if (initialFriendToDisplay != '')
            console.warn("Abstract not selected yet: ", initialFriendToDisplay)
    }

    onVisibleChanged: if (!visible) {
        rightPanelStackView.clear()
        contactList.resetSelections()
    } else {
        // La page n'est plus reconstruite a chaque changement d'onglet (MainLayout.qml).
        // C'est cette reconstruction qui relancait jusqu'ici la recherche dans l'annuaire :
        // sans elle, un contact supprime, ou ajoute directement dans le LDAP, n'apparaitrait
        // qu'a la recherche suivante. Les autres onglets n'en ont pas besoin, leurs listes
        // etant alimentees en continu par les signaux du SDK.
        // Au plus une fois toutes les 10 minutes : chaque retour sur l'onglet interrogeait l'annuaire.
        var now = Date.now()
        if (now - mainItem.lastDirectoryRefresh >= 10 * 60 * 1000) {
            mainItem.lastDirectoryRefresh = now
            contactList.refresh()
        }
    }
    property double lastDirectoryRefresh: 0
    function goToContactDetails(focusEditButton=false) {
        if (selectedContact) {
            var firstItem = rightPanelStackView.get(0)
            if (firstItem && firstItem.objectName == "contactDetail")
                // Go directly to detail
                rightPanelStackView.popToIndex(0)
            else {
                if (rightPanelStackView.depth >= 1) {
                    // Replace in background and go back to it
                    rightPanelStackView.replace(firstItem, contactDetail)
                    rightPanelStackView.popToIndex(0)
                } else {
                    // empty
                    rightPanelStackView.push(contactDetail)
                }
            }
            if(focusEditButton){
                rightPanelStackView.get(0).focusEditButton()
            }
            
        } else {
            rightPanelStackView.clear()
        }
    }
    onSelectedContactChanged: {
        // if we are editing a contact, force staying on edition page
        if (!rightPanelStackView.currentItem
            || rightPanelStackView.currentItem.objectName != "contactEdition") {
            console.log("selected contact changed, go to contact details")
            goToContactDetails()
        }
    }

    onNoItemButtonPressed: createContact("", "")

    function createContact(name, address) {
        var friendGui = Qt.createQmlObject('import Linphone
                                            FriendGui{
                                            }', mainItem)
        friendGui.core.givenName = UtilsCpp.getGivenNameFromFullName(name)
        friendGui.core.familyName = UtilsCpp.getFamilyNameFromFullName(name)
        friendGui.core.appendAddress(address)
        if (!rightPanelStackView.currentItem
                || rightPanelStackView.currentItem.objectName != "contactEdition")
            rightPanelStackView.push(contactEdition, {
                                         "contact": friendGui,
                                         //: "Nouveau contact"
                                         "title": qsTr("contact_new_title"),
                                         // "Créer"
                                         "saveButtonText": qsTr("create")
                                     })
    }

    function editContact(friendGui) {
        rightPanelStackView.push(contactEdition, {
                                     "contact": friendGui,
                                     //: "Modifier contact"
                                     "title": qsTr("contact_edit_title"),
                                     "saveButtonText": qsTr("save")
                                 })
    }

    // rightPanelStackView.initialItem: contactDetail
    showDefaultItem: rightPanelStackView.depth == 0 && !contactList.haveContacts
                     && !contactList.loading
                     && searchBar.text.length === 0

    function deleteContact(contact) {
        if (!contact)
            return
        var mainWin = UtilsCpp.getMainWindow()
        mainWin.showConfirmationLambdaPopup(
                    //: Supprimer %1 ?"
                    qsTr("contact_dialog_delete_title").arg(contact.core.fullName),
                    //: Ce contact sera définitivement supprimé.
                    qsTr("contact_dialog_delete_message"), "", function (confirmed) {
                        if (confirmed) {
                            var name = contact.core.fullName
                            contact.core.remove()
                            contactList.resetSelections()
                            UtilsCpp.showInformationPopup(
                                        //: "Contact supprimé"
                                        qsTr("contact_deleted_toast"),
                                        //: "%1 a été supprimé"
                                        qsTr("contact_deleted_message").arg(name))
                        }
                    })
    }

    Dialog {
        id: verifyDevicePopup
        property string deviceName
        property string deviceAddress
        padding: Utils.getSizeWithScreenRatio(30)
        width: Utils.getSizeWithScreenRatio(637)
        anchors.centerIn: parent
        closePolicy: Control.Popup.CloseOnEscape
        modal: true
        onAboutToHide: neverDisplayAgainCheckbox.checked = false
        //: "Augmenter la confiance"
        title: qsTr("contact_dialog_devices_trust_popup_title")
        //: "Pour augmenter le niveau de confiance vous devez appeler les différents appareils de votre contact et valider un code.
        // Vous êtes sur le point d’appeler “%1” voulez vous continuer ?"
        text: qsTr("contact_dialog_devices_trust_popup_message").arg(verifyDevicePopup.deviceName)
        buttons: RowLayout {
            RowLayout {
                spacing: Utils.getSizeWithScreenRatio(7)
                CheckBox {
                    id: neverDisplayAgainCheckbox
                }
                Text {
                    //: Ne plus afficher
                    text: qsTr("popup_do_not_show_again")
                    font.pixelSize: Utils.getSizeWithScreenRatio(14)
                    MouseArea {
                        anchors.fill: parent
                        onClicked: neverDisplayAgainCheckbox.toggle()
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
            RowLayout {
                spacing: Utils.getSizeWithScreenRatio(15)
                BigButton {
                    style: ButtonStyle.secondary
                    text: qsTr("cancel")
                    onClicked: verifyDevicePopup.close()
                }
                BigButton {
                    style: ButtonStyle.main
                    //: "Appeler"
                    text: qsTr("dialog_call")
                    onClicked: {
                        SettingsCpp.setDisplayDeviceCheckConfirmation(
                                    !neverDisplayAgainCheckbox.checked)
                        UtilsCpp.createCall(verifyDevicePopup.deviceAddress,
                                            {},
                                            LinphoneEnums.MediaEncryption.Zrtp)
                        onClicked: verifyDevicePopup.close()
                    }
                }
            }
        }
    }
    Dialog {
        id: trustInfoDialog
        width: Utils.getSizeWithScreenRatio(637)
        //: "Niveau de confiance"
        title: qsTr("contact_dialog_devices_trust_help_title")
        //: "Vérifiez les appareils de votre contact pour confirmer que vos communications seront sécurisées et sans compromission. <br>Quand tous seront vérifiés, vous atteindrez le niveau de confiance maximal."
        text: qsTr("contact_dialog_devices_trust_help_message")
        content: RowLayout {
            spacing: Utils.getSizeWithScreenRatio(50)
            Avatar {
                displayNameVal: "A C"
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(45)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
            }
            EffectImage {
                imageSource: AppIcons.arrowRight
                colorizationColor: DefaultStyle.main2_600
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(45)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
            }
            Avatar {
                displayNameVal: "A C"
                secured: true
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(45)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
            }
        }
        buttons: Button {
            //: "Ok"
            text: qsTr("dialog_ok")
            style: ButtonStyle.main
            leftPadding: Utils.getSizeWithScreenRatio(30)
            rightPadding: Utils.getSizeWithScreenRatio(30)
            onClicked: trustInfoDialog.close()
        }
    }

    leftPanelContent: FocusScope {
        id: leftPanel
        property real leftMargin: Utils.getSizeWithScreenRatio(45)
        property real rightMargin: Utils.getSizeWithScreenRatio(39)
        Layout.fillHeight: true
        Layout.fillWidth: true

        RowLayout {
            id: title
            // direction: FlexboxLayout.Row
            spacing: Utils.getSizeWithScreenRatio(16)
            // alignItems: FlexboxLayout.AlignCenter
            anchors.top: leftPanel.top
            anchors.right: leftPanel.right
            anchors.left: leftPanel.left
            anchors.leftMargin: leftPanel.leftMargin
            anchors.rightMargin: leftPanel.rightMargin
            Layout.fillHeight: false
            Text {
                Layout.fillWidth: true
                //: "Contacts"
                text: mainItem.teamMode ? "Équipe" : qsTr("bottom_navigation_contacts_label")
                maximumLineCount: 1
                color: DefaultStyle.main2_700
                font.pixelSize: Typography.h2.pixelSize
                font.weight: Typography.h2.weight
            }
            Button {
                id: createContactButton
                // Mis de cote (ConstantsCpp.contactCreationEnabled) : les contacts viennent de l'annuaire.
                visible: ConstantsCpp.contactCreationEnabled && !mainItem.teamMode
                         && (!rightPanelStackView.currentItem
                             || rightPanelStackView.currentItem.objectName !== "contactEdition")
                style: ButtonStyle.noBackground
                focus: true
                icon.source: AppIcons.plusCircle
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(28)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(28)
                icon.width: Utils.getSizeWithScreenRatio(28)
                icon.height: Utils.getSizeWithScreenRatio(28)
                onClicked: {
                    mainItem.createContact("", "")
                }
                KeyNavigation.down: searchBar
                //: Create new contact
                Accessible.name: qsTr("create_contact_accessible_name")
            }
        }

        ColumnLayout {
            anchors.top: title.bottom
            anchors.right: leftPanel.right
            anchors.left: leftPanel.left
            anchors.leftMargin: leftPanel.leftMargin
            anchors.bottom: leftPanel.bottom
            enabled: mainItem.leftPanelEnabled
            spacing: Utils.getSizeWithScreenRatio(38)
            SearchBar {
                id: searchBar
                visible: contactList.haveContacts || text.length !== 0
                Layout.rightMargin: leftPanel.rightMargin
                Layout.topMargin: Utils.getSizeWithScreenRatio(18)
                Layout.fillWidth: true
                //: Rechercher un contact
                placeholderText: mainItem.teamMode ? "Rechercher un nom ou un poste" : qsTr("search_bar_look_for_contact_text")
                KeyNavigation.up: createContactButton
                KeyNavigation.down: contactList
            }
            ColumnLayout {
                id: content
                spacing: Utils.getSizeWithScreenRatio(15)
                Text {
                    visible: !contactList.loading && !contactList.haveContacts
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Utils.getSizeWithScreenRatio(137)
                    //: Aucun résultat…
                    text: searchBar.text.length !== 0 ? qsTr("list_filter_no_result_found")
                                                      //: Aucun contact pour le moment
                                                      : mainItem.teamMode ? "Personne dans l'équipe pour le moment"
                                                                          : qsTr("contact_list_empty")
                    font {
                        pixelSize: Typography.h4.pixelSize
                        weight: Typography.h4.weight
                    }
                }
                AllContactListView {
                    id: contactList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.rightMargin: Utils.getSizeWithScreenRatio(8)
                    searchBarText: searchBar.text
                    hideSuggestions: true
                    // Postes internes dans l'onglet Equipe, les autres ici.
                    teamMode: mainItem.teamMode
                    externalOnly: !mainItem.teamMode
                    // Equipe et Contacts : petit telephone gris sur chaque ligne (vert sous la souris) et double-clic pour
                    // appeler directement ; un simple clic ouvre la fiche.
                    showCallButton: true
                    autoRefresh: true
                    showMe: false // ne pas afficher son propre compte SIP dans la liste des contacts
                    sourceFlags: LinphoneEnums.MagicSearchSource.Friends
                                 | LinphoneEnums.MagicSearchSource.FavoriteFriends
                                 | LinphoneEnums.MagicSearchSource.LdapServers
                                 | LinphoneEnums.MagicSearchSource.RemoteCardDAV
                    onHighlightedContactChanged: mainItem.selectedContact = highlightedContact
                    onContactDeletionRequested: contact => {
                        mainItem.deleteContact(contact)
                    }
                    onLoadingChanged: {
                        if (!loading && initialFriendToDisplay.length !== 0) {
                            Qt.callLater(function () {
                                if (selectContact(initialFriendToDisplay) != -1)
                                    initialFriendToDisplay = ""
                            })
                        }
                    }
                }
            }
        }
    }

    Component {
        id: contactDetail
        Item {
            objectName: "contactDetail"
            width: parent?.width
            height: parent?.height

            function focusEditButton(){
                contactDetail.button.forceActiveFocus(Qt.TabFocusReason)
            }
            component ContactDetailLayout: ColumnLayout {
                id: contactDetailLayout
                spacing: Utils.getSizeWithScreenRatio(15)
                property string label
                property var icon
                property alias content: contentControl.contentItem
                signal titleIconClicked
                RowLayout {
                    spacing: Utils.getSizeWithScreenRatio(10)
                    Text {
                        text: contactDetailLayout.label
                        // Noir neutre plutot que la couleur du theme : en bleu, le titre de section
                        // passait pour un lien.
                        color: DefaultStyle.grey_600
                        font {
                            pixelSize: Typography.h4.pixelSize
                            weight: Typography.h4.weight
                        }
                    }
                    RoundButton {
                        visible: contactDetailLayout.icon != undefined
                        icon.source: contactDetailLayout.icon
                        style: ButtonStyle.noBackgroundOrange
                        onClicked: contactDetailLayout.titleIconClicked()
                        //: More info %1
                        Accessible.name: qsTr("more_info_accessible_name").arg(contactDetailLayout.label)
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    RoundButton {
                        id: expandButton
                        style: ButtonStyle.noBackground
                        checkable: true
                        checked: true
                        icon.source: checked ? AppIcons.upArrow : AppIcons.downArrow
                        KeyNavigation.down: contentControl
                        Accessible.name: (checked ?
                            //: Shrink %1
                            qsTr("shrink_accessible_name"):
                            //: Expand %1
                            qsTr("expand_accessible_name")).arg(contactDetailLayout.label)

                    }
                }
                RoundedPane {
                    id: contentControl
                    visible: expandButton.checked
                    Layout.fillWidth: true
                    leftPadding: Utils.getSizeWithScreenRatio(20)
                    rightPadding: Utils.getSizeWithScreenRatio(20)
                    topPadding: Utils.getSizeWithScreenRatio(17)
                    bottomPadding: Utils.getSizeWithScreenRatio(17)
                }
            }
            ContactLayout {
                id: contactDetail
                anchors.fill: parent
                contact: mainItem.selectedContact
                button.color: DefaultStyle.main1_100
                //: Edit
                button.text: qsTr("contact_details_edit")
                button.style: ButtonStyle.tertiary
                button.icon.source: AppIcons.pencil
                button.onClicked: mainItem.editContact(mainItem.selectedContact)
                button.visible: mainItem.selectedContact && mainItem.selectedContact.core.isStored && !mainItem.selectedContact.core.readOnly
                property string contactAddress: contact ? contact.core.defaultAddress : ""
                // Cle de recherche dans l'historique : l'adresse SIP complete (un poste « 878 » ne doit pas ramener
                // « 0878… »), ou, pour un contact qui n'a qu'un numero de telephone, ce numero sans separateurs.
                property string historyKey: contactAddress.length > 0 ? contactAddress
                    : contact && contact.core.phoneNumbers.length > 0
                        ? String(contact.core.phoneNumbers[0].address).replace(/[^0-9+]/g, "") : ""
                property var computedContactNameObj: UtilsCpp.getDisplayName(contactAddress)
                property string computedContactName: computedContactNameObj ? computedContactNameObj.value : ""
                property string contactName: contact ? contact.core.fullName : computedContactName

                // --- Numeros et adresses du contact ------------------------------------
                // Places ici plutot que dans la section Coordonnees : l'en-tete (bannerContent)
                // et le contenu doivent tous deux y acceder.
                //
                // Adresse SIP et telephone portent souvent le meme numero : sip:222@domaine d'un
                // cote, 222 de l'autre, chacun avec son bouton d'appel. On ne garde en tete que ce
                // qui sert a joindre la personne ; l'URI rejoint les details techniques.
                property var allContactEntries: contact
                    ? UtilsCpp.append(contact.core.addresses, contact.core.phoneNumbers)
                    : []
                function splitContactEntries(entries, wantTechnical) {
                    var phones = []
                    for (var i = 0; i < entries.length; ++i) {
                        var addr = String(entries[i].address)
                        if (addr.indexOf("sip:") !== 0) phones.push(addr)
                    }
                    var out = []
                    for (var j = 0; j < entries.length; ++j) {
                        var a = String(entries[j].address)
                        var redundant = a.indexOf("sip:") === 0
                                        && phones.indexOf(UtilsCpp.getUsername(a)) !== -1
                        if (redundant === wantTechnical) out.push(entries[j])
                    }
                    return out
                }
                property var primaryEntries: splitContactEntries(allContactEntries, false)

                // Un numero court est un poste interne du PBX, pas un telephone : « 222 » n'a
                // rien d'un numero qu'on compose depuis l'exterieur.
                function isExtension(value) {
                    var v = String(value)
                    return v.indexOf("sip:") !== 0 && /^[0-9]{1,5}$/.test(v.replace(/[^0-9]/g, ""))
                }
                function numberLabel(value, fallback) {
                    //: "Poste"
                    return isExtension(value) ? qsTr("contact_details_extension_label") : fallback
                }
                // Un numero francais se lit par paires. On ne formate que ce qui en est un -- dix
                // chiffres commencant par 0 : un poste (1000, 222) ou un numero international garde
                // sa forme, decouper « 1000 » en « 10 00 » n'aiderait personne.
                function formatContactValue(value) {
                    var v = String(value)
                    if (v.indexOf("sip:") === 0) return v
                    var digits = v.replace(/[^0-9]/g, "")
                    if (/^0[0-9]{9}$/.test(digits))
                        return digits.replace(/([0-9]{2})(?=[0-9])/g, "$1 ")
                    return v
                }
                // Le numero mis en avant dans l'en-tete : le premier moyen de joindre la personne.
                property var headerEntry: primaryEntries.length > 0 ? primaryEntries[0] : null
                // L'en-tete est l'identite, pas le detail technique : pour une adresse SIP on n'y
                // montre que le nom d'utilisateur, l'URI complete restant dans les details.
                property string headerNumber: headerEntry
                    ? formatContactValue(String(headerEntry.address).indexOf("sip:") === 0
                                         ? UtilsCpp.getUsername(headerEntry.address)
                                         : headerEntry.address)
                    : ""
                // Actions dans l'en-tete, a droite du nom : identite et moyens de joindre la personne tiennent sur
                // une ligne, et la bande vide a droite du nom sert enfin. L'appel est l'action principale.
                // Trois boutons de meme largeur, icone et texte. Un externe (numero de telephone) n'a que l'appel :
                // ni messagerie ni video possibles avec lui.
                component HeaderActions: RowLayout {
                    id: headerActions
                    spacing: Utils.getSizeWithScreenRatio(10)
                    readonly property real buttonWidth: Utils.getSizeWithScreenRatio(150)
                    readonly property bool internal: !!contactDetail.contact && contactDetail.contact.core.internalExtension
                    MediumButton {
                        Layout.preferredWidth: headerActions.buttonWidth
                        style: ButtonStyle.main
                        icon.source: AppIcons.phone
                        //: "Appel"
                        text: qsTr("contact_call_action")
                        onClicked: mainWindow.startCallWithContact(contactDetail.contact, false, mainItem, false)
                    }
                    MediumButton {
                        visible: !SettingsCpp.disableChatFeature && headerActions.internal
                        Layout.preferredWidth: headerActions.buttonWidth
                        style: ButtonStyle.secondary
                        icon.source: AppIcons.chatTeardropText
                        //: "Message"
                        text: qsTr("contact_message_action")
                        onClicked: mainWindow.sendMessageToContact(contactDetail.contact)
                    }
                    MediumButton {
                        visible: SettingsCpp.videoEnabled && headerActions.internal
                        Layout.preferredWidth: headerActions.buttonWidth
                        style: ButtonStyle.secondary
                        icon.source: AppIcons.videoCamera
                        //: "Appel vidéo"
                        text: qsTr("contact_video_call_action")
                        onClicked: mainWindow.startCallWithContact(contactDetail.contact, true, mainItem, false)
                    }
                }
                bannerContent: [
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: UtilsCpp.encodeEmojiToQmlRichFormat(contactDetail.contactName)
                            textFormat: Text.RichText
                            Layout.fillWidth: true
                            maximumLineCount: 1
                            font {
                                pixelSize: Typography.h2.pixelSize
                                weight: Typography.h2.weight
                                capitalization: Font.Capitalize
                            }
                        }
                        Text {
                            visible: contactDetail.contact
                            horizontalAlignment: Text.AlignLeft
                            Layout.fillWidth: true
                            text: contactDetail.contact ? contactDetail.contact.core.presenceStatus : ""
                            color: contactDetail.contact ? contactDetail.contact.core.presenceColor : 'transparent'
                            font.pixelSize: Utils.getSizeWithScreenRatio(14)
                        }
                        Text {
                            // Note de presence, sans libelle : on est sous le nom de la personne,
                            // le contexte suffit a dire que ces mots sont les siens. Un intitule
                            // entrerait en plus en collision avec le bouton « Message » voisin.
                            // Les notes generees par le serveur sont ecartees en amont, dans
                            // FriendCore::setPresence().
                            visible: text.length > 0
                            horizontalAlignment: Text.AlignLeft
                            Layout.fillWidth: true
                            Layout.topMargin: Utils.getSizeWithScreenRatio(3)
                            text: contactDetail.contact ? contactDetail.contact.core.presenceNote : ""
                            color: DefaultStyle.main2_600
                            font.pixelSize: Utils.getSizeWithScreenRatio(13)
                            font.italic: true
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            // Le poste fait partie de l'identite : il rejoint le nom, l'etat et la
                            // note. La carte Coordonnees ne s'affiche plus pour un seul numero.
                            visible: contactDetail.headerNumber.length > 0
                            Layout.topMargin: Utils.getSizeWithScreenRatio(4)
                            spacing: Utils.getSizeWithScreenRatio(6)
                            Text {
                                text: contactDetail.headerEntry
                                      ? contactDetail.numberLabel(contactDetail.headerNumber,
                                                                  contactDetail.headerEntry.label)
                                      : ""
                                color: DefaultStyle.main2_500_main
                                font.pixelSize: Utils.getSizeWithScreenRatio(13)
                            }
                            Text {
                                text: contactDetail.headerNumber
                                color: DefaultStyle.main2_700
                                font.pixelSize: Utils.getSizeWithScreenRatio(13)
                                font.weight: Font.DemiBold
                            }
                        }
                    },
                    HeaderActions {
                        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    }
                ]
                content: Flickable {
                    id: contactDetailFlickable
                    contentWidth: parent.width
                    Connections {
                        target: FocusNavigator

                        function onFocusChanged(item, keyboardFocus) {
                            if(Utils.isDescendant(item,contactDetailFlickable) && keyboardFocus){
                                Utils.ensureVisibleY(item, contactDetailFlickable)
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: Utils.getSizeWithScreenRatio(32)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        ColumnLayout {
                            spacing: Utils.getSizeWithScreenRatio(15)
                            Layout.fillWidth: true
                            ContactDetailLayout {
                                id: infoLayout
                                Layout.fillWidth: true
                                // Un seul numero est deja affiche dans l'en-tete : une carte entiere,
                                // titre compris, pour le repeter n'apporterait rien.
                                visible: contactDetail.primaryEntries.length > 1
                                //: "Coordonnées"
                                label: qsTr("contact_details_numbers_and_addresses_title")
                                content: ListView {
                                    id: addrList
                                    height: contentHeight
                                    implicitHeight: contentHeight
                                    width: parent.width
                                    clip: true
                                    spacing: Utils.getSizeWithScreenRatio(9)
                                    model: VariantList {
                                        model: contactDetail.primaryEntries
                                    }
                                    delegate: Item {
                                        property var listViewModelData: modelData
                                        width: addrList.width
                                        height: Utils.getSizeWithScreenRatio(46)

                                        ColumnLayout {
                                            anchors.fill: parent
                                            // anchors.topMargin: Utils.getSizeWithScreenRatio(5)
                                            RowLayout {
                                                Layout.fillWidth: true
                                                // Layout.fillHeight: true
                                                // Layout.alignment: Qt.AlignVCenter
                                                // Layout.topMargin: Utils.getSizeWithScreenRatio(10)
                                                // Layout.bottomMargin: Utils.getSizeWithScreenRatio(10)
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: contactDetail.numberLabel(listViewModelData.address,
                                                                                        listViewModelData.label)
                                                        font {
                                                            pixelSize: Typography.p2.pixelSize
                                                            weight: Typography.p2.weight
                                                        }
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        property string _text: listViewModelData.address
                                                        text: contactDetail.formatContactValue(
                                                                  SettingsCpp.hideSipAddresses
                                                                  ? UtilsCpp.getUsername(_text)
                                                                  : _text)
                                                        font {
                                                            pixelSize: Typography.p1.pixelSize
                                                            weight: Typography.p1.weight
                                                        }
                                                    }
                                                }
                                                Item {
                                                    Layout.fillWidth: true
                                                }
                                                RoundButton {
                                                    style: ButtonStyle.noBackground
                                                    icon.source: AppIcons.phone
                                                    onClicked: {
                                                        UtilsCpp.createCall(
                                                                    listViewModelData.address)
                                                    }
                                                    //: Call address %1
                                                    Accessible.name: qsTr("call_adress_accessible_name").arg(listViewModelData.address)
                                                }
                                            }

                                            Rectangle {
                                                visible: index != addrList.model.count - 1
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
                                                Layout.rightMargin: Utils.getSizeWithScreenRatio(3)
                                                Layout.leftMargin: Utils.getSizeWithScreenRatio(3)
                                                color: DefaultStyle.main2_200
                                                clip: true
                                            }
                                        }
                                    }
                                }
                            }
                            RoundedPane {
                                visible: infoLayout.visible
                                         && companyText.text.length != 0
                                         || jobText.text.length != 0
                                Layout.fillWidth: true
                                topPadding: Utils.getSizeWithScreenRatio(17)
                                bottomPadding: Utils.getSizeWithScreenRatio(17)
                                leftPadding: Utils.getSizeWithScreenRatio(20)
                                rightPadding: Utils.getSizeWithScreenRatio(20)

                                contentItem: ColumnLayout {
                                    RowLayout {
                                        height: Utils.getSizeWithScreenRatio(50)
                                        visible: companyText.text.length != 0
                                        Text {
                                            //: "Société :"
                                            text: qsTr("contact_details_company_name")
                                            font {
                                                pixelSize: Typography.p2.pixelSize
                                                weight: Typography.p2.weight
                                            }
                                        }
                                        Text {
                                            id: companyText
                                            text: mainItem.selectedContact
                                                  && mainItem.selectedContact.core.organization
                                            font {
                                                pixelSize: Typography.p1.pixelSize
                                                weight: Typography.p1.weight
                                            }
                                        }
                                    }
                                    RowLayout {
                                        height: Utils.getSizeWithScreenRatio(50)
                                        visible: jobText.text.length != 0
                                        Text {
                                            //: "Poste :"
                                            text: qsTr("contact_details_job_title")
                                            font {
                                                pixelSize: Typography.p2.pixelSize
                                                weight: Typography.p2.weight
                                            }
                                        }
                                        Text {
                                            id: jobText
                                            text: mainItem.selectedContact
                                                  && mainItem.selectedContact.core.job
                                            font {
                                                pixelSize: Typography.p1.pixelSize
                                                weight: Typography.p1.weight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // Derniers appels avec cette personne (les 3 plus recents), lus dans l'historique commun.
                        // « Voir tout » ouvre l'onglet Appels filtre sur son numero.
                        ContactDetailLayout {
                            id: recentCallsLayout
                            Layout.fillWidth: true
                            visible: contactDetail.historyKey.length > 0 && recentCallsProxy.count > 0
                            label: "Derniers appels"
                            property CallHistoryProxy proxy: CallHistoryProxy {
                                id: recentCallsProxy
                                filterText: contactDetail.historyKey.length > 0 ? contactDetail.historyKey : "-"
                                initialDisplayItems: 3
                            }
                            content: ColumnLayout {
                                spacing: 0
                                Repeater {
                                    model: recentCallsProxy
                                    delegate: Item {
                                        id: recentCall
                                        readonly property var callCore: modelData ? modelData.core : null
                                        readonly property bool notConnected: callCore
                                            && (callCore.status === LinphoneEnums.CallStatus.Declined
                                                || callCore.status === LinphoneEnums.CallStatus.DeclinedElsewhere
                                                || callCore.status === LinphoneEnums.CallStatus.Aborted
                                                || callCore.status === LinphoneEnums.CallStatus.EarlyAborted)
                                        readonly property bool missed: callCore && callCore.status === LinphoneEnums.CallStatus.Missed
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(46)
                                        // Meme disposition que la liste de l'onglet Appels : fleche et libelle sur une ligne, date
                                        // dessous, duree a droite.
                                        RowLayout {
                                            anchors.fill: parent
                                            ColumnLayout {
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 0
                                                RowLayout {
                                                    // Memes icones et couleurs que l'onglet Appels.
                                                    EffectImage {
                                                        id: recentCallIcon
                                                        Layout.preferredWidth: Utils.getSizeWithScreenRatio(16)
                                                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(16)
                                                        imageSource: recentCall.notConnected ? AppIcons.arrowElbow
                                                            : recentCall.callCore && recentCall.callCore.isOutgoing ? AppIcons.arrowUpRight : AppIcons.arrowDownLeft
                                                        colorizationColor: recentCall.notConnected || recentCall.missed ? DefaultStyle.danger_500_main
                                                            : recentCall.callCore && recentCall.callCore.isOutgoing ? DefaultStyle.info_500_main : DefaultStyle.success_500_main
                                                        transform: Rotation {
                                                            angle: recentCall.notConnected && recentCall.callCore && recentCall.callCore.isOutgoing ? 180 : 0
                                                            origin.x: recentCallIcon.width / 2
                                                            origin.y: recentCallIcon.height / 2
                                                        }
                                                    }
                                                    Text {
                                                        // Libelles en clair : ceux de l'onglet Appels sont traduits pour cette page-la seulement
                                                        // (« call_outgoing » s'affichait tel quel ici).
                                                        text: recentCall.missed ? "Appel manqué"
                                                            : recentCall.callCore && recentCall.callCore.isOutgoing ? "Appel sortant" : "Appel entrant"
                                                        color: DefaultStyle.main2_700
                                                        font.pixelSize: Typography.p1.pixelSize
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                                Text {
                                                    text: recentCall.callCore ? UtilsCpp.formatDate(recentCall.callCore.date) : ""
                                                    color: recentCall.missed ? DefaultStyle.danger_500_main : DefaultStyle.main2_500_main
                                                    font.pixelSize: Utils.getSizeWithScreenRatio(12)
                                                }
                                            }
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                            }
                                            // Duree de l'appel, ou « Sans reponse » pour un appel qui n'a pas abouti.
                                            Text {
                                                readonly property bool answered: !!recentCall.callCore && recentCall.callCore.duration > 0
                                                text: answered ? UtilsCpp.formatElapsedTime(recentCall.callCore.duration, false) : "Sans réponse"
                                                color: answered ? DefaultStyle.main2_600 : DefaultStyle.main2_400
                                                font.pixelSize: Utils.getSizeWithScreenRatio(12)
                                            }
                                        }
                                        Rectangle {
                                            visible: index < recentCallsProxy.count - 1
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: Utils.getSizeWithScreenRatio(1)
                                            color: DefaultStyle.main2_200
                                        }
                                    }
                                }
                                Text {
                                    visible: recentCallsProxy.haveMore
                                    Layout.alignment: Qt.AlignRight
                                    Layout.topMargin: Utils.getSizeWithScreenRatio(6)
                                    text: "Voir tout"
                                    color: DefaultStyle.main1_500_main
                                    font.pixelSize: Utils.getSizeWithScreenRatio(13)
                                    font.underline: seeAllArea.containsMouse
                                    MouseArea {
                                        id: seeAllArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainWindow.goToCallHistoryFor(UtilsCpp.getUsername(contactDetail.historyKey))
                                    }
                                }
                            }
                        }
                        ContactDetailLayout {
                            // Echanges de la messagerie : rien a montrer pour un externe.
                            visible: !SettingsCpp.disableChatFeature && !!contactDetail.contact
                                     && contactDetail.contact.core.internalExtension
                            //: "Medias & documents"
                            label: qsTr("contact_details_medias_and_documents_title")
                            Layout.fillWidth: true
                            content: RowLayout {
                                // Deux tuiles cote a cote plutot que deux lignes avec chevron et
                                // separateur : meme acces, moitie moins de hauteur.
                                spacing: Utils.getSizeWithScreenRatio(10)
                                // Memes boutons que « Partager » (IconLabelButton) : meme taille d'icone, meme
                                // ecart icone-libelle, meme style. Les tuiles reimplementaient ce rendu a la main
                                // avec d'autres mesures (icone 22 au lieu de 24, ecart 10 au lieu de 5) : icones
                                // et libelles ne tombaient pas dans la meme colonne.
                                IconLabelButton {
                                    // Largeur preferee nulle : les deux tuiles se partagent la place a parts
                                    // egales, quelle que soit la longueur de leur libelle.
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    style: ButtonStyle.noBackground
                                    icon.source: AppIcons.photo
                                    //: "Médias"
                                    text: qsTr("contact_details_medias_tile")
                                    onClicked: {
                                        rightPanelStackView.push(contactSharedFiles, {
                                         "filter": ChatMessageFileProxy.FilterContentType.Medias})
                                    }
                                    Accessible.name: qsTr("contact_details_medias_subtitle")
                                }
                                Rectangle {
                                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(1)
                                    Layout.fillHeight: true
                                    color: DefaultStyle.main2_200
                                }
                                IconLabelButton {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    style: ButtonStyle.noBackground
                                    icon.source: AppIcons.pdf
                                    //: "Documents"
                                    text: qsTr("contact_details_documents_tile")
                                    onClicked: {
                                        rightPanelStackView.push(contactSharedFiles, {
                                         "filter": ChatMessageFileProxy.FilterContentType.Documents})
                                    }
                                    Accessible.name: qsTr("contact_details_documents_subtitle")
                                }
                            }
                        }
                        ContactDetailLayout {
                            Layout.fillWidth: true
                            // Liste les appareils verifies pour le chiffrement de bout en bout. Sans
                            // appareil elle n'afficherait que « Aucun appareil » : on la masque, en
                            // laissant la porte ouverte si le chiffrement est active un jour.
                            visible: mainItem.selectedContact
                                     ? mainItem.selectedContact.core.devices.length > 0
                                     : false
                            //: "Confiance"
                            label: qsTr("contact_details_trust_title")
                            icon: AppIcons.question
                            onTitleIconClicked: trustInfoDialog.open()
                            content: ColumnLayout {
                                spacing: Utils.getSizeWithScreenRatio(13)
                                Text {
                                    //: "Niveau de confiance - Appareils vérifiés"
                                    text: qsTr("contact_dialog_devices_trust_title")
                                    font {
                                        pixelSize: Typography.p2.pixelSize
                                        weight: Typography.p2.weight
                                    }
                                }
                                Text {
                                    visible: deviceList.count === 0
                                    //: "Aucun appareil"
                                    text: qsTr("contact_details_no_device_found")
                                }
                                ProgressBar {
                                    visible: deviceList.count > 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(28)
                                    value: mainItem.selectedContact ? mainItem.selectedContact.core.verifiedDeviceCount / deviceList.count : 0
                                }
                                ListView {
                                    id: deviceList
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.min(
                                                               Utils.getSizeWithScreenRatio(200),
                                                                contentHeight)
                                    clip: true
                                    model: mainItem.selectedContact ? mainItem.selectedContact.core.devices : []
                                    spacing: Utils.getSizeWithScreenRatio(16)
                                    delegate: RowLayout {
                                        id: deviceDelegate
                                        width: deviceList.width
                                        height: Utils.getSizeWithScreenRatio(30)
                                        property var listViewModelData: modelData
                                        property var callObj
                                        property CallGui deviceCall: callObj ? callObj.value : null
                                        //: "Appareil inconnu"
                                        property string deviceName: listViewModelData.name.length != 0 ? listViewModelData.name : qsTr("contact_device_without_name")
                                        Text {
                                            text: deviceDelegate.deviceName
                                            font.pixelSize: Utils.getSizeWithScreenRatio(14)
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                        }
                                        EffectImage {
                                            visible: listViewModelData.securityLevel === LinphoneEnums.SecurityLevel.EndToEndEncryptedAndVerified
                                            imageSource: AppIcons.trusted
                                            Layout.preferredWidth: Utils.getSizeWithScreenRatio(22)
                                            Layout.preferredHeight: Utils.getSizeWithScreenRatio(22)
                                        }

                                        SmallButton {
                                            onKeyboardFocusChanged: {
                                                if (keyboardFocus) Utils.ensureVisibleY(this, deviceList)
                                            }
                                            // Layout.preferredHeight: Utils.getSizeWithScreenRatio(30)
                                            visible: listViewModelData.securityLevel != LinphoneEnums.SecurityLevel.EndToEndEncryptedAndVerified
                                            icon.source: AppIcons.warningCircle
                                            style: ButtonStyle.tertiary
                                            //: "Vérifier"
                                            text: qsTr("contact_make_call_check_device_trust")
                                            //: Verify %1 device
                                            Accessible.name: qsTr("verify_device_accessible_name").arg(deviceDelegate.deviceName)
                                            onClicked: {
                                                if (SettingsCpp.getDisplayDeviceCheckConfirmation(
                                                            )) {
                                                    verifyDevicePopup.deviceName
                                                            = deviceDelegate.deviceName
                                                    verifyDevicePopup.deviceAddress
                                                            = listViewModelData.address
                                                    verifyDevicePopup.open()
                                                } else {
                                                    UtilsCpp.createCall(
                                                                listViewModelData.address,
                                                                {},
                                                                LinphoneEnums.MediaEncryption.Zrtp)
                                                    parent.callObj = UtilsCpp.getCallByAddress(
                                                                listViewModelData.address)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        ContactDetailLayout {
                            Layout.fillWidth: true
                            // Reservee aux contacts locaux. Pour un contact d'annuaire elle ne
                            // contiendrait que « Partager » : une section entiere pour un bouton.
                            visible: mainItem.contactEditable
                            //: "Autres actions"
                            label: qsTr("contact_details_actions_title")
                            content: ColumnLayout {
                                spacing: Utils.getSizeWithScreenRatio(10)
                                // « Éditer » retire : il doublonnait le bouton « Modifier » de l'en-tete.
                                ColumnLayout {
                                    visible: mainItem.selectedContact && mainItem.selectedContact.core.isStored && !mainItem.selectedContact.core.readOnly
                                    IconLabelButton {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(50)
                                        icon.source: mainItem.selectedContact
                                                    && mainItem.selectedContact.core.starred ? AppIcons.heartFill : AppIcons.heart
                                        text: mainItem.selectedContact
                                            && mainItem.selectedContact.core.starred
                                            //: "Retirer des favoris"
                                            ? qsTr("contact_details_remove_from_favourites")
                                            //: "Ajouter aux favoris"
                                            : qsTr("contact_details_add_to_favourites")
                                        style: ButtonStyle.noBackground
                                        onClicked: if (mainItem.selectedContact)
                                                    mainItem.selectedContact.core.lSetStarred(
                                                                !mainItem.selectedContact.core.starred)
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
                                        color: DefaultStyle.main2_200
                                    }
                                }
                                // IconLabelButton {
                                // 	Layout.fillWidth: true
                                // 	Layout.preferredHeight: Utils.getSizeWithScreenRatio(50)
                                // 	icon.source: AppIcons.bellSlash
                                // 	text: qsTr("Mettre en sourdine")
                                // 	onClicked: console.log("TODO : mute contact")
                                // }
                                // Rectangle {
                                // 	Layout.fillWidth: true
                                // 	Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
                                // 	color: DefaultStyle.main2_200
                                // }
                                // IconLabelButton {
                                // 	Layout.fillWidth: true
                                // 	Layout.preferredHeight: Utils.getSizeWithScreenRatio(50)
                                // 	icon.source: AppIcons.empty
                                // 	text: qsTr("Bloquer")
                                // 	onClicked: console.log("TODO : block contact")
                                // }
                                // Rectangle {
                                // 	Layout.fillWidth: true
                                // 	Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
                                // 	color: DefaultStyle.main2_200
                                // }
                                ColumnLayout {
                                    visible: mainItem.selectedContact && mainItem.selectedContact.core.isStored && !mainItem.selectedContact.core.readOnly
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
                                        color: DefaultStyle.main2_200
                                    }
                                    IconLabelButton {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(50)
                                        icon.source: AppIcons.trashCan
                                        //: "Supprimer ce contact"
                                        text: qsTr("contact_details_delete")
                                        onClicked: {
                                            mainItem.deleteContact(mainItem.selectedContact)
                                        }
                                        style: ButtonStyle.noBackgroundRed
                                    }
                                }
                            }
                        }
                        Item {
                            Layout.fillHeight: true
                        }
                    }
                }
            }
        }
    }

    Component {
        id: contactEdition
        ContactEdition {
            objectName: "contactEdition"
            onCloseEdition: redirectAddress => {
                goToContactDetails(true)
                if (redirectAddress) {
                    initialFriendToDisplay = redirectAddress
                }
            }
        }
    }

    Component {
        id: contactSharedFiles
        ContactSharedFiles {
            contact: mainItem.selectedContact
            onClose: rightPanelStackView.pop()
        }
    }
}
