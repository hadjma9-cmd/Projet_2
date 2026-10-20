import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls.Basic as Control
import Linphone
import EnumsToStringCpp
import UtilsCpp
import SettingsCpp
import DesktopToolsCpp
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle

AbstractWindow {
    id: mainWindow
    flags: Qt.Window
    minimumWidth: Utils.getSizeWithScreenRatio(1020)
    minimumHeight: Utils.getSizeWithScreenRatio(700)

    // Barre du haut bleu nuit sans barre de titre Windows (deplacement, reduire, agrandir, fermer).
    header: WindowTitleBar {
        id: callTitleBar
        window: mainWindow
        dark: true
        visible: frame.active && mainWindow.visibility !== Window.FullScreen

        // Chiffrement : un clic ouvre le detail.
        EffectImage {
            id: encryptionIcon
            Layout.preferredWidth: Utils.getSizeWithScreenRatio(15)
            Layout.preferredHeight: Utils.getSizeWithScreenRatio(15)
            visible: !!mainWindow.call
            colorizationColor: mainWindow.conference
                ?  DefaultStyle.info_500_main
                : mainWindow.call
                    ? mainWindow.call.core.encryption === LinphoneEnums.MediaEncryption.Srtp
                        ? DefaultStyle.info_500_main
                        : mainWindow.call.core.encryption === LinphoneEnums.MediaEncryption.Zrtp
                            ? mainWindow.call.core.isMismatch || !mainWindow.call.core.tokenVerified
                                ? DefaultStyle.warning_600
                                : DefaultStyle.info_500_main
                            : DefaultStyle.main2_300
                    : "transparent"
            imageSource: mainWindow.conference
                ?  AppIcons.lockKey
                : mainWindow.call
                ? mainWindow.call.core.encryption === LinphoneEnums.MediaEncryption.Srtp
                    ? AppIcons.lockSimple
                    : mainWindow.call && mainWindow.call.core.encryption === LinphoneEnums.MediaEncryption.Zrtp
                        ? mainWindow.call.core.isMismatch || !mainWindow.call.core.tokenVerified
                            ? AppIcons.warningCircle
                            : AppIcons.lockKey
                        : AppIcons.lockSimpleOpen
                : ""
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: mainWindow.toggleRightPanel(encryptionPanel, "encryptionPanel")
            }
        }
        Text {
            id: callStatusText
            text: (mainWindow.callState === LinphoneEnums.CallState.End || mainWindow.callState === LinphoneEnums.CallState.Released)
                //: Appel terminé
                ? qsTr("call_ended")
                : mainWindow.call && (mainWindow.call.core.paused)
                    ? (mainWindow.conference
                       //: Meeting paused
                        ? qsTr("conference_paused")
                        : mainWindow.callState === LinphoneEnums.CallState.PausedByRemote
                            //: Call paused by remote
                            ? qsTr("call_paused_by_remote")
                            //: Call paused
                            : qsTr("call_paused"))
                    : mainWindow.conference
                        ? mainWindow.conference.core.subject
                        : mainWindow.callConnected
                            //: "Appel en cours"
                            ? qsTr("call_status_in_progress")
                            : mainWindow.call
                                ? qsTr("call_dir").arg(EnumsToStringCpp.dirToString(mainWindow.call.core.dir))
                                : ""
            color: DefaultStyle.main2_200
            font {
                pixelSize: Utils.getSizeWithScreenRatio(13)
                weight: Typography.p1.weight
            }
        }
        Text {
            visible: mainWindow.callConnected
            text: "·  " + (mainWindow.call ? UtilsCpp.formatElapsedTime(mainWindow.call.core.duration) : "")
            color: DefaultStyle.main2_200
            font {
                pixelSize: Utils.getSizeWithScreenRatio(13)
                weight: Typography.p1.weight
            }
        }
        Text {
            id: conferenceDate
            text: mainWindow.conferenceInfo ? mainWindow.conferenceInfo.core.getStartEndDateString() : ""
            visible: text.length > 0
            color: DefaultStyle.main2_300
            font {
                pixelSize: Utils.getSizeWithScreenRatio(12)
                weight: Typography.p1.weight
                capitalization: Font.Capitalize
            }
        }
        // Qualite du reseau : un clic ouvre les statistiques de l'appel.
        Item {
            id: openStatisticPanelButton
            property int quality: mainWindow.call ? mainWindow.call.core.quality : 0
            visible: mainWindow.callConnected
            Layout.preferredWidth: Utils.getSizeWithScreenRatio(18)
            Layout.preferredHeight: Utils.getSizeWithScreenRatio(18)
            EffectImage {
                anchors.fill: parent
                imageSource: openStatisticPanelButton.quality >= 4 ? AppIcons.cellSignalFull : openStatisticPanelButton.quality >= 3 ? AppIcons.cellSignalMedium : openStatisticPanelButton.quality >= 2 ? AppIcons.cellSignalLow : AppIcons.cellSignalNone
                colorizationColor: openStatisticPanelButton.quality >= 2 ? DefaultStyle.main2_200 : DefaultStyle.danger_500_main
            }
            MouseArea {
                id: statisticsArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: mainWindow.toggleRightPanel(statsPanel, "statsPanel")
            }
            ToolTip {
                //: Statistiques
                text: qsTr("call_stats_title")
                visible: statisticsArea.containsMouse
                delay: 300
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }

    // modality: Qt.WindowModal
    property CallGui call

    property ConferenceGui conference: call && call.core.conference || null
    property bool isConference: call ? call.core.isConference : false

    // Chat related to call
    property var chatObj
    property ChatGui chat: chatObj && chatObj.value || null
    // Appel pour lequel la conversation a ete cherchee : un autre appel en demande une nouvelle.
    property var chatCallCore: null
    // Conversation cherchee, ou creee, seulement a l'ouverture du chat : elle l'etait a chaque appel etabli, meme
    // sans jamais ouvrir le chat (une conversation vide par numero appele, *97 compris).
    function requestCallChat() {
        if (!mainWindow.call) return
        if (mainWindow.chat && mainWindow.chatCallCore === mainWindow.call.core) return
        mainWindow.chatCallCore = mainWindow.call.core
        mainWindow.chatObj = UtilsCpp.getCurrentCallChat(mainWindow.call)
    }

    property int conferenceLayout: call && call.core.conferenceVideoLayout || 0
    property bool cameraEnabled: call && call.core.cameraEnabled
    property bool remoteVideoEnabled: call && call.core.remoteVideoEnabled

    property bool callTerminatedByUser: false
    property var callState: call ? call.core.state : LinphoneEnums.CallState.Idle
    property var transferState: call && call.core.transferState
    property bool startingCall: mainWindow.callState == LinphoneEnums.CallState.OutgoingInit
        || mainWindow.callState
        == LinphoneEnums.CallState.OutgoingProgress
        || mainWindow.callState
        == LinphoneEnums.CallState.OutgoingRinging
        || mainWindow.callState
        == LinphoneEnums.CallState.OutgoingEarlyMedia
        || mainWindow.callState == LinphoneEnums.CallState.IncomingReceived
    property Item firstButtonInBottomTab : microButton.visible ? microButton : endCallButton
    property Item lastButtonInBottomTab : acceptCallButton.visible ? acceptCallButton : endCallButton
    // Appel video ou reunion : image en grand, boutons dans une barre translucide par-dessus. Appel audio : photo et
    // halo au centre, boutons ronds en dessous avec leur nom.
    property bool videoMode: !!call && (call.core.remoteVideoEnabled || call.core.cameraEnabled || !!conference)
    property bool incomingRinging: callState === LinphoneEnums.CallState.IncomingReceived
        || callState === LinphoneEnums.CallState.IncomingEarlyMedia
        || callState === LinphoneEnums.CallState.PushIncomingReceived
    // Appel decroche, en cours (y compris en attente) : toutes les commandes sont proposees.
    property bool callRunning: !!call && !startingCall && !incomingRinging
        && callState !== LinphoneEnums.CallState.End && callState !== LinphoneEnums.CallState.Released
        && callState !== LinphoneEnums.CallState.Error && callState !== LinphoneEnums.CallState.Idle
    property bool callConnected: callState === LinphoneEnums.CallState.Connected
        || callState === LinphoneEnums.CallState.StreamsRunning

    // The incoming-call toast notification owns the CallGui it hands to this window, and
    // destroys it when the call reaches StreamsRunning (WindowsNotificationBackend.cpp).
    // That nulls mainWindow.call mid-call. Recover it from the calls model, which keeps a
    // valid CallGui for as long as the call exists.
    onCallChanged: {
        if (!call && callsModel.haveCall && callsModel.currentCall)
            mainWindow.call = callsModel.currentCall
    }

    onCallStateChanged: {
        if (callState === LinphoneEnums.CallState.Connected) {
            if (middleItemStackView.currentItem.objectName != "inCallItem") {
                middleItemStackView.replace(inCallItem)
                bottomButtonsLayout.visible = true
            }
            if (call.core.encryption === LinphoneEnums.MediaEncryption.Zrtp
                    && !mainWindow.isConference && (!call.core.tokenVerified
                                                    || call.core.isMismatch)) {
                zrtpValidation.open()
            }
        } else if (callState === LinphoneEnums.CallState.Error
                   || callState === LinphoneEnums.CallState.End) {
            zrtpValidation.close()
            callEnded(call)
        }
    }

    onTransferStateChanged: {
        console.log("Transfer state:", transferState)
        if (mainWindow.transferState === LinphoneEnums.CallState.OutgoingInit) {
            var callsWin = UtilsCpp.getOrCreateCallsWindow()
            if (!callsWin)
                return
            //: "Transfert en cours, veuillez patienter"
            callsWin.showLoadingPopup(qsTr("call_transfer_in_progress_toast"))
        } else if (mainWindow.transferState === LinphoneEnums.CallState.Error
                   || mainWindow.transferState === LinphoneEnums.CallState.End
                   || mainWindow.transferState === LinphoneEnums.CallState.Released
                   || mainWindow.transferState === LinphoneEnums.CallState.Connected) {
            var callsWin = UtilsCpp.getOrCreateCallsWindow()
            callsWin.closeLoadingPopup()
            if (transferState === LinphoneEnums.CallState.Error)
                UtilsCpp.showInformationPopup(
                            qsTr("information_popup_error_title"),
                            //: "Le transfert d'appel a échoué"
                            qsTr("call_transfer_failed_toast"), false,
                            mainWindow)
            else if (transferState === LinphoneEnums.CallState.Connected) {
                var mainWin = UtilsCpp.getMainWindow()
                UtilsCpp.smartShowWindow(mainWin)
                mainWin.transferCallSucceed()
            }
        }
    }
    onClosing: close => {
        DesktopToolsCpp.screenSaverStatus = true
        if (callsModel.haveCall) {
            close.accepted = false
            terminateAllCallsDialog.open()
        }
        if (middleItemStackView.currentItem.objectName === "waitingRoom")
        middleItemStackView.replace(inCallItem)
    }
    Connections {
        enabled: activeFocusItem !== null
        target: activeFocusItem ? activeFocusItem.Keys : null
        function onPressed(event) {
            if (rightPanel.contentLoader.item && rightPanel.contentLoader.item.objectName === "dialerPanel"){
                mainWindow.keyPressedOnDialer(event)
            }
            if ((event.key === Qt.Key_Escape || event.key === Qt.Key_Return) && mainWindow.visibility == Window.FullScreen)
                mainWindow.showNormal()
        }
    }
    
    signal keyPressedOnDialer(KeyEvent event)


    function changeLayout(layoutIndex) {
        if (layoutIndex == 0) {
            console.log("Set Grid layout")
            call.core.lSetConferenceVideoLayout(LinphoneEnums.ConferenceLayout.Grid)
        } else if (layoutIndex == 1) {
            console.log("Set AS layout")
            call.core.lSetConferenceVideoLayout(LinphoneEnums.ConferenceLayout.ActiveSpeaker)
        } else {
            console.log("Set audio-only layout", layoutIndex)
            call.core.lSetConferenceVideoLayout(LinphoneEnums.ConferenceLayout.AudioOnly)
        }
    }

    function rightPanelShows(objectName) {
        return rightPanel.visible && !!rightPanel.contentLoader.item
            && rightPanel.contentLoader.item.objectName === objectName
    }
    function toggleRightPanel(component, objectName) {
        if (rightPanelShows(objectName)) {
            rightPanel.visible = false
        } else {
            rightPanel.visible = true
            rightPanel.replace(component)
        }
    }

    function endCall(callToFinish) {
        // mainWindow.call can transiently become null (the incoming-call toast destroys
        // the CallGui it handed us). Fall back to the calls model so the hangup button
        // always terminates the live call instead of silently leaving it running.
        var c = callToFinish || mainWindow.call || callsModel.currentCall
        // Appels reunis par ce poste (« Reunir ») : la conference passe par lui, raccrocher la termine donc pour tout le
        // monde. callsModel ne compte pas l'appel en cours ; une reunion distante n'a qu'un appel.
        if (c && c.core.isConference && !callsModel.haveNonAdminMeeting && callsModel.count >= 1) {
            mainWindow.showConfirmationLambdaPopup("Terminer la conférence",
                "Raccrocher terminera l'appel pour tout le monde.", "",
                function (confirmed) {
                    if (!confirmed)
                        return
                    for (var i = 0; i < callsModel.count; ++i) {
                        var other = callsModel.getAt(i)
                        if (other && other.core.isConference)
                            other.core.lTerminate()
                    }
                    c.core.lTerminate()
                }, undefined, undefined, undefined, "danger", AppIcons.endCall)
            return
        }
        if (c)
            c.core.lTerminate()
        else if (!callsModel.haveCall)
            UtilsCpp.closeCallsWindow()
        // var mainWin = UtilsCpp.getMainWindow()
        // mainWin.goToCallHistory()
    }
    function callEnded(call) {
        if (call && call.core.state === LinphoneEnums.CallState.Error) {
            middleItemStackView.replace(inCallItem)
        }
        if (!callsModel.haveCall) {
            if (call && call.core.isConference)
                UtilsCpp.closeCallsWindow()
            else {
                bottomButtonsLayout.setButtonsEnabled(false)
                autoCloseWindow.restart()
            }
        } else {
            if (middleItemStackView.currentItem.objectName === "waitingRoom") {
                middleItemStackView.replace(inCallItem)
            }
            mainWindow.call = callsModel.currentCall
        }
    }

    signal setUpConferenceRequested(ConferenceInfoGui conferenceInfo)
    function setupConference(conferenceInfo) {
        middleItemStackView.replace(waitingRoom)
        setUpConferenceRequested(conferenceInfo)
    }

    function joinConference(uri, options) {
        if (uri.length === 0)
            UtilsCpp.showInformationPopup(qsTr("information_popup_error_title"),
                                          //: "La conférence n'a pas pu démarrer en raison d'une erreur d'uri."
                                          qsTr("conference_error_empty_uri"),mainWindow)
        else {
            UtilsCpp.createCall(uri, options)
        }
    }
    function cancelJoinConference() {
        if (!callsModel.haveCall) {
            UtilsCpp.closeCallsWindow()
        } else {
            mainWindow.call = callsModel.currentCall
        }
        middleItemStackView.replace(inCallItem)
    }
    function cancelAfterJoin() {
        endCall(mainWindow.call)
    }

    Connections {
        enabled: !!mainWindow.call
        target: mainWindow.call ? mainWindow.call.core : null
        function onSecurityUpdated() {
            if (mainWindow.call.core.encryption === LinphoneEnums.MediaEncryption.Zrtp) {
                if (call.core.tokenVerified) {
                    zrtpValidation.close()
                    zrtpValidationToast.open()
                } else {
                    zrtpValidation.open()
                }
            } else {
                zrtpValidation.close()
            }
        }
        function onTokenVerified() {
            if (!zrtpValidation.isTokenVerified) {
                zrtpValidation.securityError = true
            } else
                zrtpValidation.close()
        }
    }

    Timer {
        id: autoCloseWindow
        interval: mainWindow.callTerminatedByUser ? 1500 : 2500
        onTriggered: {
            UtilsCpp.closeCallsWindow()
        }
    }

    Dialog {
        id: terminateAllCallsDialog
        onAccepted: {
            mainWindow.callTerminatedByUser = true
            call.core.lTerminateAllCalls()
        }
        kind: "danger"
        iconSource: AppIcons.endCall
        //: "Terminer tous les appels en cours ?"
        title: qsTr("call_close_window_dialog_title")
        //: "La fenêtre est sur le point d'être fermée. Cela terminera tous les appels en cours."
        text: qsTr("call_close_window_dialog_message")
    }

    CallProxy {
        id: callsModel
        sourceModel: AppCpp.calls
        onCurrentCallChanged: {
            if (currentCall) {
                mainWindow.call = currentCall
            }
        }
        onHaveCallChanged: {
            if (!haveCall) {
                mainWindow.callEnded()
            } else {
                bottomButtonsLayout.setButtonsEnabled(true)
            }
        }
    }

    // Entree du menu Plus de la fenetre d'appel.
    component MoreOption: IconLabelButton {
        Layout.fillWidth: true
        icon.width: Utils.getSizeWithScreenRatio(24)
        icon.height: Utils.getSizeWithScreenRatio(24)
        style: ButtonStyle.noBackground
    }

    component BottomButton: Button {
        id: bottomButton
        required property string enabledIcon
        property string disabledIcon
        enabled: call != undefined
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        checkable: true
        background: Rectangle {
            anchors.fill: parent
            color: bottomButton.enabled ? disabledIcon ? DefaultStyle.grey_500 : bottomButton.pressed || bottomButton.checked ? DefaultStyle.main2_400 : DefaultStyle.grey_500 : DefaultStyle.grey_600
            radius: Utils.getSizeWithScreenRatio(71)
        }
        icon.source: disabledIcon
                     && bottomButton.checked ? disabledIcon : enabledIcon
        icon.width: Utils.getSizeWithScreenRatio(32)
        icon.height: Utils.getSizeWithScreenRatio(32)
        contentImageColor: DefaultStyle.grey_0
    }
    ZrtpAuthenticationDialog {
        id: zrtpValidation
        call: mainWindow.call
        modal: true
        closePolicy: Popup.NoAutoClose
    }
    Timer {
        id: autoCloseZrtpToast
        interval: 4000
        onTriggered: {
            zrtpValidationToast.y = -zrtpValidationToast.height * 2
        }
    }
    Control.Control {
        id: zrtpValidationToast
        // width: Utils.getSizeWithScreenRatio(269)
        y: -height * 2
        z: 1
        topPadding: Utils.getSizeWithScreenRatio(8)
        bottomPadding: Utils.getSizeWithScreenRatio(8)
        leftPadding: Utils.getSizeWithScreenRatio(50)
        rightPadding: Utils.getSizeWithScreenRatio(50)
        anchors.horizontalCenter: parent.horizontalCenter
        clip: true
        function open() {
            if (mainWindow.isConference)
                return
            y = headerItem.height / 2
            autoCloseZrtpToast.restart()
        }
        Behavior on y {
            NumberAnimation {
                duration: 1000
            }
        }
        background: Rectangle {
            anchors.fill: parent
            color: DefaultStyle.grey_0
            border.color: DefaultStyle.info_500_main
            border.width: Utils.getSizeWithScreenRatio(1)
            radius: Utils.getSizeWithScreenRatio(50)
        }
        contentItem: RowLayout {
            // anchors.centerIn: parent
            Image {
                source: AppIcons.trusted
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(24)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(24)
                fillMode: Image.PreserveAspectFit
                Layout.fillWidth: true
            }
            Text {
                color: DefaultStyle.info_500_main
                //: "Appareil authentifié"
                text: qsTr("call_can_be_trusted_toast")
                Layout.fillWidth: true
                font {
                    pixelSize: Utils.getSizeWithScreenRatio(14)
                }
            }
        }
    }

    /************************* CONTENT ********************************/
    Rectangle {
        anchors.fill: parent
        color: DefaultStyle.callBackground

        ColumnLayout {
            anchors.fill: parent
            anchors.bottomMargin: Utils.getSizeWithScreenRatio(10)
            anchors.topMargin: Utils.getSizeWithScreenRatio(10)
            spacing: Utils.getSizeWithScreenRatio(10)
            // Bandeau d'enregistrement ou de partage d'ecran. L'etat de l'appel, sa duree, le chiffrement et la
            // qualite sont dans la barre du haut (callTitleBar).
            Item {
                id: headerItem
                visible: screenSharingOrRecordBanner.wanted
                Layout.fillWidth: true
                Layout.leftMargin: Utils.getSizeWithScreenRatio(20)
                Layout.preferredHeight: screenSharingOrRecordBanner.implicitHeight
                // Banner middle of header - screen sharing or record screen
                Control.Control {
                    id: screenSharingOrRecordBanner
                    property var isScreenSharing: mainWindow.conference && mainWindow.conference.core.isLocalScreenSharing 
                    property bool wanted: mainWindow.call
                        ? !!mainWindow.conference 
                            ? mainWindow.conference.core.isRecording || isScreenSharing//mainWindow.conference.core.isLocalScreenSharing
                            : (mainWindow.call.core.recording || mainWindow.call.core.remoteRecording) 
                        : false
                    anchors.centerIn: parent
                    leftPadding: Utils.getSizeWithScreenRatio(14)
                    rightPadding: Utils.getSizeWithScreenRatio(14)
                    topPadding: Utils.getSizeWithScreenRatio(6)
                    bottomPadding: Utils.getSizeWithScreenRatio(6)
                    background: Rectangle {
                        anchors.fill: parent
                        color: DefaultStyle.grey_500
                        radius: Utils.getSizeWithScreenRatio(10)
                    }
                    contentItem: RowLayout {
                        spacing: Utils.getSizeWithScreenRatio(85)
                        RowLayout {
                            spacing: Utils.getSizeWithScreenRatio(15)
                            EffectImage {
                                imageSource: screenSharingOrRecordBanner.isScreenSharing
                                    ? AppIcons.screencast
                                    : AppIcons.recordFill
                                colorizationColor: screenSharingOrRecordBanner.isScreenSharing
                                    ? DefaultStyle.grey_0
                                    : DefaultStyle.danger_500_main
                                Layout.preferredWidth: Utils.getSizeWithScreenRatio(24)
                                Layout.preferredHeight: Utils.getSizeWithScreenRatio(24)
                            }
                            Text {
                                color: screenSharingOrRecordBanner.isScreenSharing
                                    ? DefaultStyle.grey_0
                                    : DefaultStyle.danger_500_main
                                font: Typography.b1
                                text: mainWindow.call
                                        ? screenSharingOrRecordBanner.isScreenSharing
                                            //: "You are sharing your screen"
                                            ? qsTr("conference_user_is_sharing_screen")
                                            : mainWindow.call.core.recording
                                                ? mainWindow.conference
                                                    //: "You are recording the meeting"
                                                    ? qsTr("conference_user_is_recording")
                                                    //: "You are recording the call"
                                                    : qsTr("call_user_is_recording")
                                                : mainWindow.conference
                                                    //: "Someone is recording the meeting"
                                                    ? qsTr("conference_remote_is_recording")
                                                    //: "%1 is recording the call"
                                                    : qsTr("call_remote_recording").arg(mainWindow.call.core.remoteName)
                                        : ""
                            }
                        }
                        MediumButton {
                            visible: mainWindow.call
                                     && mainWindow.call.core.recording || screenSharingOrRecordBanner.isScreenSharing
                            
                            text: screenSharingOrRecordBanner.isScreenSharing
                            //: "Stop sharing"
                            ? qsTr("call_stop_screen_sharing")
                            //: "Stop recording"
                            : qsTr("call_stop_recording")
                            Accessible.name: screenSharingOrRecordBanner.isScreenSharing ?
                            //: "Stop screen sharing"
                            qsTr("stop_screen_sharing_accessible_name")
                            //: Stop recording
                            : qsTr("stop_recording_accessible_name") 
                            style: ButtonStyle.mainLightBorder
                            onPressed: {
                                if (screenSharingOrRecordBanner.isScreenSharing) mainWindow.conference.core.lToggleScreenSharing()
                                else mainWindow.call.core.lStopRecording()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Utils.getSizeWithScreenRatio(23)
                Item {
                    id: middleArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Un autre appel sonne (Refuser, Repondre) ou attend (« Reunir », ou un clic pour basculer vers lui).
                    HeldCallsBar {
                        z: 2
                        anchors.top: parent.top
                        anchors.topMargin: Utils.getSizeWithScreenRatio(16)
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width - Utils.getSizeWithScreenRatio(40), Utils.getSizeWithScreenRatio(360))
                        currentCall: mainWindow.call
                        visible: !!shownCall && !!middleItemStackView.currentItem
                            && middleItemStackView.currentItem.objectName == "inCallItem"
                    }
                    Control.StackView {
                        id: middleItemStackView
                        initialItem: inCallItem
                        anchors.fill: parent
                        // Appel audio : place pour les boutons sous la photo. Video : boutons par-dessus l'image.
                        anchors.bottomMargin: mainWindow.videoMode || !bottomButtonsLayout.visible
                            ? 0
                            : bottomButtonsLayout.height + Utils.getSizeWithScreenRatio(24)
                    }

                    // -------------------------------------------------------------------------
                    //  Boutons de l'appel
                    // -------------------------------------------------------------------------
                    Item {
                        id: bottomButtonsLayout
                        z: 1
                        visible: !!middleItemStackView.currentItem && middleItemStackView.currentItem.objectName == "inCallItem"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Utils.getSizeWithScreenRatio(mainWindow.videoMode ? 20 : 14)
                        width: buttonsRow.implicitWidth + (mainWindow.videoMode ? Utils.getSizeWithScreenRatio(28) : 0)
                        height: buttonsRow.implicitHeight + (mainWindow.videoMode ? Utils.getSizeWithScreenRatio(16) : 0)
                        function setButtonsEnabled(enabled) {
                            buttonsRow.enabled = enabled
                        }

                        // Video : la barre devient transparente 5 s apres le depart de la souris, et revient a son
                        // survol.
                        property bool faded: false
                        opacity: mainWindow.videoMode && faded ? 0.3 : 1
                        Behavior on opacity {
                            OpacityAnimator {
                                duration: 350
                            }
                        }
                        HoverHandler {
                            id: buttonsHover
                            onHoveredChanged: {
                                if (hovered) {
                                    bottomButtonsLayout.faded = false
                                    fadeTimer.stop()
                                } else if (mainWindow.videoMode) {
                                    fadeTimer.restart()
                                }
                            }
                        }
                        Timer {
                            id: fadeTimer
                            interval: 5000
                            onTriggered: bottomButtonsLayout.faded = true
                        }
                        Connections {
                            target: mainWindow
                            function onVideoModeChanged() {
                                bottomButtonsLayout.faded = false
                                if (mainWindow.videoMode && !buttonsHover.hovered)
                                    fadeTimer.restart()
                                else
                                    fadeTimer.stop()
                            }
                        }
                        Component.onCompleted: if (mainWindow.videoMode) fadeTimer.restart()

                        // Barre translucide de la video.
                        Rectangle {
                            anchors.fill: parent
                            visible: mainWindow.videoMode
                            radius: height / 2
                            color: Qt.rgba(10 / 255, 18 / 255, 32 / 255, 0.45)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                        }

                        RowLayout {
                            id: buttonsRow
                            anchors.centerIn: parent
                            spacing: Utils.getSizeWithScreenRatio(mainWindow.videoMode ? 10 : 18)

                            CallRoundButton {
                                id: microButton
                                visible: !!mainWindow.call && !mainWindow.incomingRinging
                                translucent: mainWindow.videoMode
                                iconSource: mainWindow.call && mainWindow.call.core.microphoneMuted ? AppIcons.microphoneSlash : AppIcons.microphone
                                //: "Micro"
                                label: qsTr("call_button_microphone")
                                active: !!mainWindow.call && mainWindow.call.core.microphoneMuted
                                toolTipText: active
                                    //: "Activer le micro"
                                    ? qsTr("call_activate_microphone")
                                    //: "Désactiver le micro"
                                    : qsTr("call_deactivate_microphone")
                                onClicked: mainWindow.call.core.lSetMicrophoneMuted(!mainWindow.call.core.microphoneMuted)
                            }
                            CallRoundButton {
                                id: speakerButton
                                visible: !!mainWindow.call && !mainWindow.incomingRinging
                                translucent: mainWindow.videoMode
                                iconSource: mainWindow.call && mainWindow.call.core.speakerMuted ? AppIcons.speakerSlash : AppIcons.speaker
                                //: "Son"
                                label: qsTr("call_button_speaker")
                                active: !!mainWindow.call && mainWindow.call.core.speakerMuted
                                toolTipText: active
                                    //: "Activer le son"
                                    ? qsTr("call_activate_speaker_hint")
                                    //: "Désactiver le son"
                                    : qsTr("call_deactivate_speaker_hint")
                                onClicked: mainWindow.call.core.lSetSpeakerMuted(!mainWindow.call.core.speakerMuted)
                            }
                            CallRoundButton {
                                id: pauseButton
                                readonly property bool paused: !!mainWindow.call && (mainWindow.call.core.paused
                                    || mainWindow.callState == LinphoneEnums.CallState.Paused
                                    || mainWindow.callState == LinphoneEnums.CallState.Pausing)
                                visible: mainWindow.callRunning && !mainWindow.videoMode
                                enabled: !!mainWindow.conference || mainWindow.callState != LinphoneEnums.CallState.PausedByRemote
                                iconSource: paused ? AppIcons.play : AppIcons.phonePause
                                //: "Attente"
                                label: qsTr("call_button_hold")
                                active: paused
                                toolTipText: paused
                                    //: "Reprendre l'appel"
                                    ? qsTr("call_action_resume_call")
                                    //: "Mettre l'appel en pause"
                                    : qsTr("call_action_pause_call")
                                onClicked: mainWindow.call.core.lSetPaused(!mainWindow.call.core.paused)
                            }
                            CallRoundButton {
                                id: dialerButton
                                visible: mainWindow.callRunning && !mainWindow.videoMode
                                iconSource: AppIcons.dialer
                                //: "Clavier"
                                label: qsTr("call_button_dialer")
                                active: mainWindow.rightPanelShows("dialerPanel")
                                onClicked: mainWindow.toggleRightPanel(dialerPanel, "dialerPanel")
                            }
                            CallRoundButton {
                                id: transferCallButton
                                visible: mainWindow.callRunning && !mainWindow.videoMode && !mainWindow.conference
                                iconSource: AppIcons.transferCall
                                //: "Transfert"
                                label: qsTr("call_button_transfer")
                                //: "Transférer l'appel"
                                toolTipText: qsTr("call_action_transfer_call")
                                active: mainWindow.rightPanelShows("callTransferPanel")
                                onClicked: mainWindow.toggleRightPanel(callTransferPanel, "callTransferPanel")
                            }
                            CallRoundButton {
                                id: cameraButton
                                visible: mainWindow.callRunning && mainWindow.videoMode && SettingsCpp.videoEnabled
                                translucent: true
                                iconSource: mainWindow.cameraEnabled ? AppIcons.videoCamera : AppIcons.videoCameraSlash
                                //: "Caméra"
                                label: qsTr("call_button_camera")
                                active: mainWindow.cameraEnabled
                                toolTipText: mainWindow.cameraEnabled
                                    //: "Désactiver la vidéo"
                                    ? qsTr("call_deactivate_video_hint")
                                    //: "Activer la vidéo"
                                    : qsTr("call_activate_video_hint")
                                onClicked: mainWindow.call.core.lSetCameraEnabled(!mainWindow.call.core.cameraEnabled)
                            }
                            CallRoundButton {
                                id: screencastButton
                                visible: mainWindow.callRunning && mainWindow.videoMode && !!mainWindow.conference
                                translucent: true
                                iconSource: AppIcons.screencast
                                //: "Partager l'écran"
                                label: qsTr("call_button_share_screen")
                                active: (!!mainWindow.conference && mainWindow.conference.core.isLocalScreenSharing)
                                    || mainWindow.rightPanelShows("screencastPanel")
                                onClicked: mainWindow.toggleRightPanel(screencastPanel, "screencastPanel")
                            }
                            CallRoundButton {
                                id: moreOptionsButton
                                visible: mainWindow.callRunning
                                translucent: mainWindow.videoMode
                                iconSource: AppIcons.horizontalDots
                                //: "Plus"
                                label: qsTr("call_button_more")
                                //: "Plus d'options…"
                                toolTipText: qsTr("call_more_options_hint")
                                active: moreOptionsPopup.visible
                                onClicked: moreOptionsPopup.visible ? moreOptionsPopup.close() : moreOptionsPopup.open()

                                Control.Popup {
                                    id: moreOptionsPopup
                                    y: -height - Utils.getSizeWithScreenRatio(12)
                                    x: (moreOptionsButton.width - width) / 2
                                    padding: Utils.getSizeWithScreenRatio(10)
                                    closePolicy: Control.Popup.CloseOnEscape | Control.Popup.CloseOnPressOutsideParent
                                    background: Rectangle {
                                        color: DefaultStyle.grey_0
                                        radius: Utils.getSizeWithScreenRatio(12)
                                    }
                                    contentItem: ColumnLayout {
                                        spacing: Utils.getSizeWithScreenRatio(2)
                                        MoreOption {
                                            visible: !mainWindow.videoMode && SettingsCpp.videoEnabled
                                            icon.source: AppIcons.videoCamera
                                            //: "Activer la vidéo"
                                            text: qsTr("call_activate_video_hint")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.call.core.lSetCameraEnabled(true)
                                            }
                                        }
                                        MoreOption {
                                            visible: mainWindow.videoMode
                                            icon.source: AppIcons.dialer
                                            //: "Pavé numérique"
                                            text: qsTr("call_action_show_dialer")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.toggleRightPanel(dialerPanel, "dialerPanel")
                                            }
                                        }
                                        MoreOption {
                                            visible: mainWindow.videoMode
                                            enabled: pauseButton.enabled
                                            icon.source: pauseButton.paused ? AppIcons.play : AppIcons.phonePause
                                            text: pauseButton.toolTipText
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.call.core.lSetPaused(!mainWindow.call.core.paused)
                                            }
                                        }
                                        MoreOption {
                                            visible: mainWindow.videoMode && !mainWindow.conference
                                            icon.source: AppIcons.transferCall
                                            text: qsTr("call_action_transfer_call")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.toggleRightPanel(callTransferPanel, "callTransferPanel")
                                            }
                                        }
                                        MoreOption {
                                            icon.source: AppIcons.newCall
                                            //: "Nouvel appel"
                                            text: qsTr("call_action_start_new_call")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.toggleRightPanel(newCallPanel, "newCallPanel")
                                            }
                                        }
                                        MoreOption {
                                            icon.source: AppIcons.callList
                                            //: "Liste d'appel"
                                            text: qsTr("call_action_go_to_calls_list")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.toggleRightPanel(callListPanel, "callListPanel")
                                            }
                                        }
                                        MoreOption {
                                            visible: !SettingsCpp.disableChatFeature && (!mainWindow.conference || mainWindow.conference.core.isChatEnabled)
                                            icon.source: AppIcons.chatTeardropText
                                            //: Open chat…
                                            text: qsTr("call_open_chat_hint")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.requestCallChat()
                                                mainWindow.toggleRightPanel(chatPanel, "chatPanel")
                                            }
                                        }
                                        MoreOption {
                                            visible: !!mainWindow.conference
                                            icon.source: AppIcons.usersTwo
                                            //: "Gérer les participants"
                                            text: qsTr("call_manage_participants_hint")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.toggleRightPanel(participantListPanel, "participantListPanel")
                                            }
                                        }
                                        MoreOption {
                                            visible: !!mainWindow.conference
                                            icon.source: AppIcons.layout
                                            //: "Modifier la disposition"
                                            text: qsTr("call_action_change_conference_layout")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.toggleRightPanel(changeLayoutPanel, "changeLayoutPanel")
                                            }
                                        }
                                        MoreOption {
                                            visible: !!mainWindow.call && !mainWindow.conference && !SettingsCpp.disableCallRecordings
                                            enabled: !!mainWindow.call && mainWindow.call.core.recordable
                                            icon.source: AppIcons.recordFill
                                            contentImageColor: mainWindow.call && mainWindow.call.core.recording ? DefaultStyle.danger_500_main : DefaultStyle.main2_500_main
                                            hoveredImageColor: contentImageColor
                                            textColor: contentImageColor
                                            hoveredTextColor: textColor
                                            text: mainWindow.call && mainWindow.call.core.recording
                                                //: "Terminer l'enregistrement"
                                                ? qsTr("call_action_stop_recording")
                                                //: "Enregistrer l'appel"
                                                : qsTr("call_action_record")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                if (mainWindow.call.core.recording)
                                                    mainWindow.call.core.lStopRecording()
                                                else
                                                    mainWindow.call.core.lStartRecording()
                                            }
                                        }
                                        MoreOption {
                                            icon.source: AppIcons.settings
                                            //: "Paramètres"
                                            text: qsTr("call_action_go_to_settings")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                mainWindow.toggleRightPanel(settingsPanel, "settingsPanel")
                                            }
                                        }
                                        MoreOption {
                                            visible: mainWindow.videoMode
                                            icon.source: AppIcons.fullscreen
                                            //: "Mode Plein écran"
                                            text: qsTr("call_action_full_screen")
                                            onClicked: {
                                                moreOptionsPopup.close()
                                                if (mainWindow.visibility === Window.FullScreen)
                                                    mainWindow.showNormal()
                                                else
                                                    mainWindow.showFullScreen()
                                            }
                                        }
                                    }
                                }
                            }
                            // Raccrocher, ou refuser un appel entrant : pastille rouge, un peu a l'ecart.
                            CallRoundButton {
                                id: endCallButton
                                visible: !!mainWindow.call
                                Layout.leftMargin: mainWindow.incomingRinging ? 0 : Utils.getSizeWithScreenRatio(14)
                                translucent: mainWindow.videoMode
                                showLabel: !mainWindow.videoMode
                                danger: true
                                iconSource: AppIcons.endCall
                                label: mainWindow.incomingRinging
                                    //: "Refuser"
                                    ? qsTr("call_button_decline")
                                    //: "Raccrocher"
                                    : qsTr("call_button_hang_up")
                                //: "Terminer l'appel"
                                toolTipText: qsTr("call_action_end_call")
                                onClicked: {
                                    mainWindow.callTerminatedByUser = true
                                    mainWindow.endCall(mainWindow.call)
                                }
                            }
                            CallRoundButton {
                                id: acceptCallButton
                                visible: mainWindow.callState === LinphoneEnums.CallState.IncomingReceived
                                Layout.leftMargin: Utils.getSizeWithScreenRatio(40)
                                success: true
                                iconSource: AppIcons.phone
                                //: "Répondre"
                                label: qsTr("call_button_answer")
                                //: "Accepter l'appel"
                                toolTipText: qsTr("call_action_accept_call")
                                onClicked: mainWindow.call.core.lAccept(false)
                            }
                        }
                    }
                }
                CallSettingsPanel {
                    id: rightPanel
                    Layout.fillHeight: true
                    Layout.rightMargin: Utils.getSizeWithScreenRatio(20)
                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(393)
                    Layout.topMargin: Utils.getSizeWithScreenRatio(10)
                    property int currentIndex: 0
                    visible: false
                    onVisibleChanged: if(!visible) contentLoader.sourceComponent = null
                    function replace(id, properties) {
                        rightPanel.customHeaderButtons = null
                        contentLoader.sourceComponent = null
                        contentLoader.sourceComponent = id
                        for (var key in properties) {
                            contentLoader.item[key] = properties[key]
                        }
                    }
                    headerStack.currentIndex: 0
                    headerValidateButtonText: qsTr("add")
                    KeyNavigation.tab : Utils.isDescendant(nextItemInFocusChain(), rightPanel) ? nextItemInFocusChain() : mainWindow.firstButtonInBottomTab

                    // Do not consider padding for chat
                    // Binding on topPadding {
                    //     when: rightPanel.contentLoader.item && rightPanel.contentLoader.item.objectName === "chatPanel"
                    //     value: Utils.getSizeWithScreenRatio(10)
                    //     restoreMode: Binding.RestoreBindingOrValue
                    // }
                    Binding on leftPadding {
                        when: rightPanel.contentLoader.item && rightPanel.contentLoader.item.objectName === "chatPanel"
                        value: 0
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    Binding on rightPadding {
                        when: rightPanel.contentLoader.item && rightPanel.contentLoader.item.objectName == "chatPanel"
                        value: 0
                        restoreMode: Binding.RestoreBindingOrValue
                    }
                    Connections {
                        target: rightPanel.contentLoader
                        function onItemChanged() {
                            if (rightPanel.contentLoader.item) {
                                if (rightPanel.contentLoader.item.objectName === "callTransferPanel") {
                                    //: "Transférer %1 à…"
                                    rightPanel.headerTitleText = qsTr("call_transfer_current_call_title").arg(mainWindow.call.core.remoteName)
                                }
                                else if (rightPanel.contentLoader.item.objectName === "newCallPanel") {
                                    //: "Nouvel appel"
                                    rightPanel.headerTitleText = qsTr("call_action_start_new_call")
                                }
                                else if (rightPanel.contentLoader.item.objectName === "dialerPanel") {
                                    // Meme nom que le bouton qui l'ouvre.
                                    rightPanel.headerTitleText = "Clavier"
                                }
                                else if (rightPanel.contentLoader.item.objectName === "changeLayoutPanel") {
                                    //: "Modifier la disposition"
                                    rightPanel.headerTitleText = qsTr("call_action_change_layout")
                                }
                                else if (rightPanel.contentLoader.item.objectName === "callListPanel") {
                                    //: "Liste d'appel"
                                    rightPanel.headerTitleText = qsTr("call_action_go_to_calls_list")
                                }
                                else if (rightPanel.contentLoader.item.objectName === "chatPanel") {
                                    rightPanel.headerTitleText = ""
                                }
                                else if (rightPanel.contentLoader.item.objectName === "settingsPanel") {
                                    //: "Paramètres"
                                    rightPanel.headerTitleText = qsTr("call_action_go_to_settings")
                                }
                                else if (rightPanel.contentLoader.item.objectName === "screencastPanel") {
                                    //: "Partage de votre écran"
                                    rightPanel.headerTitleText = qsTr("conference_action_screen_sharing")
                                }
                                else if (rightPanel.contentLoader.item.objectName === "encryptionPanel") {
                                    //: Chiffrement
                                    rightPanel.headerTitleText = qsTr("call_encryption_title")
                                }
                                else if (rightPanel.contentLoader.item.objectName === "statsPanel") {
                                    //: Statistiques
                                    rightPanel.headerTitleText = qsTr("call_stats_title")
                                }
                            }
                            if (!rightPanel.contentLoader.item || rightPanel.contentLoader.item.objectName !== "participantListPanel") rightPanel.headerStack.currentIndex = 0

                            // Update tab focus properties
                            var firstContentFocusableItem = Utils.getFirstFocusableItemInItem(rightPanel.contentLoader.item)
                            rightPanel.firstContentFocusableItem = firstContentFocusableItem ?? mainWindow.firstButtonInBottomTab
                            var lastContentFocusableItem = Utils.getLastFocusableItemInItem(rightPanel.contentLoader.item)
                            if(lastContentFocusableItem != undefined){
                                lastContentFocusableItem.KeyNavigation.tab = mainWindow.firstButtonInBottomTab
                            }
                        }
                    }

                    // Binding on rightPadding {
                    //     when: rightPanel.contentLoader.item && rightPanel.contentLoader.item.objectName == "participantListView"
                    //     value: Utils.getSizeWithScreenRatio(10)
                    //     restoreMode: Binding.RestoreBindingOrValue
                    // }

                    Item {
                        id: numericPadContainer
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: childrenRect.height
                    }
                }
            }

            Component {
                id: callTransferPanel
                Control.Control {
                    id: callTransferControl
                    objectName: "callTransferPanel"
                    width: parent.width

                    Connections {
                        target: mainWindow
                        function onConferenceChanged() {
                            if (mainWindow.conference && callTransferControl.visible) rightPanel.visible = false
                        }
                    }

                    NewCallForm {
                        id: newCallForm
                        width: parent.width
                        height: rightPanel.contentItemHeight
                        Keys.onEscapePressed: event => {
                            rightPanel.visible = false
                            event.accepted = true
                        }
                        startGroupButtonVisible: false
                        displayCurrentCalls: true
                        searchBarColor: DefaultStyle.grey_0
                        searchBarBorderColor: DefaultStyle.grey_200
                        searchBarRightMaring: 0
                        onContactClicked: contact => {
                            var callsWin = UtilsCpp.getOrCreateCallsWindow()
                            if (contact)
                            //: "Confirmer le transfert"
                            callsWin.showConfirmationLambdaPopup(qsTr("call_transfer_confirm_dialog_tittle"),
                                                                //: "Vous allez transférer %1 à %2."
                                                                qsTr("call_transfer_confirm_dialog_message").arg(mainWindow.call.core.remoteName).arg(contact.core.fullName), "",
                                function (confirmed) {
                                    if (confirmed) {
                                        mainWindow.transferCallToContact(mainWindow.call,contact,newCallForm)
                                    }
                                }, undefined, undefined, undefined, "info", AppIcons.transferCall)
                        }
                        onTransferCallToAnotherRequested: dest => {
                            var callsWin = UtilsCpp.getOrCreateCallsWindow()
                            console.log("transfer to",dest)
                            callsWin.showConfirmationLambdaPopup(qsTr("call_transfer_confirm_dialog_tittle"),
                                                                qsTr("call_transfer_confirm_dialog_message").arg(mainWindow.call.core.remoteName).arg(dest.core.remoteName),"",
                                function (confirmed) {
                                if (confirmed) {
                                    mainWindow.call.core.lTransferCallToAnother(dest.core.remoteAddress)
                                }
                            }, undefined, undefined, undefined, "info", AppIcons.transferCall)
                        }
                        numPadPopup: numPadPopup

                        NumericPadPopup {
                            id: numPadPopup
                            parent: numericPadContainer
                            width: parent.width
                            roundedBottom: true
                            lastRowVisible: false
                            visible: false
                            Component.onCompleted: parent.height = height
                        }
                    }
                }
            }
            Component {
                id: newCallPanel
                Control.Control {
                    objectName: "newCallPanel"
                    width: parent.width
                    NewCallForm {
                        id: newCallForm
                        width: parent.width
                        height: rightPanel.contentItemHeight
                        startGroupButtonVisible: false
                        searchBarColor: DefaultStyle.grey_0
                        searchBarBorderColor: DefaultStyle.grey_200
                        numPadPopup: numericPad
                        onContactClicked: contact => {
                            mainWindow.startCallWithContact(contact, false, rightPanel)
                        }
                        Connections {
                            target: mainWindow
                            function onCallChanged() {
                                if (rightPanel.contentLoader.item.objectName === "newCallPanel")
                                    rightPanel.visible = false
                            }
                        }

                        NumericPadPopup {
                            id: numericPad
                            width: parent.width
                            parent: numericPadContainer
                            roundedBottom: true
                            visible: newCallForm.searchBar.numericPadButton.checked
                            onLaunchCall: {
                                rightPanel.visible = false
                                UtilsCpp.createCall(newCallForm.searchBar.text)
                            }
                            Component.onCompleted: parent.height = height
                        }
                    }
                }
            }
            Component {
                id: dialerPanel
                Control.Control {
                    id: dialerPanelContent
                    objectName: "dialerPanel"
                    width: parent.width
                    Keys.onEscapePressed: event => {
                        rightPanel.visible = false
                        event.accepted = true
                    }
                    // Chiffres tapes en grand en haut, pave juste dessous (DtmfPad) ; clavier de l'ordinateur :
                    // pave numerique seulement.
                    FocusScope {
                        width: parent.width
                        height: rightPanel.contentItemHeight
                        DtmfPad {
                            id: dtmfPad
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            call: callsModel.currentCall
                            Connections {
                                target: mainWindow
                                function onKeyPressedOnDialer(event) {
                                    dtmfPad.handleKeyPadEvent(event)
                                }
                            }
                        }
                    }
                }
            }
            Component {
                id: changeLayoutPanel
                ChangeLayoutForm {
                    id: changeLayoutPanel
                    objectName: "changeLayoutPanel"
                    width: parent.width
                    call: mainWindow.call
                    Connections {
                        target: mainWindow
                        function onConferenceChanged() {
                            if (mainWindow.conference && changeLayoutPanel.visible) rightPanel.visible = false
                        }
                    }
                    Keys.onEscapePressed: event => {
                        rightPanel.visible = false
                        event.accepted = true
                    }
                    onChangeLayoutRequested: index => {
                        mainWindow.changeLayout(index)
                    }
                }
            }
            Component {
                id: callListPanel
                ColumnLayout {
                    objectName: "callListPanel"
                    Keys.onEscapePressed: event => {
                        rightPanel.visible = false
                        event.accepted = true
                    }
                    spacing: 0
                    Component {
                        id: mergeCallPopupButton
                        PopupButton {
                            // « Reunir » passe par la barre des appels en attente, qui verifie que tous les appels sont
                            // internes (pas d'appel exterieur ni venu d'une file) : plus de fusion de tous les appels ici.
                            visible: false
                            id: popupbutton
                            popup.contentItem: IconLabelButton {
                                icon.source: AppIcons.arrowsMerge
                                icon.width: Utils.getSizeWithScreenRatio(32)
                                icon.height: Utils.getSizeWithScreenRatio(32)
                                //: call_action_merge_calls
                                text: qsTr("Merger tous les appels")
                                textSize: Utils.getSizeWithScreenRatio(14)
                                onClicked: {
                                    callsModel.lMergeAll()
                                    popupbutton.close()
                                }
                            }
                        }
                    }
                    RoundedPane {
                        Layout.fillWidth: true
                        Layout.maximumHeight: rightPanel.height
                        visible: callList.contentHeight > 0
                        leftPadding: Utils.getSizeWithScreenRatio(16)
                        rightPadding: Utils.getSizeWithScreenRatio(6)
                        topPadding: Utils.getSizeWithScreenRatio(15)
                        bottomPadding: Utils.getSizeWithScreenRatio(16)

                        Layout.topMargin: Utils.getSizeWithScreenRatio(15)
                        Layout.bottomMargin: Utils.getSizeWithScreenRatio(16)
                        Layout.leftMargin: Utils.getSizeWithScreenRatio(16)
                        Layout.rightMargin: Utils.getSizeWithScreenRatio(16)

                        contentItem: CallListView {
                            id: callList
                        }
                    }
                    Item {
                        Layout.fillHeight: true
                    }
                    Connections {
                        target: rightPanel.contentLoader
                        function onItemChanged() {
                            if (rightPanel.contentLoader.item.objectName === "callListPanel") {
                                rightPanel.customHeaderButtons = mergeCallPopupButton.createObject(rightPanel)
                            }
                        }
                    }
                }
            }
            Component {
                id: chatPanel
                Control.Control {
                    objectName: "chatPanel"
                    width: parent.width
                    Component.onCompleted: chatView.forceActiveFocus()
                    contentItem: SelectedChatView {
                        id: chatView
                        width: parent.width
                        height: rightPanel.contentItemHeight
                        Keys.onEscapePressed: event => {
                            rightPanel.visible = false
                            event.accepted = true
                        }
                        call: mainWindow.call
                        chat: mainWindow.chat

                        Connections {
                            enabled: rightPanel.contentLoader.item.objectName === "chatPanel"
                            target: chatView.callHeaderContent
                            function onHeightChanged() {
                                rightPanel.headerStack.height = chatView.callHeaderContent.height
                            }

                        }
                    }
                    Connections {
                        target: rightPanel.contentLoader
                        function onItemChanged() {
                            if (rightPanel.contentLoader.item.objectName === "chatPanel") {
                                rightPanel.customHeaderButtons = chatView.callHeaderContent
                                rightPanel.headerStack.height = chatView.callHeaderContent.height
                            }
                        }
                    }
                }
            }
            Component {
                id: settingsPanel
                MultimediaSettings {
                    id: inSettingsPanel
                    objectName: "settingsPanel"
                    Keys.onEscapePressed: event => {
                        rightPanel.visible = false
                        event.accepted = true
                    }
                    call: mainWindow.call
                    height: childrenRect.height
                    width: parent.width
                }
            }
            Component {
                id: screencastPanel
                Control.Control {
                    id: screencastControl
                    objectName: "screencastPanel"
                    width: parent.width
                    Keys.onEscapePressed: event => {
                        rightPanel.visible = false
                        event.accepted = true
                    }
                    Connections {
                        target: mainWindow
                        function onConferenceChanged() {
                            if (mainWindow.conference && screencastControl.visible) rightPanel.visible = false
                        }
                    }
                    contentItem: ScreencastSettings {
                        id: screencastsettings
                        anchors.topMargin: Utils.getSizeWithScreenRatio(16)
                        width: parent.width
                        call: mainWindow.call
                        onIsLocalScreenSharingChanged:  {
                            // Check if component is ready as well so we can reopen the panel after starting sharing screen
                            // and change shared window or screen if needed
                            if (isLocalScreenSharing && status === Component.Ready) rightPanel.visible = false
                        }
                    }
                }
            }
            Component {
                id: participantListPanel
                Control.Control {
                    id: participantControl
                    width: parent.width
                    objectName: "participantListPanel"
                    Keys.onEscapePressed: event => {
                        rightPanel.visible = false
                        event.accepted = true
                    }
                    Connections {
                        target: mainWindow
                        function onConferenceChanged() {
                            if (!mainWindow.conference && participantControl.visible) rightPanel.visible = false
                        }
                    }
                    Control.StackView {
                        id: participantsStack
                        width: parent.width
                        height: rightPanel.contentItemHeight
                        // anchors.fill: parent
                        // anchors.bottomMargin: Utils.getSizeWithScreenRatio(16)
                        // anchors.leftMargin: Utils.getSizeWithScreenRatio(17)
                        // anchors.rightMargin: Utils.getSizeWithScreenRatio(17)
                        initialItem: participantListComp
                        onCurrentItemChanged: rightPanel.headerStack.currentIndex = currentItem.Control.StackView.index
                        property list<string> selectedParticipants

                        Connections {
                            target: rightPanel
                            function onReturnRequested() {
                                participantsStack.pop()
                            }
                        }

                        Component {
                            id: participantListComp
                            ParticipantListView {
                                id: participantList
                                objectName: "participantListView"
                                call: mainWindow.call
                                height: contentHeight
                                width: parent.width
                                rightMargin: 0
                                Component {
                                    id: headerbutton
                                    PopupButton {
                                        popup.contentItem: IconLabelButton {
                                            icon.source: AppIcons.shareNetwork
                                            //: Partager le lien de la réunion
                                            text: qsTr("conference_share_link_title")
                                            onClicked: {
                                                UtilsCpp.copyToClipboard(mainWindow.conference ? mainWindow.conference.core.uri : mainWindow.call.core.remoteAddress)
                                                //: Copié
                                                showInformationPopup(qsTr("copied"),
                                                //: Le lien de la réunion a été copié dans le presse-papier
                                                qsTr("information_popup_meeting_address_copied_to_clipboard"),true)
                                            }
                                        }
                                    }
                                }
                                
                                onVisibleChanged: if (visible) {
                                    rightPanel.customHeaderButtons = headerbutton.createObject(rightPanel)
                                    //: "Participants (%1)"
                                    rightPanel.headerTitleText = qsTr("conference_participants_list_title").arg(count)
                                }
                                onAddParticipantRequested: participantsStack.push(addParticipantComp)
                                onCountChanged: {
                                    rightPanel.headerTitleText = qsTr("conference_participants_list_title").arg(count)
                                }
                                Connections {
                                    target: participantsStack
                                    function onCurrentItemChanged() {
                                        if (participantsStack.currentItem == participantList)
                                            rightPanel.headerTitleText = qsTr("conference_participants_list_title").arg(participantList.count)
                                    }
                                }
                                Connections {
                                    target: rightPanel
                                    function onValidateRequested() {
                                        participantList.model.addAddresses(participantsStack.selectedParticipants)
                                        participantsStack.pop()
                                    }
                                }
                            }
                        }
                        Component {
                            id: addParticipantComp
                            AddParticipantsForm {
                                id: addParticipantLayout
                                // height: childrenRect.height
                                // width: parent.width
                                searchBarColor: DefaultStyle.grey_0
                                searchBarBorderColor: DefaultStyle.grey_200
                                onSelectedParticipantsCountChanged: {
                                    rightPanel.headerSubtitleText = qsTr("group_call_participant_selected", '', selectedParticipantsCount).arg(selectedParticipantsCount)
                                    participantsStack.selectedParticipants = selectedParticipants
                                }
                                Connections {
                                    target: participantsStack
                                    function onCurrentItemChanged() {
                                        if (participantsStack.currentItem == addParticipantLayout) {
                                            rightPanel.headerTitleText = qsTr("meeting_schedule_add_participants_title")
                                            rightPanel.headerSubtitleText = qsTr("group_call_participant_selected", '', addParticipantLayout.selectedParticipants.length).arg(addParticipantLayout.selectedParticipants.length)
                                        } else {
                                            rightPanel.headerSubtitleText = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Component {
                id: encryptionPanel
                EncryptionSettings {
                    objectName: "encryptionPanel"
                    call: mainWindow.call
                    width: parent.width
                    onEncryptionValidationRequested: zrtpValidation.open()
                }
            }
            Component {
                id: statsPanel
                CallStatistics {
                    objectName: "statsPanel"
                    width: parent.width
                    call: mainWindow.call
                }
            }
            Component {
                id: waitingRoom
                WaitingRoom {
                    id: waitingRoomIn
                    objectName: "waitingRoom"
                    Layout.alignment: Qt.AlignCenter
                    onSettingsButtonCheckedChanged: {
                        if (settingsButtonChecked) {
                            rightPanel.visible = true
                            rightPanel.replace(settingsPanel, {"forceUpdatingDeviceWithoutSaving": true})
                        } else {
                            rightPanel.visible = false
                        }
                    }
                    Binding {
                        target: callStatusText
                        when: middleItemStackView.currentItem.objectName === "waitingRoom"
                        property: "text"
                        value: waitingRoomIn.conferenceInfo ? waitingRoomIn.conferenceInfo.core.subject : ''
                    }
                    Binding {
                        target: conferenceDate
                        when: middleItemStackView.currentItem.objectName === "waitingRoom"
                        property: "text"
                        value: waitingRoomIn.conferenceInfo ? waitingRoomIn.conferenceInfo.core.startEndDateString : ''
                    }
                    Connections {
                        target: rightPanel
                        function onVisibleChanged() {
                            if (!rightPanel.visible) {
                                waitingRoomIn.settingsButtonChecked = false
                            }
                        }
                    }
                    Connections {
                        target: mainWindow
                        function onSetUpConferenceRequested(conferenceInfo) {
                            waitingRoomIn.conferenceInfo = conferenceInfo
                        }
                    }
                    onJoinConfRequested: uri => {
                        mainWindow.joinConference(uri, {
                            "microEnabled": microEnabled,
                            "localVideoEnabled": localVideoEnabled
                        })
                    }
                    onCancelJoiningRequested: mainWindow.cancelJoinConference()
                    onCancelAfterJoinRequested: mainWindow.cancelAfterJoin()
                }
            }
            Component {
                id: inCallItem
                Loader {
                    objectName: "inCallItem"
                    asynchronous: true
                    sourceComponent: Item {
                        CallLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Utils.getSizeWithScreenRatio(20)
                            anchors.rightMargin: rightPanel.visible ? 0 : Utils.getSizeWithScreenRatio(10) // Grid and AS have 10 in right margin (so apply -10 here)
                            anchors.topMargin: Utils.getSizeWithScreenRatio(10)
                            call: mainWindow.call
                            callTerminatedByUser: mainWindow.callTerminatedByUser
                        }
                    }
                }
            }


        }
    }
}
