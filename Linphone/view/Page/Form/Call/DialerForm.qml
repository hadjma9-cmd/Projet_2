import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Control

import Linphone
import UtilsCpp
import 'qrc:/qt/qml/Linphone/view/Style/buttonStyle.js' as ButtonStyle
import "qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js" as Utils

// Clavier de « Nouvel appel » : on compose un numero, ou on tape un nom au clavier de l'ordinateur. Les
// personnes correspondantes, collegues d'abord puis contacts, sont proposees sous la saisie : un clic, ou
// Entree sur la suggestion surlignee, les appelle. Entree apres un numero appelle le numero tape, meme
// s'il n'est pas enregistre.
FocusScope {
	id: mainItem

	// Suggestions affichees au plus ; leur place est reservee, le pave ne bouge pas quand elles apparaissent.
	property int maxSuggestions: 3
	// Taille des photos des suggestions (45 dans la petite fenetre, taille commune a ses menus).
	property real suggestionAvatarSize: Utils.getSizeWithScreenRatio(34)
	readonly property real suggestionHeight: Utils.getSizeWithScreenRatio(50)
	readonly property string typedText: numberField.text.trim()
	// Un nom des qu'un caractere autre qu'un chiffre ou un separateur est tape ; sinon un numero, sans ses
	// separateurs (espaces, points, tirets, parentheses).
	readonly property bool isName: /[^0-9+*#\s.()\/-]/.test(typedText)
	readonly property string number: isName ? "" : typedText.replace(/[\s.()\/-]/g, "")
	// Suggestion surlignee : la premiere pour un nom ; aucune pour un numero (Entree appelle le numero
	// tape), sauf choix aux fleches.
	property int highlightedIndex: -1
	signal callRequested(string number)

	function focusNumber() {
		numberField.forceActiveFocus()
	}
	function callContact(contact) {
		// Suggestion choisie : appel direct, comme un bouton telephone.
		UtilsCpp.getMainWindow().startCallWithContact(contact, false, mainItem, false)
	}
	function launchCall() {
		var suggestion = mainItem.highlightedIndex >= 0 ? suggestions.itemAt(mainItem.highlightedIndex) : null
		if (suggestion && suggestion.friendGui)
			mainItem.callContact(suggestion.friendGui)
		else if (mainItem.number.length > 0)
			mainItem.callRequested(mainItem.number)
	}
	// Touche du pave : saisie au curseur, puis le focus revient a la saisie pour que le clavier
	// de l'ordinateur continue d'y ecrire.
	function insertText(text) {
		if (numberField.selectedText.length > 0)
			numberField.remove(numberField.selectionStart, numberField.selectionEnd)
		numberField.insert(numberField.cursorPosition, text)
		numberField.forceActiveFocus()
	}
	function eraseText() {
		if (numberField.selectedText.length > 0)
			numberField.remove(numberField.selectionStart, numberField.selectionEnd)
		else if (numberField.cursorPosition > 0)
			numberField.remove(numberField.cursorPosition - 1, numberField.cursorPosition)
		numberField.forceActiveFocus()
	}
	// Formulaire garde d'une ouverture a l'autre (CallPage) : saisie effacee, comme sur une page neuve.
	function clear() {
		numberField.clear()
		searchDelay.stop()
		mainItem.searchedText = ""
		mainItem.highlightedIndex = -1
	}

	// Recherche lancee une fois la saisie posee.
	property string searchedText: ""
	onTypedTextChanged: {
		searchDelay.restart()
		mainItem.highlightedIndex = mainItem.isName ? 0 : -1
	}
	Timer {
		id: searchDelay
		interval: 300
		onTriggered: mainItem.searchedText = mainItem.isName ? mainItem.typedText : mainItem.number
	}
	property MagicSearchProxy matchProxy: MagicSearchProxy {
		searchText: mainItem.searchedText
		showMe: false
		sourceFlags: LinphoneEnums.MagicSearchSource.All
		aggregationFlag: LinphoneEnums.MagicSearchAggregation.Friend
		filterType: MagicSearchProxy.FilteringTypes.App
		            | MagicSearchProxy.FilteringTypes.Ldap
		            | MagicSearchProxy.FilteringTypes.CardDAV
		// Collegues d'abord (disponibles en tete), puis contacts.
		sortByPresence: true
		initialDisplayItems: mainItem.maxSuggestions
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		// Numero ou nom tape
		Item {
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(26)
			Layout.preferredHeight: Utils.getSizeWithScreenRatio(56)
			TextInput {
				id: numberField
				anchors.fill: parent
				focus: true
				clip: true
				horizontalAlignment: TextInput.AlignHCenter
				verticalAlignment: TextInput.AlignVCenter
				color: DefaultStyle.main2_700
				font.family: DefaultStyle.defaultFont
				font.pixelSize: Utils.getSizeWithScreenRatio(36)
				font.weight: Font.Bold
				font.letterSpacing: Utils.getSizeWithScreenRatio(2)
				selectByMouse: true
				validator: RegularExpressionValidator {
					regularExpression: /[0-9A-Za-zÀ-ÖØ-öø-ÿ+*#\s.()\/'-]{0,40}/
				}
				//: "Numéro à appeler"
				Accessible.name: qsTr("dialer_number_accessible_name")
				Keys.onPressed: event => {
					if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
						mainItem.launchCall()
						event.accepted = true
					} else if (event.key === Qt.Key_Down) {
						mainItem.highlightedIndex = Math.min(suggestions.count - 1, mainItem.highlightedIndex + 1)
						event.accepted = true
					} else if (event.key === Qt.Key_Up) {
						mainItem.highlightedIndex = Math.max(-1, mainItem.highlightedIndex - 1)
						event.accepted = true
					} else if ((event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
							   || event.key === Qt.Key_Asterisk || event.key === Qt.Key_Plus) {
						// Meme effet qu'un appui sur la touche du pave (animation et tonalite) ;
						// le caractere arrive par buttonPressed.
						numPad.handleKeyPadEvent(event)
					}
				}
			}
			Text {
				anchors.centerIn: parent
				visible: numberField.text.length === 0
				text: "Saisissez un numéro ou un nom"
				color: DefaultStyle.main2_400
				font.pixelSize: Utils.getSizeWithScreenRatio(20)
			}
		}

		// Personnes correspondantes
		Item {
			Layout.fillWidth: true
			Layout.topMargin: Utils.getSizeWithScreenRatio(4)
			Layout.preferredHeight: mainItem.maxSuggestions * mainItem.suggestionHeight
			Column {
				anchors.fill: parent
				Repeater {
					id: suggestions
					model: mainItem.typedText.length > 0 ? mainItem.matchProxy : null
					// La liste change sous la surbrillance : elle reste sur une suggestion existante, et un nom
					// tape surligne la premiere des que les resultats arrivent.
					onCountChanged: {
						if (mainItem.highlightedIndex >= count)
							mainItem.highlightedIndex = count - 1
						if (mainItem.isName && mainItem.highlightedIndex < 0 && count > 0)
							mainItem.highlightedIndex = 0
					}
					delegate: Rectangle {
						id: suggestion
						property var friendGui: $modelData
						readonly property string username: friendGui ? UtilsCpp.getUsername(friendGui.core.defaultAddress) : ""
						readonly property bool isExtension: /^[0-9]{1,5}$/.test(username)
						readonly property bool highlighted: index === mainItem.highlightedIndex || suggestionHover.hovered
						width: parent ? parent.width : 0
						height: mainItem.suggestionHeight
						radius: Utils.getSizeWithScreenRatio(10)
						color: highlighted ? DefaultStyle.main2_100 : "transparent"
						RowLayout {
							anchors.fill: parent
							anchors.leftMargin: Utils.getSizeWithScreenRatio(10)
							anchors.rightMargin: Utils.getSizeWithScreenRatio(10)
							spacing: Utils.getSizeWithScreenRatio(12)
							Avatar {
								Layout.preferredWidth: mainItem.suggestionAvatarSize
								Layout.preferredHeight: mainItem.suggestionAvatarSize
								shadowEnabled: false
								contact: suggestion.friendGui
							}
							ColumnLayout {
								Layout.fillWidth: true
								spacing: 0
								Text {
									Layout.fillWidth: true
									text: suggestion.friendGui ? suggestion.friendGui.core.fullName : ""
									color: DefaultStyle.main2_700
									font.pixelSize: Typography.p1.pixelSize
									font.weight: Typography.p1.weight
									elide: Text.ElideRight
									maximumLineCount: 1
								}
								Text {
									Layout.fillWidth: true
									property string status: suggestion.friendGui ? suggestion.friendGui.core.presenceStatus : ""
									//: "Poste %1"
									text: suggestion.isExtension
										  ? qsTr("dialer_contact_extension").arg(suggestion.username) + (status.length > 0 ? " · " + status : "")
										  : suggestion.username
									color: DefaultStyle.main2_600
									font.pixelSize: Utils.getSizeWithScreenRatio(12)
									elide: Text.ElideRight
									maximumLineCount: 1
								}
							}
							// Appel : sur la suggestion surlignee ou survolee.
							Rectangle {
								visible: suggestion.highlighted
								Layout.preferredWidth: Utils.getSizeWithScreenRatio(34)
								Layout.preferredHeight: Utils.getSizeWithScreenRatio(34)
								radius: width / 2
								color: DefaultStyle.success_500_main
								EffectImage {
									anchors.centerIn: parent
									width: Utils.getSizeWithScreenRatio(18)
									height: Utils.getSizeWithScreenRatio(18)
									imageSource: AppIcons.phone
									colorizationColor: DefaultStyle.grey_0
									fillMode: Image.PreserveAspectFit
								}
							}
						}
						HoverHandler {
							id: suggestionHover
							cursorShape: Qt.PointingHandCursor
						}
						TapHandler {
							onTapped: mainItem.callContact(suggestion.friendGui)
						}
						Accessible.role: Accessible.Button
						Accessible.name: suggestion.friendGui ? suggestion.friendGui.core.fullName : ""
					}
				}
			}
		}

		NumericPad {
			id: numPad
			Layout.alignment: Qt.AlignHCenter
			Layout.topMargin: Utils.getSizeWithScreenRatio(8)
			// Touches teintees : la page est blanche, les touches par defaut le sont aussi.
			keyStyle: ButtonStyle.numericPadLight
			keySize: Utils.getSizeWithScreenRatio(64)
			keyColumnSpacing: Utils.getSizeWithScreenRatio(30)
			keyRowSpacing: Utils.getSizeWithScreenRatio(14)
			onButtonPressed: text => mainItem.insertText(text)
			onWipe: mainItem.eraseText()
			onLaunchCall: mainItem.launchCall()
		}

		Item {
			Layout.fillHeight: true
		}
	}
}
