import QtQuick
import QtQuick.Effects

import QtQuick.Layouts
import QtQuick.Controls.Basic as Control


import Linphone
import CustomControls 1.0
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle

// CustomControls : FocusHelper (etat du focus clavier), absent jusqu'ici d'ou une erreur a chaque affichage.
PopupButton {
    id: presenceAndRegistrationItem
    // Le compte est passe explicitement. Ce composant le lisait auparavant sur un parent
    // nomme mainItem, par portee dynamique : il n'etait donc utilisable que sous un tel
    // parent (Contact.qml). Le bandeau principal peut desormais s'en servir aussi.
    property AccountGui account: null
    // Tailles reglables ; les valeurs par defaut sont celles d'origine (liste des comptes).
    property real barHeight: Utils.getSizeWithScreenRatio(24)
    property real textPixelSize: Utils.getSizeWithScreenRatio(12)
    property int textWeight: Utils.getSizeWithScreenRatio(300)
    property real statusIconSize: Utils.getSizeWithScreenRatio(11)
    property real arrowSize: Utils.getSizeWithScreenRatio(14)
    // 25 = marges et espacements ; avec les tailles par defaut on retrouve les 50 d'origine.
    width: presenceOrRegistrationText.implicitWidth + statusIconSize + arrowSize + Utils.getSizeWithScreenRatio(25)
    height: barHeight
    enabled: presenceAndRegistrationItem.account && presenceAndRegistrationItem.account.core.registrationState === LinphoneEnums.RegistrationState.Ok
    onEnabledChanged: if(!enabled) close()
    property bool editCustomStatus : false
    contentItem: Control.Control {
        id: presenceBar
        property bool isRegistered: presenceAndRegistrationItem.account?.core.registrationState === LinphoneEnums.RegistrationState.Ok
	    property bool keyboardFocus: FocusHelper.keyboardFocus
        background: Rectangle {
            color: UtilsCpp.getPresenceBackgroundColor(presenceAndRegistrationItem.account.core.presence)
            border.color: DefaultStyle.main2_900
            // Pas de contour noir de focus clavier, comme pour les boutons (Button.qml).
            border.width: 0
            radius: Utils.getSizeWithScreenRatio(15)
        }

        RowLayout {
            anchors.fill: parent
            Image {
                id: registrationImage
                sourceSize.width: presenceAndRegistrationItem.statusIconSize
                sourceSize.height: presenceAndRegistrationItem.statusIconSize
                smooth: false
                Layout.preferredWidth: presenceAndRegistrationItem.statusIconSize
                Layout.preferredHeight: presenceAndRegistrationItem.statusIconSize
                source: presenceBar.isRegistered 
                    ? presenceAndRegistrationItem.account.core.presenceIcon 
                    : presenceAndRegistrationItem.account?.core.registrationIcon || ""
                Layout.leftMargin: Utils.getSizeWithScreenRatio(8)
                RotationAnimator on rotation {
                    running: presenceAndRegistrationItem.account && presenceAndRegistrationItem.account.core.registrationState === LinphoneEnums.RegistrationState.Progress
                    direction: RotationAnimator.Clockwise
                    from: 0
                    to: 360
                    loops: Animation.Infinite
                    duration: 10000
                }
            }
            Text {
                id: presenceOrRegistrationText
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                visible: presenceAndRegistrationItem.account
                font.weight: presenceAndRegistrationItem.textWeight
                font.pixelSize: presenceAndRegistrationItem.textPixelSize
                color: presenceBar.isRegistered ? presenceAndRegistrationItem.account.core.presenceColor : presenceAndRegistrationItem.account?.core.registrationColor
                text: presenceBar.isRegistered ? presenceAndRegistrationItem.account.core.presenceStatus : presenceAndRegistrationItem.account?.core.humaneReadableRegistrationState
            }
            EffectImage {
                fillMode: Image.PreserveAspectFit
                imageSource: AppIcons.downArrow
                colorizationColor: DefaultStyle.main2_600
                Layout.preferredHeight: presenceAndRegistrationItem.arrowSize
                Layout.preferredWidth: presenceAndRegistrationItem.arrowSize
                Layout.rightMargin: Utils.getSizeWithScreenRatio(8)
            }
        }
    }
    popup.onOpened: popup.forceActiveFocus()
    popup.contentItem: FocusScope {
        implicitWidth: Utils.getSizeWithScreenRatio(280)
        implicitHeight: Utils.getSizeWithScreenRatio(20) + (setCustomStatus.visible ? Utils.getSizeWithScreenRatio(240) : setPresence.implicitHeight)
        Rectangle {
            anchors.fill: parent
            Presence {
                id: setPresence
                visible: !presenceAndRegistrationItem.editCustomStatus
                anchors.fill: parent
                anchors.margins: Utils.getSizeWithScreenRatio(20)
                accountGui: presenceAndRegistrationItem.account
                onSetCustomStatusClicked: {
                    presenceAndRegistrationItem.editCustomStatus = true
                }
                onIsSet: presenceAndRegistrationItem.popup.close()
            }
            PresenceSetCustomStatus {
                id: setCustomStatus
                visible: presenceAndRegistrationItem.editCustomStatus
                anchors.fill: parent
                anchors.margins: Utils.getSizeWithScreenRatio(20)
                accountGui: presenceAndRegistrationItem.account
                onVisibleChanged: {
                    if (!visible) {
                        presenceAndRegistrationItem.editCustomStatus = false
                    }
                }
                onIsSet: presenceAndRegistrationItem.popup.close()
            }
        }
    }
}