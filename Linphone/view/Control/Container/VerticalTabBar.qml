import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import QtQuick.Effects
import Linphone
import SettingsCpp
import CustomControls 1.0
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

Control.TabBar {
	id: mainItem
    //spacing: Utils.getSizeWithScreenRatio(32)
    topPadding: Utils.getSizeWithScreenRatio(36)

	property var model
	readonly property real cornerRadius: Utils.getSizeWithScreenRatio(25)

	property AccountGui defaultAccount

	property int visibleCount: 0

	signal enterPressed()
	signal spacePressed()
	
	// Call it after model is ready. If done before, Repeater will not be updated
	function initButtons(){
		actionsRepeater.model = mainItem.model
	}
	function updateVisibleCount() {
		mainItem.visibleCount = 0
		contentChildren.forEach(child => {
			if (child.visible) mainItem.visibleCount = mainItem.visibleCount + 1
		})
	}
	
	onDefaultAccountChanged: {
		if (defaultAccount) defaultAccount.core?.lRefreshNotifications()
	}

    Connections {
        target: SettingsCpp
        function onDisableMeetingsFeatureChanged() {
            initButtons()
        }
        function onDisableChatFeatureChanged() {
            initButtons()
        }
    }
	
    contentItem: ListView {
        model: mainItem.contentModel
        currentIndex: mainItem.currentIndex

        spacing: mainItem.spacing
        orientation: ListView.Vertical
        // boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        // snapMode: ListView.SnapToItem

        // highlightMoveDuration: 0
        // highlightRangeMode: ListView.ApplyRange
        // preferredHighlightBegin: 40
        // preferredHighlightEnd: width - 40
    }

	background: Item {
		id: background
		anchors.fill: parent
		// Un seul rectangle arrondi au seul coin superieur droit. Les trois rectangles d'origine
		// (tout arrondi, puis coins recouverts) ne pouvaient pas porter un degrade continu.
		// Fonce en haut, ou se trouvent les onglets et leur texte blanc ; plus clair en bas, vide.
		Rectangle {
			anchors.fill: parent
			topRightRadius: mainItem.cornerRadius
			gradient: Gradient {
				GradientStop { position: 0.0; color: DefaultStyle.main1_gradient_top }
				GradientStop { position: 1.0; color: DefaultStyle.main1_gradient_bottom }
			}
		}
	}
	
    Repeater {
		id: actionsRepeater
		Control.TabButton {
			id: tabButton
			width: mainItem.width
			Binding on height {
				when: !tabButton.visible
				value: 0
			}
    		anchors.topMargin: index === 0 ? Utils.getSizeWithScreenRatio(36) : 0
            bottomInset:  Utils.getSizeWithScreenRatio(32)
            topInset:  Utils.getSizeWithScreenRatio(32)
			hoverEnabled: true
			visible: modelData?.isVisible ? modelData.isVisible()
				: modelData?.visible != undefined ? modelData.visible : true
			onVisibleChanged: mainItem.updateVisibleCount()
			text: modelData.accessibilityLabel
			property bool keyboardFocus: FocusHelper.keyboardFocus
			focusPolicy: Qt.StrongFocus
			activeFocusOnTab: true
			// Entree « action » (fonction action du modele : clavier, messagerie vocale) : meme allure et
			// memes dimensions qu'un onglet, pour un espacement identique, mais elle s'execute au clic
			// sans devenir l'onglet courant.
			checkable: !modelData?.action
			UnreadNotification {
				badgeType: modelData.label
				unread: modelData?.unread ? modelData.unread()
				: !defaultAccount
				? -1
				: index === 0 
					? defaultAccount.core?.unreadCallNotifications || -1
					: index === 2 
						? defaultAccount.core?.unreadMessageNotifications || -1
						: 0
				anchors.right: parent.right
                anchors.rightMargin: Utils.getSizeWithScreenRatio(15)
				anchors.top: parent.top
			}
			// Pastille sans chiffre : du nouveau sans nombre connu (messagerie vocale).
			Rectangle {
				visible: modelData?.alert ? modelData.alert() : false
				width: Utils.getSizeWithScreenRatio(10)
				height: width
				radius: width / 2
				color: DefaultStyle.danger_500_main
				anchors.right: parent.right
				anchors.rightMargin: Utils.getSizeWithScreenRatio(17)
				anchors.top: parent.top
				anchors.topMargin: Utils.getSizeWithScreenRatio(2)
			}
			MouseArea {
				anchors.fill: tabButton
				cursorShape: tabButton.hovered ? Qt.PointingHandCursor : Qt.ArrowCursor
				acceptedButtons: Qt.NoButton				
			}
			background: Rectangle {
				// Black border for keyboard navigation
				visible: tabButton.keyboardFocus
				color: "transparent"
				border.color: DefaultStyle.main2_900
				border.width: Utils.getSizeWithScreenRatio(3)
				radius: Utils.getSizeWithScreenRatio(5)
				anchors.fill: tabButton
			}
			contentItem: ColumnLayout {
				EffectImage {
					id: buttonIcon
					property real buttonSize: Utils.getSizeWithScreenRatio(mainItem.currentIndex !== index && tabButton.hovered ? 26 : 24)
					imageSource: mainItem.currentIndex === index ? modelData.selectedIcon : modelData.icon
					Layout.preferredWidth: buttonSize
					Layout.preferredHeight: buttonSize
					// Dessin agrandi dans le meme cadre (iconScale) : l'espacement des entrees ne change pas.
					imageWidth: Math.round(buttonSize * (modelData?.iconScale || 1))
					imageHeight: Math.round(buttonSize * (modelData?.iconScale || 1))
					Layout.alignment: Qt.AlignHCenter
					fillMode: Image.PreserveAspectFit
					colorizationColor: DefaultStyle.grey_0
					useColor: !modelData.colored
					onStatusChanged: if (status === Image.Ready && !buttonText.visible) buttonText.visible = true
				}
				Text {
					id: buttonText
					text: modelData.label
					visible: false
					font {
						weight: mainItem.currentIndex === index
							? Utils.getSizeWithScreenRatio(800)
							: tabButton.hovered
								? Utils.getSizeWithScreenRatio(600)
								: Utils.getSizeWithScreenRatio(400)
						pixelSize: Utils.getSizeWithScreenRatio(11)
					}
					color: DefaultStyle.grey_0
					Layout.fillWidth: true
					Layout.preferredHeight: txtMeter.height
					Layout.alignment: Qt.AlignHCenter
					horizontalAlignment: Text.AlignHCenter
					leftPadding: Utils.getSizeWithScreenRatio(3)
					rightPadding: Utils.getSizeWithScreenRatio(3)
				}
			}
			TextMetrics {
				id: txtMeter
				text: modelData.label
				font: buttonText.font
				Component.onCompleted: {
                    font.weight = Utils.getSizeWithScreenRatio(800)
					mainItem.implicitWidth = Math.max(mainItem.implicitWidth, advanceWidth + buttonIcon.buttonSize)
				}
			}
			Keys.onPressed: event => {
                if (modelData?.action && (event.key === Qt.Key_Enter || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Space)) {
                    modelData.action()
                    event.accepted = true
                } else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                    mainItem.enterPressed()
                } else if(event.key === Qt.Key_Space){
					mainItem.spacePressed()
				} else if(event.key === Qt.Key_Down){
					event.accepted = true;
					if(TabBar.index >= mainItem.visibleCount - 1)
       					return;
					tabButton.nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason)
				} else if(event.key === Qt.Key_Up){
					event.accepted = true;
					if(TabBar.index <= 0)
       					return;
					tabButton.nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
				}
			}
			onClicked: {
				if (modelData?.action)
					modelData.action()
				else
					mainItem.setCurrentIndex(TabBar.index)
			}
		}
	}
}
