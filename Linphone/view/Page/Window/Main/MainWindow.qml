import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls.Basic
import Linphone
import UtilsCpp
import SettingsCpp
import 'qrc:/qt/qml/Linphone/view/Control/Tool/Helper/utils.js' as Utils

AbstractWindow {
	id: mainWindow
    // height: Utils.getSizeWithScreenRatio(982)
    title: applicationName
	// TODO : handle this bool when security mode is implemented
	property bool firstConnection: true
    property int initialWidth
    property int initialHeight
    Component.onCompleted: {
        initialWidth = width
        initialHeight = height
    }

	color: DefaultStyle.grey_0
    minimumWidth: Utils.getSizeWithScreenRatio(1020)
    minimumHeight: Utils.getSizeWithScreenRatio(700)

	signal callCreated()
	property var accountProxy

	// TODO : use this to make the border transparent
	flags: Qt.Window

	// Barre du haut sans barre de titre Windows (deplacement, reduire, agrandir, fermer). Petite fenetre : taille
	// fixe, epingle « toujours au premier plan » ; bleu nuit pendant un appel.
	header: WindowTitleBar {
		window: mainWindow
		maximizable: !mainWindow.compact
		pinnable: mainWindow.compact
		pinned: AppCpp.compactPinned
		onPinClicked: AppCpp.compactPinned = !AppCpp.compactPinned
		dark: mainWindow.compact && !!compactLoader.item && compactLoader.item.callVisible
	}

	// ------------------------------------------------------------------------------------------------------------
	//  Petite fenetre (format telephone, comme 3CX : 414 x 632 a l'interieur)
	// ------------------------------------------------------------------------------------------------------------
	readonly property int compactWidth: 414
	readonly property int compactHeight: 632
	// Seulement une fois connecte : les pages de connexion restent dans la grande fenetre.
	readonly property bool compact: AppCpp.compactMode && compactLoader.active
	property rect normalGeometry: Qt.rect(0, 0, 0, 0)
	property bool normalWasMaximized: false
	Settings {
		id: compactPosition
		category: "compact"
		property int x: -1000000
		property int y: -1000000
	}
	onCompactChanged: applyWindowMode()
	function applyWindowMode() {
		if (mainWindow.compact) {
			mainWindow.normalWasMaximized = mainWindow.visibility === Window.Maximized
			if (mainWindow.normalWasMaximized) mainWindow.showNormal()
			mainWindow.normalGeometry = Qt.rect(mainWindow.x, mainWindow.y, mainWindow.width, mainWindow.height)
			mainWindow.minimumWidth = 0
			mainWindow.minimumHeight = 0
			mainWindow.maximumWidth = mainWindow.compactWidth
			mainWindow.maximumHeight = mainWindow.compactHeight
			mainWindow.width = mainWindow.compactWidth
			mainWindow.height = mainWindow.compactHeight
			mainWindow.minimumWidth = mainWindow.compactWidth
			mainWindow.minimumHeight = mainWindow.compactHeight
			// Premiere fois : en bas a droite de l'ecran, pres de l'horloge ; ensuite la ou on l'a laissee.
			if (compactPosition.x > -1000000) {
				mainWindow.x = compactPosition.x
				mainWindow.y = compactPosition.y
			} else {
				mainWindow.x = Screen.virtualX + Screen.desktopAvailableWidth - mainWindow.compactWidth - 16
				mainWindow.y = Screen.virtualY + Screen.desktopAvailableHeight - mainWindow.compactHeight - 48
			}
		} else {
			if (mainWindow.width === mainWindow.compactWidth && mainWindow.height === mainWindow.compactHeight) {
				compactPosition.x = mainWindow.x
				compactPosition.y = mainWindow.y
			}
			mainWindow.maximumWidth = 16777215
			mainWindow.maximumHeight = 16777215
			mainWindow.minimumWidth = Utils.getSizeWithScreenRatio(1020)
			mainWindow.minimumHeight = Utils.getSizeWithScreenRatio(700)
			if (mainWindow.normalGeometry.width > 0) {
				mainWindow.x = mainWindow.normalGeometry.x
				mainWindow.y = mainWindow.normalGeometry.y
				mainWindow.width = mainWindow.normalGeometry.width
				mainWindow.height = mainWindow.normalGeometry.height
			}
			if (mainWindow.normalWasMaximized) mainWindow.showMaximized()
		}
	}
	// Position de la petite fenetre gardee pour la prochaine fois.
	onXChanged: if (mainWindow.compact) compactPosition.x = mainWindow.x
	onYChanged: if (mainWindow.compact) compactPosition.y = mainWindow.y
	// menuBar: Rectangle {
	// 	width: parent.width
    // 	height: Utils.getSizeWithScreenRatio(40)
	// 	color: DefaultStyle.grey_100
	// }

	function openMainPage(connectionSucceed){
		if (!mainStackViewLoader.item || !mainStackViewLoader.item.currentItem || mainStackViewLoader.item.currentItem.objectName !== "mainPage") mainStackViewLoader.item.replace(mainPage, StackView.Immediate)
        //: "Connexion réussie"
        if (connectionSucceed) mainWindow.showInformationPopup(qsTr("information_popup_connexion_succeed_title"),
                                                               //: "Vous êtes connecté en mode %1"
                                                               qsTr("information_popup_connexion_succeed_message").arg(
                                                               //: interopérable
                                                               qsTr("interoperable")))
	}
	function goToCallHistory() {
		openMainPage()
		mainStackViewLoader.item.currentItem.goToCallHistory()
	}
	function goToNewCall() {
		openMainPage()
		mainStackViewLoader.item.currentItem.goToNewCall()
	}
	function displayContactPage(contactAddress) {
		openMainPage()
		mainStackViewLoader.item?.currentItem.displayContactPage(contactAddress)
	}
	function displayCreateContactPage(name, contactAddress) {
		openMainPage()
		mainStackViewLoader.item?.currentItem.createContact(name, contactAddress)
	}
	function displayChatPage(contactAddress) {
		openMainPage()
		mainStackViewLoader.item?.currentItem.displayChatPage(contactAddress)
	}
	function openChat(chat) {
		if (mainWindow.compact) {
			compactLoader.item.openChat(chat)
			return
		}
		openMainPage()
		mainStackViewLoader.item?.currentItem.openChat(chat)
	}
	function transferCallSucceed() {
		openMainPage()
        //: "Appel transféré"
        mainWindow.showInformationPopup(qsTr("call_transfer_successful_toast_title"),
                                        //: "Votre correspondant a été transféré au contact sélectionné"
                                        qsTr("call_transfer_successful_toast_message"))
	}
	function initStackViewItem() {
        if(accountProxy && accountProxy.isInitialized) {
            if (accountProxy.haveAccount) openMainPage()
            else mainStackViewLoader.item.replace(sipLoginPage, StackView.Immediate)
        }
    }
	
	function goToLogin() {
		mainStackViewLoader.item.replace(sipLoginPage)
	}

	function openSettings() {
		openMainPage()
		mainStackViewLoader.item.currentItem.openSettings()
	}
	function openHelp() {
		openMainPage()
		mainStackViewLoader.item.currentItem.openHelp()
	}

	function scheduleMeeting(subject, addresses) {
		openMainPage()
		mainStackViewLoader.item.currentItem.scheduleMeeting(subject, addresses)
	}

	property bool authenticationPopupOpened: false
	Component {
		id: authenticationPopupComp
		AuthenticationDialog{
			onOpened: mainWindow.authenticationPopupOpened = true
			onClosed: {
				mainWindow.authenticationPopupOpened = false
				destroy()
			}
		}
	}

	function reauthenticateAccount(identity, domain, callback){
		if (authenticationPopupOpened) return
		if (mainStackViewLoader.item?.currentItem.objectName === "loginPage" 
		|| mainStackViewLoader.item?.currentItem.objectName === "sipLoginPage")
			return
		console.log("Showing authentication dialog")
		var popup = authenticationPopupComp.createObject(mainWindow, {"identity": identity, "domain": domain, "callback":callback})	// Callback ownership is not passed
		popup.open()
		popup.announce()
	}

	Connections {
		target: SettingsCpp
		function onAssistantGoDirectlyToThirdPartySipAccountLoginChanged() {
            initStackViewItem()
		}
		function onIsSavedChanged(saved) {
            if (saved) UtilsCpp.showInformationPopup(qsTr("information_popup_success_title"),
                                                                   //: "Les changements ont été sauvegardés"
                                                                   qsTr("information_popup_changes_saved"), true, mainWindow)
        }
	}

	Connections {
		target: LoginPageCpp
		function onRegistrationStateChanged() {
			if (LoginPageCpp.registrationState === LinphoneEnums.RegistrationState.Ok) {
				openMainPage(true)
				// proposeH264CodecsDownload() est déclarée sur le StackView de mainStackViewComp :
				// elle n'est pas dans la portée de ce bloc Connections, il faut passer par le Loader.
				mainStackViewLoader.item?.proposeH264CodecsDownload()
			}
		}
	}

	Loader {
		id: accountProxyLoader
		active: AppCpp.coreStarted
		sourceComponent: AccountProxy {
            onInitializedChanged: if (isInitialized) {
				mainWindow.accountProxy = this
				mainWindow.initStackViewItem()
            }
		}
	}

	Loader {
		id: mainStackViewLoader
		active: AppCpp.coreStarted
		anchors.fill: parent
		// Masquee (gardee en memoire) pendant la petite fenetre : retour instantane a la grande.
		visible: !compactLoader.active
		sourceComponent: mainStackViewComp
	}

	// Petite fenetre, par-dessus la grande une fois connecte.
	Loader {
		id: compactLoader
		anchors.fill: parent
		active: AppCpp.compactMode && !!mainStackViewLoader.item && !!mainStackViewLoader.item.currentItem
			&& mainStackViewLoader.item.currentItem.objectName === "mainPage"
		sourceComponent: CompactLayout {
			onOpenSettingsRequested: {
				AppCpp.compactMode = false
				mainWindow.openSettings()
			}
			onOpenHelpRequested: {
				AppCpp.compactMode = false
				mainWindow.openHelp()
			}
		}
	}

	Loader {
		anchors.fill: parent
		active: !AppCpp.coreStarted
		sourceComponent: splashScreen
	}

	Loader {
		anchors.fill: parent
		active: AppCpp.coreGlobalState === 4
		sourceComponent: ssoPage
	}

	Component {
		id: mainStackViewComp
		StackView {
			id: mainWindowStackView
			// H264 Cisco codec download
			PayloadTypeProxy {
				id: downloadableVideoPayloadTypeProxy
				filterType: PayloadTypeProxy.Video | PayloadTypeProxy.Downloadable
			}
			Repeater {
				id: codecDownloader
				model: null
				Item {
					Component.onCompleted: {
						if (modelData.core.mimeType == "H264")
							Utils.openCodecOnlineInstallerDialog(mainWindow, modelData.core)
					}
				}
			}
			function proposeH264CodecsDownload() {
				codecDownloader.model = downloadableVideoPayloadTypeProxy
			}
		}
	}

	Component {
		id: splashScreen
		Rectangle {
			color: DefaultStyle.grey_0
			Image {
				anchors.centerIn: parent
				source: AppIcons.splashscreenLogo
                sourceSize.width: Utils.getSizeWithScreenRatio(395)
                sourceSize.height: Utils.getSizeWithScreenRatio(395)
                width: Utils.getSizeWithScreenRatio(395)
                height: Utils.getSizeWithScreenRatio(395)
			}
		}
	}
	Component {
		id: ssoPage
		Rectangle {
			color: DefaultStyle.grey_0
			Image {
				id: logoImage
				anchors.centerIn: parent
				source: AppIcons.splashscreenLogo
                sourceSize.width: Utils.getSizeWithScreenRatio(395)
                sourceSize.height: Utils.getSizeWithScreenRatio(395)
                width: Utils.getSizeWithScreenRatio(395)
                height: Utils.getSizeWithScreenRatio(395)
			}
			ColumnLayout {
				anchors.top: logoImage.bottom
				anchors.topMargin: Utils.getSizeWithScreenRatio(24)
				anchors.horizontalCenter: parent.horizontalCenter
				Text {
					Layout.alignment: Qt.AlignHCenter
					//: "Trying to connect to single sign on on web page ..."
					text: qsTr("oidc_connection_waiting_message")
					font: Typography.h2
					horizontalAlignment: Text.AlignHCenter
				}
				Text {
					Layout.alignment: Qt.AlignHCenter
					text: UtilsCpp.formatDuration(AppCpp.remainingTimeBeforeOidcTimeout)
					font: Typography.h3m
					horizontalAlignment: Text.AlignHCenter
				}
				Button {
					Layout.alignment: Qt.AlignHCenter
					//: Cancel
					text: qsTr("cancel")
					onClicked: AppCpp.lForceOidcTimeout()
				}
			}
		}
	}
	Component {
		id: sipLoginPage
		SIPLoginPage {
			objectName: "sipLoginPage"
			onGoBack: openMainPage()
			onGoToRegister: mainStackViewLoader.item.replace(registerPage)
            showBackButton: false
            StackView.onActivated: if (mainWindow.accountProxy?.haveAccount) showBackButton = true
		}
	}
	Component {
		id: registerPage
		RegisterPage {
			onReturnToLogin: goToLogin()
            //: "Veuillez valider le captcha sur la page web"
            onBrowserValidationRequested: mainWindow.showLoadingPopup(qsTr("captcha_validation_loading_message"), true)
			Connections {
				target: RegisterPageCpp
				function onNewAccountCreationSucceed(withEmail, address, sipIdentityAddress) {
					mainStackViewLoader.item.push(checkingPage, {"registerWithEmail": withEmail, "address": address, "sipIdentityAddress": sipIdentityAddress})
				}
				function onRegisterNewAccountFailed(errorMessage) {
                    //: "Erreur lors de la création"
                    mainWindow.showInformationPopup(qsTr("assistant_register_error_title"), errorMessage, false)
					mainWindow.closeLoadingPopup()
				}
				function onTokenConversionSucceed(){ mainWindow.closeLoadingPopup()}
			}
		}
	}
	Component {
		id: checkingPage
		RegisterCheckingPage {
			id: registerCheckingPage
			onReturnToRegister: mainStackViewLoader.item.pop()
			onSendCode: (code) => {
				RegisterPageCpp.linkNewAccountUsingCode(code, registerWithEmail, sipIdentityAddress)
			}
			Connections {
				target: RegisterPageCpp
				function onLinkingNewAccountWithCodeSucceed() {
					goToLogin()
					//: "Compte créé"
					mainWindow.showInformationPopup(qsTr("assistant_register_success_title"),
													//: "Le compte a été créé. Vous pouvez maintenant vous connecter"
													qsTr("assistant_register_success_message"), true)
				}
				function onLinkingNewAccountWithCodeFailed(errorMessage) {
					registerCheckingPage.errorMessage = ""
					//: "Erreur dans le code de validation"
					if (errorMessage.length === 0) errorMessage = qsTr("assistant_register_error_code")
					registerCheckingPage.errorMessage = errorMessage
				}
			}
		}
	}
	Component {
		id: securityModePage
		SecurityModePage {
			id: securePage
			onModeSelected: (index) => {
				// TODO : connect to cpp part when ready
				var selectedMode = index == 0 ? "chiffrement" : "interoperable"
				console.debug("[SelectMode]User: User selected mode " + selectedMode)
				openMainPage()
			}
		}
	}
	Component {
		id: mainPage
		MainLayout {
			id: mainLayout
			objectName: "mainPage"
			onAddAccountRequest: goToLogin()
			onAccountRemoved: {
				initStackViewItem()
			}
			Connections {
				target: mainWindow
				function onCallCreated(){ mainLayout.callCreated() }
			}
			// StackView.onActivated: connectionSecured(0) // TODO : connect to cpp part when ready
		}
	}

}
