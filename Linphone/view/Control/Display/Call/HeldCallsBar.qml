import QtQuick
import QtQuick.Layouts
import Linphone
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

// Autres appels pendant un appel, en haut de l'ecran d'appel (Combine et grande fenetre). Cachee s'il n'y a qu'un appel.
// - Un appel sonne : qui appelle, « Refuser » et « Repondre » (l'appel en cours passe alors en attente, le SDK s'en
//   charge).
// - Sinon, les appels en attente : qui attend, « Reunir » pour mettre tout le monde ensemble (conference geree par ce
//   poste), et un clic ailleurs sur la barre pour basculer vers l'appel en attente.
Rectangle {
	id: mainItem
	property CallGui currentCall

	// L'appel en cours est etabli : on ne reunit qu'avec quelqu'un qui a decroche.
	readonly property var currentState: currentCall ? currentCall.core.state : LinphoneEnums.CallState.Idle
	readonly property bool currentConnected: currentState === LinphoneEnums.CallState.StreamsRunning
		|| currentState === LinphoneEnums.CallState.Connected
		|| currentState === LinphoneEnums.CallState.Updating
		|| currentState === LinphoneEnums.CallState.UpdatedByRemote
	readonly property bool currentInConference: !!currentCall && currentCall.core.isConference
	// Appels decroches qui attendent : tous sauf l'appel en cours et, si on est en conference, ceux qui y sont avec nous.
	// Un appel qui sonne encore ou qui se termine n'en fait pas partie.
	readonly property var heldCalls: {
		var list = []
		for (var i = 0; i < callRepeater.count; ++i) {
			var item = callRepeater.itemAt(i)
			if (item && item.waiting)
				list.push(item.modelData)
		}
		return list
	}
	// Appel entrant pendant l'appel en cours (le premier, s'il y en a plusieurs).
	readonly property var ringingCall: {
		for (var i = 0; i < callRepeater.count; ++i) {
			var item = callRepeater.itemAt(i)
			if (item && item.ringing)
				return item.modelData
		}
		return null
	}
	readonly property bool showRinging: !!ringingCall
	readonly property var shownCall: showRinging ? ringingCall : (heldCalls.length > 0 ? heldCalls[0] : null)
	// Reunir : seulement des appels internes (poste a poste), aucun appel exterieur ni venu d'une file.
	readonly property bool mergeAllowed: !!currentCall && currentCall.core.internalCall
		&& heldCalls.every(function (c) { return c.core.internalCall })
	readonly property bool heldConference: heldCalls.length > 1
		&& heldCalls.every(function (c) { return c.core.isConference })
	readonly property string title: showRinging
		? ringingCall.core.remoteName
		: heldCalls.length === 0
			? ""
			: heldCalls.length === 1
				? heldCalls[0].core.remoteName
				: heldConference
					? "Conférence · " + (heldCalls.length + 1) + " personnes"
					: heldCalls.length + " appels"

	visible: !!shownCall
	implicitHeight: content.implicitHeight + Utils.getSizeWithScreenRatio(16)
	radius: Utils.getSizeWithScreenRatio(12)
	color: barArea.enabled && barArea.containsMouse ? DefaultStyle.callButtonHovered : DefaultStyle.callButton

	// Tous les appels ; l'appel en cours est ecarte ici (le filtre du modele ne suit pas ses changements).
	CallProxy {
		id: allCalls
		sourceModel: AppCpp.calls
		showCurrentCall: true
	}
	Repeater {
		id: callRepeater
		model: allCalls
		delegate: Item {
			required property var modelData
			readonly property var callState: modelData.core.state
			readonly property bool other: !!mainItem.currentCall && modelData.core !== mainItem.currentCall.core
			readonly property bool ringing: other && (callState === LinphoneEnums.CallState.IncomingReceived
				|| callState === LinphoneEnums.CallState.IncomingEarlyMedia
				|| callState === LinphoneEnums.CallState.PushIncomingReceived)
			readonly property bool answered: callState === LinphoneEnums.CallState.Connected
				|| callState === LinphoneEnums.CallState.StreamsRunning
				|| callState === LinphoneEnums.CallState.Pausing
				|| callState === LinphoneEnums.CallState.Paused
				|| callState === LinphoneEnums.CallState.PausedByRemote
				|| callState === LinphoneEnums.CallState.Resuming
				|| callState === LinphoneEnums.CallState.Updating
				|| callState === LinphoneEnums.CallState.UpdatedByRemote
			readonly property bool waiting: other && answered
				&& !(mainItem.currentInConference && modelData.core.isConference)
		}
	}

	// Basculer : l'appel en cours passe en attente, celui qui attendait reprend (ou on rejoint sa conference).
	function switchToHeld() {
		if (heldCalls.length === 0)
			return
		if (currentCall && !currentCall.core.paused)
			currentCall.core.lSetPaused(true)
		heldCalls[0].core.lSetPaused(false)
	}

	// Bouton en pilule de la barre : Reunir, Refuser, Repondre.
	component BarButton: Rectangle {
		id: barButton
		property string label
		property string iconSource: ""
		property color baseColor: DefaultStyle.main1_button
		signal clicked
		Layout.preferredWidth: buttonRow.implicitWidth + Utils.getSizeWithScreenRatio(28)
		Layout.preferredHeight: Utils.getSizeWithScreenRatio(32)
		radius: height / 2
		color: buttonArea.pressed ? Qt.darker(baseColor, 1.15)
			: buttonArea.containsMouse ? Qt.lighter(baseColor, 1.15) : baseColor
		RowLayout {
			id: buttonRow
			anchors.centerIn: parent
			spacing: Utils.getSizeWithScreenRatio(6)
			EffectImage {
				visible: barButton.iconSource !== ""
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(15)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(15)
				imageSource: barButton.iconSource
				colorizationColor: DefaultStyle.grey_0
			}
			Text {
				text: barButton.label
				color: DefaultStyle.grey_0
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				font.weight: Font.Bold
			}
		}
		MouseArea {
			id: buttonArea
			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.PointingHandCursor
			onClicked: barButton.clicked()
		}
		Accessible.role: Accessible.Button
		Accessible.name: label
	}

	// Basculer en cliquant sur la barre : pas pour un appel qui sonne (Refuser ou Repondre), ni pendant que l'appel en
	// cours sonne encore (un appel sortant ne se met pas en attente).
	MouseArea {
		id: barArea
		anchors.fill: parent
		enabled: !mainItem.showRinging
			&& (mainItem.currentConnected || (!!mainItem.currentCall && mainItem.currentCall.core.paused))
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: mainItem.switchToHeld()
	}

	RowLayout {
		id: content
		anchors.fill: parent
		anchors.leftMargin: Utils.getSizeWithScreenRatio(10)
		anchors.rightMargin: Utils.getSizeWithScreenRatio(8)
		anchors.topMargin: Utils.getSizeWithScreenRatio(8)
		anchors.bottomMargin: Utils.getSizeWithScreenRatio(8)
		spacing: Utils.getSizeWithScreenRatio(10)
		Avatar {
			Layout.preferredWidth: Utils.getSizeWithScreenRatio(32)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(32)
			call: mainItem.shownCall
			displayPresence: false
			shadowEnabled: false
		}
		ColumnLayout {
			Layout.fillWidth: true
			spacing: 0
			Text {
				Layout.fillWidth: true
				text: mainItem.title
				color: DefaultStyle.grey_0
				elide: Text.ElideRight
				font.pixelSize: Utils.getSizeWithScreenRatio(14)
			}
			RowLayout {
				spacing: Utils.getSizeWithScreenRatio(4)
				EffectImage {
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(12)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(12)
					imageSource: mainItem.showRinging ? AppIcons.phone : AppIcons.phonePause
					colorizationColor: mainItem.showRinging ? DefaultStyle.success_500_main : DefaultStyle.main2_400
				}
				Text {
					text: mainItem.showRinging ? "appel entrant" : "en attente"
					color: mainItem.showRinging ? DefaultStyle.success_500_main : DefaultStyle.main2_400
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
				}
			}
		}
		// Appel entrant.
		BarButton {
			visible: mainItem.showRinging
			label: "Refuser"
			baseColor: DefaultStyle.danger_500_main
			onClicked: if (mainItem.ringingCall) mainItem.ringingCall.core.lDecline()
		}
		BarButton {
			visible: mainItem.showRinging
			label: "Répondre"
			baseColor: DefaultStyle.success_500_main
			onClicked: if (mainItem.ringingCall) mainItem.ringingCall.core.lAccept(false)
		}
		// Reunir : seulement quand la personne appelee a decroche.
		BarButton {
			visible: !mainItem.showRinging && mainItem.currentConnected && mainItem.mergeAllowed
			label: "Réunir"
			iconSource: AppIcons.arrowsMerge
			onClicked: allCalls.lMergeAll()
			Accessible.name: "Réunir les appels"
		}
	}
	Accessible.role: Accessible.Button
	Accessible.name: showRinging ? "Appel entrant de " + title : "Basculer vers " + title + ", en attente"
}
