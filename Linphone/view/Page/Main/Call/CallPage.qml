import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import SettingsCpp
import ConstantsCpp
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

AbstractMainPage {
    id: mainItem
    //: "Nouvel appel"
    noItemButtonText: qsTr("history_call_start_title")
    //: "Historique d'appel vide"
    emptyListText: qsTr("call_history_empty_title")
    newItemIconSource: AppIcons.newCall

    property var selectedRowHistoryGui
    signal listViewUpdated
    signal goToCallForwardSettings

    onVisibleChanged: if (!visible) {
        goToCallHistory()
    }

    /**
     * Focus on the first pertinent element in the page (LINQT-2202)
     * @override
     */
    function forceActiveFocus(reason = undefined){
        listStackView.currentItem?.newCallButton?.forceActiveFocus(reason)
    }

    //Group call properties
    property ConferenceInfoGui confInfoGui
    property AccountProxy accounts: AccountProxy {
        id: accountProxy
    }
    property AccountGui account: accountProxy.defaultAccount
    property bool isRegistered: account ? account.core?.registrationState
                                          == LinphoneEnums.RegistrationState.Ok : false
    property int selectedParticipantsCount
    signal createCallFromSearchBarRequested
    signal createContactRequested(string name, string address)
    signal openNumPadRequest
    // Mode de « Nouvel appel » : Clavier (vrai) ou Contacts. Le dernier choix est garde ; le bouton
    // pave du bandeau ouvre toujours le clavier.
    property bool newCallDialerMode: true
    signal dialerFocusRequested

    Connections {
        enabled: confInfoGui
        target: confInfoGui ? confInfoGui.core : null
        function onConferenceSchedulerStateChanged() {
            if (confInfoGui.core.schedulerState === LinphoneEnums.ConferenceSchedulerState.Ready) {
                listStackView.pop()
            }
        }
    }

    onSelectedRowHistoryGuiChanged: {
        // Un seul panneau dans la pile : replace() n'echange que l'element du dessus, et le detail
        // laisse sous une conversation de conference restait en memoire, cache.
        if (rightPanelStackView.depth > 1)
            rightPanelStackView.pop(null, Control.StackView.Immediate)
        if (selectedRowHistoryGui)
            rightPanelStackView.replace(contactDetailComp,
                                        Control.StackView.Immediate)
        else
            rightPanelStackView.replace(emptySelection,
                                        Control.StackView.Immediate)
    }
    rightPanelStackView.initialItem: emptySelection
    rightPanelStackView.width: Utils.getSizeWithScreenRatio(360)

    onNoItemButtonPressed: goToNewCall()

    showDefaultItem: listStackView.currentItem
                     && listStackView.currentItem.objectName == "historyListItem"
                     && listStackView.currentItem.listView.count === 0 || false

    // Page « Nouvel appel » (Contacts et Clavier) construite une seule fois puis reutilisee : la
    // recreer a chaque ouverture relancait ses recherches de contacts et figeait l'interface.
    // Elle est remise a zero en quittant la pile (voir newCallItem), comme une page neuve.
    property Item newCallPageItem: null
    function goToNewCall() {
        if (!listStackView.currentItem || listStackView.currentItem.objectName == "newCallItem")
            return
        // Encore en train de sortir (animation de retour) : la repousser maintenant la ferait
        // disparaitre a la fin de cette animation. Page neuve dans ce cas, comme auparavant.
        if (newCallPageItem && newCallPageItem.parent !== newCallPageHolder
                && !listStackView.find(function (item) { return item === mainItem.newCallPageItem }))
            newCallPageItem = null
        if (!newCallPageItem)
            newCallPageItem = newCallItem.createObject(newCallPageHolder)
        if (!newCallPageItem)
            return
        if (newCallPageItem.parent === newCallPageHolder)
            listStackView.push(newCallPageItem)
        else // Deja dans la pile, sous le formulaire d'appel de groupe.
            listStackView.popToItem(newCallPageItem, Control.StackView.PopTransition)
    }
    // Retour a l'historique, toujours au bas de la pile. replace() n'echangeait que l'element du
    // dessus : chaque retour empilait une nouvelle liste d'historique sur l'ancienne, et toutes
    // restaient en memoire, cachees, mises a jour a chaque appel.
    function goToCallHistory() {
        if (listStackView.depth > 1)
            listStackView.popToIndex(0, mainItem.visible ? Control.StackView.PopTransition
                                                         : Control.StackView.Immediate)
    }
    // Demande du bouton numeroteur du bandeau (relayee par MainLayout) : page « Nouvel appel »,
    // onglet Clavier, numero pret a etre saisi.
    onOpenNumPadRequest: {
        newCallDialerMode = true
        goToNewCall()
        dialerFocusRequested()
    }

    Dialog {
        id: deleteHistoryPopup
        width: Utils.getSizeWithScreenRatio(637)
        //: Supprimer l\'historique d\'appels ?
        title: qsTr("history_dialog_delete_all_call_logs_title")
        //: "L'ensemble de votre historique d'appels sera définitivement supprimé."
        text: qsTr("history_dialog_delete_all_call_logs_message")
    }
    Dialog {
        id: deleteForUserPopup
        width: Utils.getSizeWithScreenRatio(637)
        //: Supprimer l'historique d\'appels ?
        title: qsTr("history_dialog_delete_call_logs_title")
        //: "L\'ensemble de votre historique d\'appels avec ce correspondant sera définitivement supprimé."
        text: qsTr("history_dialog_delete_call_logs_message")
    }

    leftPanelContent: Item {
        id: leftPanel
        Layout.fillWidth: true
        Layout.fillHeight: true

        Control.StackView {
            id: listStackView
            anchors.fill: parent
            anchors.leftMargin: Utils.getSizeWithScreenRatio(45)
            clip: true
            initialItem: historyListItem
            focus: true
            onActiveFocusChanged: if (activeFocus) {
                currentItem.forceActiveFocus()
            }
        }
        // Garde la page « Nouvel appel » tant qu'elle n'est pas affichee (voir goToNewCall).
        Item {
            id: newCallPageHolder
            visible: false
        }
    }

    Component {                 
        id: historyListItem
        FocusScope {
            objectName: "historyListItem"
            property alias listView: historyListView
            property alias newCallButton: newCallButton

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                RowLayout {
                    id: titleCallLayout
                    // direction: FlexboxLayout.Row
                    spacing: Utils.getSizeWithScreenRatio(16)
                    // alignItems: FlexboxLayout.AlignCenter
                    Layout.rightMargin: Utils.getSizeWithScreenRatio(39)
                    Layout.fillHeight: false
                    Text {
                        Layout.fillWidth: true
                        //: "Appels"
                        text: qsTr("call_history_call_list_title")
						maximumLineCount: 1
                        color: DefaultStyle.main2_700
                        font.pixelSize: Typography.h2.pixelSize
                        font.weight: Typography.h2.weight
                    }
                    PopupButton {
                        id: removeHistory
                        icon.width: Utils.getSizeWithScreenRatio(24)
                        icon.height: Utils.getSizeWithScreenRatio(24)
                        focus: true
                        popup.x: 0
                        KeyNavigation.right: newCallButton
                        KeyNavigation.down: listStackView
                        //: Call history options
                        popUpTitle: qsTr("call_history_list_options_accessible_name")
                        popup.contentItem: ColumnLayout {
                            IconLabelButton {
                                Layout.fillWidth: true
                                focus: visible
                                //: "Supprimer l'historique"
                                text: qsTr("menu_delete_history")
                                icon.source: AppIcons.trashCan
                                style: ButtonStyle.hoveredBackgroundRed
                                onClicked: {
                                    removeHistory.close()
                                    deleteHistoryPopup.open()
                                }
                            }
                        }
                        Connections {
                            target: deleteHistoryPopup
                            onAccepted: {
                                if (listStackView.currentItem.listView)
                                    listStackView.currentItem.listView.model.removeAllEntries()
                            }
                        }
                    }
                    Button {
                        id: newCallButton
                        focus: true
                        style: ButtonStyle.noBackground
                        icon.source: AppIcons.newCall
                        Layout.preferredWidth: Utils.getSizeWithScreenRatio(34)
                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(34)
                        icon.width: Utils.getSizeWithScreenRatio(28)
                        icon.height: Utils.getSizeWithScreenRatio(28)
                        KeyNavigation.left: removeHistory
                        KeyNavigation.down: listStackView
                        //: Create new call
                        Accessible.name: qsTr("create_new_call_accessible_name")
                        onClicked: {
                            console.debug("[CallPage]User: create new call")
                            mainItem.goToNewCall()
                        }
                    }
                }
                SearchBar {
                    id: searchBar
                    Layout.fillWidth: true
                    Layout.topMargin: Utils.getSizeWithScreenRatio(18)
                    Layout.rightMargin: Utils.getSizeWithScreenRatio(39)
                    //: "Rechercher un appel"
                    placeholderText: qsTr("call_search_in_history")
                    visible: historyListView.count !== 0 || text.length !== 0
                    focus: true
                    KeyNavigation.up: newCallButton
                    KeyNavigation.down: historyListView
                    Binding {
                        target: mainItem
                        property: "showDefaultItem"
                        when: searchBar.text.length != 0
                        value: false
                    }
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                            mainItem.createCallFromSearchBarRequested()
                        }
                    }
                }
                Button {
                    visible: SettingsCpp.callForwardToAddress.length > 0 && !SettingsCpp.disableCallForward
                    Layout.fillWidth: true
                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(40)
                    Layout.topMargin: Utils.getSizeWithScreenRatio(18)
                    Layout.rightMargin: Utils.getSizeWithScreenRatio(39)
                    radius: Utils.getSizeWithScreenRatio(25)
                    color: "transparent"
                    borderColor: DefaultStyle.warning_500_main
                    borderWidth: Utils.getSizeWithScreenRatio(2)
                    text: qsTr("call_forward_to_address_info") + (SettingsCpp.callForwardToAddress == 'voicemail' ? qsTr("call_forward_to_address_info_voicemail") : SettingsCpp.callForwardToAddress)
                    textColor: DefaultStyle.warning_500_main
                    textSize: Typography.p1.pixelSize
                    textWeight: Typography.p1.weight
                    icon.source: AppIcons.callForward
                    contentImageColor: DefaultStyle.warning_500_main
                    icon.width: Utils.getSizeWithScreenRatio(24)
                    icon.height: Utils.getSizeWithScreenRatio(24)

                    onClicked: {
                        goToCallForwardSettings()
                    }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Control.Control {
                        id: listLayout
                        anchors.fill: parent
                        anchors.rightMargin: Utils.getSizeWithScreenRatio(39)
                        padding: 0
                        background: Item {}
                        contentItem: ColumnLayout {
                            Text {
                                visible: historyListView.count === 0 && !historyListView.loading
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                Layout.alignment: Qt.AlignHCenter
                                maximumLineCount: 2
                                Layout.topMargin: Utils.getSizeWithScreenRatio(137)
                                //: "Aucun résultat…"
                                text: searchBar.text.length != 0 ? qsTr("list_filter_no_result_found")
                                                                   //: "Aucun appel dans votre historique"
                                                                 : qsTr("history_list_empty_history")
                                font {
                                    pixelSize: Typography.h4.pixelSize
                                    weight: Typography.h4.weight
                                }
                            }
                            CallHistoryListView {
                                id: historyListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.topMargin: Utils.getSizeWithScreenRatio(38)
                                searchBar: searchBar
                                Control.ScrollBar.vertical: scrollbar

                                Connections {
                                    target: mainItem
                                    function onListViewUpdated() {
                                        historyListView.model.reload()
                                    }
                                }
                                Binding {
                                    target: mainItem
                                    property: "showDefaultItem"
                                    when: historyListView.loading
                                    value: false
                                }
                                // getAt() rend un nouvel objet a chaque appel, meme pour la meme ligne : le
                                // panneau de detail etait reconstruit (avec sa propre liste d'historique) a
                                // chaque variation de la liste, en boucle pendant les appels. Il ne l'est plus
                                // que si l'appel selectionne change vraiment.
                                function updateSelectedRow() {
                                    var gui = model.getAt(currentIndex)
                                    var current = mainItem.selectedRowHistoryGui
                                    if (gui && current && gui.core === current.core) return
                                    mainItem.selectedRowHistoryGui = gui
                                }
                                onCurrentIndexChanged: updateSelectedRow()
                                onCountChanged: updateSelectedRow()
                            }
                        }
                    }
                    ScrollBar {
                        id: scrollbar
                        visible: historyListView.contentHeight > parent.height
                        active: visible
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.rightMargin: Utils.getSizeWithScreenRatio(8)
                        policy: Control.ScrollBar.AsNeeded
                    }
                }
                
            }
        }
    }

    Component {
        id: newCallItem
        FocusScope {
            id: newCallPage
            objectName: "newCallItem"
            width: parent?.width
            height: parent?.height
            function focusCurrentMode(reason) {
                if (mainItem.newCallDialerMode)
                    dialerForm.focusNumber()
                else
                    callContactsList.forceActiveFocus(reason)
            }
            Control.StackView.onActivated: {
                const focusReason = FocusNavigator.doesLastFocusWasKeyboard() ? Qt.TabFocusReason : Qt.OtherFocusReason
                newCallPage.focusCurrentMode(focusReason)
            }
            // Page reutilisee (voir goToNewCall) : en quittant la pile, elle redevient une page neuve,
            // sans numero ni recherche. Remplacee entre-temps (reouverture pendant son animation de
            // retour), elle ne sert plus.
            Control.StackView.onRemoved: {
                if (mainItem.newCallPageItem !== newCallPage) {
                    newCallPage.destroy()
                    return
                }
                callContactsList.reset()
                dialerForm.clear()
            }
            Connections {
                target: mainItem
                enabled: mainItem.newCallPageItem === newCallPage
                function onDialerFocusRequested() {
                    newCallPage.focusCurrentMode(Qt.OtherFocusReason)
                }
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                RowLayout {
                    spacing: Utils.getSizeWithScreenRatio(10)
                    Button {
                        icon.width: Utils.getSizeWithScreenRatio(24)
                        icon.height: Utils.getSizeWithScreenRatio(24)
                        Layout.preferredWidth: Utils.getSizeWithScreenRatio(30)
                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(30)
                        style: ButtonStyle.noBackground
                        icon.source: AppIcons.leftArrow
                        focus: true
                        KeyNavigation.down: listStackView
                        //: Return to call history
                        Accessible.name: qsTr("return_to_call_history_accessible_name")
                        onClicked: {
                            console.debug(
                                        "[CallPage]User: return to call history")
                            listStackView.pop()
                            listStackView.forceActiveFocus()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        //: "Nouvel appel"
                        text: qsTr("call_action_start_new_call")
                        color: DefaultStyle.main2_700
                        font.pixelSize: Typography.h2.pixelSize
                        font.weight: Typography.h2.weight
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }
                // Deux facons d'appeler : composer un numero, comme sur un telephone (Clavier), ou
                // choisir un contact par son nom (Contacts).
                Rectangle {
                    Layout.topMargin: Utils.getSizeWithScreenRatio(18)
                    Layout.rightMargin: Utils.getSizeWithScreenRatio(39)
                    Layout.fillWidth: true
                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(44)
                    radius: height / 2
                    color: DefaultStyle.main2_100
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Utils.getSizeWithScreenRatio(4)
                        spacing: Utils.getSizeWithScreenRatio(4)
                        Repeater {
                            model: [{
                                    //: "Contacts"
                                    "label": qsTr("new_call_tab_contacts"),
                                    "iconSource": AppIcons.adressBook,
                                    "dialer": false
                                }, {
                                    //: "Clavier"
                                    "label": qsTr("new_call_tab_dialer"),
                                    "iconSource": AppIcons.dialer,
                                    "dialer": true
                                }]
                            Button {
                                required property var modelData
                                readonly property bool selected: mainItem.newCallDialerMode === modelData.dialer
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                style: selected ? ButtonStyle.main : ButtonStyle.noBackground
                                text: modelData.label
                                icon.source: modelData.iconSource
                                icon.width: Utils.getSizeWithScreenRatio(18)
                                icon.height: Utils.getSizeWithScreenRatio(18)
                                textSize: Utils.getSizeWithScreenRatio(15)
                                textWeight: Font.Bold
                                spacing: Utils.getSizeWithScreenRatio(8)
                                Accessible.role: Accessible.PageTab
                                onClicked: {
                                    mainItem.newCallDialerMode = modelData.dialer
                                    newCallPage.focusCurrentMode(Qt.OtherFocusReason)
                                }
                            }
                        }
                    }
                }
                StackLayout {
                    Layout.topMargin: Utils.getSizeWithScreenRatio(18)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: mainItem.newCallDialerMode ? 1 : 0
                    // Contacts : recherche par nom, sans pave.
                    NewCallForm {
                        id: callContactsList
                        searchBarColor: DefaultStyle.grey_100
                        onContactClicked: contact => {
                            mainWindow.startCallWithContact(contact, false, callContactsList)
                        }
                        onGroupCreationRequested: {
                            console.log("groupe call requetsed")
                            listStackView.push(groupCallItem)
                        }
                    }
                    // Clavier : numero compose puis appel, sans recherche.
                    Item {
                        DialerForm {
                            id: dialerForm
                            anchors.fill: parent
                            anchors.rightMargin: Utils.getSizeWithScreenRatio(39)
                            onCallRequested: number => UtilsCpp.createCall(number)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: groupCallItem
        GroupCreationFormLayout {
            objectName: "groupCallItem"
            //: "Appel de groupe"
            formTitle: qsTr("call_start_group_call_title")
            //: "Lancer"
            createGroupButtonText: qsTr("call_action_start_group_call")
            Control.StackView.onActivated: {
                addParticipantsLayout.forceActiveFocus()
            }
            onReturnRequested: {
                listStackView.pop()
                listStackView.currentItem?.forceActiveFocus()
            }
            onGroupCreationRequested: {
                if (groupName.text.length === 0) {
                    UtilsCpp.showInformationPopup(qsTr("information_popup_error_title"),
                                                    //: "Un nom doit être donné à l'appel de groupe
                                                    qsTr("group_call_error_must_have_name"), false)
                } else if (!mainItem.isRegistered) {
                    UtilsCpp.showInformationPopup(qsTr("information_popup_error_title"),
                                //: "Vous n'etes pas connecté"
                                qsTr("group_call_error_not_connected"), false)
                } else {
                    UtilsCpp.createGroupCall(groupName.text, addParticipantsLayout.selectedParticipants)
                }
            }
        }
    }

    Component {
        id: emptySelection
        Item {
            objectName: "emptySelection"
        }
    }
    Component {
        id: contactDetailComp
        FocusScope {
            CallHistoryLayout {
                id: contactDetail
                anchors.fill: parent
                anchors.topMargin: Utils.getSizeWithScreenRatio(45)
                anchors.bottomMargin: Utils.getSizeWithScreenRatio(45)
                visible: mainItem.selectedRowHistoryGui != undefined
                callHistoryGui: selectedRowHistoryGui

                property var contactObj: UtilsCpp.findFriendByAddress(specificAddress)
                contact: contactObj && contactObj.value || null
                specificAddress: callHistoryGui
                                 && callHistoryGui.core.remoteAddress || ""
                property bool isLocalFriend: contact ? contact.core.isAppFriend : false
                // Sans creation de contacts, tout contact trouve (annuaire compris) s'ouvre dans sa fiche.
                property bool showExistingContact: !!contact && (isLocalFriend || !ConstantsCpp.contactCreationEnabled)

                buttonContent: PopupButton {
                    id: detailOptions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    popUpTitle: qsTr("call_history_options_accessible_name")
                    popup.x: width
                    popup.contentItem: FocusScope {
                        implicitHeight: detailsButtons.implicitHeight
                        implicitWidth: detailsButtons.implicitWidth
                        Keys.onPressed: event => {
                                            if (event.key == Qt.Key_Left
                                                || event.key == Qt.Key_Escape) {
                                                detailOptions.popup.close()
                                                event.accepted = true
                                            }
                                        }
                        ColumnLayout {
                            id: detailsButtons
                            anchors.fill: parent
                            IconLabelButton {
                                id: addContactButton
                                visible: contactDetail.showExistingContact || ConstantsCpp.contactCreationEnabled
                                Layout.fillWidth: true
                                //: "Show contact"
                                text: contactDetail.showExistingContact ? qsTr("menu_see_existing_contact") :
                                                              //: "Add to contacts"
                                                              qsTr("menu_add_address_to_contacts")
                                icon.source: contactDetail.showExistingContact ? AppIcons.adressBook : AppIcons.plusCircle
                                icon.width: Utils.getSizeWithScreenRatio(32)
                                icon.height: Utils.getSizeWithScreenRatio(32)
                                onClicked: {
                                    detailOptions.close()
                                    if (contactDetail.showExistingContact)
                                        mainWindow.displayContactPage(contactDetail.contactAddress)
                                    else
                                        mainItem.createContactRequested(contactDetail.contactName, contactDetail.contactAddress)
                                }
                                KeyNavigation.up: visibleChildren.length
                                                    != 0 ? detailOptions.getPreviousItem(
                                                                0) : null
                                KeyNavigation.down: visibleChildren.length
                                                    != 0 ? detailOptions.getNextItem(
                                                                0) : null
                            }
                            // IconLabelButton {
                            // 	background: Item {}
                            // 	enabled: false
                            // 	contentItem: IconLabel {
                            // 		text: qsTr("Bloquer")
                            // 		iconSource: AppIcons.empty
                            // 	}
                            // 	onClicked: console.debug("[CallPage.qml] TODO : block user")
                            // }
                            IconLabelButton {
                                id: deleteHistoryButton
                                Layout.fillWidth: true
                                //: "Supprimer l'historique"
                                text: qsTr("menu_delete_history")
                                icon.source: AppIcons.trashCan
                                icon.width: Utils.getSizeWithScreenRatio(32)
                                icon.height: Utils.getSizeWithScreenRatio(32)
                                style: ButtonStyle.hoveredBackgroundRed
                                Connections {
                                    target: deleteForUserPopup
                                    function onAccepted() {
                                        detailListView.model.removeEntriesWithFilter(
                                                    detailListView.searchText)
                                        mainItem.listViewUpdated()
                                    }
                                }
                                onClicked: {
                                    detailOptions.close()
                                    deleteForUserPopup.open()
                                }
                                KeyNavigation.up: visibleChildren.length
                                                    != 0 ? detailOptions.getPreviousItem(
                                                                1) : null
                                KeyNavigation.down: visibleChildren.length
                                                    != 0 ? detailOptions.getNextItem(
                                                                1) : null
                            }
                        }
                    }
                }
                onConferenceChatDisplayRequested: {
                    rightPanelStackView.push(historyChatComp, {"callHistory": mainItem.selectedRowHistoryGui})
                }
                detailContent: Item {
                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(360)
                    Layout.fillHeight: true
                    RoundedPane {
                        id: detailControl
                        visible: detailListView.count > 0
                        width: parent.width
                        height: Math.min(parent.height, detailListView.contentHeight) + topPadding + bottomPadding
                        background: Rectangle {
                            id: detailListBackground
                            anchors.fill: parent
                            color: DefaultStyle.grey_0
                            radius: Utils.getSizeWithScreenRatio(15)
                        }
                        contentItem: Control.ScrollView {
                            id: historyScrollView
                            Control.ScrollBar.vertical: ScrollBar {
                                id: historyScrollBar
                                visible: historyScrollView.contentHeight > historyScrollView.height
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                            }
                            CallHistoryListView {
                                id: detailListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.rightMargin: historyScrollBar.width + Utils.getSizeWithScreenRatio(8)
                                spacing: Utils.getSizeWithScreenRatio(14)
                                clip: true
                                searchText: mainItem.selectedRowHistoryGui ? mainItem.selectedRowHistoryGui.core.remoteAddress : ""
                                busyIndicatorSize: Utils.getSizeWithScreenRatio(40)

                                delegate: Item {
                                    width: detailListView.width
                                    height: Utils.getSizeWithScreenRatio(56)
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Utils.getSizeWithScreenRatio(20)
                                        anchors.rightMargin: Utils.getSizeWithScreenRatio(20)
                                        anchors.verticalCenter: parent.verticalCenter
                                        ColumnLayout {
                                            Layout.alignment: Qt.AlignVCenter
                                            RowLayout {
                                                EffectImage {
                                                    id: statusIcon
                                                    imageSource: modelData.core.status
                                                                === LinphoneEnums.CallStatus.Declined
                                                                || modelData.core.status === LinphoneEnums.CallStatus.DeclinedElsewhere || modelData.core.status === LinphoneEnums.CallStatus.Aborted || modelData.core.status === LinphoneEnums.CallStatus.EarlyAborted ? AppIcons.arrowElbow : modelData.core.isOutgoing ? AppIcons.arrowUpRight : AppIcons.arrowDownLeft
                                                    colorizationColor: modelData.core.status === LinphoneEnums.CallStatus.Declined || modelData.core.status === LinphoneEnums.CallStatus.DeclinedElsewhere || modelData.core.status === LinphoneEnums.CallStatus.Aborted || modelData.core.status === LinphoneEnums.CallStatus.EarlyAborted || modelData.core.status === LinphoneEnums.CallStatus.Missed ? DefaultStyle.danger_500_main : modelData.core.isOutgoing ? DefaultStyle.info_500_main : DefaultStyle.success_500_main
                                                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(16)
                                                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(16)
                                                    transform: Rotation {
                                                        angle: modelData.core.isOutgoing
                                                            && (modelData.core.status === LinphoneEnums.CallStatus.Declined || modelData.core.status === LinphoneEnums.CallStatus.DeclinedElsewhere || modelData.core.status === LinphoneEnums.CallStatus.Aborted || modelData.core.status === LinphoneEnums.CallStatus.EarlyAborted) ? 180 : 0
                                                        origin {
                                                            x: statusIcon.width / 2
                                                            y: statusIcon.height / 2
                                                            }
                                                        }
                                                    }
                                                Text {
                                                    //: "Appel manqué"
                                                    text: modelData.core.status === LinphoneEnums.CallStatus.Missed ? qsTr("notification_missed_call_title")
                                                                                                                    : modelData.core.isOutgoing
                                                                                                                        //: "Appel sortant"
                                                                                                                        ? qsTr("call_outgoing")
                                                                                                                        //: "Appel entrant"
                                                                                                                        : qsTr("call_audio_incoming")
                                                    color: DefaultStyle.main2_700
                                                    font {
                                                        pixelSize: Typography.p1.pixelSize
                                                        weight: Font.DemiBold
                                                    }
                                                }
                                            }
                                            Text {
                                                text: UtilsCpp.formatDate(modelData.core.date)
                                                color: modelData.core.status === LinphoneEnums.CallStatus.Missed ? DefaultStyle.danger_500_main : DefaultStyle.main2_500_main
                                                font {
                                                    pixelSize: Utils.getSizeWithScreenRatio(12)
                                                    weight: Typography.p1s.weight
                                                }
                                            }
                                        }
                                        Item {
                                            Layout.fillHeight: true
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: UtilsCpp.formatElapsedTime(modelData.core.duration,false)
                                            color: DefaultStyle.main2_600
                                            font {
                                                pixelSize: Typography.b3.pixelSize
                                                weight: Typography.b3.weight
                                            }
                                        }
                                    }
                                }
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
    Component {
        id: historyChatComp
        SelectedChatView {
            backButtonVisible: true
            property var callHistory: null
            property var chatObj: callHistory ? UtilsCpp.getChatForCallLog(callHistory) : null
            chat: chatObj ? chatObj.value : null
            onBackButtonPressed: {
                rightPanelStackView.pop()
            }
        }
    }

    component IconLabel: RowLayout {
        id: iconLabel
        property string text
        property string iconSource
        property color colorizationColor: DefaultStyle.main2_500_main
        EffectImage {
            imageSource: iconLabel.iconSource
            Layout.preferredWidth: Utils.getSizeWithScreenRatio(24)
            Layout.preferredHeight: Utils.getSizeWithScreenRatio(24)
            fillMode: Image.PreserveAspectFit
            colorizationColor: iconLabel.colorizationColor
        }
        Text {
            text: iconLabel.text
            color: iconLabel.colorizationColor
            font {
                pixelSize: Typography.p1.pixelSize
                weight: Typography.p1.weight
            }
        }
    }
}
