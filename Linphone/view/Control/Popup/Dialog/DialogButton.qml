import QtQuick
import QtQuick.Layouts
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Bouton d'une fenetre de decision : tous de la meme largeur dans leur rangee (ou leur colonne), a une hauteur paire
// et fixe, la meme partout.
MediumButton {
	Layout.fillWidth: true
	Layout.preferredWidth: 1
	Layout.preferredHeight: 2 * Math.round(Utils.getSizeWithScreenRatio(AppCpp.compactMode ? 38 : 42) / 2)
	topPadding: 0
	bottomPadding: 0
	// Le texte reste centre ; marges reduites pour qu'un mot tienne dans un tiers de la petite fenetre.
	leftPadding: Utils.getSizeWithScreenRatio(8)
	rightPadding: Utils.getSizeWithScreenRatio(8)
}
