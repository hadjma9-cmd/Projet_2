import QtQuick
import QtQuick.Shapes
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Casque des files d'attente. Une seule file : le casque seul, allume (file active) ou eteint. A partir de 2 files :
// entoure d'un anneau decoupe, un segment par file dans le sens des aiguilles d'une montre depuis le haut (plein =
// file active). Au-dela de 6 files, les segments seraient trop fins : un seul arc, proportionnel aux files actives.
Item {
	id: mainItem
	property int count: QueuesCpp.queueCount
	property int active: QueuesCpp.connectedCount
	property color onColor: DefaultStyle.grey_0
	property color offColor: Qt.rgba(1, 1, 1, 0.28)
	property color iconOnColor: onColor
	property color iconOffColor: Qt.rgba(1, 1, 1, 0.45)
	// Seul (une file) : la taille des autres icones de la bande ; un peu plus petit dans l'anneau.
	property real iconSize: Utils.getSizeWithScreenRatio(ringShown ? 20 : 22)
	property real strokeWidth: Utils.getSizeWithScreenRatio(2.6)

	readonly property bool ringShown: count >= 2
	readonly property bool segmented: count >= 2 && count <= 6
	readonly property real centerX: width / 2
	readonly property real centerY: height / 2
	readonly property real ringRadius: Math.min(width, height) / 2 - strokeWidth / 2 - Utils.getSizeWithScreenRatio(1)
	// Ecart entre deux segments, en degres, a longueur constante : le bout arrondi du trait en mange la moitie de
	// chaque cote.
	readonly property real gapDegrees: (strokeWidth + Utils.getSizeWithScreenRatio(3.5)) / ringRadius * 180 / Math.PI

	EffectImage {
		x: Math.round((mainItem.width - width) / 2)
		y: Math.round((mainItem.height - height) / 2)
		width: mainItem.iconSize
		height: mainItem.iconSize
		imageSource: AppIcons.headset
		colorizationColor: mainItem.active > 0 ? mainItem.iconOnColor : mainItem.iconOffColor
	}

	// Anneau trace par le moteur de courbes de Qt : net a toute taille et a toute echelle d'ecran (un calque lisse,
	// rendu trop petit sur un ecran agrandi, le rendait flou et crenele).
	Item {
		anchors.fill: parent
		visible: mainItem.ringShown

		// Un segment par file.
		Repeater {
			model: mainItem.segmented ? mainItem.count : 0
			delegate: Shape {
				required property int index
				anchors.fill: parent
				preferredRendererType: Shape.CurveRenderer
				ShapePath {
					strokeColor: index < mainItem.active ? mainItem.onColor : mainItem.offColor
					strokeWidth: mainItem.strokeWidth
					fillColor: "transparent"
					capStyle: Qt.RoundCap
					PathAngleArc {
						centerX: mainItem.centerX
						centerY: mainItem.centerY
						radiusX: mainItem.ringRadius
						radiusY: mainItem.ringRadius
						startAngle: -90 + index * 360 / mainItem.count + mainItem.gapDegrees / 2
						sweepAngle: 360 / mainItem.count - mainItem.gapDegrees
					}
				}
			}
		}
		// Plus de 6 files : le cercle eteint, puis l'arc des files actives par-dessus.
		Shape {
			anchors.fill: parent
			visible: !mainItem.segmented
			preferredRendererType: Shape.CurveRenderer
			ShapePath {
				strokeColor: mainItem.offColor
				strokeWidth: mainItem.strokeWidth
				fillColor: "transparent"
				PathAngleArc {
					centerX: mainItem.centerX
					centerY: mainItem.centerY
					radiusX: mainItem.ringRadius
					radiusY: mainItem.ringRadius
					startAngle: -90
					sweepAngle: 360
				}
			}
			ShapePath {
				strokeColor: mainItem.active > 0 ? mainItem.onColor : "transparent"
				strokeWidth: mainItem.strokeWidth
				fillColor: "transparent"
				capStyle: Qt.RoundCap
				PathAngleArc {
					centerX: mainItem.centerX
					centerY: mainItem.centerY
					radiusX: mainItem.ringRadius
					radiusY: mainItem.ringRadius
					startAngle: -90
					sweepAngle: mainItem.count > 0 ? 360 * mainItem.active / mainItem.count : 0
				}
			}
		}
	}
}
