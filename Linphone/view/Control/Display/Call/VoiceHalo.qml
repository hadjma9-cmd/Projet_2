import QtQuick
import Linphone

// Halo autour de la photo du correspondant, qui suit sa voix : calme quand il se tait, il grandit et s'eclaire
// quand il parle, davantage quand il crie. Il monte vite et redescend plus doucement, pour ne pas trembler entre
// deux syllabes. Le volume n'est mesure que pendant l'affichage du halo (requestRemoteVolume).
Item {
	id: mainItem
	property CallGui call: null
	property bool active: true
	// Diametre de la photo entouree.
	property real baseSize: 120
	property color color: DefaultStyle.callHalo

	readonly property bool measuring: mainItem.active && mainItem.visible && !!mainItem.call
	readonly property real level: mainItem.measuring ? mainItem.call.core.remoteVolume : 0
	property real _previousLevel: 0
	property bool _rising: false
	property CallGui _requestedCall: null

	width: baseSize
	height: baseSize

	onLevelChanged: {
		mainItem._rising = mainItem.level > mainItem._previousLevel
		mainItem._previousLevel = mainItem.level
	}
	onMeasuringChanged: updateRequest()
	onCallChanged: updateRequest()
	Component.onCompleted: updateRequest()
	Component.onDestruction: {
		if (mainItem._requestedCall) mainItem._requestedCall.core.requestRemoteVolume(false)
		mainItem._requestedCall = null
	}

	function updateRequest() {
		var wanted = mainItem.measuring ? mainItem.call : null
		if (wanted === mainItem._requestedCall) return
		if (mainItem._requestedCall) mainItem._requestedCall.core.requestRemoteVolume(false)
		mainItem._requestedCall = wanted
		if (mainItem._requestedCall) mainItem._requestedCall.core.requestRemoteVolume(true)
	}

	// Taille et transparence animees sur le fil de rendu (Animator) : rien a recalculer dans la mise en page.
	component Ring: Rectangle {
		id: ring
		property real restOpacity
		property real gain
		property real growth
		anchors.centerIn: parent
		height: width
		radius: width / 2
		color: mainItem.color
		opacity: ring.restOpacity + mainItem.level * ring.gain
		scale: 1 + mainItem.level * ring.growth
		Behavior on scale {
			ScaleAnimator {
				duration: mainItem._rising ? 70 : 260
				easing.type: Easing.OutQuad
			}
		}
		Behavior on opacity {
			OpacityAnimator {
				duration: mainItem._rising ? 70 : 260
				easing.type: Easing.OutQuad
			}
		}
	}

	Ring {
		width: mainItem.baseSize * 1.5
		restOpacity: 0.10
		gain: 0.22
		growth: 0.45
	}
	Ring {
		width: mainItem.baseSize * 1.25
		restOpacity: 0.18
		gain: 0.30
		growth: 0.25
	}
}
