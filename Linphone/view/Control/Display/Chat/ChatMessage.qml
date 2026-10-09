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

Control.Control {
    id: mainItem
    property color backgroundColor
    property bool isFirstMessage

    property ChatMessageGui chatMessage
    property ChatGui chat
    property string searchedTextPart
    property string ownReaction: chatMessage? chatMessage.core.ownReaction : ""
    property string fromAddress: chatMessage? chatMessage.core.fromAddress : ""
    property bool isRemoteMessage: chatMessage? chatMessage.core.isRemoteMessage : false
    property bool isFromChatGroup: chatMessage? chatMessage.core.isFromChatGroup : false
    property bool isReply: chatMessage? chatMessage.core.isReply : false
    property bool isForward: chatMessage? chatMessage.core.isForward : false
    property string replyText: chatMessage? chatMessage.core.replyText : ""
    property string replyMessageId: chatMessage? chatMessage.core.replyMessageId : ""
    property var msgState: chatMessage ? chatMessage.core.messageState : LinphoneEnums.ChatMessageState.StateIdle
    hoverEnabled: true
    property bool linkHovered: false
    property real maxWidth: parent ? parent.width : Utils.getSizeWithScreenRatio(300)
    // Barre d'actions (⋯, reactions) partagee par la conversation (ChatMessageActions) : elle se pose dans
    // actionsSlotItem au survol de ce message.
    property Item actionBar: null
    readonly property Item actionsSlotItem: actionsSlot
    readonly property string selectedText: chatBubbleContent.selectedText
    onHoveredChanged: {
        if (!actionBar) return
        if (hovered) actionBar.show(mainItem)
        else actionBar.hide(mainItem)
    }
    // Bulle recyclee pour un autre message (liste de la conversation) : rien ne doit rester du precedent.
    function resetForReuse() {
        if (actionBar) actionBar.release(mainItem)
        hightlightTimer.stop()
        highlightRectangle.opacity = 0
        linkHovered = false
        chatBubbleContent.resetForReuse()
    }
    Component.onDestruction: if (actionBar) actionBar.release(mainItem)

    leftPadding: isRemoteMessage ? Utils.getSizeWithScreenRatio(5) : 0

    signal messageDeletionRequested()
	signal messageEditionRequested()
	signal isFileHoveringChanged(bool isFileHovering)
    signal showReactionsForMessageRequested()
    signal showImdnStatusForMessageRequested()
    signal replyToMessageRequested()
    signal forwardMessageRequested()
    signal endOfVoiceRecordingReached()
    signal requestAutoPlayVoiceRecording()
    signal searchMessageByIdRequested(string id)
    onRequestAutoPlayVoiceRecording: chatBubbleContent.requestAutoPlayVoiceRecording()

    Timer {
        id: hightlightTimer
        interval: 1000
        repeat: false
        onTriggered: highlightRectangle.opacity = 0
    }
    function requestHighlight() {
        highlightRectangle.opacity = 0.8
        hightlightTimer.start()
    }

    background: Item {
        anchors.fill: parent
    }
    
    function handleDefaultMouseEvent(event) {
		if (event.button === Qt.RightButton && actionBar) {
			actionBar.openOptions(mainItem)
		}
	}

    contentItem: ColumnLayout {
        spacing: Utils.getSizeWithScreenRatio(5)
        Text {
            id: fromNameText
            Layout.alignment: Qt.AlignTop
            Layout.leftMargin: mainItem.isFromChatGroup ? Utils.getSizeWithScreenRatio(9) + avatar.width : 0
            visible: mainItem.isFromChatGroup && mainItem.isRemoteMessage && mainItem.isFirstMessage && !replyLayout.visible
            maximumLineCount: 1
            width: implicitWidth
            x: mapToItem(this, chatBubble.x, chatBubble.y).x
            text: mainItem.chatMessage.core.fromName
            color: DefaultStyle.main2_500_main
            font {
                pixelSize: Typography.p4.pixelSize
                weight: Typography.p4.weight
            }
        }
        RowLayout {
            id: forwardLayout
            spacing: Utils.getSizeWithScreenRatio(8)
            visible: mainItem.isForward
            Layout.leftMargin: mainItem.isFromChatGroup ? Utils.getSizeWithScreenRatio(9) + avatar.width : 0
            Layout.alignment: mainItem.isRemoteMessage ? Qt.AlignLeft: Qt.AlignRight
            EffectImage {
                imageSource: AppIcons.forward
                colorizationColor: DefaultStyle.main2_500_main
                Layout.preferredWidth: Utils.getSizeWithScreenRatio(12)
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(12)
            }
            Text {
                //: Forwarded
                text: qsTr("chat_message_forwarded")
                color: DefaultStyle.main2_600
                font {
                    pixelSize: Typography.p4.pixelSize
                    weight: Typography.p4.weight
                }
            }
        }
        RowLayout {
            id: replyLayout
            visible: mainItem.isReply
            Layout.leftMargin: mainItem.isFromChatGroup ? Utils.getSizeWithScreenRatio(9) + avatar.width : 0
            layoutDirection: mainItem.isRemoteMessage ? Qt.LeftToRight : Qt.RightToLeft
            ColumnLayout {
                spacing: Utils.getSizeWithScreenRatio(5)
                RowLayout {
                    id: replyLabel
                    spacing: Utils.getSizeWithScreenRatio(8)
                    Layout.fillWidth: false
                    Layout.alignment: mainItem.isRemoteMessage ? Qt.AlignLeft : Qt.AlignRight
                    EffectImage {
                        imageSource: AppIcons.reply
                        colorizationColor: DefaultStyle.main2_500_main
                        Layout.preferredWidth: Utils.getSizeWithScreenRatio(12)
                        Layout.preferredHeight: Utils.getSizeWithScreenRatio(12)
                    }
                    Text {
                        Layout.alignment: mainItem.isRemoteMessage ? Qt.AlignLeft: Qt.AlignRight
                        text: mainItem.isRemoteMessage 
                            ? mainItem.chatMessage.core.repliedToName !== "" 
                                //: %1 replied to %2
                                ? qsTr("chat_message_remote_replied_to").arg(mainItem.chatMessage.core.fromName).arg(mainItem.chatMessage.core.repliedToName)
                                //: %1 replied
                                : qsTr("chat_message_remote_replied").arg(mainItem.chatMessage.core.fromName)
                            : mainItem.chatMessage.core.repliedToName !== "" 
                                //: You replied to %1
                                ? qsTr("chat_message_user_replied_to").arg(mainItem.chatMessage.core.repliedToName)
                                //: You replied
                                : qsTr("chat_message_user_replied")
                        color: DefaultStyle.main2_600
                        font {
                            pixelSize: Typography.p4.pixelSize
                            weight: Typography.p4.weight
                        }
                    }
                }
                Control.Control {
                    id: replyMessage
                    visible: mainItem.replyText !== ""
                    Layout.alignment: mainItem.isRemoteMessage ? Qt.AlignLeft : Qt.AlignRight
                    spacing: Utils.getSizeWithScreenRatio(5)
                    topPadding: Utils.getSizeWithScreenRatio(12)
                    bottomPadding: Utils.getSizeWithScreenRatio(19)
                    leftPadding: Utils.getSizeWithScreenRatio(18)
                    rightPadding: Utils.getSizeWithScreenRatio(18)
                    Layout.preferredWidth: Math.min(implicitWidth, mainItem.maxWidth - avatar.implicitWidth)
                    background: Rectangle {
                        anchors.fill: parent
                        color: DefaultStyle.grey_200
                        radius: Utils.getSizeWithScreenRatio(16)
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                mainItem.searchMessageByIdRequested(mainItem.replyMessageId)
                            }
                        }
                    }
                    contentItem: Text {
                        Layout.fillWidth: true
                        text: mainItem.replyText
                        color: DefaultStyle.main2_800
                        font {
                            pixelSize: Typography.p1.pixelSize
                            weight: Typography.p1.weight
                        }
                    }
                }
            }
            Item{Layout.fillWidth: true}
        }
        RowLayout {
            id: bubbleLayout
            z: replyLayout.z + 1
            spacing: 0
            layoutDirection: mainItem.isRemoteMessage ? Qt.LeftToRight : Qt.RightToLeft
            Layout.topMargin: replyMessage.visible ? Utils.getSizeWithScreenRatio(-20) : 0

            Avatar {
                id: avatar
                shadowEnabled: false
                visible: mainItem.isFromChatGroup && mainItem.isRemoteMessage
                Layout.preferredWidth: mainItem.isRemoteMessage ? 26 : 0
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignTop
                _address: chatMessage ? chatMessage.core.fromAddress : ""
            }
            Item {
                id: bubbleContainer
                // Layout.topMargin: isFirstMessage ? 16 : 0
                Layout.leftMargin: mainItem.isFromChatGroup ? Utils.getSizeWithScreenRatio(9) : 0
                Layout.preferredHeight: childrenRect.height
                Layout.preferredWidth: childrenRect.width

                Control.Control {
                    id: chatBubble
                    spacing: Utils.getSizeWithScreenRatio(2)
                    topPadding: Utils.getSizeWithScreenRatio(12)
                    bottomPadding: Utils.getSizeWithScreenRatio(6)
                    leftPadding: Utils.getSizeWithScreenRatio(18)
                    rightPadding: Utils.getSizeWithScreenRatio(18)

                    MouseArea { // Default mouse area. Each sub bubble can control the mouse and pass on to the main mouse handler. Child bubble mouse area must cover the entire bubble.
                        id: defaultMouseArea
                        // visible: invitationLoader.status !== Loader.Ready // Add other bubbles here that could control the mouse themselves, then add in bubble a signal onMouseEvent
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked:  (mouse) => mainItem.handleDefaultMouseEvent(mouse)
                    }
                    
                    background: Item {
                        anchors.fill: parent
                        visible: !chatBubbleContent.isOnlyEmojis
                        Rectangle {
                            anchors.fill: parent
                            color: mainItem.backgroundColor
                            radius: Utils.getSizeWithScreenRatio(16)
                        }
                        Rectangle {
                            visible: mainItem.isFirstMessage && mainItem.isRemoteMessage
                            anchors.top: parent.top
                            anchors.left: parent.left
                            width: Utils.getSizeWithScreenRatio(parent.width / 4)
                            height: Utils.getSizeWithScreenRatio(parent.height / 4)
                            color: mainItem.backgroundColor
                        }
                        Rectangle {
                            visible: mainItem.isFirstMessage && !mainItem.isRemoteMessage
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            width: Utils.getSizeWithScreenRatio(parent.width / 4)
                            height: Utils.getSizeWithScreenRatio(parent.height / 4)
                            color: mainItem.backgroundColor
                        }
                        Rectangle {
                            id: highlightRectangle
                            anchors.fill: parent
                            radius: Utils.getSizeWithScreenRatio(16)
                            color: Qt.lighter(mainItem.backgroundColor, 2)
                            border.color: mainItem.backgroundColor
                            border.width: Utils.getSizeWithScreenRatio(2)
                            opacity: 0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    }
                    contentItem: ColumnLayout {
                        spacing: Utils.getSizeWithScreenRatio(5)
                        width: Math.min(implicitWidth, mainItem.maxWidth - chatBubble.leftPadding - chatBubble.rightPadding)
                        Text {
                            id: retractedId
                            visible: mainItem.chatMessage.core.isRetracted
                            font: Typography.p1i
                            color: DefaultStyle.info_800_main
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: mainItem.chatMessage.core.text
                            textFormat: Text.RichText
                        }
                        ChatMessageContent {
                            id: chatBubbleContent
                            Layout.fillWidth: true
                            // Layout.fillHeight: true
                            // Layout.preferredWidth: 50//bubbleContainer.width - bubbleContainer.leftPadding - bubbleContainer.rightPadding
                            chatGui: mainItem.chat
                            visible: !mainItem.chatMessage.core.isRetracted
                            searchedTextPart: mainItem.searchedTextPart
                            chatMessageGui: mainItem.chatMessage
                            maxWidth: mainItem.maxWidth
                            // RectangleTest{anchors.fill: parent}
                            onMouseEvent: (event) => {
                                mainItem.handleDefaultMouseEvent(event)
                            }
                            onEndOfVoiceRecordingReached: mainItem.endOfVoiceRecordingReached()
                        }
                        RowLayout {
                            Layout.preferredHeight: childrenRect.height
                            Layout.alignment: mainItem.isRemoteMessage ? Qt.AlignLeft : Qt.AlignRight
                            layoutDirection: mainItem.isRemoteMessage ? Qt.RightToLeft : Qt.LeftToRight
                            spacing: Utils.getSizeWithScreenRatio(7)
                            RowLayout {
                                spacing: Utils.getSizeWithScreenRatio(3)
                                Layout.preferredHeight: childrenRect.height
                                Text {
                                    id: ephemeralTime
                                    visible: mainItem.chatMessage.core.isEphemeral
                                    color: DefaultStyle.main2_500_main
                                    text: UtilsCpp.formatDuration(mainItem.chatMessage.core.ephemeralDuration * 1000)
                                    font {
                                        pixelSize: Typography.p3.pixelSize
                                        weight: Typography.p3.weight
                                    }
                                }
                                EffectImage {
                                    visible: mainItem.chatMessage.core.isEphemeral
                                    imageSource: AppIcons.clockCountDown
                                    colorizationColor: DefaultStyle.main2_500_main
                                    Layout.preferredWidth: visible ? 14 : 0
                                    Layout.preferredHeight: visible ? 14 : 0
                                }
                            }
                            RowLayout {
                                spacing: mainItem.isRemoteMessage && !mainItem.chatMessage.core.isEdited ? 0 : Utils.getSizeWithScreenRatio(5)
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredHeight: childrenRect.height
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: qsTr("conversation_message_edited_label")
                                    visible: mainItem.chatMessage.core.isEdited
                                    color: DefaultStyle.main2_500_main
                                    font {
										pixelSize: Typography.p3.pixelSize
										weight: Typography.p3.weight
                                    }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: UtilsCpp.formatDate(mainItem.chatMessage.core.timestamp, true, false, "dd/MM")
                                    color: DefaultStyle.main2_500_main
                                    font {
										pixelSize: Typography.p3.pixelSize
										weight: Typography.p3.weight
                                    }
                                }
                                EffectImage {
                                    // Imdn status icon
                                    visible: !mainItem.isRemoteMessage
                                    Layout.preferredWidth: visible ? 14 : 0
                                    Layout.preferredHeight: visible ? 14 : 0
                                    Layout.alignment: Qt.AlignVCenter
                                    colorizationColor: DefaultStyle.main1_500_main
                                    imageSource: mainItem.msgState === LinphoneEnums.ChatMessageState.StateDelivered
                                        ? AppIcons.envelope
                                        : mainItem.msgState === LinphoneEnums.ChatMessageState.StateDeliveredToUser
                                            ? AppIcons.check
                                            : mainItem.msgState === LinphoneEnums.ChatMessageState.StateNotDelivered
                                                ? AppIcons.warningCircle
                                                : mainItem.msgState === LinphoneEnums.ChatMessageState.StateDisplayed
                                                    ? AppIcons.checks
                                                    : mainItem.msgState === LinphoneEnums.ChatMessageState.StatePendingDelivery
                                                    || mainItem.msgState === LinphoneEnums.ChatMessageState.StateIdle
                                                        ? AppIcons.hourglass
                                                        : ""
                                    // Roue construite seulement pendant un envoi : une par message, toujours cachee
                                    // sinon, elle pesait sur l'ouverture des conversations.
                                    Loader {
                                        anchors.fill: parent
                                        active: mainItem.msgState === LinphoneEnums.ChatMessageState.StateInProgress
                                            || mainItem.msgState === LinphoneEnums.ChatMessageState.StateFileTransferInProgress
                                        sourceComponent: BusyIndicator {}
                                    }
                                }
                            }
                        }
                    }
                }
                // Place qu'occupait le bouton des reactions meme cache (un element cache compte dans la taille de son
                // conteneur) : l'espacement entre les messages reste identique.
                Item {
                    visible: false
                    anchors.top: chatBubble.bottom
                    anchors.topMargin: Utils.getSizeWithScreenRatio(-6)
                    width: Utils.getSizeWithScreenRatio(16)
                    height: Utils.getSizeWithScreenRatio(16)
                }
                // Bouton des reactions construit seulement s'il y en a : un bouton complet par message, presque
                // toujours cache, pesait sur l'ouverture des conversations.
                Loader {
                    id: reactionsLoader
                    active: !!mainItem.chatMessage && mainItem.chatMessage.core.reactionsSingleton.length > 0
                    anchors.top: chatBubble.bottom
                    anchors.topMargin: Utils.getSizeWithScreenRatio(-6)
                    Binding {
                        target: reactionsLoader
                        when: !mainItem.isRemoteMessage
                        property: "anchors.left"
                        value: chatBubble.left
                    }
                    Binding {
                        target: reactionsLoader
                        when: mainItem.isRemoteMessage
                        property: "anchors.right"
                        value: chatBubble.right
                    }
                    sourceComponent: Button {
                        id: reactionsButton
                        onClicked: mainItem.showReactionsForMessageRequested()
                        topPadding: Utils.getSizeWithScreenRatio(8)
                        bottomPadding: Utils.getSizeWithScreenRatio(8)
                        leftPadding: Utils.getSizeWithScreenRatio(8)
                        rightPadding: Utils.getSizeWithScreenRatio(8)
                        background: Rectangle {
                            color: DefaultStyle.grey_100
                            border.color: DefaultStyle.grey_0
                            border.width: Utils.getSizeWithScreenRatio(2)
                            radius: Utils.getSizeWithScreenRatio(20)
                        }
                        contentItem: RowLayout {
                            spacing: Utils.getSizeWithScreenRatio(6)
                            Repeater {
                                id: reactionList
                                model: mainItem.chatMessage ? mainItem.chatMessage.core.reactionsSingleton : []
                                delegate: RowLayout {
                                    spacing: Utils.getSizeWithScreenRatio(3)
                                    Text {
                                        text: UtilsCpp.encodeEmojiToQmlRichFormat(modelData.body)
                                        textFormat: Text.RichText
                                        font {
                                            pixelSize: Utils.getSizeWithScreenRatio(15)
                                            weight: Utils.getSizeWithScreenRatio(400)
                                        }
                                    }
                                    Text {
                                        visible: modelData.count > 1
                                        text: modelData.count
                                        verticalAlignment: Text.AlignBottom
                                        font {
                                            pixelSize: Typography.p4.pixelSize
                                            weight: Typography.p4.weight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Emplacement de la barre d'actions partagee, vide (largeur nulle) sauf au survol de ce message.
            Item {
                id: actionsSlot
                readonly property bool occupied: !!mainItem.actionBar && mainItem.actionBar.message === mainItem
                visible: occupied
                Layout.leftMargin: Utils.getSizeWithScreenRatio(8)
                Layout.rightMargin: Utils.getSizeWithScreenRatio(8)
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: occupied ? mainItem.actionBar.implicitWidth : 0
                Layout.preferredHeight: occupied ? mainItem.actionBar.implicitHeight : 0
            }
            Item{Layout.fillWidth: true}
        }
    }
}
