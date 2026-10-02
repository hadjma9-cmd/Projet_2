import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Qt.labs.platform 1.1
import QtQuick.Effects

import Linphone
import UtilsCpp
import SettingsCpp
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle

Item {
    id: mainItem
    property var callObj
    property var contextualMenuOpenedComponent: undefined
    // Icones a droite du bandeau : meme ecart visible entre deux dessins, au pixel pres.
    // Un SVG n'occupe pas tout son cadre de 256 (les trois points n'en prennent que le
    // milieu) : des boutons regulierement espaces laissent des vides inegaux. Chaque icone
    // recoit donc un emplacement cale sur l'emprise horizontale de son dessin (left, right,
    // en unites du cadre, mesurees au rendu) plus une demi-marge de chaque cote, obtenu par
    // les marges de mise en page du bouton. Valeurs entieres : dessins nets, et ecarts egaux
    // a moins d'un pixel (les bords des dessins tombent entre deux pixels).
    readonly property real headerButtonSize: Utils.getSizeWithScreenRatio(36)
    readonly property real headerIconSize: Utils.getSizeWithScreenRatio(28)
    readonly property real headerIconHalfGap: Math.round(Utils.getSizeWithScreenRatio(12))
    // Bord gauche de la boite de l'icone dans son emplacement.
    function headerIconX(iconSize, left) {
        return headerIconHalfGap - Math.floor(iconSize * left / 256)
    }
    function headerSlotWidth(iconSize, left, right) {
        return headerIconX(iconSize, left) + Math.ceil(iconSize * right / 256) + headerIconHalfGap
    }
    // iconOffset : position de la boite de l'icone dans l'element ; centree si omis.
    function headerLeftMargin(itemWidth, iconSize, left, iconOffset) {
        if (iconOffset === undefined)
            iconOffset = (itemWidth - iconSize) / 2
        return headerIconX(iconSize, left) - iconOffset
    }
    function headerRightMargin(itemWidth, iconSize, left, right, iconOffset) {
        return headerSlotWidth(iconSize, left, right) - headerLeftMargin(itemWidth, iconSize, left, iconOffset) - itemWidth
    }

    property bool focusPageOnNextLoad: false // Focus the page on next load - usefull cause of loader

    signal addAccountRequest
    signal openNewCallRequest
    signal callCreated
    signal openCallHistory
    signal openNumPadRequest
    signal displayContactRequested(string contactAddress)
    signal displayChatRequested(string contactAddress)
    signal openChatRequested(ChatGui chat)
    signal createContactRequested(string name, string address)
    signal scheduleMeetingRequested(string subject, list<string> addresses)
    signal accountRemoved

    function goToNewCall() {
        tabbar.currentIndex = 0;
        mainItem.openNewCallRequest();
    }
    function goToCallHistory() {
        tabbar.currentIndex = 0;
        mainItem.openCallHistory();
    }
    function displayContactPage(contactAddress) {
        tabbar.currentIndex = 1;
        mainItem.displayContactRequested(contactAddress);
    }
    function displayChatPage(contactAddress) {
        tabbar.currentIndex = 2;
        mainItem.displayChatRequested(contactAddress);
    }
    function openChat(chat) {
        tabbar.currentIndex = 2;
        mainItem.openChatRequested(chat);
    }
    function createContact(name, address) {
        tabbar.currentIndex = 1;
        mainItem.createContactRequested(name, address);
    }
    function scheduleMeeting(subject, addresses) {
        tabbar.currentIndex = 3;
        mainItem.scheduleMeetingRequested(subject, addresses);
    }

    function openContextualMenuComponent(component) {
        if (mainItem.contextualMenuOpenedComponent && mainItem.contextualMenuOpenedComponent != component) {
            mainStackView.pop();
            if (mainItem.contextualMenuOpenedComponent) {
                mainItem.contextualMenuOpenedComponent.destroy();
            }
            mainItem.contextualMenuOpenedComponent = undefined;
        }
        if (!mainItem.contextualMenuOpenedComponent) {
            mainStackView.push(component);
            mainItem.contextualMenuOpenedComponent = component;
        }
        settingsMenuButton.popup.close();
    }

    function closeContextualMenuComponent() {
        if (!SettingsCpp.isSaved) {
                           //: Modifications non enregistrées
        UtilsCpp.getMainWindow().showConfirmationLambdaPopup(qsTr("contact_editor_popup_abort_confirmation_title"),
            //: Vous avez des modifications non enregistrées. Si vous quittez cette page, vos changements seront perdus. Voulez-vous enregistrer vos modifications avant de continuer ?
            qsTr("contact_editor_popup_abort_confirmation_message"),
				"",
			function (confirmed) {
				if (confirmed) {
					SettingsCpp.save()
				} else {
					SettingsCpp.undo()
				}
				mainStackView.pop();
                if (mainItem.contextualMenuOpenedComponent)
                    mainItem.contextualMenuOpenedComponent.destroy();
                mainItem.contextualMenuOpenedComponent = undefined;
                //: "Ne pas enregistrer"
            }, qsTr("contact_editor_dialog_abort_confirmation_do_not_save"),
            //: "Enregistrer"
            qsTr("contact_editor_dialog_abort_confirmation_save")
		)
	    } else {
            mainStackView.pop();
            if (mainItem.contextualMenuOpenedComponent)
                mainItem.contextualMenuOpenedComponent.destroy();
            mainItem.contextualMenuOpenedComponent = undefined;
        }
    }

    function openAccountSettings(account) {
        var page = accountSettingsPageComponent.createObject(parent, {
            "account": account
        });
        openContextualMenuComponent(page);
    }

    AccountProxy {
        id: accountProxy
        onDefaultAccountChanged: if (tabbar.currentIndex === 0 && defaultAccount)
            defaultAccount.core?.lResetMissedCalls()
    }

    // Messagerie vocale (barre laterale) : cumul sur tous les comptes, recalcule quand un compte
    // apparait ou que son indicateur de messages (MWI) ou son adresse de messagerie change.
    property int voicemailCount: 0
    property bool voicemailShowMwi: false
    property bool voicemailAvailable: false
    function updateCumulatedMwi() {
        var count = 0;
        var showMwi = false;
        var supportsVoiceMail = false;
        for (var i = 0; i < accountProxy.count; i++) {
            var core = accountProxy.getAt(i).core;
            count += core.voicemailCount;
            showMwi |= core.showMwi;
            supportsVoiceMail |= core.voicemailAddress.length > 0;
        }
        mainItem.voicemailShowMwi = showMwi;
        mainItem.voicemailCount = count;
        mainItem.voicemailAvailable = showMwi || supportsVoiceMail;
    }
    function openVoicemail() {
        if (accountProxy.count > 1) {
            avatarButton.popup.open();
        } else {
            if (accountProxy.defaultAccount.core.voicemailAddress.length > 0)
                UtilsCpp.createCall(accountProxy.defaultAccount.core.voicemailAddress);
            else
                UtilsCpp.showInformationPopup(qsTr("information_popup_error_title"),
                //: "L'URI de messagerie vocale n'est pas définie."
                qsTr("no_voicemail_uri_error_message"), false);
        }
    }
    Repeater {
        model: accountProxy
        delegate: Item {
            Component.onCompleted: mainItem.updateCumulatedMwi()
            Connections {
                target: modelData ? modelData.core : null
                function onShowMwiChanged() {
                    mainItem.updateCumulatedMwi();
                }
                function onVoicemailAddressChanged() {
                    mainItem.updateCumulatedMwi();
                }
            }
        }
    }

    CallProxy {
        id: callsModel
        sourceModel: AppCpp.calls
    }

    Item {
        anchors.fill: parent

        Popup {
            id: currentCallNotif
            background: Item {}
            closePolicy: Control.Popup.NoAutoClose
            visible: currentCall && currentCall.core.state != LinphoneEnums.CallState.Idle && currentCall.core.state != LinphoneEnums.CallState.IncomingReceived && currentCall.core.state != LinphoneEnums.CallState.PushIncomingReceived
            x: mainItem.width / 2 - width / 2
            y: contentItem.height / 2
            property var currentCall: callsModel.currentCall ? callsModel.currentCall : null
            property string remoteName: currentCall ? currentCall.core.remoteName : ""
            contentItem: MediumButton {
                style: ButtonStyle.toast
                text: currentCallNotif.currentCall ? currentCallNotif.currentCall.core.conference ? ("Réunion en cours : ") + currentCallNotif.currentCall.core.conference.core.subject : (("Appel en cours : ") + currentCallNotif.remoteName) : "appel en cours"
                onClicked: {
                    var callsWindow = UtilsCpp.getOrCreateCallsWindow(currentCallNotif.currentCall);
                    UtilsCpp.smartShowWindow(callsWindow);
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0
            anchors.topMargin: Utils.getSizeWithScreenRatio(25)

            VerticalTabBar {
                id: tabbar
                Layout.fillHeight: true
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(82)
                defaultAccount: accountProxy.defaultAccount
                currentIndex: 0
                onCountChanged: if (currentIndex >= count) currentIndex = 0
                Binding on currentIndex {
                    when: mainItem.contextualMenuOpenedComponent != undefined
                    value: -1
                }
                model: [
                    {
                        "icon": AppIcons.phone,
                        "selectedIcon": AppIcons.phoneSelected,
                        //: "Appels"
                        "label": qsTr("bottom_navigation_calls_label"),
                        //: "Open calls page"
                        "accessibilityLabel": qsTr("open_calls_page_accessible_name")
                    },
                    {
                        "icon": AppIcons.adressBook,
                        "selectedIcon": AppIcons.adressBookSelected,
                        //: "Contacts"
                        "label": qsTr("bottom_navigation_contacts_label"),
                        //: "Open contacts page"
                        "accessibilityLabel": qsTr("open_contacts_page_accessible_name")
                    },
                    {
                        "icon": AppIcons.chatTeardropText,
                        "selectedIcon": AppIcons.chatTeardropTextSelected,
                        //: "Messages" (« Conversations » etait coupe dans la barre laterale)
                        "label": qsTr("bottom_navigation_conversations_label"),
                        //: "Open conversations page"
                        "accessibilityLabel": qsTr("open_conversations_page_accessible_name"),
                        "visible": !SettingsCpp.disableChatFeature
                    },
                    {
                        "icon": AppIcons.videoconference,
                        "selectedIcon": AppIcons.videoconferenceSelected,
                        //: "Réunions"
                        "label": qsTr("bottom_navigation_meetings_label"),
                        //: "Open meetings page"
                        "accessibilityLabel": qsTr("open_contact_page_accessible_name"),
                        "visible": !SettingsCpp.disableMeetingsFeature
                    },
                    // Actions, construites comme les onglets pour un espacement identique ; elles
                    // s'executent au clic sans devenir l'onglet courant (voir VerticalTabBar).
                    {
                        "icon": AppIcons.dialer,
                        "selectedIcon": AppIcons.dialer,
                        //: "Clavier"
                        "label": qsTr("sidebar_dialer_label"),
                        //: "Open dialer"
                        "accessibilityLabel": qsTr("open_dialer_acccessibility_label"),
                        "action": function () {
                            // L'onglet Appels d'abord : la page d'appel n'est creee qu'a son
                            // premier affichage, et doit exister pour recevoir la demande.
                            mainItem.goToNewCall();
                            mainItem.openNumPadRequest();
                        }
                    },
                    {
                        "icon": AppIcons.voicemail,
                        "selectedIcon": AppIcons.voicemail,
                        //: "Boîte vocale"
                        "label": qsTr("sidebar_voicemail_label"),
                        "accessibilityLabel": qsTr("sidebar_voicemail_label"),
                        // Dessin large et bas : agrandi (28 au lieu de 24) pour peser autant que
                        // ses voisins, dans le meme cadre.
                        "iconScale": 28 / 24,
                        "isVisible": function () {
                            return mainItem.voicemailAvailable;
                        },
                        "unread": function () {
                            return mainItem.voicemailShowMwi ? mainItem.voicemailCount : 0;
                        },
                        "alert": function () {
                            return mainItem.voicemailShowMwi && mainItem.voicemailCount === 0;
                        },
                        "action": function () {
                            mainItem.openVoicemail();
                        }
                    }
                ]
                onCurrentIndexChanged: {
                    if (currentIndex === -1 || currentIndex >= tabbar.visibleCount)
                        return;
                    if (currentIndex === 0 && accountProxy.defaultAccount)
                        accountProxy.defaultAccount.core?.lResetMissedCalls();
                    if (mainItem.contextualMenuOpenedComponent) {
                        closeContextualMenuComponent();
                    }
                }
                Keys.onPressed: event => {
                    if (event.key == Qt.Key_Right) {
                        mainStackView.currentItem.forceActiveFocus();
                    }
                }

                /**
                 * Focus the page when user select the page with keyboard.
                 * Do not add this behavior on the arrows
                 */
                onEnterPressed: {
                    focusPageOnNextLoad = true
                }
                onSpacePressed: {
                    focusPageOnNextLoad = true
                }
                
                Component.onCompleted: {
                    if (SettingsCpp.shortcutCount > 0) {
                        var shortcuts = SettingsCpp.shortcuts;
                        shortcuts.forEach(shortcut => {
                            model.push({
                                "icon": shortcut.icon,
                                "selectedIcon": shortcut.icon,
                                "label": shortcut.name,
                                "colored": true,
                                "link": shortcut.link
                            });
                        });
                    }
                    initButtons();
                    currentIndex = SettingsCpp.getLastActiveTabIndex();
                    tabbar.updateVisibleCount()
                    if (currentIndex === -1 || currentIndex >= tabbar.visibleCount)
                        currentIndex = 0;
                }
            }
            ColumnLayout {
                spacing: 0

                RowLayout {
                    id: topRow
                    // Hauteur figee : sans cela, un enfant capable de s'etirer (les mises en page
                    // imbriquees le peuvent par defaut) fait partager au bandeau la hauteur de la
                    // fenetre avec la page affichee dessous.
                    Layout.fillHeight: false
                    // 68 : la place d'une photo de profil de 60.
                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(68)
                    Layout.leftMargin: Utils.getSizeWithScreenRatio(45)
                    // 33 + demi-marge de 12 de la derniere icone : bord droit du menu a 45, comme la
                    // photo a 45 du bord gauche.
                    Layout.rightMargin: Utils.getSizeWithScreenRatio(33)
                    spacing: Utils.getSizeWithScreenRatio(25)
                    // Bloc identite : avatar (ouvre la liste des comptes), nom et poste, puis
                    // pastille de statut cliquable. Il occupe la place laissee par la barre de
                    // recherche globale retiree.
                    RowLayout {
                        // Taille naturelle uniquement : une RowLayout imbriquee s'etire par defaut.
                        Layout.fillWidth: false
                        Layout.fillHeight: false
                        spacing: Utils.getSizeWithScreenRatio(10)
                        PopupButton {
                            id: avatarButton
                            // Photo mise en avant, plus grande que les icones de droite.
                            Layout.preferredWidth: Utils.getSizeWithScreenRatio(60)
                            Layout.preferredHeight: width
                            // Ni fond ni ombre : le bouton garde le focus apres un clic, et son
                            // cercle restait affiche autour de la photo.
                            style: ButtonStyle.noBackground
                            shadowEnabled: false
                            popup.topPadding: Utils.getSizeWithScreenRatio(23)
                            popup.bottomPadding: Utils.getSizeWithScreenRatio(23)
                            popup.leftPadding: Utils.getSizeWithScreenRatio(24)
                            popup.rightPadding: Utils.getSizeWithScreenRatio(24)
                            //: "Account list"
                            popUpTitle: qsTr("account_list_accessible_name")
                            contentItem: Item {
                                Avatar {
                                    id: avatar
                                    height: avatarButton.height
                                    width: avatarButton.width
                                    account: accountProxy.defaultAccount
                                }
                            }
                            popup.contentItem: AccountListView {
                                id: accounts
                                popupId: avatarButton
                                onAddAccountRequest: mainItem.addAccountRequest()
                                onEditAccount: function (account) {
                                    avatarButton.popup.close();
                                    openAccountSettings(account);
                                }
                                getPreviousItem: avatarButton.getPreviousItem
                                getNextItem: avatarButton.getNextItem
                            }
                        }
                        ContactDescription {
                            // ColumnLayout dont les textes demandent a remplir l'espace : sans ces
                            // deux lignes, elle poussait la pastille a droite et etirait le bandeau.
                            Layout.fillWidth: false
                            Layout.fillHeight: false
                            // Plus grand que dans la liste des comptes, a l'echelle de la photo.
                            topTextPixelSize: Typography.h2m.pixelSize
                            topTextWeight: Typography.h3m.weight
                            bottomTextPixelSize: Typography.p1.pixelSize
                            account: accountProxy.defaultAccount
                            // Toujours le poste seul, jamais l'adresse SIP complete : le reglage
                            // hide_sip_addresses vaut false par defaut, et « sip:878@domaine… »
                            // tiendrait mal dans le bandeau.
                            bottomText: accountProxy.defaultAccount
                                ? UtilsCpp.getUsername(accountProxy.defaultAccount.core.identityAddress)
                                : ""
                        }
                        // La pastille fixe sa taille avec width/height et non implicitWidth : la mise
                        // en page ne lui reservait que la largeur par defaut d'un PopupButton (30) et
                        // elle debordait sur les icones de droite. On l'enveloppe, comme Contact.qml.
                        Item {
                            visible: accountProxy.defaultAccount?.core.publishEnabled || false
                            Layout.preferredWidth: headerStatusPopup.width
                            Layout.preferredHeight: headerStatusPopup.height
                            ContactStatusPopup {
                                id: headerStatusPopup
                                account: accountProxy.defaultAccount
                                barHeight: Utils.getSizeWithScreenRatio(30)
                                textPixelSize: Utils.getSizeWithScreenRatio(13)
                                // Graisse normale : en leger, le statut paraissait pale a cote du nom en gras.
                                textWeight: Font.Normal
                                statusIconSize: Utils.getSizeWithScreenRatio(13)
                                arrowSize: Utils.getSizeWithScreenRatio(16)
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        // Aucun espacement propre : chaque icone porte le sien (headerSlotWidth).
                        spacing: 0
                        // Notifications coupees (menu ⋮) : cloche barree, seul indice visible de cet
                        // etat. En tete du groupe : celui-ci etant aligne a droite, elle apparait et
                        // disparait sans deplacer les autres icones. Meme taille et meme gris qu'elles,
                        // barre en rouge : deux couches superposees, EffectImage ne teintant une image
                        // que d'une seule couleur.
                        PopupButton {
                            id: notificationsOffButton
                            visible: SettingsCpp.dnd
                            Layout.preferredWidth: mainItem.headerButtonSize
                            Layout.preferredHeight: mainItem.headerButtonSize
                            // Cloche et barre reunies : 32 a 219 sur 256.
                            Layout.leftMargin: mainItem.headerLeftMargin(mainItem.headerButtonSize, mainItem.headerIconSize, 32)
                            Layout.rightMargin: mainItem.headerRightMargin(mainItem.headerButtonSize, mainItem.headerIconSize, 32, 219)
                            style: ButtonStyle.noBackground
                            icon.width: mainItem.headerIconSize
                            icon.height: mainItem.headerIconSize
                            contentItem: Item {
                                EffectImage {
                                    anchors.fill: parent
                                    imageSource: AppIcons.bellSlash
                                    imageWidth: notificationsOffButton.icon.width
                                    imageHeight: notificationsOffButton.icon.height
                                    colorizationColor: notificationsOffButton.pressed
                                        ? notificationsOffButton.pressedImageColor
                                        : notificationsOffButton.hovered
                                            ? notificationsOffButton.hoveredImageColor
                                            : notificationsOffButton.contentImageColor
                                }
                                EffectImage {
                                    anchors.fill: parent
                                    imageSource: AppIcons.bellSlashBar
                                    imageWidth: notificationsOffButton.icon.width
                                    imageHeight: notificationsOffButton.icon.height
                                    colorizationColor: DefaultStyle.danger_500_main
                                }
                            }
                            popup.padding: Utils.getSizeWithScreenRatio(14)
                            //: "Notifications désactivées"
                            popUpTitle: qsTr("do_not_disturb_accessible_name")
                            popup.contentItem: ColumnLayout {
                                IconLabelButton {
                                    Layout.fillWidth: true
                                    focus: visible
                                    // « Activer les notifications » : cloche simple, comme dans le menu ⋮.
                                    icon.width: Utils.getSizeWithScreenRatio(32)
                                    icon.height: Utils.getSizeWithScreenRatio(32)
                                    //: "Activer les notifications"
                                    text: qsTr("contact_presence_status_disable_do_not_disturb")
                                    icon.source: AppIcons.bell
                                    onClicked: {
                                        notificationsOffButton.popup.close();
                                        SettingsCpp.dnd = false;
                                    }
                                }
                            }
                        }
                        // Pave numerique et messagerie vocale : dans la barre laterale, sous les
                        // onglets. Messagerie : deja un onglet de la barre laterale.
                        PopupButton {
                            id: settingsMenuButton
                            // Trois barres, icone de 28 comme la cloche : l'engrenage aurait fait doublon
                            // avec l'entree Parametres du menu.
                            Layout.preferredWidth: mainItem.headerButtonSize
                            Layout.preferredHeight: mainItem.headerButtonSize
                            // Barres : de 4 a 24 px sur 28 (list-bars.svg), rapporte au cadre de 256.
                            Layout.leftMargin: mainItem.headerLeftMargin(mainItem.headerButtonSize, mainItem.headerIconSize, 256 * 4 / 28)
                            Layout.rightMargin: mainItem.headerRightMargin(mainItem.headerButtonSize, mainItem.headerIconSize, 256 * 4 / 28, 256 * 24 / 28)
                            icon.source: AppIcons.menuBars
                            icon.width: mainItem.headerIconSize
                            icon.height: mainItem.headerIconSize
                            // Jamais de rond autour de l'icone : le style par defaut colorait le fond
                            // tant que le bouton gardait le focus, soit jusqu'au clic suivant ailleurs.
                            // Seule l'icone fonce au survol et a l'appui, comme ses voisines.
                            style: ButtonStyle.noBackground
                            shadowEnabled: false
                            contentItem: EffectImage {
                                imageSource: settingsMenuButton.icon.source
                                imageWidth: settingsMenuButton.icon.width
                                imageHeight: settingsMenuButton.icon.height
                                colorizationColor: settingsMenuButton.colorizationColor
                            }
                            popup.width: Utils.getSizeWithScreenRatio(271)
                            popup.padding: Utils.getSizeWithScreenRatio(14)
                            //: "Application options"
                            popUpTitle: qsTr("application_options_accessible_name")
                            popup.Accessible.role: Accessible.PopupMenu
                            popup.contentItem: FocusScope {
                                id: popupFocus
                                implicitHeight: settingsButtons.implicitHeight
                                implicitWidth: settingsButtons.implicitWidth
                                Keys.onPressed: event => {
                                    if (event.key == Qt.Key_Left || event.key == Qt.Key_Escape) {
                                        settingsMenuButton.popup.close();
                                        event.accepted = true;
                                    }
                                }

                                ColumnLayout {
                                    id: settingsButtons
                                    spacing: Utils.getSizeWithScreenRatio(16)
                                    anchors.fill: parent

                                    IconLabelButton {
                                        id: accountButton
                                        Layout.fillWidth: true
                                        visible: !SettingsCpp.hideAccountSettings
                                        icon.width: Utils.getSizeWithScreenRatio(32)
                                        icon.height: Utils.getSizeWithScreenRatio(32)

                                        //: Mon compte
                                        text: qsTr("drawer_menu_manage_account")
                                        icon.source: AppIcons.manageProfile
                                        onClicked: openAccountSettings(accountProxy.defaultAccount ? accountProxy.defaultAccount : accountProxy.firstAccount())
                                        KeyNavigation.up: visibleChildren.length != 0 ? settingsMenuButton.getPreviousItem(0) : null
                                        KeyNavigation.down: visibleChildren.length != 0 ? settingsMenuButton.getNextItem(0) : null
                                    }
                                    IconLabelButton {
                                        id: dndButton
                                        Layout.fillWidth: true
                                        icon.width: Utils.getSizeWithScreenRatio(32)
                                        icon.height: Utils.getSizeWithScreenRatio(32)
                                        text: SettingsCpp.dnd ? qsTr("contact_presence_status_disable_do_not_disturb") :
                                        //: "Désactiver les notifications"
                                        qsTr("contact_presence_status_enable_do_not_disturb")
                                        // « Desactiver les notifications » : cloche barree, barre en rouge, comme celle
                                        // qui apparait alors dans le bandeau. « Activer les notifications » :
                                        // cloche simple.
                                        icon.source: SettingsCpp.dnd ? AppIcons.bell : AppIcons.bellSlash
                                        overlayIconSource: SettingsCpp.dnd ? "" : AppIcons.bellSlashBar
                                        overlayIconColor: DefaultStyle.danger_500_main
                                        onClicked: {
                                            settingsMenuButton.popup.close();
                                            SettingsCpp.dnd = !SettingsCpp.dnd;
                                        }
                                        KeyNavigation.up: visibleChildren.length != 0 ? settingsMenuButton.getPreviousItem(1) : null
                                        KeyNavigation.down: visibleChildren.length != 0 ? settingsMenuButton.getNextItem(1) : null
                                    }
                                    IconLabelButton {
                                        id: settingsButton
                                        Layout.fillWidth: true
                                        visible: !SettingsCpp.hideSettings
                                        icon.width: Utils.getSizeWithScreenRatio(32)
                                        icon.height: Utils.getSizeWithScreenRatio(32)
                                        text: qsTr("settings_title")
                                        icon.source: AppIcons.settings
                                        onClicked: {
                                            var page = settingsPageComponent.createObject(parent);
                                            openContextualMenuComponent(page)
                                        }
                                        KeyNavigation.up: visibleChildren.length != 0 ? settingsMenuButton.getPreviousItem(2) : null
                                        KeyNavigation.down: visibleChildren.length != 0 ? settingsMenuButton.getNextItem(2) : null
                                    }
                                    // FileDialog {
                                    //     id: fileDialog
                                    //     folder: UtilsCpp.getCaptureDirpaths()
                                    // }
                                    IconLabelButton {
                                        id: recordsButton
                                        Layout.fillWidth: true
                                        visible: !SettingsCpp.disableCallRecordings
                                        icon.width: Utils.getSizeWithScreenRatio(32)
                                        icon.height: Utils.getSizeWithScreenRatio(32)
                                        //: "Enregistrements"
                                        text: qsTr("recordings_title")
                                        icon.source: AppIcons.recordFill
                                        onClicked: {
                                            settingsMenuButton.popup.close()
                                            UtilsCpp.openNativeDialog(UtilsCpp.getCaptureDirpaths())
                                            // fileDialog.folder = UtilsCpp.getCaptureDirpaths()
                                            // fileDialog.open()
                                            // var page = recordingsPageComponent.createObject(parent);
                                            // openContextualMenuComponent(page)
                                        }
                                        KeyNavigation.up: visibleChildren.length != 0 ? settingsMenuButton.getPreviousItem(3) : null
                                        KeyNavigation.down: visibleChildren.length != 0 ? settingsMenuButton.getNextItem(3) : null
                                    }
                                    IconLabelButton {
                                        id: helpButton
                                        Layout.fillWidth: true
                                        icon.width: Utils.getSizeWithScreenRatio(32)
                                        icon.height: Utils.getSizeWithScreenRatio(32)
                                        //: "Aide"
                                        text: qsTr("help_title")
                                        icon.source: AppIcons.question
                                        onClicked: {
                                            var page = helpPageComponent.createObject(parent);
                                            openContextualMenuComponent(page)
                                        }
                                        KeyNavigation.up: visibleChildren.length != 0 ? settingsMenuButton.getPreviousItem(4) : null
                                        KeyNavigation.down: visibleChildren.length != 0 ? settingsMenuButton.getNextItem(4) : null
                                    }
                                    IconLabelButton {
                                        id: quitButton
                                        Layout.fillWidth: true
                                        icon.width: Utils.getSizeWithScreenRatio(32)
                                        icon.height: Utils.getSizeWithScreenRatio(32)
                                        //: "Quitter l'application"
                                        text: qsTr("help_quit_title")
                                        icon.source: AppIcons.power
                                        onClicked: {
                                            settingsMenuButton.popup.close();
                                            //: "Quitter %1 ?"
                                            UtilsCpp.getMainWindow().showConfirmationLambdaPopup("", qsTr("quit_app_question").arg(applicationName), "", function (confirmed) {
                                                if (confirmed) {
                                                    console.info("Exiting App from Top Menu");
                                                    Qt.quit();
                                                }
                                            });
                                        }
                                        KeyNavigation.up: visibleChildren.length != 0 ? settingsMenuButton.getPreviousItem(5) : null
                                        KeyNavigation.down: visibleChildren.length != 0 ? settingsMenuButton.getNextItem(5) : null
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
                                        visible: addAccountButton.visible
                                        color: DefaultStyle.main2_400
                                    }
                                    IconLabelButton {
                                        id: addAccountButton
                                        Layout.fillWidth: true
                                        visible: SettingsCpp.maxAccount == 0 || SettingsCpp.maxAccount > accountProxy.count
                                        icon.width: Utils.getSizeWithScreenRatio(32)
                                        icon.height: Utils.getSizeWithScreenRatio(32)
                                        //: "Ajouter un compte"
                                        text: qsTr("drawer_menu_add_account")
                                        icon.source: AppIcons.plusCircle
                                        onClicked: mainItem.addAccountRequest()
                                        KeyNavigation.up: visibleChildren.length != 0 ? settingsMenuButton.getPreviousItem(7) : null
                                        KeyNavigation.down: visibleChildren.length != 0 ? settingsMenuButton.getNextItem(7) : null
                                    }
                                }
                            }

                            MouseArea {
                                z: parent.z + 1
                                anchors.fill: parent
                                acceptedButtons: Qt.RightButton
                                onPressAndHold: (mouse) => {
                                    debugPopup.open()
                                }
                                PopupButton {
                                    id: debugPopup
                                    visible: false
                                    popup.contentItem: Button {
                                        text: "debug: force crash"
                                        onClicked: UtilsCpp.forceCrash()
                                    }
                                }
                            }
                        }
                    }
                }
                Component {
                    id: mainStackLayoutComponent
                    StackLayout {
                        id: mainStackLayout
                        objectName: "mainStackLayout"
                        property int _currentIndex: tabbar.currentIndex
                        currentIndex: -1
                        onActiveFocusChanged: if (activeFocus && currentIndex >= 0)
                            children[currentIndex].forceActiveFocus()
                        on_CurrentIndexChanged: {
                            if (count > 0) {
                                if (_currentIndex >= count && tabbar.model[_currentIndex].link) {
                                    Qt.openUrlExternally(tabbar.model[_currentIndex].link);
                                } else if (_currentIndex >= 0) {
                                    currentIndex = _currentIndex;
                                    SettingsCpp.setLastActiveTabIndex(currentIndex);
                                }
                            }
                        }
                        Loader {
                            // Une fois chargee, la page reste en memoire. Auparavant chaque changement
                            // d'onglet detruisait la page quittee et reconstruisait l'autre de zero --
                            // historique, recherche dans l'annuaire, avatars -- d'ou le temps de
                            // chargement a chaque clic. StackLayout n'affiche de toute facon que
                            // l'onglet courant : les autres restent invisibles.
                            property bool keptAlive: false
                            active: keptAlive || mainStackLayout.currentIndex === 0
                            sourceComponent: CallPage {
                                id: callPage
                                Connections {
                                    target: mainItem
                                    function onOpenNewCallRequest() {
                                        callPage.goToNewCall();
                                    }
                                    function onCallCreated() {
                                        callPage.goToCallHistory();
                                    }
                                    function onOpenCallHistory() {
                                        callPage.goToCallHistory();
                                    }
                                    function onOpenNumPadRequest() {
                                        callPage.openNumPadRequest();
                                    }
                                }
                                onCreateContactRequested: (name, address) => {
                                    mainItem.createContact(name, address);
                                }
                                onGoToCallForwardSettings: {
                                    var page = settingsPageComponent.createObject(parent, {
                                        defaultIndex: 1
                                    });
                                    openContextualMenuComponent(page);
                                }
                            }
                            onLoaded: {
                                // Differe : pose pendant le chargement, que declenche la liaison « active »,
                                // il reevaluait cette liaison en cours de route (boucle signalee au journal).
                                Qt.callLater(function() { keptAlive = true })
                                if(focusPageOnNextLoad) item.forceActiveFocus(Qt.TabFocusReason)
                                focusPageOnNextLoad = false
                            }
                            // La page n'etant plus reconstruite, onLoaded ne se declenche qu'une fois :
                            // le focus clavier est donc repose quand elle redevient l'onglet courant.
                            onVisibleChanged: if (visible && item && focusPageOnNextLoad) {
                                item.forceActiveFocus(Qt.TabFocusReason)
                                focusPageOnNextLoad = false
                            }
                        }
                        Loader {
                            property bool keptAlive: false
                            active: keptAlive || mainStackLayout.currentIndex === 1
                            sourceComponent: ContactPage {
                                id: contactPage
                                Connections {
                                    target: mainItem
                                    function onCreateContactRequested(name, address) {
                                        contactPage.createContact(name, address);
                                    }
                                    function onDisplayContactRequested(contactAddress) {
                                        contactPage.initialFriendToDisplay = contactAddress;
                                    }
                                }
                            }
                            onLoaded: {
                                // Differe : pose pendant le chargement, que declenche la liaison « active »,
                                // il reevaluait cette liaison en cours de route (boucle signalee au journal).
                                Qt.callLater(function() { keptAlive = true })
                                if(focusPageOnNextLoad) item.forceActiveFocus(Qt.TabFocusReason)
                                focusPageOnNextLoad = false
                            }
                            // La page n'etant plus reconstruite, onLoaded ne se declenche qu'une fois :
                            // le focus clavier est donc repose quand elle redevient l'onglet courant.
                            onVisibleChanged: if (visible && item && focusPageOnNextLoad) {
                                item.forceActiveFocus(Qt.TabFocusReason)
                                focusPageOnNextLoad = false
                            }
                        }
                        Loader {
                            property bool keptAlive: false
                            active: keptAlive || mainStackLayout.currentIndex === 2
                            sourceComponent: ChatPage {
                                id: chatPage
                                Connections {
                                    target: mainItem
                                    function onDisplayChatRequested(contactAddress) {
                                        console.log("display chat requested, open with address", contactAddress);
                                        chatPage.remoteAddress = "";
                                        chatPage.remoteAddress = contactAddress;
                                    }
                                    function onOpenChatRequested(chat) {
                                        console.log("open chat requested, open", chat.core.title);
                                        chatPage.openChatRequested(chat);
                                    }
                                }
                            }
                            onLoaded: {
                                // Differe : pose pendant le chargement, que declenche la liaison « active »,
                                // il reevaluait cette liaison en cours de route (boucle signalee au journal).
                                Qt.callLater(function() { keptAlive = true })
                                if(focusPageOnNextLoad) item.forceActiveFocus(Qt.TabFocusReason)
                                focusPageOnNextLoad = false
                            }
                            // La page n'etant plus reconstruite, onLoaded ne se declenche qu'une fois :
                            // le focus clavier est donc repose quand elle redevient l'onglet courant.
                            onVisibleChanged: if (visible && item && focusPageOnNextLoad) {
                                item.forceActiveFocus(Qt.TabFocusReason)
                                focusPageOnNextLoad = false
                            }
                        }

                        Loader {
                            property bool keptAlive: false
                            active: keptAlive || mainStackLayout.currentIndex === 3
                            sourceComponent: Component {
                                id: meetingComp
                                MeetingPage {
                                    id: meetingPage
                                    Connections {
                                        target: mainItem
                                        function onScheduleMeetingRequested(subject, addresses) {
                                            meetingPage.createPreFilledMeeting(subject, addresses);
                                        }
                                    }
                                }
                            }
                            onLoaded: {
                                // Differe : pose pendant le chargement, que declenche la liaison « active »,
                                // il reevaluait cette liaison en cours de route (boucle signalee au journal).
                                Qt.callLater(function() { keptAlive = true })
                                if(focusPageOnNextLoad) item.forceActiveFocus(Qt.TabFocusReason)
                                focusPageOnNextLoad = false
                            }
                            // La page n'etant plus reconstruite, onLoaded ne se declenche qu'une fois :
                            // le focus clavier est donc repose quand elle redevient l'onglet courant.
                            onVisibleChanged: if (visible && item && focusPageOnNextLoad) {
                                item.forceActiveFocus(Qt.TabFocusReason)
                                focusPageOnNextLoad = false
                            }
                        }

                    }
                }
                Component {
                    id: accountSettingsPageComponent
                    AccountSettingsPage {
                        onGoBack: {
                            closeContextualMenuComponent()
                            if(FocusNavigator.doesLastFocusWasKeyboard()){
                                mainItem.nextItemInFocusChain().forceActiveFocus(Qt.TabFocusReason)
                            }
                        }
                        onAccountRemoved: {
                            closeContextualMenuComponent();
                            mainItem.accountRemoved();
                        }
                    }
                }
                Component {
                    id: settingsPageComponent
                    SettingsPage {
                        onGoBack: {
                            closeContextualMenuComponent()
                            if(FocusNavigator.doesLastFocusWasKeyboard()){
                                mainItem.nextItemInFocusChain().forceActiveFocus(Qt.TabFocusReason)
                            }
                        }
                    }
                }
                Component {
                    id: recordingsPageComponent
                    RecordPage {
                        // onGoBack: {
                        //     closeContextualMenuComponent()
                        //     if(FocusNavigator.doesLastFocusWasKeyboard()){
                        //         mainItem.nextItemInFocusChain().forceActiveFocus(Qt.TabFocusReason)
                        //     }
                        // }
                    }
                }
                Component {
                    id: helpPageComponent
                    HelpPage {
                        onGoBack: {
                            closeContextualMenuComponent()
                            if(FocusNavigator.doesLastFocusWasKeyboard()){
                                mainItem.nextItemInFocusChain().forceActiveFocus(Qt.TabFocusReason)
                            }
                        }
                    }
                }
                Control.StackView {
                    id: mainStackView
                    property Transition noTransition: Transition {
                        PropertyAnimation {
                            property: "opacity"
                            from: 1
                            to: 1
                            duration: 0
                        }
                    }
                    pushEnter: noTransition
                    pushExit: noTransition
                    popEnter: noTransition
                    popExit: noTransition
                    Layout.topMargin: Utils.getSizeWithScreenRatio(24)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    initialItem: mainStackLayoutComponent
                }
            }
        }
    }
}
