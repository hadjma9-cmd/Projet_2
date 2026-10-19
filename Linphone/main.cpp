#include <qloggingcategory.h>

#ifdef _WIN32
#include <Windows.h>
#include <shlguid.h>  // CLSID_ShellLink
#include <shobjidl.h> // IShellLinkW, IPropertyStore

FILE *gStream = NULL;
#include "core/notifier/DesktopNotificationManagerCompat.hpp"
#include "core/notifier/NotificationActivator.hpp"
#include <objbase.h>     // StringFromCLSID, CoTaskMemFree
#include <propkey.h>     // PKEY_AppUserModel_ID, PKEY_AppUserModel_ToastActivatorCLSID
#include <propvarutil.h> // InitPropVariantFromString, PropVariantClear
#endif

#include "core/App.hpp"
#include "core/logger/QtLogger.hpp"
#include "core/path/Paths.hpp"

#include <QApplication>
#include <QLocale>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QSurfaceFormat>
#include <QTranslator>

#ifdef QT_QML_DEBUG
#include <QQmlDebuggingEnabler>
#include <QStandardPaths>
#endif

#define WIDEN2(x) L##x
#define WIDEN(x) WIDEN2(x)

static const wchar_t *mAumid = WIDEN(APPLICATION_NAME);

void cleanStream() {
#ifdef _WIN32
	if (gStream) {
		fflush(stdout);
		fflush(stderr);
		fclose(gStream);
	}
#endif
}

// Relance de l'application (App::relaunch) : un processus neuf, qui attend la fin de celui-ci avant de demarrer.
static const char *gWaitPidVariable = "GAMAPHONE_WAIT_PID";

static void relaunchApplication(const QString &program) {
	QProcess process;
	process.setProgram(program);
	QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
	environment.insert(gWaitPidVariable, QString::number(QCoreApplication::applicationPid()));
	process.setProcessEnvironment(environment);
	if (!process.startDetached()) qWarning() << "[Main] Relaunch failed for" << program;
}

// Une seule instance tourne a la fois : relancee pendant que la precedente se ferme encore, l'application se
// croirait en double et s'arreterait. Elle attend donc la fin de celle qui l'a lancee.
static void waitForPreviousInstance() {
	bool ok = false;
	const qulonglong pid = qEnvironmentVariable(gWaitPidVariable).toULongLong(&ok);
	qunsetenv(gWaitPidVariable);
	if (!ok || pid == 0) return;
#ifdef _WIN32
	if (HANDLE previous = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(pid))) {
		WaitForSingleObject(previous, 30000);
		CloseHandle(previous);
	}
#endif
}

int main(int argc, char *argv[]) {
	waitForPreviousInstance();

#if defined _WIN32
	qInfo() << "Thread ID:" << GetCurrentThreadId();
	APTTYPE aptBefore;
	APTTYPEQUALIFIER qualBefore;
	CoGetApartmentType(&aptBefore, &qualBefore);
	qInfo() << "ApartmentType BEFORE CoInitializeEx:" << aptBefore;

	HRESULT hrCom = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	qInfo() << "CoInitializeEx STA result:" << Qt::hex << hrCom;

	//  Register AUMID and COM server (for a packaged app, this is a no-operation)
	auto hr = DesktopNotificationManagerCompat::RegisterAumidAndComServer(mAumid, __uuidof(NotificationActivator));
	if (FAILED(hr)) {
		qWarning() << "RegisterAumidAndComServer failed:" << Qt::hex << hr;
	}
#endif
	// Useful to share camera on Fullscreen (other context) or multiscreens
	lDebug() << "[Main] Setting ShareOpenGLContexts";
	QApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
	lDebug() << "[Main] Disabling VSync";
	// Ignore vertical sync. This way, we avoid blinking on resizes(and other refresh like layouts etc.).
	auto ignoreVSync = QSurfaceFormat::defaultFormat();
	ignoreVSync.setSwapInterval(0);
	QSurfaceFormat::setDefaultFormat(ignoreVSync);
	// Interface QML : bytecode compile a l'avance dans le programme (qmlcachegen), sans aucun cache sur disque.
	// QML_DISABLE_DISK_CACHE (reglage precedent, contre les caches .qmlc corrompus) ecartait aussi ce bytecode :
	// toute l'interface etait recompilee a chaque lancement. « aot-bytecode » ne lit ni n'ecrit de fichier de
	// cache, le probleme de cache corrompu ne peut donc pas revenir.
	lDebug() << "[Main] QML: ahead-of-time bytecode only, no disk cache";
	qputenv("QML_DISK_CACHE", "aot-bytecode");
	lDebug() << "[Main] Setting application to UTF8";
	setlocale(LC_CTYPE, ".UTF8");
	lDebug() << "[Main] Creating application";

	auto app = QSharedPointer<App>::create(argc, argv);

#if defined _WIN32
	hr = DesktopNotificationManagerCompat::RegisterActivator();
	if (FAILED(hr)) {
		qWarning() << "RegisterActivator failed:" << Qt::hex << hr;
	}
#endif

#ifdef ACCESSBILITY_WORKAROUND
	QAccessible::installUpdateHandler(DummyUpdateHandler);
	QAccessible::installRootObjectHandler(DummyRootObjectHandler);
#endif

	if (app->isSecondary()) {
		lDebug() << "[Main] Sending command from secondary application";
		app->sendCommand();
		qInfo() << QStringLiteral("[Main] Running secondary app success. Kill it now.");
		app->clean();
		cleanStream();
		return EXIT_SUCCESS;
	} else {
		lDebug() << "[Main] Initializing core for primary application";
		app->initCore();
		lDebug() << "[Main] Preparing application's connections";
		app->setSelf(app);
	}

	int result = 0;
	do {
		lDebug() << "[Main] Sending command from primary application";
		app->sendCommand();
		lInfo() << "[Main] Running application";
		result = app->exec();
	} while (result == (int)App::StatusCode::gRestartCode);
	QString message = "[Main] Exiting app with the code : " + QString::number(result);
	if (!result) lInfo() << message;
	else lWarning() << message;
	app->clean();
	if (App::relaunchRequested()) relaunchApplication(QCoreApplication::applicationFilePath());
	app = nullptr;
	cleanStream();

	return result;
}
