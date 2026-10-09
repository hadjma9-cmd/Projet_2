import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import QtQuick.Effects

import Linphone

// TODO : A loader may be needed here to refresh the colorization effect (effect2) which is not refreshed when visibility change
// and causes colorization issue when effect image is inside a popup (not seen in the popup recently tested, may be an obsolete bug)
Item {
	id: mainItem
	property url imageSource: ""
	property var fillMode: Image.PreserveAspectFit
	property var colorizationColor
	property real imageWidth: width
	property real imageHeight: height
	property bool useColor: colorizationColor != undefined
	property bool shadowEnabled: false
	property bool isImageReady: false
	property bool retainWhileLoading: true
	property alias status: image.status
	// Effets construits seulement quand ils servent. Chaque icone creait d'office deux effets de colorisation et une
	// ombre (le plus souvent desactivee), meme cachee : premier cout de creation des pages et des listes (une ligne de
	// conversation compte 9 icones, la plupart cachees). Une fois construits, ils sont gardes.
	// Colorisation : des la premiere apparition de l'icone.
	property bool _shown: false
	onVisibleChanged: if (visible) _shown = true
	Component.onCompleted: {
		if (visible) _shown = true
		if (shadowEnabled) _shadowUsed = true
	}
	// Ombre : des sa premiere activation, puis activee et desactivee comme avant (QTBUG-124730).
	property bool _shadowUsed: false
	onShadowEnabledChanged: if (shadowEnabled) _shadowUsed = true
	// Icone de l'application (image://internal/) : demandee directement dans sa couleur au fournisseur d'images,
	// au lieu d'etre dessinee en noir puis recoloree par deux effets graphiques. Meme rendu, sans effet. Les autres
	// images (photos, fichiers) gardent les effets.
	readonly property color _tint: colorizationColor ? colorizationColor : "black"
	readonly property bool _providerColor: useColor && String(imageSource).startsWith("image://internal/")
	readonly property url _coloredSource: _providerColor
		? String(imageSource) + (String(imageSource).indexOf("?") === -1 ? "?" : "&") + "color=" + String(_tint).substring(1)
		: imageSource
	Image {
		id: image
		visible: !colorizer.item
		source: mainItem._coloredSource
		fillMode: mainItem.fillMode
		retainWhileLoading: mainItem.retainWhileLoading
		sourceSize.width: width
		sourceSize.height: height
		width: mainItem.imageWidth
		height: mainItem.imageHeight
		Layout.preferredWidth: mainItem.imageWidth
		Layout.preferredHeight: mainItem.imageHeight
		anchors.centerIn: parent
		onStatusChanged: mainItem.isImageReady = (status == Image.Ready)
	}
	Loader {
		id: colorizer
		anchors.fill: image
		active: mainItem.useColor && !mainItem._providerColor && mainItem._shown
		sourceComponent: Item {
			MultiEffect {
				id: effect
				visible: false
				anchors.fill: parent
				source: image
				maskSource: image
				brightness: 1.0
			}
			MultiEffect {
				anchors.fill: effect
				source: effect
				maskSource: effect
				colorizationColor: mainItem.colorizationColor ? mainItem.colorizationColor : 'black'
				colorization: 1.0
			}
		}
	}
	Loader {
		anchors.fill: image
		z: mainItem.z - 1
		active: mainItem.shadowEnabled || mainItem._shadowUsed
		sourceComponent: MultiEffect {
			enabled: mainItem.shadowEnabled
			source: image
			visible: mainItem.shadowEnabled
			// Crash : https://bugreports.qt.io/browse/QTBUG-124730?
			shadowEnabled: true //mainItem.shadowEnabled
			shadowColor: DefaultStyle.grey_1000
			shadowBlur: 0
			shadowOpacity: mainItem.shadowEnabled ? 0.7 : 0.0
		}
	}
}
