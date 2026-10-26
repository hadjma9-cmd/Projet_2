import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import Linphone
import UtilsCpp
import SettingsCpp
import DesktopToolsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

ApplicationWindow {
    id: mainWindow
    x: 0
    y: 0
    width: Math.min(Utils.getSizeWithScreenRatio(1512), Screen.desktopAvailableWidth)
    height: Math.min(Utils.getSizeWithScreenRatio(982), Screen.desktopAvailableHeight)

    onActiveChanged: {
        if (active) UtilsCpp.setLastActiveWindow(this)
    }
    onVisibleChanged: {
        AppCpp.handleAppActivity()
    }
    Component.onDestruction: if (UtilsCpp.getLastActiveWindow() === this) UtilsCpp.setLastActiveWindow(null)

    property bool isFullscreen: visibility == Window.FullScreen
    onIsFullscreenChanged: DesktopToolsCpp.screenSaverStatus = !isFullscreen


    MouseArea {
        anchors.fill: parent
        onClicked: mainWindow.contentItem.forceActiveFocus()
    }

    Component {
        id: popupComp
        InformationPopup{}
    }

    Component{
        id: confirmPopupComp
        Dialog {
            property var requestDialog
            property int index
            property var callback: requestDialog?.result
            signal closePopup(int index)
            onClosed: closePopup(index)
            text: requestDialog?.message
            details: requestDialog?.details
            firstButtonAccept: title.length === 0
            secondButtonAccept: title.length !== 0
            // For C++, requestDialog need to be call directly
            onAccepted: requestDialog ? requestDialog.result(1) : callback(1)
            onRejected: requestDialog ? requestDialog.result(0) : callback(0)
        }
    }

    Component {
        id: addressChooserPopupComp
        // Choix du numero (ou de l'adresse) d'un contact qui en a plusieurs : meme fenetre que les autres decisions,
        // une carte par numero, Annuler dessous. L'icone suit l'action (appel, video, message, transfert).
        Dialog {
            id: addressChooserPopup
            property FriendGui contact
            signal addressChosen(string address)
            kind: "info"
            // Le contact en titre, la question (selon l'action) dessous.
            title: contact ? contact.core.fullName : ""
            onOpened: popuplist.forceActiveFocus()
            onClosed: destroy()
            content: ListView {
                id: popuplist
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, addressChooserPopup.evenSize(280))
                interactive: contentHeight > height
                clip: true
                model: VariantList {
                    model: addressChooserPopup.contact && addressChooserPopup.contact.core.allAddresses || []
                }
                spacing: addressChooserPopup.evenSize(8)
                keyNavigationEnabled: true
                activeFocusOnTab: true
                onActiveFocusChanged: {
                    if (activeFocus) currentIndex = 0
                    else currentIndex = -1
                }
                Keys.onPressed: event => {
                    if (currentItem && (event.key == Qt.Key_Return || event.key == Qt.Key_Enter || event.key == Qt.Key_Space)) {
                        addressChooserPopup.addressChosen(currentItem.address)
                        event.accepted = true
                    }
                }
                delegate: Rectangle {
                    id: addressCard
                    property string address: modelData.address
                    width: popuplist.width
                    height: addressChooserPopup.evenSize(addressChooserPopup.compactWindow ? 52 : 56)
                    radius: addressChooserPopup.evenSize(10)
                    color: cardMouseArea.containsMouse ? DefaultStyle.main2_100 : DefaultStyle.grey_0
                    border.width: Utils.getSizeWithScreenRatio(1)
                    // Bordure bleue : la carte choisie par Entree (clavier).
                    border.color: index === popuplist.currentIndex ? DefaultStyle.main1_500_main : DefaultStyle.main2_200
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 2 * addressChooserPopup.evenSize(12)
                        Text {
                            // Sans libelle, le numero seul reste centre dans la carte.
                            visible: text.length > 0
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: modelData.label
                            color: DefaultStyle.main2_500_main
                            font {
                                pixelSize: Utils.getSizeWithScreenRatio(addressChooserPopup.compactWindow ? 12 : 13)
                                weight: Typography.p1.weight
                            }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: SettingsCpp.hideSipAddresses ? UtilsCpp.getUsername(modelData.address) : modelData.address
                            color: DefaultStyle.main2_800
                            font {
                                pixelSize: Utils.getSizeWithScreenRatio(addressChooserPopup.compactWindow ? 14 : 15)
                                weight: Typography.p2.weight
                            }
                        }
                    }
                    MouseArea {
                        id: cardMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: addressChooserPopup.addressChosen(addressCard.address)
                    }
                }
            }
            buttons: DialogButton {
                text: "Annuler"
                style: ButtonStyle.secondary
                onClicked: addressChooserPopup.close()
            }
        }
    }

    // Ouvre le choix de l'adresse, centre sur toute la fenetre de l'element qui le demande (et non sur cet element, une
    // ligne de liste par exemple).
    function chooseContactAddress(contact, parentItem, iconSource, question, onChosen) {
        var root = parentItem
        while (root.parent) root = root.parent
        var addressPopup = addressChooserPopupComp.createObject(root, {"contact": contact, "iconSource": iconSource,
                                                                       "text": question})
        addressPopup.addressChosen.connect(function(address) {
            onChosen(address)
            addressPopup.close()
        })
        addressPopup.open()
    }

    // Regle : un bouton telephone appelle directement (confirm = false) ; un clic sur une ligne de liste qui lance
    // l'appel demande confirmation (par defaut), une erreur y etant vite arrivee.
    function startCallWithContact(contact, videoEnabled, parentItem, confirm) {
        if (parentItem == undefined) parentItem = mainWindow.contentItem
        if (contact) {
            console.log("START CALL WITH", contact.core.fullName, "addresses count", contact.core.allAddresses.length)
            if (contact.core.allAddresses.length > 1) {
                chooseContactAddress(contact, parentItem, videoEnabled ? AppIcons.videoCamera : AppIcons.phone,
                                     videoEnabled ? "Quel numéro appeler en vidéo ?" : "Quel numéro appeler ?",
                                     function(address) {
                    UtilsCpp.createCall(address, {'localVideoEnabled': videoEnabled})
                })

            } else {
                var addressToCall = contact.core.defaultAddress.length === 0
                    ? contact.core.phoneNumbers.length === 0
                        ? ""
                        : contact.core.phoneNumbers[0].address
                    : contact.core.defaultAddress
                if (addressToCall.length == 0) return
                if (confirm === false) UtilsCpp.createCall(addressToCall, {'localVideoEnabled': videoEnabled})
                else confirmCallWithContact(contact, addressToCall, videoEnabled)
            }
        }
    }

    // Confirmation avant un appel lance depuis un contact : « Souhaitez-vous appeler Lucas Louis
    // (878) ? ». Quand le contact a plusieurs adresses, le choix de l'adresse fait deja office de
    // confirmation : on n'en demande pas une seconde.
    function confirmCallWithContact(contact, address, videoEnabled) {
        confirmCall(contact ? contact.core.fullName : "", address, videoEnabled)
    }
    // Meme confirmation a partir d'un nom et d'une adresse, sans contact (historique des appels : numero inconnu).
    function confirmCall(name, address, videoEnabled) {
        var username = UtilsCpp.getUsername(address)
        // Meme regle que la fiche contact (ContactPage.isExtension) : 1 a 5 chiffres = un poste,
        // affiche seul ; sinon l'adresse complete, sauf si les adresses SIP sont masquees.
        var number = (/^[0-9]{1,5}$/.test(username) || SettingsCpp.hideSipAddresses) ? username : address
        // Le nom d'abord, le numero entre parentheses.
        name = name || ""
        var target = (name.length !== 0 && name !== username) ? name + " (" + number + ")" : number
        var question = videoEnabled
            //: "Souhaitez-vous lancer un appel vidéo avec %1 ?"
            ? qsTr("call_confirmation_video_question").arg(target)
            //: "Souhaitez-vous appeler %1 ?"
            : qsTr("call_confirmation_question").arg(target)
        mainWindow.showConfirmationLambdaPopup("", question, "", function (confirmed) {
            if (confirmed) UtilsCpp.createCall(address, {'localVideoEnabled': videoEnabled})
        },
        //: "Appeler"
        qsTr("dialog_call"), undefined, undefined, "info", (videoEnabled ? AppIcons.videoCamera : AppIcons.phone))
    }

    function sendMessageToContact(contact, parentItem) {
        if (parentItem == undefined) parentItem = mainWindow.contentItem
        if (contact) {
            console.log("SEND MESSAGE TO", contact.core.fullName, "addresses count", contact.core.allAddresses.length)
            if (contact.core.allAddresses.length > 1) {
                chooseContactAddress(contact, parentItem, AppIcons.chatTeardropText, "À quel numéro écrire ?",
                                     function(address) {
                    displayChatPage(address)
                })

            } else {
                displayChatPage(contact.core.defaultAddress)
            }
        }
    }

    function transferCallToContact(call, contact, parentItem) {
        if (!call || !contact) return
        if (parentItem == undefined) parentItem = mainWindow.contentItem
        if (contact) {
            console.log("[AbstractWindow] Transfer call to", contact.core.fullName, "addresses count", contact.core.allAddresses.length, call)
            if (contact.core.allAddresses.length > 1) {
                chooseContactAddress(contact, parentItem, AppIcons.transferCall, "Vers quel numéro transférer ?",
                                     function(address) {
                    call.core.lTransferCall(address)
                })

            } else {
                var addressToCall = contact.core.defaultAddress.length === 0
                    ? contact.core.phoneNumbers.length === 0
                        ? ""
                        : contact.core.phoneNumbers[0].address
                    : contact.core.defaultAddress
                if (addressToCall.length != 0) call.core.lTransferCall(addressToCall)
            }
        }
    }

    function removeFromPopupLayout(index) {
        popupLayout.popupList.splice(index, 1)
    }
    // Petits messages verts (succes) et rouges (erreur) affiches apres une action : retires a la demande. Toutes les
    // demandes, C++ comme QML, passent par ici ; le message reste ecrit dans le journal.
    function showInformationPopup(title, description, isSuccess) {
        console.info("[Information] " + (isSuccess === false ? "erreur" : "succes") + " : " + title + " - " + description)
    }
    function showLoadingPopup(text, cancelButtonVisible, callback) {
        if (cancelButtonVisible == undefined) cancelButtonVisible = false
        loadingPopup.text = text
        loadingPopup.callback = callback
        loadingPopup.cancelButtonVisible = cancelButtonVisible
        loadingPopup.open()
    }
    function closeLoadingPopup() {
        loadingPopup.close()
    }

    function showConfirmationPopup(requestDialog){
        console.log("Showing confirmation popup")
        var popup = confirmPopupComp.createObject(popupLayout, {"requestDialog": requestDialog})
        popup.open()
        popup.closePopup.connect(removeFromPopupLayout)
    }

    // kind : « info » (bleu, defaut), « warning » (orange) ou « danger » (rouge) ; iconSource : icone du rond (AppIcons).
    function showConfirmationLambdaPopup(title,text, details, callback, firstButtonText, secondButtonText, customContent, kind, iconSource){
        console.log("Showing confirmation lambda popup")
        var popup = confirmPopupComp.createObject(popupLayout, {"title": title, "text": text, "details":details,"callback":callback})
        if (firstButtonText != undefined) popup.firstButtonText = firstButtonText
        if (secondButtonText != undefined) popup.secondButtonText = secondButtonText
        if (customContent != undefined) popup.content = customContent
        if (kind != undefined) popup.kind = kind
        if (iconSource != undefined) popup.iconSource = iconSource
        popup.open()
        popup.closePopup.connect(removeFromPopupLayout)
    }

    ColumnLayout {
        id: popupLayout
        anchors.fill: parent
        Layout.alignment: Qt.AlignBottom
        property real nextY: mainWindow.height
        property list<InformationPopup> popupList
        property int popupCount: popupList.length
        spacing: Utils.getSizeWithScreenRatio(15)
        onPopupCountChanged: {
            nextY = mainWindow.height
            for(var i = 0; i < popupCount; ++i) {
                var popupItem = popupList[i]
                if( popupItem ){
                    popupItem.y = nextY - popupItem.height
                    popupItem.index = i
                    nextY = nextY - popupItem.height - 15
                }
            }
        }
    }

    LoadingPopup {
        id: loadingPopup
        modal: true
        closePolicy: Popup.NoAutoClose
        anchors.centerIn: parent
        padding: Utils.getSizeWithScreenRatio(20)
        underlineColor: DefaultStyle.main1_500_main
        radius: Utils.getSizeWithScreenRatio(15)
    }
    FPSCounter{
        anchors.top: parent.top
        anchors.left: parent.left
        height: 50
        width: fpsText.implicitWidth
        z: 100
        visible: !SettingsCpp.hideFps
        Text{
            id: fpsText
            font.bold: true
            font.italic: true
            font.pixelSize: Utils.getSizeWithScreenRatio(14)
            // "%1 FPS"
            text: qsTr("fps_counter").arg(parent.fps)
            color: parent.fps < 30 ? DefaultStyle.danger_500_main : DefaultStyle.main2_900
        }
    }
}
