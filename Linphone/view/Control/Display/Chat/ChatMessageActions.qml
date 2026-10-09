import QtQuick
import QtQuick.Layouts
import Linphone
import UtilsCpp
import ConstantsCpp
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Barre d'actions des messages (menu ⋯ et reactions), unique pour toute la conversation : elle vient se poser dans
// le message survole (ChatMessage.actionsSlotItem), comme sur Slack ou Discord. Chaque bulle construisait auparavant
// la sienne, 3 menus et 14 boutons jamais vus pour la plupart, ce qui figeait l'ouverture des conversations.
// Textes rattaches au contexte de traduction « ChatMessage », d'ou ils viennent.
RowLayout {
    id: mainItem
    // Message servi (bulle ChatMessage), ou null : barre cachee, hors de la scene.
    property var message: null
    readonly property bool menuOpened: optionsMenu.popup.opened || emojiButton.popup.opened || emojiPickerButton.popup.opened
    readonly property bool barHovered: optionsMenu.hovered || emojiButton.hovered

    // Posee dans un emplacement de sa taille exacte (voir ChatMessage) : ni ancrage ni etirement.
    visible: !!message
    width: implicitWidth
    height: implicitHeight
    spacing: Utils.getSizeWithScreenRatio(7)
    layoutDirection: message && message.isRemoteMessage ? Qt.LeftToRight : Qt.RightToLeft

    // Survol d'un message : la barre s'y pose, sauf si un de ses menus est ouvert sur un autre.
    function show(msg) {
        if (!msg || msg === mainItem.message || mainItem.menuOpened)
            return
        mainItem.message = msg
        mainItem.parent = msg.actionsSlotItem
    }
    // Fin du survol : la souris a pu passer du message a la barre, d'ou la verification differee.
    function hide(msg) {
        if (msg === mainItem.message)
            Qt.callLater(mainItem.releaseIfIdle)
    }
    function releaseIfIdle() {
        if (!mainItem.message || mainItem.menuOpened || mainItem.barHovered || mainItem.message.hovered)
            return
        mainItem.message = null
        mainItem.parent = null
    }
    // Bulle recyclee pour un autre message ou detruite : la barre la quitte aussitot.
    function release(msg) {
        if (msg !== mainItem.message)
            return
        optionsMenu.close()
        emojiButton.close()
        emojiPickerButton.close()
        mainItem.message = null
        mainItem.parent = null
    }
    // Clic droit sur un message : son menu ⋯.
    function openOptions(msg) {
        if (!msg)
            return
        if (mainItem.message !== msg) {
            optionsMenu.close()
            emojiButton.close()
            emojiPickerButton.close()
            mainItem.show(msg)
        }
        if (mainItem.message === msg)
            optionsMenu.open()
    }
    onMenuOpenedChanged: if (!menuOpened) Qt.callLater(mainItem.releaseIfIdle)
    onBarHoveredChanged: if (!barHovered) Qt.callLater(mainItem.releaseIfIdle)

    PopupButton {
        id: optionsMenu
        popup.padding: 0
        popup.contentItem: ColumnLayout {
            spacing: 0
            IconLabelButton {
                visible: !!mainItem.message && mainItem.message.msgState === LinphoneEnums.ChatMessageState.StateNotDelivered
                inverseLayout: true
                //: "Re-send"
                text: qsTranslate("ChatMessage", "chat_message_send_again")
                icon.source: AppIcons.chatTeardropText
                Layout.fillWidth: true
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                onClicked: {
                    mainItem.message.chatMessage.core.lSend(false)
                    optionsMenu.close()
                }
            }
            IconLabelButton {
                inverseLayout: true
                //: "Reception info"
                text: qsTranslate("ChatMessage", "chat_message_reception_info")
                icon.source: AppIcons.chatTeardropText
                Layout.fillWidth: true
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                onClicked: {
                    mainItem.message.showImdnStatusForMessageRequested()
                    optionsMenu.close()
                }
            }
            IconLabelButton {
                inverseLayout: true
                //: "Edit"
                text: qsTranslate("ChatMessage", "menu_edit_chat_message")
                visible: !!mainItem.message && mainItem.message.chatMessage.core.isEditable
                icon.source: AppIcons.pencil
                Layout.fillWidth: true
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                onClicked: {
                    mainItem.message.messageEditionRequested()
                    optionsMenu.close()
                }
            }
            IconLabelButton {
                inverseLayout: true
                visible: !!mainItem.message && !mainItem.message.chatMessage.core.isRetracted
                //: Reply
                text: qsTranslate("ChatMessage", "chat_message_reply")
                icon.source: AppIcons.reply
                Layout.fillWidth: true
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                onClicked: {
                    mainItem.message.replyToMessageRequested()
                    optionsMenu.close()
                }
            }
            IconLabelButton {
                inverseLayout: true
                visible: !!mainItem.message && !mainItem.message.chatMessage.core.isRetracted
                text: !!mainItem.message && mainItem.message.selectedText != ""
                    //: "Copy selection"
                    ? qsTranslate("ChatMessage", "chat_message_copy_selection")
                    //: "Copy"
                    : qsTranslate("ChatMessage", "chat_message_copy")
                icon.source: AppIcons.copy
                Layout.fillWidth: true
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                onClicked: {
                    var message = mainItem.message
                    var success = UtilsCpp.copyToClipboard(message.selectedText != "" ? message.selectedText : message.chatMessage.core.text)
                    //: Copied
                    if (success) UtilsCpp.showInformationPopup(qsTranslate("ChatMessage", "chat_message_copied_to_clipboard_title"),
                                    //: "to clipboard"
                                    qsTranslate("ChatMessage", "chat_message_copied_to_clipboard_toast"))
                    optionsMenu.close()
                }
            }
            IconLabelButton {
                inverseLayout: true
                visible: !!mainItem.message && !mainItem.message.chatMessage.core.isRetracted
                //: Forward
                text: qsTranslate("ChatMessage", "chat_message_forward")
                icon.source: AppIcons.forward
                Layout.fillWidth: true
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                onClicked: {
                    mainItem.message.forwardMessageRequested()
                    optionsMenu.close()
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(1)
                color: DefaultStyle.main2_400
            }
            IconLabelButton {
                inverseLayout: true
                //: "Delete"
                text: qsTranslate("ChatMessage", "chat_message_delete")
                icon.source: AppIcons.trashCan
                Layout.fillWidth: true
                Layout.preferredHeight: Utils.getSizeWithScreenRatio(45)
                onClicked: {
                    mainItem.message.messageDeletionRequested()
                    optionsMenu.close()
                }
                style: ButtonStyle.hoveredBackgroundRed
            }
        }
    }
    PopupButton {
        id: emojiButton
        style: ButtonStyle.noBackground
        icon.source: AppIcons.smiley
        popup.contentItem: RowLayout {
            Repeater {
                model: ConstantsCpp.reactionsList
                delegate: Button {
                    text: UtilsCpp.encodeEmojiToQmlRichFormat(modelData)
                    textFormat: Text.RichText
                    background: Rectangle {
                        anchors.fill: parent
                        color: DefaultStyle.grey_200
                        radius: parent.width * 4
                        visible: !!mainItem.message && mainItem.message.ownReaction === modelData
                    }
                    onClicked: {
                        var message = mainItem.message
                        if (message && modelData) {
                            if (message.ownReaction === modelData) message.chatMessage.core.lRemoveReaction()
                            else message.chatMessage.core.lSendReaction(modelData)
                        }
                        emojiButton.close()
                    }
                }
            }
            PopupButton {
                id: emojiPickerButton
                icon.source: AppIcons.plusCircle
                popup.width: Utils.getSizeWithScreenRatio(393)
                popup.height: Utils.getSizeWithScreenRatio(291)
                // Selecteur construit au premier clic, puis garde.
                popup.onAboutToShow: emojiPickerLoader.active = true
                popup.contentItem: Loader {
                    id: emojiPickerLoader
                    active: false
                    focus: true
                    sourceComponent: EmojiPicker {
                        id: emojiPicker
                        onEmojiClicked: (emoji) => {
                            var message = mainItem.message
                            if (message && message.chatMessage) {
                                if (message.ownReaction === emoji) message.chatMessage.core.lRemoveReaction()
                                else message.chatMessage.core.lSendReaction(emoji)
                            }
                            emojiPickerButton.close()
                            emojiButton.close()
                        }
                    }
                }
            }
        }
    }
}
