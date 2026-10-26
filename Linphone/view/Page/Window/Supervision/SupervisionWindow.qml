import QtQuick
import QtQuick.Layouts
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Fenetre a part du tableau des files, ouverte depuis la grande fenetre (menu du casque, ou icone a sa place) ou le
// Combine (icone a cote de l'epingle). Une seule a la fois : un nouveau clic la ramene au premier plan. Fermee, elle
// est seulement cachee, et sa connexion en direct au serveur est coupee.
AbstractWindow {
	id: mainWindow
	flags: Qt.Window
	title: "Tableau des files"
	width: Math.min(Utils.getSizeWithScreenRatio(1100), Screen.desktopAvailableWidth)
	height: Math.min(Utils.getSizeWithScreenRatio(780), Screen.desktopAvailableHeight)
	minimumWidth: Utils.getSizeWithScreenRatio(420)
	minimumHeight: Utils.getSizeWithScreenRatio(520)
	color: DefaultStyle.grey_100

	// Meme barre du haut que les autres fenetres (deplacement, reduire, agrandir, fermer), sans barre Windows.
	header: WindowTitleBar {
		window: mainWindow
		visible: frame.active && mainWindow.visibility !== Window.FullScreen
	}

	SupervisionPage {
		anchors.fill: parent
		active: mainWindow.visible
	}
}
