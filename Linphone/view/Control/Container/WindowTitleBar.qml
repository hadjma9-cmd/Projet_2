import QtQuick
import QtQuick.Layouts
import Linphone

// Barre du haut des fenetres sans barre de titre Windows : on la tient pour deplacer la fenetre (double-clic :
// agrandir ou retablir), boutons reduire, agrandir et fermer a droite. Le contenu place dans la barre s'aligne a
// gauche ; ses elements cliquables gardent leurs clics. Masquee hors de Windows, ou la fenetre garde son cadre.
// A declarer comme en-tete de la fenetre (header), pour qu'elle existe avant la fenetre native.
Rectangle {
	id: mainItem
	required property var window
	property bool dark: false
	// Petite fenetre : taille fixe, ni bouton agrandir ni bords de redimensionnement.
	property bool maximizable: true
	property bool pinnable: false
	property bool pinned: false
	property alias frame: windowFrame
	default property alias content: contentRow.data

	signal pinClicked()

	readonly property color glyphColor: mainItem.dark ? DefaultStyle.main2_300 : DefaultStyle.main2_700
	readonly property bool maximized: mainItem.window && mainItem.window.visibility === Window.Maximized

	visible: windowFrame.active
	implicitHeight: 32
	color: mainItem.dark ? DefaultStyle.callBackground : DefaultStyle.grey_0

	WindowFrame {
		id: windowFrame
		window: mainItem.window
		titleBar: mainItem
		maximizeButton: maximizeButton
		resizable: mainItem.maximizable
		stayOnTop: mainItem.pinnable && mainItem.pinned
	}

	// Filet de separation avec le contenu, sur fond clair seulement.
	Rectangle {
		visible: !mainItem.dark
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		height: 1
		color: DefaultStyle.main2_100
	}

	RowLayout {
		id: contentRow
		anchors.left: parent.left
		anchors.right: buttonsRow.left
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: 14
		spacing: 8
	}

	component CaptionButton: Item {
		id: captionButton
		property bool isClose: false
		// Etat donne par Windows (bouton agrandir) : son survol et ses clics ne passent pas par le QML.
		property bool externalHovered: false
		property bool externalPressed: false
		readonly property bool isHovered: buttonArea.containsMouse || externalHovered
		readonly property bool isPressed: buttonArea.pressed || externalPressed
		readonly property color currentGlyphColor: captionButton.isClose && captionButton.isHovered
			? DefaultStyle.grey_0
			: mainItem.glyphColor
		signal clicked()
		width: 46
		height: mainItem.height
		Rectangle {
			anchors.fill: parent
			color: captionButton.isClose
				? (captionButton.isPressed ? DefaultStyle.titleBarClosePressed
					: captionButton.isHovered ? DefaultStyle.titleBarClose : "transparent")
				: captionButton.isPressed
					? (mainItem.dark ? DefaultStyle.titleBarButtonPressedDark : DefaultStyle.titleBarButtonPressed)
					: captionButton.isHovered
						? (mainItem.dark ? DefaultStyle.titleBarButtonHoveredDark : DefaultStyle.titleBarButtonHovered)
						: "transparent"
		}
		// Curseur fleche, comme les boutons de fenetre de Windows.
		MouseArea {
			id: buttonArea
			anchors.fill: parent
			hoverEnabled: true
			onClicked: captionButton.clicked()
		}
	}

	Row {
		id: buttonsRow
		anchors.right: parent.right
		anchors.top: parent.top
		anchors.bottom: parent.bottom

		CaptionButton {
			id: pinButton
			visible: mainItem.pinnable
			onClicked: mainItem.pinClicked()
			EffectImage {
				anchors.centerIn: parent
				width: 16
				height: 16
				imageSource: mainItem.pinned ? AppIcons.pushPinFill : AppIcons.pushPin
				colorizationColor: mainItem.pinned ? DefaultStyle.main1_500_main : pinButton.currentGlyphColor
			}
		}
		CaptionButton {
			id: minimizeButton
			onClicked: mainItem.window.showMinimized()
			Rectangle {
				anchors.centerIn: parent
				width: 10
				height: 1
				color: minimizeButton.currentGlyphColor
			}
		}
		CaptionButton {
			id: maximizeButton
			visible: mainItem.maximizable
			externalHovered: windowFrame.maximizeHovered
			externalPressed: windowFrame.maximizePressed
			// Sous Windows, le clic passe par Windows (menu d'ancrage) : ce gestionnaire ne sert qu'ailleurs.
			onClicked: windowFrame.toggleMaximized()
			Item {
				anchors.centerIn: parent
				width: 10
				height: 10
				// Agrandir : un carre ; retablir : deux carres decales.
				Rectangle {
					visible: mainItem.maximized
					x: 2
					y: 0
					width: 8
					height: 8
					radius: 1
					color: "transparent"
					border.width: 1
					border.color: maximizeButton.currentGlyphColor
				}
				Rectangle {
					x: 0
					y: mainItem.maximized ? 2 : 0
					width: mainItem.maximized ? 8 : 10
					height: mainItem.maximized ? 8 : 10
					radius: 1
					color: mainItem.maximized ? mainItem.color : "transparent"
					border.width: 1
					border.color: maximizeButton.currentGlyphColor
				}
			}
		}
		CaptionButton {
			id: closeButton
			isClose: true
			onClicked: mainItem.window.close()
			Repeater {
				model: [45, -45]
				Rectangle {
					anchors.centerIn: parent
					width: 13
					height: 1
					antialiasing: true
					rotation: modelData
					color: closeButton.currentGlyphColor
				}
			}
		}
	}
}
