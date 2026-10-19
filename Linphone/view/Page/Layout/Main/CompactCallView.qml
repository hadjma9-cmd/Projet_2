import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import UtilsCpp
import SettingsCpp
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils
import "qrc:/qt/qml/Linphone/view/Style/buttonStyle.js" as ButtonStyle

// Appel dans la petite fenetre (audio seulement), au style bleu nuit de la fenetre d'appel : appel entrant (Refuser,
// Repondre, halo vert qui pulse), appel en cours (photo et halo de la voix, Micro, Son, Attente, Clavier, Transfert,
// Plus, Raccrocher). Clavier, transfert, nouvel appel, liste des appels et choix des appareils s'ouvrent par-dessus.
Rectangle {
	id: mainItem
	property CallGui call
	readonly property var callState: call ? call.core.state : LinphoneEnums.CallState.Idle
	readonly property bool incoming: callState === LinphoneEnums.CallState.IncomingReceived
		|| callState === LinphoneEnums.CallState.IncomingEarlyMedia
		|| callState === LinphoneEnums.CallState.PushIncomingReceived
	readonly property bool outgoing: callState === LinphoneEnums.CallState.OutgoingInit
		|| callState === LinphoneEnums.CallState.OutgoingProgress
		|| callState === LinphoneEnums.CallState.OutgoingRinging
		|| callState === LinphoneEnums.CallState.OutgoingEarlyMedia
	readonly property bool ended: callState === LinphoneEnums.CallState.End
		|| callState === LinphoneEnums.CallState.Released
		|| callState === LinphoneEnums.CallState.Error
	readonly property bool running: !!call && !incoming && !outgoing && !ended
	readonly property bool connected: callState === LinphoneEnums.CallState.Connected
		|| callState === LinphoneEnums.CallState.StreamsRunning
	readonly property bool paused: !!call && (call.core.paused || callState === LinphoneEnums.CallState.Paused
		|| callState === LinphoneEnums.CallState.Pausing)

	// Appels reunis en conference par ce poste (au moins deux) : photos et noms de l'ecran de conference.
	readonly property var conferenceMembers: {
		var list = []
		for (var i = 0; i < conferenceCalls.count; ++i) {
			var item = conferenceCalls.itemAt(i)
			if (item && item.member)
				list.push(item.modelData)
		}
		return list
	}
	readonly property bool inConference: !!call && call.core.isConference && conferenceMembers.length >= 2
	// Participants affiches en photo : trois au plus, le reste en « +N ».
	readonly property int shownMembers: Math.min(conferenceMembers.length, 3)

	color: DefaultStyle.callBackground

	CallProxy {
		id: allCalls
		sourceModel: AppCpp.calls
		showCurrentCall: true
	}
	Repeater {
		id: conferenceCalls
		model: allCalls
		delegate: Item {
			required property var modelData
			readonly property bool member: modelData.core.isConference
		}
	}
	AccountProxy {
		id: accountProxy
	}

	// Raccrocher en conference : la conference passe par ce poste, elle s'arrete donc pour tout le monde.
	function endConference() {
		UtilsCpp.getMainWindow().showConfirmationLambdaPopup("Terminer la conférence",
			"Raccrocher terminera l'appel pour tout le monde.", "",
			function (confirmed) {
				if (!confirmed)
					return
				var members = mainItem.conferenceMembers
				for (var i = 0; i < members.length; ++i)
					members[i].core.lTerminate()
			})
	}

	// Rien ne passe a la petite fenetre dessous : ni clic (droit compris), ni survol (bulles, curseur), ni molette.
	MouseArea {
		anchors.fill: parent
		hoverEnabled: true
		acceptedButtons: Qt.AllButtons
		onWheel: wheel => wheel.accepted = true
	}

	function openPanel(component, title) {
		panelTitle.text = title
		panelLoader.sourceComponent = component
	}
	function closePanel() {
		panelLoader.sourceComponent = null
	}

	ColumnLayout {
		anchors.fill: parent
		anchors.topMargin: Utils.getSizeWithScreenRatio(10)
		anchors.bottomMargin: Utils.getSizeWithScreenRatio(18)
		spacing: Utils.getSizeWithScreenRatio(8)

		// Etat de l'appel et sa duree.
		RowLayout {
			Layout.alignment: Qt.AlignHCenter
			spacing: Utils.getSizeWithScreenRatio(6)
			EffectImage {
				visible: mainItem.running
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(13)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(13)
				imageSource: mainItem.call && mainItem.call.core.encryption !== LinphoneEnums.MediaEncryption.None
					? AppIcons.lockSimple : AppIcons.lockSimpleOpen
				colorizationColor: DefaultStyle.main2_300
			}
			Text {
				text: mainItem.inConference
					? "Conférence" + (mainItem.connected && mainItem.call
						? "  ·  " + UtilsCpp.formatElapsedTime(mainItem.call.core.duration) : "")
					: mainItem.incoming
					? "Appel entrant"
					: mainItem.outgoing
						? "Appel en cours…"
						: mainItem.ended
							? "Appel terminé"
							: mainItem.paused
								? "En attente"
								: "Appel en cours" + (mainItem.connected && mainItem.call
									? "  ·  " + UtilsCpp.formatElapsedTime(mainItem.call.core.duration) : "")
				color: DefaultStyle.main2_200
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
			}
		}

		// Un autre appel sonne (Refuser, Repondre) ou attend (« Reunir », ou un clic pour basculer vers lui).
		HeldCallsBar {
			Layout.fillWidth: true
			Layout.leftMargin: Utils.getSizeWithScreenRatio(16)
			Layout.rightMargin: Utils.getSizeWithScreenRatio(16)
			currentCall: mainItem.call
			visible: !!shownCall && !mainItem.incoming && !mainItem.ended
		}

		// Le correspondant a allume sa camera (video reellement recue) : sa video se voit en grande fenetre. Ma camera
		// reste coupee, a allumer moi-meme si je le veux.
		Rectangle {
			id: videoBanner
			visible: !!mainItem.call && mainItem.call.core.remoteVideoRequested && mainItem.running
			Layout.fillWidth: true
			Layout.leftMargin: Utils.getSizeWithScreenRatio(14)
			Layout.rightMargin: Utils.getSizeWithScreenRatio(14)
			Layout.preferredHeight: bannerContent.implicitHeight + Utils.getSizeWithScreenRatio(18)
			radius: Utils.getSizeWithScreenRatio(10)
			color: "#0E2A4A"
			border.width: 1
			border.color: DefaultStyle.main1_500_main
			Timer {
				interval: 10000
				running: videoBanner.visible
				onTriggered: if (mainItem.call) mainItem.call.core.remoteVideoRequested = false
			}
			ColumnLayout {
				id: bannerContent
				anchors.fill: parent
				anchors.margins: Utils.getSizeWithScreenRatio(9)
				spacing: Utils.getSizeWithScreenRatio(6)
				RowLayout {
					spacing: Utils.getSizeWithScreenRatio(8)
					EffectImage {
						Layout.preferredWidth: Utils.getSizeWithScreenRatio(16)
						Layout.preferredHeight: Utils.getSizeWithScreenRatio(16)
						imageSource: AppIcons.videoCamera
						colorizationColor: DefaultStyle.main1_300
					}
					Text {
						Layout.fillWidth: true
						text: (mainItem.call ? mainItem.call.core.remoteName : "") + " a activé sa caméra"
						color: DefaultStyle.grey_0
						elide: Text.ElideRight
						font.pixelSize: Utils.getSizeWithScreenRatio(13)
					}
					Item {
						Layout.preferredWidth: Utils.getSizeWithScreenRatio(18)
						Layout.preferredHeight: Utils.getSizeWithScreenRatio(18)
						Repeater {
							model: [45, -45]
							Rectangle {
								anchors.centerIn: parent
								width: Utils.getSizeWithScreenRatio(12)
								height: 1
								antialiasing: true
								rotation: modelData
								color: DefaultStyle.main2_300
							}
						}
						MouseArea {
							anchors.fill: parent
							cursorShape: Qt.PointingHandCursor
							onClicked: mainItem.call.core.remoteVideoRequested = false
						}
					}
				}
				Rectangle {
					Layout.alignment: Qt.AlignRight
					Layout.preferredWidth: switchText.implicitWidth + Utils.getSizeWithScreenRatio(20)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(26)
					radius: height / 2
					color: switchArea.containsMouse ? Qt.lighter(DefaultStyle.main1_button, 1.15) : DefaultStyle.main1_button
					Text {
						id: switchText
						anchors.centerIn: parent
						text: "Voir la vidéo"
						color: DefaultStyle.grey_0
						font.pixelSize: Utils.getSizeWithScreenRatio(12)
					}
					MouseArea {
						id: switchArea
						anchors.fill: parent
						hoverEnabled: true
						cursorShape: Qt.PointingHandCursor
						onClicked: {
							mainItem.call.core.remoteVideoRequested = false
							// Grande fenetre : la fenetre d'appel revient et montre sa video.
							AppCpp.compactMode = false
						}
					}
				}
			}
		}

		// Correspondant : photo, halo (voix ou sonnerie), nom et numero. En conference : les photos des participants qui
		// se chevauchent (la sienne en dernier), le nombre de personnes et leurs noms.
		Item {
			Layout.fillWidth: true
			Layout.fillHeight: true
			ColumnLayout {
				visible: mainItem.inConference
				anchors.centerIn: parent
				spacing: Utils.getSizeWithScreenRatio(6)
				Row {
					Layout.alignment: Qt.AlignHCenter
					Layout.bottomMargin: Utils.getSizeWithScreenRatio(8)
					spacing: -Utils.getSizeWithScreenRatio(18)
					Repeater {
						model: mainItem.conferenceMembers.slice(0, mainItem.shownMembers)
						delegate: Rectangle {
							required property var modelData
							width: Utils.getSizeWithScreenRatio(80)
							height: width
							radius: width / 2
							color: DefaultStyle.callBackground
							Avatar {
								anchors.centerIn: parent
								width: Utils.getSizeWithScreenRatio(74)
								height: width
								call: parent.modelData
								displayPresence: false
								shadowEnabled: false
							}
						}
					}
					Rectangle {
						visible: mainItem.conferenceMembers.length > mainItem.shownMembers
						width: Utils.getSizeWithScreenRatio(80)
						height: width
						radius: width / 2
						color: DefaultStyle.callBackground
						Rectangle {
							anchors.centerIn: parent
							width: Utils.getSizeWithScreenRatio(74)
							height: width
							radius: width / 2
							color: DefaultStyle.callButton
							Text {
								anchors.centerIn: parent
								text: "+" + (mainItem.conferenceMembers.length - mainItem.shownMembers)
								color: DefaultStyle.grey_0
								font.pixelSize: Utils.getSizeWithScreenRatio(22)
								font.weight: Font.Medium
							}
						}
					}
					Rectangle {
						width: Utils.getSizeWithScreenRatio(80)
						height: width
						radius: width / 2
						color: DefaultStyle.callBackground
						Avatar {
							anchors.centerIn: parent
							width: Utils.getSizeWithScreenRatio(74)
							height: width
							account: accountProxy.defaultAccount
							displayPresence: false
							shadowEnabled: false
						}
					}
				}
				Text {
					Layout.alignment: Qt.AlignHCenter
					text: "Conférence · " + (mainItem.conferenceMembers.length + 1) + " personnes"
					color: DefaultStyle.grey_0
					font {
						pixelSize: Utils.getSizeWithScreenRatio(20)
						weight: Font.Medium
					}
				}
				Text {
					Layout.alignment: Qt.AlignHCenter
					Layout.maximumWidth: mainItem.width - Utils.getSizeWithScreenRatio(40)
					text: mainItem.conferenceMembers.map(function (c) { return c.core.remoteName }).join(", ") + " et vous"
					color: DefaultStyle.main2_300
					elide: Text.ElideRight
					horizontalAlignment: Text.AlignHCenter
					font.pixelSize: Utils.getSizeWithScreenRatio(13)
				}
			}
			ColumnLayout {
				visible: !mainItem.inConference
				anchors.centerIn: parent
				spacing: Utils.getSizeWithScreenRatio(6)
				Item {
					Layout.alignment: Qt.AlignHCenter
					Layout.preferredWidth: Utils.getSizeWithScreenRatio(170)
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(170)
					// Sonnerie (appel entrant ou sortant) : halo vert qui pulse.
					Repeater {
						model: mainItem.incoming || mainItem.outgoing ? 2 : 0
						Rectangle {
							anchors.centerIn: parent
							width: Utils.getSizeWithScreenRatio(110)
							height: width
							radius: width / 2
							color: mainItem.incoming ? DefaultStyle.success_500_main : DefaultStyle.callHalo
							opacity: 0
							// Meme periode pour les deux anneaux, decales d'une demi-pulsation.
							SequentialAnimation on scale {
								loops: Animation.Infinite
								running: true
								PauseAnimation {
									duration: index * 700
								}
								NumberAnimation {
									from: 1
									to: 1.55
									duration: 1400
									easing.type: Easing.OutQuad
								}
								PauseAnimation {
									duration: (1 - index) * 700
								}
							}
							SequentialAnimation on opacity {
								loops: Animation.Infinite
								running: true
								PauseAnimation {
									duration: index * 700
								}
								NumberAnimation {
									from: 0.35
									to: 0
									duration: 1400
									easing.type: Easing.OutQuad
								}
								PauseAnimation {
									duration: (1 - index) * 700
								}
							}
						}
					}
					VoiceHalo {
						anchors.centerIn: parent
						baseSize: Utils.getSizeWithScreenRatio(110)
						call: mainItem.call
						active: mainItem.running && !mainItem.paused
						visible: active
					}
					Avatar {
						anchors.centerIn: parent
						width: Utils.getSizeWithScreenRatio(110)
						height: width
						call: mainItem.call
						displayPresence: false
						shadowEnabled: false
					}
				}
				Text {
					Layout.alignment: Qt.AlignHCenter
					Layout.maximumWidth: mainItem.width - Utils.getSizeWithScreenRatio(40)
					text: mainItem.call ? mainItem.call.core.remoteName : ""
					color: DefaultStyle.grey_0
					elide: Text.ElideRight
					font {
						pixelSize: Utils.getSizeWithScreenRatio(20)
						weight: Font.Medium
					}
				}
				Text {
					Layout.alignment: Qt.AlignHCenter
					property string address: mainItem.call ? mainItem.call.core.remoteAddress : ""
					text: SettingsCpp.hideSipAddresses || /^sip:[0-9+*#]+@/.test(address) ? UtilsCpp.getUsername(address) : address
					color: DefaultStyle.main2_300
					font.pixelSize: Utils.getSizeWithScreenRatio(13)
				}
			}
		}

		// Appel en cours : deux rangees de trois.
		GridLayout {
			id: runningButtons
			visible: mainItem.running
			Layout.alignment: Qt.AlignHCenter
			columns: 3
			columnSpacing: Utils.getSizeWithScreenRatio(30)
			rowSpacing: Utils.getSizeWithScreenRatio(12)
			CallRoundButton {
				iconSource: mainItem.call && mainItem.call.core.microphoneMuted ? AppIcons.microphoneSlash : AppIcons.microphone
				label: "Micro"
				size: Utils.getSizeWithScreenRatio(50)
				active: !!mainItem.call && mainItem.call.core.microphoneMuted
				onClicked: mainItem.call.core.lSetMicrophoneMuted(!mainItem.call.core.microphoneMuted)
			}
			CallRoundButton {
				iconSource: mainItem.call && mainItem.call.core.speakerMuted ? AppIcons.speakerSlash : AppIcons.speaker
				label: "Son"
				size: Utils.getSizeWithScreenRatio(50)
				active: !!mainItem.call && mainItem.call.core.speakerMuted
				onClicked: mainItem.call.core.lSetSpeakerMuted(!mainItem.call.core.speakerMuted)
			}
			CallRoundButton {
				iconSource: mainItem.paused ? AppIcons.play : AppIcons.phonePause
				label: "Attente"
				size: Utils.getSizeWithScreenRatio(50)
				active: mainItem.paused
				enabled: mainItem.callState !== LinphoneEnums.CallState.PausedByRemote
				onClicked: mainItem.call.core.lSetPaused(!mainItem.call.core.paused)
			}
			CallRoundButton {
				iconSource: AppIcons.dialer
				label: "Clavier"
				size: Utils.getSizeWithScreenRatio(50)
				active: panelLoader.sourceComponent === dtmfPanel
				onClicked: mainItem.openPanel(dtmfPanel, "Clavier")
			}
			CallRoundButton {
				iconSource: AppIcons.transferCall
				label: "Transfert"
				size: Utils.getSizeWithScreenRatio(50)
				active: panelLoader.sourceComponent === transferPanel
				onClicked: mainItem.openPanel(transferPanel, "Transférer à…")
			}
			CallRoundButton {
				id: moreButton
				iconSource: AppIcons.horizontalDots
				label: "Plus"
				size: Utils.getSizeWithScreenRatio(50)
				active: moreMenu.visible
				onClicked: moreMenu.visible ? moreMenu.close() : moreMenu.open()
				Control.Popup {
					id: moreMenu
					y: -height - Utils.getSizeWithScreenRatio(8)
					x: moreButton.width - width
					padding: Utils.getSizeWithScreenRatio(8)
					closePolicy: Control.Popup.CloseOnEscape | Control.Popup.CloseOnPressOutsideParent
					background: Rectangle {
						color: DefaultStyle.grey_0
						radius: Utils.getSizeWithScreenRatio(12)
					}
					contentItem: ColumnLayout {
						spacing: Utils.getSizeWithScreenRatio(2)
						IconLabelButton {
							Layout.fillWidth: true
							style: ButtonStyle.noBackground
							icon.source: AppIcons.newCall
							icon.width: Utils.getSizeWithScreenRatio(22)
							icon.height: Utils.getSizeWithScreenRatio(22)
							text: "Nouvel appel"
							onClicked: {
								moreMenu.close()
								mainItem.openPanel(newCallPanel, "Nouvel appel")
							}
						}
						IconLabelButton {
							Layout.fillWidth: true
							style: ButtonStyle.noBackground
							icon.source: AppIcons.callList
							icon.width: Utils.getSizeWithScreenRatio(22)
							icon.height: Utils.getSizeWithScreenRatio(22)
							text: "Liste des appels"
							onClicked: {
								moreMenu.close()
								mainItem.openPanel(callListPanel, "Liste des appels")
							}
						}
						IconLabelButton {
							Layout.fillWidth: true
							visible: !SettingsCpp.disableCallRecordings
							enabled: !!mainItem.call && mainItem.call.core.recordable
							style: ButtonStyle.noBackground
							icon.source: AppIcons.recordFill
							icon.width: Utils.getSizeWithScreenRatio(22)
							icon.height: Utils.getSizeWithScreenRatio(22)
							contentImageColor: mainItem.call && mainItem.call.core.recording ? DefaultStyle.danger_500_main : DefaultStyle.main2_500_main
							hoveredImageColor: contentImageColor
							textColor: contentImageColor
							hoveredTextColor: textColor
							text: mainItem.call && mainItem.call.core.recording ? "Arrêter l'enregistrement" : "Enregistrer l'appel"
							onClicked: {
								moreMenu.close()
								if (mainItem.call.core.recording)
									mainItem.call.core.lStopRecording()
								else
									mainItem.call.core.lStartRecording()
							}
						}
						IconLabelButton {
							Layout.fillWidth: true
							style: ButtonStyle.noBackground
							icon.source: AppIcons.settings
							icon.width: Utils.getSizeWithScreenRatio(22)
							icon.height: Utils.getSizeWithScreenRatio(22)
							text: "Micro et haut-parleur"
							onClicked: {
								moreMenu.close()
								mainItem.openPanel(devicesPanel, "Micro et haut-parleur")
							}
						}
					}
				}
			}
		}

		// Appel sortant qui sonne : micro et son.
		RowLayout {
			visible: mainItem.outgoing
			Layout.alignment: Qt.AlignHCenter
			spacing: Utils.getSizeWithScreenRatio(30)
			CallRoundButton {
				iconSource: mainItem.call && mainItem.call.core.microphoneMuted ? AppIcons.microphoneSlash : AppIcons.microphone
				label: "Micro"
				size: Utils.getSizeWithScreenRatio(50)
				active: !!mainItem.call && mainItem.call.core.microphoneMuted
				onClicked: mainItem.call.core.lSetMicrophoneMuted(!mainItem.call.core.microphoneMuted)
			}
			CallRoundButton {
				iconSource: mainItem.call && mainItem.call.core.speakerMuted ? AppIcons.speakerSlash : AppIcons.speaker
				label: "Son"
				size: Utils.getSizeWithScreenRatio(50)
				active: !!mainItem.call && mainItem.call.core.speakerMuted
				onClicked: mainItem.call.core.lSetSpeakerMuted(!mainItem.call.core.speakerMuted)
			}
		}

		// Raccrocher, ou Refuser et Repondre.
		RowLayout {
			Layout.alignment: Qt.AlignHCenter
			Layout.topMargin: Utils.getSizeWithScreenRatio(6)
			spacing: Utils.getSizeWithScreenRatio(48)
			CallRoundButton {
				visible: !!mainItem.call && !mainItem.ended
				danger: true
				size: Utils.getSizeWithScreenRatio(54)
				iconSource: AppIcons.endCall
				label: mainItem.incoming ? "Refuser" : "Raccrocher"
				onClicked: mainItem.inConference ? mainItem.endConference() : mainItem.call.core.lTerminate()
			}
			CallRoundButton {
				visible: mainItem.callState === LinphoneEnums.CallState.IncomingReceived
					|| mainItem.callState === LinphoneEnums.CallState.IncomingEarlyMedia
				success: true
				size: Utils.getSizeWithScreenRatio(54)
				iconSource: AppIcons.phone
				label: "Répondre"
				// Audio seulement en petite fenetre.
				onClicked: mainItem.call.core.lAccept(false)
			}
		}
	}

	// Panneaux par-dessus l'appel : clavier, transfert, nouvel appel, liste des appels, appareils audio.
	Rectangle {
		id: panel
		visible: !!panelLoader.sourceComponent
		anchors.fill: parent
		color: DefaultStyle.grey_0
		onVisibleChanged: if (!visible) panelTitle.text = ""
		// Une zone vide du panneau ne transmet rien aux boutons de l'appel dessous (Raccrocher compris).
		MouseArea {
			anchors.fill: parent
			hoverEnabled: true
			acceptedButtons: Qt.AllButtons
			onWheel: wheel => wheel.accepted = true
		}
		ColumnLayout {
			anchors.fill: parent
			spacing: 0
			RowLayout {
				Layout.fillWidth: true
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(48)
				Layout.leftMargin: Utils.getSizeWithScreenRatio(8)
				Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
				spacing: Utils.getSizeWithScreenRatio(6)
				RoundButton {
					style: ButtonStyle.noBackground
					icon.source: AppIcons.leftArrow
					icon.width: Utils.getSizeWithScreenRatio(22)
					icon.height: Utils.getSizeWithScreenRatio(22)
					onClicked: mainItem.closePanel()
				}
				Text {
					id: panelTitle
					Layout.fillWidth: true
					color: DefaultStyle.main2_700
					elide: Text.ElideRight
					font {
						pixelSize: Utils.getSizeWithScreenRatio(16)
						weight: Font.Medium
					}
				}
			}
			Loader {
				id: panelLoader
				Layout.fillWidth: true
				Layout.fillHeight: true
				Layout.leftMargin: Utils.getSizeWithScreenRatio(12)
				Layout.rightMargin: Utils.getSizeWithScreenRatio(12)
				Layout.bottomMargin: Utils.getSizeWithScreenRatio(12)
			}
		}
	}

	// Fin de l'appel : les panneaux se ferment.
	onEndedChanged: if (ended) closePanel()

	Component {
		id: dtmfPanel
		// Meme pave que la fenetre d'appel (chiffres tapes en grand, pave juste dessous) ; touches teintees, le
		// panneau etant blanc. Clavier de l'ordinateur : pave numerique seulement.
		DtmfPad {
			id: dtmfPad
			call: mainItem.call
			keyStyle: ButtonStyle.numericPadLight
			focus: true
			Keys.onPressed: event => dtmfPad.handleKeyPadEvent(event)
			Component.onCompleted: forceActiveFocus()
		}
	}
	Component {
		id: transferPanel
		NewCallForm {
			startGroupButtonVisible: false
			displayCurrentCalls: true
			searchBarColor: DefaultStyle.grey_100
			searchBarRightMaring: 0
			onContactClicked: contact => {
				var window = UtilsCpp.getMainWindow()
				window.showConfirmationLambdaPopup("Transférer l'appel",
					"Transférer " + mainItem.call.core.remoteName + " à " + contact.core.fullName + " ?", "",
					function (confirmed) {
						if (confirmed) {
							window.transferCallToContact(mainItem.call, contact, mainItem)
							mainItem.closePanel()
						}
					})
			}
			onTransferCallToAnotherRequested: dest => {
				mainItem.call.core.lTransferCallToAnother(dest.core.remoteAddress)
				mainItem.closePanel()
			}
		}
	}
	Component {
		id: newCallPanel
		NewCallForm {
			startGroupButtonVisible: false
			searchBarColor: DefaultStyle.grey_100
			searchBarRightMaring: 0
			onContactClicked: contact => {
				mainItem.closePanel()
				UtilsCpp.getMainWindow().startCallWithContact(contact, false, mainItem)
			}
		}
	}
	Component {
		id: callListPanel
		Control.ScrollView {
			CallListView {
				width: parent.width
			}
		}
	}
	Component {
		id: devicesPanel
		Control.ScrollView {
			MultimediaSettings {
				width: parent.width
				call: mainItem.call
			}
		}
	}
}
