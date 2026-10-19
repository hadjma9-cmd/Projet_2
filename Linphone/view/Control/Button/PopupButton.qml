import QtQuick
import QtQuick.Controls.Basic as Control
import QtQuick.Effects
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle

Button {
    id: mainItem
    property alias popup: popup
    shadowEnabled: mainItem.activeFocus && !keyboardFocus || hovered
    property alias popupBackgroundColor: popupBackground.color
    backgroundColor: checked ? pressedColor : hovered || mainItem.activeFocus ? hoveredColor : color
    property string popUpTitle: ""
    property int popupY: height
    // Menu a droite du bouton, aligne sur son haut (bouton dans une bande etroite, petite fenetre), au lieu de dessous.
    property bool popupBeside: false
    Accessible.role: Accessible.ButtonMenu
    Accessible.name: popup.visible ?
    //: "Close %1 popup"
    qsTr("close_popup_panel_accessible_name").arg(popUpTitle) :
    //: "Open %1" popup
    qsTr("open_popup_panel_accessible_name").arg(popUpTitle)
    style: ButtonStyle.popupButton
    checked: popup.visible
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    bottomPadding: 0
    icon.source: AppIcons.verticalDots
    icon.width: Utils.getSizeWithScreenRatio(24)
    icon.height: Utils.getSizeWithScreenRatio(24)
    implicitWidth: Utils.getSizeWithScreenRatio(30)
    implicitHeight: Utils.getSizeWithScreenRatio(30)
    // Menu deja ouvert au moins une fois : son ombre existe (voir le fond du menu).
    property bool _popupShown: false
    function close() {
        popup.close();
    }
    function open() {
        popup.open();
    }

    function isFocusable(item) {
        return item.activeFocusOnTab;
    }

    /**
     * Check if an element has at least one child that is focusable
     */
    function hasFocusableChild(content) {
        return content.children.some(child => isFocusable(child));
    }

    // Element qui porte les entrees du menu, y compris quand le menu est construit a son ouverture (Loader) : elles
    // sont alors dans l'element charge.
    function _menuContent() {
        var content = popup.contentItem;
        if (content instanceof Loader)
            content = content.item;
        return content instanceof FocusScope ? content.children[0] : content;
    }

    function getPreviousItem(index) {
        return _getPreviousItem(_menuContent(), index);
    }

    function getNextItem(index) {
        return _getNextItem(_menuContent(), index);
    }

    // Parcours borne avec retour au debut de la liste. L'ancienne version se rappelait elle-meme
    // sans fin (depassement de pile, crash) quand le seul enfant focalisable etait masque.
    function _getPreviousItem(content, index) {
        if (!content || !content.visible)
            return null;
        var count = content.children.length;
        if (count === 0)
            return null;
        if (index <= 0 || index > count)
            index = count;
        for (var i = 1; i <= count; ++i) {
            var child = content.children[(index - i + count) % count];
            if (child && child.visible && isFocusable(child))
                return child;
        }
        return null;
    }

    function _getNextItem(content, index) {
        if (!content)
            return null;
        var count = content.children.length;
        if (count === 0)
            return null;
        if (index < -1 || index >= count)
            index = -1;
        for (var i = 1; i <= count; ++i) {
            var child = content.children[(index + i) % count];
            if (child && child.visible && isFocusable(child))
                return child;
        }
        return null;
    }

    Keys.onPressed: event => {
        if (mainItem.checked) {
            if (event.key == Qt.Key_Escape || event.key == Qt.Key_Left || event.key == Qt.Key_Space) {
                mainItem.close();
                mainItem.forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
            } else if (event.key == Qt.Key_Up) {
                var previousItem = getPreviousItem(0);
                if (previousItem)
                    previousItem.forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
            } else if (event.key == Qt.Key_Tab || event.key == Qt.Key_Down) {
                var nextItem = getNextItem(-1);
                if (nextItem)
                    nextItem.forceActiveFocus(Qt.BacktabFocusReason);
                event.accepted = true;
            }
        } else if (event.key == Qt.Key_Space) {
            mainItem.open();
            event.accepted = true;
        }
    }

    background: Item {
        anchors.fill: mainItem
        Rectangle {
            id: buttonBackground
            anchors.fill: parent
            color: mainItem.backgroundColor
            radius: Utils.getSizeWithScreenRatio(40)
            border.color: mainItem.keyboardFocus ? mainItem.keyboardFocusedBorderColor : mainItem.borderColor
            border.width: mainItem.keyboardFocus ? mainItem.keyboardFocusedBorderWidth : mainItem.borderWidth
        }
        // Ombre construite des sa premiere activation (survol, focus), puis gardee (voir Button).
        Loader {
            anchors.fill: buttonBackground
            active: mainItem.shadowEnabled || mainItem._shadowUsed
            sourceComponent: MultiEffect {
                enabled: mainItem.shadowEnabled
                source: buttonBackground
                visible: mainItem.shadowEnabled
                // Crash : https://bugreports.qt.io/browse/QTBUG-124730
                shadowEnabled: true //mainItem.shadowEnabled
                shadowColor: DefaultStyle.grey_1000
                shadowBlur: 0.1
                shadowOpacity: mainItem.shadowEnabled ? 0.5 : 0.0
            }
        }
    }
    contentItem: EffectImage {
        imageSource: mainItem.icon.source
        imageWidth: mainItem.icon.width
        imageHeight: mainItem.icon.height
        colorizationColor: mainItem.contentImageColor
    }
    // Curseur main au survol, comme les autres boutons : la zone souris de Button ne le donnait pas ici.
    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
    onPressed: {
        if (popup.visible)
            popup.close();
        else
            popup.open();
    }
    Control.Popup {
        id: popup
        onAboutToShow: mainItem._popupShown = true
        x: 0
        y: mainItem.popupY
        visible: false
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnPressOutside | Popup.CloseOnEscape
        padding: Utils.getSizeWithScreenRatio(10)
        parent: mainItem // Explicit define for coordinates references.
        function updatePosition() {
            if (!visible)
                return;
            var popupHeight = popup.height + popup.padding;
            var popupWidth = popup.width + popup.padding;
            var winPosition = mainItem.Window.contentItem ? mainItem.Window.contentItem.mapToItem(mainItem, 0, 0) : {
                "x": 0,
                "y": 0
            };
            if (mainItem.popupBeside) {
                var gap = Utils.getSizeWithScreenRatio(8)
                y = Math.max(Math.min(winPosition.y + mainItem.Window.height - popupHeight - gap, 0), winPosition.y + gap);
                x = Math.min(mainItem.width + gap, winPosition.x + mainItem.Window.width - popupWidth - gap);
                return;
            }
            // Stay inside main window
            y = Math.max(Math.min(winPosition.y + mainItem.Window.height - popupHeight, mainItem.popupY), winPosition.y);
            x = Math.max(Math.min(winPosition.x + mainItem.Window.width - popupWidth, 0), winPosition.x);
            // Avoid overlapping with popup button by going to the right (todo: check if left is better?)
            if (y < mainItem.height && y + popupHeight > 0) {
                x += mainItem.width;
            }
            var globalPos = mapToItem(mainItem.Window.contentItem, x, y);
            if (globalPos.x + popupWidth >= mainItem.Window.width) {
                x = -popupWidth;
            }
        }

        onHeightChanged: Qt.callLater(updatePosition)
        onWidthChanged: Qt.callLater(updatePosition)
        onVisibleChanged: Qt.callLater(updatePosition)

        Connections {
            target: mainItem.Window
            function onHeightChanged() {
                Qt.callLater(popup.updatePosition);
            }
            function onWidthChanged() {
                Qt.callLater(popup.updatePosition);
            }
        }

        background: Item {
            anchors.fill: parent
            Rectangle {
                id: popupBackground
                anchors.fill: parent
                color: DefaultStyle.grey_0
                radius: Utils.getSizeWithScreenRatio(16)
            }
            // Ombre du menu construite a sa premiere ouverture : chaque bouton de menu en creait une d'office.
            Loader {
                anchors.fill: popupBackground
                active: mainItem._popupShown
                sourceComponent: MultiEffect {
                    source: popupBackground
                    shadowEnabled: true
                    shadowBlur: 0.1
                    shadowColor: DefaultStyle.grey_1000
                    shadowOpacity: 0.4
                }
            }
            MouseArea {
                anchors.fill: parent
            }
        }
    }
}
