import QtQuick
import QtQuick.Layouts
import Linphone
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Onglet « Statistiques » du tableau des files : periode (aujourd'hui, 7 jours, 30 jours), chiffres de toutes les files,
// puis le detail par file et par agent. Memes cartes et couleurs que l'onglet « En direct ». Lu a l'ouverture de
// l'onglet et au changement de periode (appels termines seulement), pas en direct.
ColumnLayout {
	id: mainItem

	// Onglet affiche (fenetre visible et onglet choisi) : les chiffres sont relus a chaque ouverture.
	property bool active: false
	property string period: "day"
	readonly property var stats: SupervisionCpp.stats
	readonly property bool haveStats: !!stats && stats.period === period
	readonly property var totals: haveStats ? stats.totals : null

	readonly property color answeredColor: "#4AA36B"
	readonly property color answeredText: "#2F7D4F"
	readonly property color abandonedText: "#B23B3B"

	spacing: 0
	onActiveChanged: if (active) SupervisionCpp.loadStats(period)
	onPeriodChanged: if (active) SupervisionCpp.loadStats(period)
	Component.onCompleted: if (active) SupervisionCpp.loadStats(period)

	// « 0:24 », « 1 h 05 ».
	function duration(seconds) {
		seconds = Math.max(0, Math.round(seconds || 0))
		if (seconds < 3600)
			return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
		return Math.floor(seconds / 3600) + " h " + String(Math.floor(seconds % 3600 / 60)).padStart(2, "0")
	}
	function plural(n, one, many) {
		return n + " " + (n > 1 ? many : one)
	}

	// Periode, et de quand datent les chiffres.
	RowLayout {
		Layout.fillWidth: true
		Layout.topMargin: Utils.getSizeWithScreenRatio(18)
		spacing: Utils.getSizeWithScreenRatio(12)
		Rectangle {
			Layout.preferredHeight: periodRow.implicitHeight + 2 * Utils.getSizeWithScreenRatio(4)
			Layout.preferredWidth: periodRow.implicitWidth + 2 * Utils.getSizeWithScreenRatio(4)
			radius: height / 2
			color: DefaultStyle.grey_0
			Row {
				id: periodRow
				anchors.centerIn: parent
				spacing: Utils.getSizeWithScreenRatio(2)
				Repeater {
					model: [{"key": "day", "label": "Aujourd'hui"}, {"key": "week", "label": "7 derniers jours"},
						{"key": "month", "label": "30 derniers jours"}]
					delegate: Rectangle {
						required property var modelData
						readonly property bool selected: mainItem.period === modelData.key
						width: periodLabel.implicitWidth + 2 * Utils.getSizeWithScreenRatio(14)
						height: periodLabel.implicitHeight + 2 * Utils.getSizeWithScreenRatio(6)
						radius: height / 2
						color: selected ? DefaultStyle.main1_500_main : periodArea.containsMouse ? DefaultStyle.main2_100 : "transparent"
						Text {
							id: periodLabel
							anchors.centerIn: parent
							text: modelData.label
							font.pixelSize: Utils.getSizeWithScreenRatio(13)
							font.weight: parent.selected ? Font.DemiBold : Font.Normal
							color: parent.selected ? DefaultStyle.grey_0 : DefaultStyle.main2_600
						}
						MouseArea {
							id: periodArea
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: mainItem.period = parent.modelData.key
						}
					}
				}
			}
		}
		Item {
			Layout.fillWidth: true
		}
		Text {
			text: SupervisionCpp.statsLoading ? "Mise à jour…"
				: mainItem.haveStats ? (mainItem.period === "day" ? "Depuis minuit" : mainItem.period === "week" ? "Sur 7 jours" : "Sur 30 jours")
					+ " · appels terminés · " + new Date(mainItem.stats.server_time * 1000).toLocaleTimeString(Qt.locale("fr_FR"), "HH:mm")
				: ""
			font.pixelSize: Utils.getSizeWithScreenRatio(12)
			color: DefaultStyle.main2_500_main
		}
	}

	Text {
		visible: !mainItem.haveStats && SupervisionCpp.statsLoading
		Layout.topMargin: Utils.getSizeWithScreenRatio(24)
		text: "Chargement des statistiques…"
		font.pixelSize: Utils.getSizeWithScreenRatio(14)
		color: DefaultStyle.main2_500_main
	}
	Text {
		visible: SupervisionCpp.statsError.length > 0 && !SupervisionCpp.statsLoading
		Layout.topMargin: Utils.getSizeWithScreenRatio(24)
		text: SupervisionCpp.statsError
		font.pixelSize: Utils.getSizeWithScreenRatio(14)
		color: "#8A4B0B"
	}

	// Chiffres de toutes les files.
	GridLayout {
		visible: mainItem.haveStats
		Layout.fillWidth: true
		Layout.topMargin: Utils.getSizeWithScreenRatio(16)
		columns: Math.max(2, Math.min(6, Math.floor(width / Utils.getSizeWithScreenRatio(150))))
		columnSpacing: Utils.getSizeWithScreenRatio(10)
		rowSpacing: Utils.getSizeWithScreenRatio(10)
		Repeater {
			model: {
				var t = mainItem.totals
				if (!t)
					return []
				return [
					{"label": "Appels reçus", "value": t.received, "color": DefaultStyle.main2_800},
					{"label": "Pris", "value": t.answered, "color": mainItem.answeredText},
					{"label": "Abandonnés", "value": t.abandoned, "color": t.abandoned > 0 ? mainItem.abandonedText : DefaultStyle.main2_800},
					{"label": "Taux de prise", "value": t.received > 0 ? Math.round(t.answered * 100 / t.received) + " %" : "–", "color": DefaultStyle.main2_800},
					{"label": "Attente moyenne", "value": t.received > 0 ? mainItem.duration(t.avg_wait) : "–", "color": DefaultStyle.main2_800},
					{"label": "Attente max", "value": t.received > 0 ? mainItem.duration(t.max_wait) : "–", "color": DefaultStyle.main2_800}
				]
			}
			delegate: Rectangle {
				required property var modelData
				Layout.fillWidth: true
				Layout.preferredHeight: kpiColumn.implicitHeight + 2 * Utils.getSizeWithScreenRatio(14)
				radius: Utils.getSizeWithScreenRatio(14)
				color: DefaultStyle.grey_0
				ColumnLayout {
					id: kpiColumn
					x: Utils.getSizeWithScreenRatio(16)
					anchors.verticalCenter: parent.verticalCenter
					width: parent.width - 2 * x
					spacing: Utils.getSizeWithScreenRatio(2)
					Text {
						text: modelData.label
						font.pixelSize: Utils.getSizeWithScreenRatio(12)
						color: DefaultStyle.main2_500_main
						elide: Text.ElideRight
						Layout.fillWidth: true
					}
					Text {
						text: String(modelData.value)
						font.pixelSize: Utils.getSizeWithScreenRatio(22)
						font.weight: Font.DemiBold
						font.features: {"tnum": 1}
						color: modelData.color
					}
				}
			}
		}
	}

	// Par file.
	Text {
		visible: mainItem.haveStats && (mainItem.stats.queues || []).length > 0
		Layout.topMargin: Utils.getSizeWithScreenRatio(26)
		text: "Par file"
		font.pixelSize: Utils.getSizeWithScreenRatio(13)
		color: DefaultStyle.main2_500_main
	}
	Repeater {
		model: mainItem.haveStats ? mainItem.stats.queues || [] : []
		delegate: Rectangle {
			id: queueCard
			required property var modelData
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(10)
			Layout.preferredHeight: queueColumn.implicitHeight + 2 * Utils.getSizeWithScreenRatio(14)
			radius: Utils.getSizeWithScreenRatio(14)
			color: DefaultStyle.grey_0
			ColumnLayout {
				id: queueColumn
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
						textFormat: Text.StyledText
						text: queueCard.modelData.received === 0 ? "Aucun appel"
							: mainItem.plural(queueCard.modelData.received, "reçu", "reçus")
							  + "  ·  <font color=\"" + mainItem.answeredText + "\">" + queueCard.modelData.answered + " pris</font>"
							  + "  ·  <font color=\"" + mainItem.abandonedText + "\">" + mainItem.plural(queueCard.modelData.abandoned, "abandonné", "abandonnés") + "</font>"
							  + "  ·  attente " + mainItem.duration(queueCard.modelData.avg_wait)
						font.pixelSize: Utils.getSizeWithScreenRatio(13)
						color: DefaultStyle.main2_600
					}
				}
				// Part des appels pris (vert) et abandonnes (rouge).
				Rectangle {
					Layout.fillWidth: true
					Layout.preferredHeight: Utils.getSizeWithScreenRatio(6)
					radius: height / 2
					color: queueCard.modelData.received > 0 ? "#F7C1C1" : DefaultStyle.main2_100
					Rectangle {
						width: queueCard.modelData.received > 0 ? parent.width * queueCard.modelData.answered / queueCard.modelData.received : 0
						height: parent.height
						radius: height / 2
						color: mainItem.answeredColor
					}
				}
			}
		}
	}

	// Par agent.
	Text {
		visible: mainItem.haveStats
		Layout.topMargin: Utils.getSizeWithScreenRatio(26)
		text: "Par agent"
		font.pixelSize: Utils.getSizeWithScreenRatio(13)
		color: DefaultStyle.main2_500_main
	}
	Rectangle {
		visible: mainItem.haveStats
		Layout.fillWidth: true
		Layout.topMargin: Utils.getSizeWithScreenRatio(10)
		Layout.preferredHeight: agentColumn.implicitHeight + 2 * Utils.getSizeWithScreenRatio(6)
		radius: Utils.getSizeWithScreenRatio(14)
		color: DefaultStyle.grey_0
		ColumnLayout {
			id: agentColumn
			x: 0
			y: Utils.getSizeWithScreenRatio(6)
			width: parent.width
			spacing: 0
			Text {
				visible: mainItem.haveStats && (mainItem.stats.agents || []).length === 0
				Layout.margins: Utils.getSizeWithScreenRatio(10)
				Layout.leftMargin: Utils.getSizeWithScreenRatio(16)
				text: "Aucun appel pris sur la période"
				font.pixelSize: Utils.getSizeWithScreenRatio(13)
				color: DefaultStyle.main2_500_main
			}
			Repeater {
				model: mainItem.haveStats ? mainItem.stats.agents || [] : []
				delegate: ColumnLayout {
					id: agentRow
					required property var modelData
					required property int index
					Layout.fillWidth: true
					spacing: 0
					Rectangle {
						visible: agentRow.index > 0
						Layout.fillWidth: true
						Layout.leftMargin: Utils.getSizeWithScreenRatio(16)
						Layout.rightMargin: Utils.getSizeWithScreenRatio(16)
						Layout.preferredHeight: 1
						color: DefaultStyle.main2_100
					}
					RowLayout {
						Layout.fillWidth: true
						Layout.leftMargin: Utils.getSizeWithScreenRatio(16)
						Layout.rightMargin: Utils.getSizeWithScreenRatio(16)
						Layout.topMargin: Utils.getSizeWithScreenRatio(8)
						Layout.bottomMargin: Utils.getSizeWithScreenRatio(8)
						spacing: Utils.getSizeWithScreenRatio(10)
						Rectangle {
							Layout.preferredWidth: Utils.getSizeWithScreenRatio(28)
							Layout.preferredHeight: Utils.getSizeWithScreenRatio(28)
							radius: width / 2
							color: DefaultStyle.main1_100
							Text {
								anchors.centerIn: parent
								text: agentRow.modelData.name.split(" ").filter(function (w) { return w.length > 0 })
									.slice(0, 2).map(function (w) { return w[0].toUpperCase() }).join("")
								font.pixelSize: Utils.getSizeWithScreenRatio(11)
								font.weight: Font.DemiBold
								color: DefaultStyle.main1_500_main
							}
						}
						Text {
							Layout.fillWidth: true
							textFormat: Text.StyledText
							text: agentRow.modelData.name + (agentRow.modelData.extension.length > 0 && agentRow.modelData.extension !== agentRow.modelData.name
								? " <font color=\"" + DefaultStyle.main2_400 + "\">(" + agentRow.modelData.extension + ")</font>" : "")
							font.pixelSize: Utils.getSizeWithScreenRatio(13)
							font.weight: Font.DemiBold
							color: DefaultStyle.main2_800
							elide: Text.ElideRight
						}
						Text {
							Layout.preferredWidth: Utils.getSizeWithScreenRatio(110)
							horizontalAlignment: Text.AlignRight
							text: mainItem.plural(agentRow.modelData.answered, "appel pris", "appels pris")
							font.pixelSize: Utils.getSizeWithScreenRatio(13)
							color: DefaultStyle.main2_600
						}
						Text {
							Layout.preferredWidth: Utils.getSizeWithScreenRatio(130)
							horizontalAlignment: Text.AlignRight
							text: agentRow.modelData.avg_talk > 0 ? "durée moy. " + mainItem.duration(agentRow.modelData.avg_talk) : ""
							font.pixelSize: Utils.getSizeWithScreenRatio(13)
							font.features: {"tnum": 1}
							color: DefaultStyle.main2_500_main
						}
					}
				}
			}
		}
	}
}
