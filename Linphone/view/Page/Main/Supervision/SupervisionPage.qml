import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Tableau des files (grande fenetre, page 5 de la bande), ouvert a tous les postes du domaine. De haut en bas :
// bandeau d'etat (des appels attendent / tout est calme), appels a prendre (toutes files confondues, les plus anciens
// d'abord), puis une carte par file avec ses agents. Donnees en direct (SupervisionCpp) tant que la page est affichee ;
// les durees avancent ici, a partir des heures recues. Couleurs des agents : vert libre, jaune sonne, bleu en appel,
// rouge en pause.
Item {
	id: mainItem

	readonly property var queues: SupervisionCpp.queues
	// Heure du serveur, a la seconde : base des durees affichees.
	property real now: Date.now() / 1000 + SupervisionCpp.clockOffset

	readonly property color freeColor: "#4AA36B"
	readonly property color ringColor: "#E8B43A"
	readonly property color callColor: DefaultStyle.main1_500_main
	readonly property color pauseColor: DefaultStyle.danger_500_main
	readonly property color warnColor: "#B8650F"
	readonly property real margin: Utils.getSizeWithScreenRatio(32)

	// Appels qui attendent ou qui sonnent, toutes files confondues, les plus anciens d'abord.
	readonly property var pending: {
		var list = []
		for (var i = 0; i < queues.length; ++i) {
			var calls = queues[i].calls || []
			for (var j = 0; j < calls.length; ++j)
				if (calls[j].state !== "answered")
					list.push({"call": calls[j], "queue": queues[i].name})
		}
		list.sort(function (a, b) { return a.call.since - b.call.since })
		return list
	}
	readonly property int waitingCount: pending.filter(function (p) { return p.call.state === "waiting" }).length

	// Lecture en direct seulement tant que la fenetre du tableau est ouverte (un element reste « visible » dans une
	// fenetre cachee : la fenetre donne cet etat).
	property bool active: visible
	onActiveChanged: active ? SupervisionCpp.start() : SupervisionCpp.stop()
	Component.onCompleted: if (active) SupervisionCpp.start()
	Component.onDestruction: SupervisionCpp.stop()

	Timer {
		interval: 1000
		repeat: true
		running: mainItem.active
		triggeredOnStart: true
		onTriggered: mainItem.now = Date.now() / 1000 + SupervisionCpp.clockOffset
	}

	// « 1:47 », « 2 h 05 », « 17 j ».
	function duration(since) {
		var seconds = Math.max(0, Math.floor(mainItem.now - since))
		if (!since)
			return ""
		if (seconds < 3600)
			return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
		if (seconds < 86400)
			return Math.floor(seconds / 3600) + " h " + String(Math.floor(seconds % 3600 / 60)).padStart(2, "0")
		return Math.floor(seconds / 86400) + " j"
	}
	function callerLabel(call) {
		return call.name && call.name.length > 0 ? call.name + " · " + call.number
			: call.number && call.number.length > 0 ? call.number : "Numéro masqué"
	}

	// Etiquette d'un agent : icone pleine dans la couleur de son etat, prenom, etat ecrit, duree ; en appel, le
	// correspondant dessous.
	component AgentLabel: Rectangle {
		id: agentLabel
		property var agent
		readonly property string agentState: agent ? agent.state : ""
		readonly property color stateColor: agentState === "free" ? mainItem.freeColor
			: agentState === "ringing" ? mainItem.ringColor
			: agentState === "incall" ? mainItem.callColor
			: agentState === "pause" ? mainItem.pauseColor : DefaultStyle.main2_400
		readonly property color textColor: agentState === "free" ? "#2F7D4F"
			: agentState === "ringing" ? "#9A6B00"
			: agentState === "incall" ? DefaultStyle.main1_500_main
			: agentState === "pause" ? "#B23B3B" : DefaultStyle.main2_500_main
		Layout.fillWidth: true
		Layout.preferredHeight: labelRow.implicitHeight + 2 * Utils.getSizeWithScreenRatio(8)
		radius: Utils.getSizeWithScreenRatio(10)
		color: DefaultStyle.main2_100
		RowLayout {
			id: labelRow
			anchors.fill: parent
			anchors.leftMargin: Utils.getSizeWithScreenRatio(10)
			anchors.rightMargin: Utils.getSizeWithScreenRatio(12)
			spacing: Utils.getSizeWithScreenRatio(10)
			Rectangle {
				Layout.preferredWidth: Utils.getSizeWithScreenRatio(26)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(26)
				radius: width / 2
				color: agentLabel.stateColor
				EffectImage {
					id: stateIcon
					anchors.centerIn: parent
					width: Utils.getSizeWithScreenRatio(14)
					height: width
					imageSource: agentLabel.agentState === "free" ? AppIcons.check
						: agentLabel.agentState === "ringing" ? AppIcons.phoneCall
						: agentLabel.agentState === "incall" ? AppIcons.phone
						: agentLabel.agentState === "pause" ? AppIcons.pause : AppIcons.signOut
					colorizationColor: DefaultStyle.grey_0
					// Le combine vibre tant que ca sonne.
					SequentialAnimation on rotation {
						running: agentLabel.agentState === "ringing" && mainItem.active
						loops: Animation.Infinite
						onRunningChanged: if (!running) stateIcon.rotation = 0
						NumberAnimation { to: -16; duration: 160 }
						NumberAnimation { to: 14; duration: 160 }
						NumberAnimation { to: -8; duration: 160 }
						NumberAnimation { to: 0; duration: 160 }
						PauseAnimation { duration: 460 }
					}
				}
			}
			ColumnLayout {
				Layout.fillWidth: true
				spacing: 0
				RowLayout {
					spacing: Utils.getSizeWithScreenRatio(8)
					Text {
						text: agentLabel.agent ? agentLabel.agent.name : ""
						font.pixelSize: Utils.getSizeWithScreenRatio(13)
						font.weight: Font.DemiBold
						color: DefaultStyle.main2_800
						elide: Text.ElideRight
						Layout.maximumWidth: Utils.getSizeWithScreenRatio(130)
					}
					Text {
						text: agentLabel.agentState === "free" ? "Libre"
							: agentLabel.agentState === "ringing" ? "Sonne"
							: agentLabel.agentState === "incall" ? "En appel"
							: agentLabel.agentState === "pause" ? "En pause" : "Déconnecté"
						font.pixelSize: Utils.getSizeWithScreenRatio(12)
						font.weight: Font.DemiBold
						color: agentLabel.textColor
					}
				}
				Text {
					visible: agentLabel.agentState === "incall" && !!agentLabel.agent && agentLabel.agent.with.length > 0
					Layout.fillWidth: true
					text: agentLabel.agent ? "avec " + agentLabel.agent.with : ""
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
					color: DefaultStyle.main2_500_main
					elide: Text.ElideRight
				}
			}
			Text {
				text: agentLabel.agent ? mainItem.duration(agentLabel.agent.since) : ""
				font.pixelSize: Utils.getSizeWithScreenRatio(12)
				font.features: {"tnum": 1}
				color: DefaultStyle.main2_500_main
			}
		}
	}

	Control.ScrollView {
		anchors.fill: parent
		contentWidth: availableWidth
		Control.ScrollBar.horizontal.policy: Control.ScrollBar.AlwaysOff

		ColumnLayout {
			id: content
			x: Math.max(mainItem.margin, (parent.width - width) / 2)
			width: Math.min(parent.width - 2 * mainItem.margin, Utils.getSizeWithScreenRatio(1000))
			spacing: 0

			// Titre, et l'etat de la connexion s'il y a un souci.
			RowLayout {
				Layout.fillWidth: true
				Layout.topMargin: Utils.getSizeWithScreenRatio(28)
				spacing: Utils.getSizeWithScreenRatio(12)
				Text {
					text: "Tableau des files"
					font: Typography.h2
					color: DefaultStyle.main2_700
				}
				Text {
					visible: SupervisionCpp.loaded && !SupervisionCpp.live
					text: "Reconnexion…"
					font.pixelSize: Utils.getSizeWithScreenRatio(12)
					color: DefaultStyle.main2_500_main
				}
				Item {
					Layout.fillWidth: true
				}
			}

			Text {
				visible: !SupervisionCpp.loaded
				Layout.topMargin: Utils.getSizeWithScreenRatio(24)
				text: "Chargement du tableau…"
				font.pixelSize: Utils.getSizeWithScreenRatio(14)
				color: DefaultStyle.main2_500_main
			}
			Text {
				visible: SupervisionCpp.loaded && mainItem.queues.length === 0
				Layout.topMargin: Utils.getSizeWithScreenRatio(24)
				text: "Aucune file d'attente dans votre domaine."
				font.pixelSize: Utils.getSizeWithScreenRatio(14)
				color: DefaultStyle.main2_500_main
			}

			// Bandeau d'etat.
			Rectangle {
				id: statusBand
				visible: SupervisionCpp.loaded && mainItem.queues.length > 0
				readonly property bool calm: mainItem.pending.length === 0
				Layout.fillWidth: true
				Layout.topMargin: Utils.getSizeWithScreenRatio(18)
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(74)
				radius: Utils.getSizeWithScreenRatio(14)
				color: calm ? "#E8F4EC" : "#FDF1E4"
				RowLayout {
					anchors.fill: parent
					anchors.leftMargin: Utils.getSizeWithScreenRatio(18)
					anchors.rightMargin: Utils.getSizeWithScreenRatio(18)
					spacing: Utils.getSizeWithScreenRatio(14)
					Rectangle {
						Layout.preferredWidth: Utils.getSizeWithScreenRatio(44)
						Layout.preferredHeight: Utils.getSizeWithScreenRatio(44)
						radius: width / 2
						color: statusBand.calm ? "#CBE7D4" : "#FAD9B6"
						EffectImage {
							anchors.centerIn: parent
							width: Utils.getSizeWithScreenRatio(22)
							height: width
							imageSource: statusBand.calm ? AppIcons.check : AppIcons.hourglass
							colorizationColor: statusBand.calm ? "#2F7D4F" : "#8A4B0B"
						}
					}
					ColumnLayout {
						Layout.fillWidth: true
						spacing: Utils.getSizeWithScreenRatio(2)
						Text {
							text: mainItem.pending.length === 0 ? "Tout est calme"
								: mainItem.waitingCount > 1 ? mainItem.waitingCount + " appels attendent"
								: mainItem.waitingCount === 1 ? "1 appel attend"
								: mainItem.pending.length > 1 ? mainItem.pending.length + " appels sonnent" : "1 appel sonne"
							font.pixelSize: Utils.getSizeWithScreenRatio(16)
							font.weight: Font.DemiBold
							color: DefaultStyle.main2_800
						}
						Text {
							Layout.fillWidth: true
							text: mainItem.pending.length === 0 ? "Aucun appel à prendre"
								: "Le plus ancien depuis " + mainItem.duration(mainItem.pending[0].call.since) + " · " + mainItem.pending[0].queue
							font.pixelSize: Utils.getSizeWithScreenRatio(13)
							color: mainItem.pending.length === 0 ? "#2F7D4F" : "#8A4B0B"
							elide: Text.ElideRight
						}
					}
				}
			}

			// Appels a prendre.
			Text {
				visible: mainItem.pending.length > 0
				Layout.topMargin: Utils.getSizeWithScreenRatio(22)
				text: "À prendre"
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				color: DefaultStyle.main2_500_main
			}
			Repeater {
				model: mainItem.pending
				delegate: Rectangle {
					id: callRow
					required property var modelData
					readonly property var call: modelData.call
					readonly property bool ringing: call.state === "ringing"
					readonly property real waited: Math.max(0, mainItem.now - call.since)
					readonly property bool late: !ringing && waited >= 60
					Layout.fillWidth: true
					Layout.topMargin: Utils.getSizeWithScreenRatio(8)
					Layout.preferredHeight: callColumn.implicitHeight + 2 * Utils.getSizeWithScreenRatio(12)
					radius: Utils.getSizeWithScreenRatio(12)
					color: DefaultStyle.grey_0
					RowLayout {
						anchors.fill: parent
						anchors.leftMargin: Utils.getSizeWithScreenRatio(16)
						anchors.rightMargin: Utils.getSizeWithScreenRatio(16)
						spacing: Utils.getSizeWithScreenRatio(14)
						EffectImage {
							Layout.preferredWidth: Utils.getSizeWithScreenRatio(20)
							Layout.preferredHeight: Utils.getSizeWithScreenRatio(20)
							imageSource: callRow.ringing ? AppIcons.phoneCall : AppIcons.hourglass
							colorizationColor: callRow.ringing ? "#C79400" : callRow.late ? mainItem.warnColor : DefaultStyle.main2_400
						}
						ColumnLayout {
							id: callColumn
							Layout.fillWidth: true
							spacing: Utils.getSizeWithScreenRatio(2)
							RowLayout {
								spacing: Utils.getSizeWithScreenRatio(8)
								Text {
									text: mainItem.callerLabel(callRow.call)
									font.pixelSize: Utils.getSizeWithScreenRatio(14)
									font.weight: Font.DemiBold
									color: DefaultStyle.main2_800
								}
								Rectangle {
									Layout.preferredHeight: queueTag.implicitHeight + Utils.getSizeWithScreenRatio(4)
									Layout.preferredWidth: queueTag.implicitWidth + Utils.getSizeWithScreenRatio(14)
									radius: Utils.getSizeWithScreenRatio(8)
									color: DefaultStyle.main1_100
									Text {
										id: queueTag
										anchors.centerIn: parent
										text: callRow.modelData.queue
										font.pixelSize: Utils.getSizeWithScreenRatio(11)
										color: DefaultStyle.main1_500_main
									}
								}
							}
							Text {
								Layout.fillWidth: true
								text: (callRow.ringing && callRow.call.agents.length > 0
									? "sonne chez " + callRow.call.agents.join(", ") + " depuis "
									: "attend depuis ") + mainItem.duration(callRow.call.since)
								font.pixelSize: Utils.getSizeWithScreenRatio(12)
								color: callRow.late ? mainItem.warnColor : DefaultStyle.main2_500_main
								elide: Text.ElideRight
							}
							// Attente : la barre se remplit en 3 minutes, orange au-dela d'une minute.
							Rectangle {
								Layout.fillWidth: true
								Layout.topMargin: Utils.getSizeWithScreenRatio(4)
								Layout.preferredHeight: Utils.getSizeWithScreenRatio(4)
								radius: height / 2
								color: DefaultStyle.main2_100
								Rectangle {
									width: parent.width * Math.min(1, callRow.waited / 180)
									height: parent.height
									radius: height / 2
									color: callRow.ringing ? "#F0CF7A" : callRow.late ? "#E9A35B" : "#9CC1D4"
								}
							}
						}
					}
				}
			}

			// Files et leurs agents.
			Text {
				visible: SupervisionCpp.loaded && mainItem.queues.length > 0
				Layout.topMargin: Utils.getSizeWithScreenRatio(26)
				text: "Files"
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				color: DefaultStyle.main2_500_main
			}
			Repeater {
				model: mainItem.queues
				delegate: Rectangle {
					id: queueCard
					required property var modelData
					readonly property int waiting: (modelData.calls || []).filter(function (c) {
						return c.state !== "answered"
					}).length
					Layout.fillWidth: true
					Layout.topMargin: Utils.getSizeWithScreenRatio(10)
					Layout.preferredHeight: cardColumn.implicitHeight + 2 * Utils.getSizeWithScreenRatio(14)
					radius: Utils.getSizeWithScreenRatio(14)
					color: DefaultStyle.grey_0
					border.width: waiting > 0 ? Utils.getSizeWithScreenRatio(1.5) : 0
					border.color: "#F0C9A0"
					ColumnLayout {
						id: cardColumn
						x: Utils.getSizeWithScreenRatio(16)
						y: Utils.getSizeWithScreenRatio(14)
						width: parent.width - 2 * x
						spacing: Utils.getSizeWithScreenRatio(10)
						RowLayout {
							Layout.fillWidth: true
							spacing: Utils.getSizeWithScreenRatio(8)
							Text {
								text: queueCard.modelData.name
								font.pixelSize: Utils.getSizeWithScreenRatio(15)
								font.weight: Font.Bold
								color: DefaultStyle.main2_800
							}
							Text {
								text: queueCard.modelData.number
								font.pixelSize: Utils.getSizeWithScreenRatio(12)
								color: DefaultStyle.main2_400
							}
							Item {
								Layout.fillWidth: true
							}
							Text {
								text: queueCard.waiting > 0 ? queueCard.waiting + " en attente" : "calme"
								font.pixelSize: Utils.getSizeWithScreenRatio(13)
								font.weight: queueCard.waiting > 0 ? Font.DemiBold : Font.Normal
								color: queueCard.waiting > 0 ? "#8A4B0B" : "#2F7D4F"
							}
						}
						Text {
							visible: (queueCard.modelData.agents || []).length === 0
							text: "Aucun agent dans cette file"
							font.pixelSize: Utils.getSizeWithScreenRatio(12)
							color: DefaultStyle.main2_500_main
						}
						GridLayout {
							Layout.fillWidth: true
							columns: Math.max(1, Math.floor(width / Utils.getSizeWithScreenRatio(280)))
							columnSpacing: Utils.getSizeWithScreenRatio(8)
							rowSpacing: Utils.getSizeWithScreenRatio(8)
							Repeater {
								model: queueCard.modelData.agents || []
								delegate: AgentLabel {
									required property var modelData
									agent: modelData
								}
							}
						}
					}
				}
			}
			Item {
				Layout.preferredHeight: Utils.getSizeWithScreenRatio(32)
			}
		}
	}
}
