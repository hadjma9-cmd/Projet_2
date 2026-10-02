import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Qt.labs.qmlmodels
import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

ListView {
    id: mainItem
    spacing: Utils.getSizeWithScreenRatio(4)
    property ChatGui chat
    property color backgroundColor
    property bool lastItemVisible: false
    property int lastIndexFoundWithFilter: -1
    property real busyIndicatorSize: Utils.getSizeWithScreenRatio(60)
    property bool loading: false
    // La roue n'apparait que si le chargement se prolonge : un chargement rapide ne fait plus
    // clignoter « zone vide, roue, messages ».
    property bool busyIndicatorShown: false
    onLoadingChanged: {
        if (loading) {
            busyIndicatorDelay.restart()
        } else {
            busyIndicatorDelay.stop()
            busyIndicatorShown = false
        }
    }
    Timer {
        id: busyIndicatorDelay
        interval: 300
        onTriggered: mainItem.busyIndicatorShown = mainItem.loading
    }

    // Position de lecture de chaque conversation, retrouvee en y revenant. Cle : identifiant de la
    // conversation ; valeur : index du message affiche en haut. Liste inversee (le plus recent en
    // bas) : positionViewAtIndex(..., ListView.End) y place l'element en haut de la vue.
    property var readingPositions: ({})
    property string displayedChatId: ""
    function saveReadingPosition() {
        if (displayedChatId === "") return
        if (atYEnd) {
            // Deja sur les derniers messages : on y reviendra naturellement.
            delete readingPositions[displayedChatId]
            return
        }
        var topIndex = indexAt(contentX + width / 2, contentY + 1)
        if (topIndex >= 0) readingPositions[displayedChatId] = topIndex
    }

    // Conversations recentes chargees des l'ouverture de l'onglet, pour s'ouvrir sans attente.
    Component.onCompleted: eventLogProxy.preloadRecentChats(5)
    property bool isEncrypted: chat && chat.core.isEncrypted
    property bool showEncryptedInfo: AppCpp.currentAccount !== null && AppCpp.currentAccount.core.limeServerUrl !== "" && AppCpp.currentAccount.core.conferenceFactoryAddress !== ""
    highlightFollowsCurrentItem: true

    verticalLayoutDirection: ListView.BottomToTop
    signal showReactionsForMessageRequested(ChatMessageGui chatMessage)
    signal showImdnStatusForMessageRequested(ChatMessageGui chatMessage)
    signal replyToMessageRequested(ChatMessageGui chatMessage)
    signal forwardMessageRequested(ChatMessageGui chatMessage)
    signal editMessageRequested(ChatMessageGui chatMessage)
    signal requestHighlight(int indexToHighlight)
    signal requestAutoPlayVoiceRecording(int indexToPlay)
    signal searchMessageByIdRequested(string id)
    currentIndex: -1

    property string filterText
    onFilterTextChanged: {
        lastIndexFoundWithFilter = -1
        if (filterText === "") return
        eventLogProxy.filterText = filterText
        var indexVisible = indexAt(contentX, contentY)
        eventLogProxy.findIndexCorrespondingToFilter(indexVisible, true, true)
    }
    signal findIndexWithFilter(bool forward)
    property bool searchForward: true
    onFindIndexWithFilter: (forward) => {
        if (filterText === "") return
        searchForward = forward
        eventLogProxy.findIndexCorrespondingToFilter(currentIndex, searchForward, false)
    }
    onSearchMessageByIdRequested: (id) => {
        eventLogProxy.findChatMessageById(id)
    }

    Button {
        visible: !mainItem.lastItemVisible && !atYEnd
        icon.source: AppIcons.downArrow
        leftPadding: Utils.getSizeWithScreenRatio(20)
        rightPadding: Utils.getSizeWithScreenRatio(20)
        topPadding: Utils.getSizeWithScreenRatio(20)
        bottomPadding: Utils.getSizeWithScreenRatio(20)
        anchors.bottom: parent.bottom
        style: ButtonStyle.main
        anchors.right: parent.right
        anchors.bottomMargin: Utils.getSizeWithScreenRatio(18)
        anchors.rightMargin: Utils.getSizeWithScreenRatio(18)
        onClicked: {
            var index = eventLogProxy.findFirstUnreadIndex()
            mainItem.positionViewAtIndex(index, ListView.Contain)
            eventLogProxy.markIndexAsRead(index)
        }
        UnreadNotification {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Utils.getSizeWithScreenRatio(-5)
            anchors.rightMargin: Utils.getSizeWithScreenRatio(-5)
            unread: mainItem.chat?.core.unreadMessagesCount || 0
        }
    }

    onAtYBeginningChanged: {
        if (atYBeginning && count !== 0) {
            eventLogProxy.displayMore()
        }
    }
    onAtYEndChanged: {
        if (atYEnd && chat && count !== 0) {
            chat.core.lMarkAsRead()
        }
    }

    Connections {
        // enabled: chat !== null
        target: mainItem.chat ? mainItem.chat.core : null
        function onUnreadMessagesCountChanged() {
            if (mainItem.atYEnd){
                if (mainWindow.active) {
                    mainItem.chat.core.lMarkAsRead()
                }
            }
        }
    }
    Connections {
        target: mainWindow
        function onActiveChanged() {
            if (mainWindow.active && mainItem.atYEnd && mainItem.chat) mainItem.chat.core.lMarkAsRead()
        }
    }

    model: EventLogProxy {
        id: eventLogProxy
        chatGui: mainItem.chat
        filterText: mainItem.filterText
        initialDisplayItems: 20
        displayItemsStep: 20
        onModelAboutToBeReset: {
            loading = true
        }
        onChatAboutToChange: {
            mainItem.saveReadingPosition()
            loading = true
        }
        onModelReset: loading = false
        onModelUpdated: {
            loading = false
            var index = eventLogProxy.findFirstUnreadIndex()
            var itemToSelect = mainItem.itemAtIndex(index)
            var chatId = mainItem.chat ? mainItem.chat.core.identifier : ""
            // Retour sur une conversation quittee en cours de lecture : on reprend au meme endroit.
            // Sinon (premiere ouverture, rechargement de la meme conversation), comportement habituel.
            var savedIndex = chatId !== mainItem.displayedChatId ? mainItem.readingPositions[chatId] : undefined
            if (savedIndex !== undefined) eventLogProxy.loadUntil(savedIndex)
            if (savedIndex !== undefined && savedIndex < mainItem.count) {
                mainItem.positionViewAtIndex(savedIndex, ListView.End)
            } else {
                mainItem.positionViewAtIndex(index, ListView.Beginning)
            }
            var lastMessage = itemAtIndex(0)
            // Peut ne pas exister si la position restauree est loin des derniers messages.
            mainItem.lastItemVisible = lastMessage ? lastMessage.isFullyVisible : false
            eventLogProxy.markIndexAsRead(index)
            mainItem.displayedChatId = chatId
        }
        onEventInsertedByUser: (index) => {
            mainItem.positionViewAtIndex(index, ListView.Beginning)
        }
        onIndexWithFilterFound: (index) => {
            if (index !== -1) {
                currentIndex = index
                mainItem.positionViewAtIndex(index, ListView.Center)
                mainItem.requestHighlight(index)
                mainItem.lastIndexFoundWithFilter = index
            } else {
                if (mainItem.lastIndexFoundWithFilter !== index) {
                    //: Find message
                    UtilsCpp.showInformationPopup(qsTr("popup_info_find_message_title"),
                    mainItem.searchForward 
                        //: Last result reached
                        ? qsTr("info_popup_last_result_message")
                        //: First result reached
                        : qsTr("info_popup_first_result_message"), false, mainWindow)
                    mainItem.positionViewAtIndex(mainItem.lastIndexFoundWithFilter, ListView.Center)
                    mainItem.requestHighlight(mainItem.lastIndexFoundWithFilter)
                }
                else {
                    //: Find message
                    UtilsCpp.showInformationPopup(qsTr("popup_info_find_message_title"),
                    //: No result found
                    qsTr("info_popup_no_result_message"), false, mainWindow)
                }
            }
        }
        onFoundMessagById: (index) => {
            if (index !== -1) {
                currentIndex = index
                mainItem.positionViewAtIndex(index, ListView.Center)
                mainItem.requestHighlight(index)
            }
        }
    }

    // Messages plus hauts que la vue, hors pied de liste : la marge du pied en dependait directement, et le pied
    // change la hauteur du contenu (boucle signalee dans le journal). Mise a jour differee et sans le pied : stable.
    property bool contentOverflows: false
    function updateContentOverflows() {
        contentOverflows = contentHeight - (footerItem ? footerItem.height : 0) > height
    }
    onContentHeightChanged: Qt.callLater(updateContentOverflows)
    onHeightChanged: Qt.callLater(updateContentOverflows)

    footer: RowLayout {
        visible: mainItem.chat && !mainItem.loading
        height: visible ? (headerMessage.height + headerMessage.topMargin + headerMessage.bottomMargin) : Utils.getSizeWithScreenRatio(30)
        // width: headerMessage.width
        anchors.horizontalCenter: parent.horizontalCenter
        Control.Control {
            id: headerMessage
            visible: mainItem.showEncryptedInfo
            property int topMargin: Utils.getSizeWithScreenRatio(mainItem.contentOverflows ? 30 : 50)
            property int bottomMargin: Utils.getSizeWithScreenRatio(30)
            property int sideMargin: Utils.getSizeWithScreenRatio(5)
            Layout.topMargin: topMargin
            Layout.bottomMargin: bottomMargin
            Layout.alignment: Qt.AlignTop
            Layout.maximumWidth: mainItem.width - (sideMargin*2)
            padding: Utils.getSizeWithScreenRatio(10)
            background: Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: DefaultStyle.main2_200
                border.width: Utils.getSizeWithScreenRatio(2)
                radius: Utils.getSizeWithScreenRatio(10)
            }
            contentItem: RowLayout {
                EffectImage {
                    Layout.preferredWidth: Utils.getSizeWithScreenRatio(23)
                    Layout.preferredHeight: Utils.getSizeWithScreenRatio(23)
                    imageSource: mainItem.isEncrypted ? AppIcons.lockSimple : AppIcons.lockSimpleOpen
                    colorizationColor: mainItem.isEncrypted ? DefaultStyle.info_500_main : DefaultStyle.warning_700
                }
                ColumnLayout {
                    spacing: Utils.getSizeWithScreenRatio(2)
                    Text {
                        text: mainItem.isEncrypted
                            //: End to end encrypted chat
                            ? qsTr("chat_message_list_encrypted_header_title")
                            //: This conversation is not encrypted !
                            : qsTr("unencrypted_conversation_warning")
                        Layout.fillWidth: true
                        color: mainItem.isEncrypted ? DefaultStyle.info_500_main : DefaultStyle.warning_700
                        font {
                            pixelSize: Typography.p2.pixelSize
                            weight: Typography.p2.weight
                        }
                    }
                    Text {
                        text: mainItem.isEncrypted
                            //: Messages in this conversation are e2e encrypted. \n Only your correspondent can decrypt them.
                            ? qsTr("chat_message_list_encrypted_header_message")
                            //: Messages are not end to end encrypted, \n make sure you don't share any sensitive information !
                            : qsTr("chat_message_list_not_encrypted_header_message")
                        Layout.fillWidth: true
                        color: DefaultStyle.grey_400
                        font {
                            pixelSize: Typography.p3.pixelSize
                            weight: Typography.p3.weight
                        }
                    }
                }
            }
        }
    }
    footerPositioning: mainItem.contentHeight > mainItem.height ? ListView.InlineFooter : ListView.PullBackFooter
    headerPositioning: ListView.OverlayHeader
    header: Control.Control {
        visible: composeLayout.composingName !== "" && composeLayout.composingName !== undefined
        width: mainItem.width
        // Taille naturelle de la ligne (implicitHeight) : sa hauteur dependait de celle du bandeau, et inversement.
        height: visible ? composeLayout.implicitHeight + topPadding + bottomPadding : 0
        z: mainItem.z + 2
        topPadding: Utils.getSizeWithScreenRatio(5)
        bottomPadding: Utils.getSizeWithScreenRatio(5)
        background: Rectangle {
            anchors.fill: parent
            color: mainItem.backgroundColor
        }
        contentItem: RowLayout {
            id: composeLayout
            property var composingName: mainItem.chat?.core.composingName
            Avatar {
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(20)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(20)
                shadowEnabled: false
                _address: mainItem.chat?.core.composingAddress
            }
            Text {
                Layout.fillWidth: true
                font {
                    pixelSize: Typography.p3.pixelSize
                    weight: Typography.p3.weight
                }
                //: %1 is writing…
                text: qsTr("chat_message_is_writing_info").arg(composeLayout.composingName)
            }
        }
    }

    BusyIndicator {
        anchors.horizontalCenter: mainItem.horizontalCenter
        anchors.verticalCenter: mainItem.verticalCenter
        visible: mainItem.busyIndicatorShown
        height: visible ? mainItem.busyIndicatorSize : 0
        width: mainItem.busyIndicatorSize
        indicatorHeight: mainItem.busyIndicatorSize
        indicatorWidth: mainItem.busyIndicatorSize
        indicatorColor: DefaultStyle.main1_500_main
    }

    
	Dialog {
        id: messageDeletionDialog
        width: Utils.getSizeWithScreenRatio(637)
        //: "Supprimer le message ?"
        title: qsTr("conversation_dialog_delete_chat_message_title")
        property var chatMessage
        buttons: RowLayout {
				id: buttonsLayout
				Layout.alignment: Qt.AlignBottom | Qt.AlignRight
                spacing: Utils.getSizeWithScreenRatio(20)
				MediumButton {
					id: firstButtonId
					text: qsTr("conversation_dialog_delete_locally_label")
					style: ButtonStyle.main
					onClicked: {
						messageDeletionDialog.chatMessage.core.lDelete()
						messageDeletionDialog.close()
					}
					KeyNavigation.left: thirdButtonId
					KeyNavigation.right: secondButtonId
				}
				MediumButton {
					id: secondButtonId
					visible: !!messageDeletionDialog.chatMessage && messageDeletionDialog.chatMessage.core.isOutgoing && messageDeletionDialog.chatMessage.core.isRetractable && !messageDeletionDialog.chatMessage.core.isRetracted
					text: qsTr("conversation_dialog_delete_for_everyone_label")
					style: ButtonStyle.main
					onClicked: {
						messageDeletionDialog.chatMessage.core.lRetract()
						messageDeletionDialog.close()
					}
					KeyNavigation.left: firstButtonId
					KeyNavigation.right: thirdButtonId
				}
				MediumButton {
					id: thirdButtonId
					text: qsTr("dialog_cancel")
					style: ButtonStyle.secondary
					onClicked: {
						messageDeletionDialog.close()
					}
					KeyNavigation.left: secondButtonId
					KeyNavigation.right: firstButtonId
				}
			}
    }
    
    delegate: DelegateChooser {
        role: "eventType"
        DelegateChoice {
            roleValue: "chatMessage"
            delegate: ChatMessage {
                id: chatMessageDelegate
                visible: !mainItem.loading
                property int yoff: Math.round(chatMessageDelegate.y - mainItem.contentY)
                property bool isFullyVisible: (yoff > mainItem.y && yoff + height < mainItem.y + mainItem.height)
                chatMessage: modelData.core.chatMessageGui
                onIsFullyVisibleChanged: {
                    if (index === 0) {
                        mainItem.lastItemVisible = isFullyVisible
                    }
                }
                Component.onCompleted: {
                    if (index === 0) {
                        mainItem.lastItemVisible = isFullyVisible
                    }
                }
                chat: mainItem.chat
                searchedTextPart: mainItem.filterText
                maxWidth: Math.round(mainItem.width * (3/4))
                width: mainItem.width
                property var previousIndex: index - 1
                property ChatMessageGui nextChatMessage: index <= 0 
                    ? null 
                    : eventLogProxy.getEventAtIndex(index-1)
                        ? eventLogProxy.getEventAtIndex(index-1).core.chatMessageGui
                        : null
                property var previousFromAddress: eventLogProxy.getEventAtIndex(index+1)?.core.chatMessage?.fromAddress
                backgroundColor: isRemoteMessage ? DefaultStyle.main2_100 : DefaultStyle.main1_100
                isFirstMessage: !previousFromAddress || previousFromAddress !== chatMessage.core.fromAddress
                anchors.right: !isRemoteMessage && parent
                    ? parent.right
                    : undefined

                onMessageDeletionRequested: {
                    messageDeletionDialog.chatMessage = chatMessage
                    messageDeletionDialog.open()
                }
                onMessageEditionRequested: mainItem.editMessageRequested(chatMessage)
                onShowReactionsForMessageRequested: mainItem.showReactionsForMessageRequested(chatMessage)
                onShowImdnStatusForMessageRequested: mainItem.showImdnStatusForMessageRequested(chatMessage)
                onReplyToMessageRequested: mainItem.replyToMessageRequested(chatMessage)
                onSearchMessageByIdRequested: (id) => mainItem.searchMessageByIdRequested(id)
                onForwardMessageRequested: mainItem.forwardMessageRequested(chatMessage)
                onEndOfVoiceRecordingReached: {
                    if (nextChatMessage && nextChatMessage.core.isVoiceRecording) mainItem.requestAutoPlayVoiceRecording(index - 1)
                }
                Connections {
                    target: mainItem
                    function onRequestHighlight(indexToHighlight) {
                        if (indexToHighlight === index) {
                            requestHighlight()
                        }
                    }
                    function onRequestAutoPlayVoiceRecording(indexToPlay) {
                        if (indexToPlay === index) {
                            chatMessageDelegate.requestAutoPlayVoiceRecording()
                        }
                    }
                }
				Connections {
					target: chatMessage.core
					onIsRetractedChanged: {
						if (chatMessage.core.isRetracted && chatMessage.core.isOutgoing) {
								UtilsCpp.showInformationPopup(qsTr("info_toast_deleted_title"),
															//: The message has been deleted
															qsTr("info_toast_deleted_message"), true)
						}
					}
				}
            }
        }

        DelegateChoice {
            roleValue: "event"
            delegate: Item {
                id: eventDelegate
                visible: !mainItem.loading
                property int yoff: Math.round(eventDelegate.y - mainItem.contentY)
                property bool isFullyVisible: (yoff > mainItem.y && yoff + height < mainItem.y + mainItem.height)
                onIsFullyVisibleChanged: {
                    if (index === 0) {
                        mainItem.lastItemVisible = isFullyVisible
                    }
                }
                property bool showTopMargin: !header.visible && index == 0
                width: mainItem.width
                height: (showTopMargin ? Utils.getSizeWithScreenRatio(30) : 0) + eventItem.implicitHeight
                Event {
                    id: eventItem
                    anchors.top: parent.top
                    anchors.topMargin: showTopMargin ? Utils.getSizeWithScreenRatio(30) : 0
                    width: parent.width
                    eventLogGui: modelData
                }
            }
        }
        
		DelegateChoice {
            roleValue: "ephemeralEvent"
            delegate: Item {
                id: ephemeralEventDelegate
                visible: !mainItem.loading
                property int yoff: Math.round(ephemeralEventDelegate.y - mainItem.contentY)
                property bool isFullyVisible: (yoff > mainItem.y && yoff + height < mainItem.y + mainItem.height)
                onIsFullyVisibleChanged: {
                    if (index === 0) {
                        mainItem.lastItemVisible = isFullyVisible
                    }
                }
                property bool showTopMargin: !header.visible && index == 0
                width: mainItem.width
                //height: Utils.getSizeWithScreenRatio(40)
                height: (showTopMargin ? Utils.getSizeWithScreenRatio(30) : 0) + ephemeralEventItem.height
                EphemeralEvent {
                    id: ephemeralEventItem
                    anchors.top: parent.top
                    anchors.topMargin: showTopMargin ? Utils.getSizeWithScreenRatio(30) : 0
                    eventLogGui: modelData
                }
            }
        }
    }
}
