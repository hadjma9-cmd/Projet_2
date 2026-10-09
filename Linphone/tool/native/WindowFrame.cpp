/*
 * Copyright (c) 2010-2024 Belledonne Communications SARL.
 *
 * This file is part of linphone-desktop
 * (see https://www.linphone.org).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include "WindowFrame.hpp"

#include <QCoreApplication>
#include <QMargins>
#include <QPlatformSurfaceEvent>
#include <QScreen>
#include <QTimer>

#ifdef Q_OS_WIN
#include <windows.h>
#include <windowsx.h>
#endif

// =============================================================================

#ifdef Q_OS_WIN
namespace {
// Epaisseur du bord de redimensionnement natif, en pixels physiques.
int frameThickness(UINT dpi) {
	return GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

bool isSizingHit(LRESULT hit) {
	switch (hit) {
		case HTLEFT:
		case HTRIGHT:
		case HTTOP:
		case HTTOPLEFT:
		case HTTOPRIGHT:
		case HTBOTTOM:
		case HTBOTTOMLEFT:
		case HTBOTTOMRIGHT:
			return true;
		default:
			return false;
	}
}

bool itemContains(QQuickItem *item, const QPointF &scenePos) {
	return item && item->isVisible() && item->contains(item->mapFromScene(scenePos));
}

bool acceptsPointer(const QQuickItem *item) {
	return item->isEnabled() &&
	       ((item->acceptedMouseButtons() & Qt::LeftButton) != Qt::NoButton || item->acceptHoverEvents());
}
} // namespace
#endif

WindowFrame::WindowFrame(QObject *parent) : QObject(parent) {
#ifdef Q_OS_WIN
	QCoreApplication::instance()->installNativeEventFilter(this);
#endif
}

WindowFrame::~WindowFrame() {
#ifdef Q_OS_WIN
	if (auto app = QCoreApplication::instance()) app->removeNativeEventFilter(this);
#endif
}

QQuickWindow *WindowFrame::getWindow() const {
	return mWindow;
}

void WindowFrame::setWindow(QQuickWindow *window) {
	if (mWindow == window) return;
	if (mWindow) {
		disconnect(mWindow, nullptr, this, nullptr);
		mWindow->removeEventFilter(this);
	}
	mWindow = window;
#ifdef Q_OS_WIN
	if (mWindow) {
		// Creation de la fenetre native (eventFilter) : la zone cliente doit y etre recalculee.
		mWindow->installEventFilter(this);
		if (!mWindow->handle()) {
			// Lu par Qt a la creation de la fenetre native : la barre de titre et le bord du haut sont retires
			// (zone cliente etendue jusqu'en haut), et Qt en tient compte dans ses calculs de position et de taille.
			// Les bords lateraux et du bas, invisibles depuis Windows 10, restent pour le redimensionnement.
			const qreal dpr = mWindow->screen() ? mWindow->screen()->devicePixelRatio() : 1.0;
			const UINT dpi = UINT(qRound(96.0 * dpr));
			const int top = GetSystemMetricsForDpi(SM_CYCAPTION, dpi) + frameThickness(dpi);
			mWindow->setProperty("_q_windowsCustomMargins", QVariant::fromValue(QMargins(0, -top, 0, 0)));
		}
		// Style et premier plan appliques des que la fenetre native existe (affichage), puis a chaque changement.
		connect(mWindow, &QWindow::visibleChanged, this, [this](bool visible) {
			if (!visible) return;
			applyNativeStyle();
			applyStayOnTop();
			QTimer::singleShot(0, this, &WindowFrame::nudgeClientArea);
		});
		if (mWindow->handle()) {
			applyNativeStyle();
			applyStayOnTop();
			SetWindowPos(reinterpret_cast<HWND>(mWindow->winId()), nullptr, 0, 0, 0, 0,
			             SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
		}
	}
#endif
	emit windowChanged();
}

QQuickItem *WindowFrame::getTitleBar() const {
	return mTitleBar;
}

void WindowFrame::setTitleBar(QQuickItem *item) {
	if (mTitleBar == item) return;
	mTitleBar = item;
	emit titleBarChanged();
}

QQuickItem *WindowFrame::getMaximizeButton() const {
	return mMaximizeButton;
}

void WindowFrame::setMaximizeButton(QQuickItem *item) {
	if (mMaximizeButton == item) return;
	mMaximizeButton = item;
	emit maximizeButtonChanged();
}

bool WindowFrame::isResizable() const {
	return mResizable;
}

void WindowFrame::setResizable(bool resizable) {
	if (mResizable == resizable) return;
	mResizable = resizable;
	applyNativeStyle();
	emit resizableChanged();
}

bool WindowFrame::isStayOnTop() const {
	return mStayOnTop;
}

void WindowFrame::setStayOnTop(bool stayOnTop) {
	if (mStayOnTop == stayOnTop) return;
	mStayOnTop = stayOnTop;
	applyStayOnTop();
	emit stayOnTopChanged();
}

bool WindowFrame::isActive() const {
#ifdef Q_OS_WIN
	return true;
#else
	return false;
#endif
}

bool WindowFrame::isMaximizeHovered() const {
	return mMaximizeHovered;
}

bool WindowFrame::isMaximizePressed() const {
	return mMaximizePressed;
}

void WindowFrame::setMaximizeHovered(bool hovered) {
	if (mMaximizeHovered == hovered) return;
	mMaximizeHovered = hovered;
	emit maximizeHoveredChanged();
}

void WindowFrame::setMaximizePressed(bool pressed) {
	if (mMaximizePressed == pressed) return;
	mMaximizePressed = pressed;
	emit maximizePressedChanged();
}

void WindowFrame::toggleMaximized() {
	if (!mWindow || !mResizable) return;
	if (mWindow->visibility() == QWindow::Maximized) mWindow->showNormal();
	else mWindow->showMaximized();
}

// Fenetre de taille fixe (petite fenetre) : ni agrandissement (double-clic sur la barre, menu systeme), ni bords
// de redimensionnement.
void WindowFrame::applyNativeStyle() {
#ifdef Q_OS_WIN
	if (!mWindow || !mWindow->handle()) return;
	auto hwnd = reinterpret_cast<HWND>(mWindow->winId());
	const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
	const LONG_PTR wanted = mResizable ? (style | WS_MAXIMIZEBOX) : (style & ~LONG_PTR(WS_MAXIMIZEBOX));
	if (wanted != style) {
		SetWindowLongPtrW(hwnd, GWL_STYLE, wanted);
		SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
		             SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
	}
#endif
}

// Directement par Windows : passer par les drapeaux de la fenetre Qt recreerait son style et rendrait la barre de
// titre retiree.
void WindowFrame::applyStayOnTop() {
#ifdef Q_OS_WIN
	if (!mWindow || !mWindow->handle()) return;
	auto hwnd = reinterpret_cast<HWND>(mWindow->winId());
	const bool topMost = (GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
	if (topMost == mStayOnTop) return;
	SetWindowPos(hwnd, mStayOnTop ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
	             SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
#endif
}

// Zone cliente sans barre de titre prise en compte par Windows. Selon Microsoft (« Custom Window Frame Using DWM »),
// la zone calculee dans WM_NCCALCSIZE n'est appliquee qu'une fois la zone cliente redimensionnee, ou si le recalcul est
// demande a la creation de la fenetre ; sinon la fenetre s'affiche avec le cadre standard. D'ou, a l'ouverture, une
// bande claire de 31 px en haut (l'ancienne barre de titre) et des clics decales d'autant, jusqu'a un clic ou un
// agrandissement. Les deux remedes sont appliques : recalcul a la creation (eventFilter), puis, apres l'affichage, zone
// cliente reduite d'un pixel puis remise (vaut aussi pour la petite fenetre, de taille fixe).
bool WindowFrame::eventFilter(QObject *watched, QEvent *event) {
#ifdef Q_OS_WIN
	if (watched == mWindow && event->type() == QEvent::PlatformSurface &&
	    static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated) {
		applyNativeStyle();
		// Zone cliente reduite d'un pixel puis remise, fenetre encore cachee : Qt, qui recalcule ses marges a chaque
		// changement de taille, prend la bonne zone avant le premier affichage. Mesure (journal) : a l'ouverture de la
		// fenetre d'appel, Qt la croyait 31 px plus bas (y 31, 931 de haut) que la zone reelle (y 0, 962), et ne
		// s'alignait qu'au recalage apres affichage.
		setClientTopShift(1);
		setClientTopShift(0);
	}
#endif
	return QObject::eventFilter(watched, event);
}

void WindowFrame::nudgeClientArea() {
#ifdef Q_OS_WIN
	if (!mWindow || !mWindow->handle() || !mWindow->isVisible()) return;
	if (IsIconic(reinterpret_cast<HWND>(mWindow->winId()))) return;
	setClientTopShift(1);
	QTimer::singleShot(50, this, [this]() { setClientTopShift(0); });
#endif
}

void WindowFrame::setClientTopShift(int shift) {
#ifdef Q_OS_WIN
	if (!mWindow || !mWindow->handle()) return;
	mClientTopShift = shift;
	SetWindowPos(reinterpret_cast<HWND>(mWindow->winId()), nullptr, 0, 0, 0, 0,
	             SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE);
#else
	Q_UNUSED(shift)
#endif
}

// Element cliquable sous le curseur dans la barre de titre (bouton) : il garde ses clics, la barre ne deplace la
// fenetre que depuis ses zones vides.
bool WindowFrame::isInteractiveAt(const QPointF &scenePos) const {
#ifdef Q_OS_WIN
	QQuickItem *item = mTitleBar;
	if (!item) return false;
	QPointF pos = item->mapFromScene(scenePos);
	while (item) {
		QQuickItem *child = item->childAt(pos.x(), pos.y());
		if (!child) break;
		pos = item->mapToItem(child, pos);
		if (acceptsPointer(child)) return true;
		item = child;
	}
#else
	Q_UNUSED(scenePos)
#endif
	return false;
}

bool WindowFrame::nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) {
#ifdef Q_OS_WIN
	if (eventType != "windows_generic_MSG" || !mWindow || !mWindow->handle()) return false;
	auto msg = static_cast<MSG *>(message);
	if (!msg || msg->hwnd != reinterpret_cast<HWND>(mWindow->winId())) return false;
	// Messages de la souris et du clavier : Qt les filtre a leur sortie de la file, sans resultat a renvoyer
	// (result nul) ; les ecarter (true) suffit. Ecrire dans result faisait planter l'application au survol du
	// bouton agrandir.
	qintptr unusedResult = 0;
	if (!result) result = &unusedResult;

	switch (msg->message) {
		case WM_NCCALCSIZE: {
			// Calcul par defaut (bords lateraux et du bas conserves), puis zone cliente remontee jusqu'en haut de la
			// fenetre : plus de barre de titre. Agrandie, la fenetre deborde de l'ecran de l'epaisseur du bord : on la
			// rentre en haut comme Windows le fait sur les autres cotes. Les deux formes du message (wParam vrai :
			// changement de taille ; faux : simple question sur la zone cliente) recoivent la meme reponse ; la seconde
			// renvoyait la zone avec barre de titre, 31 px plus bas.
			RECT *clientRect = msg->wParam ? &reinterpret_cast<NCCALCSIZE_PARAMS *>(msg->lParam)->rgrc[0]
			                               : reinterpret_cast<RECT *>(msg->lParam);
			if (!clientRect) return false;
			const LONG originalTop = clientRect->top;
			// Resultat de Windows garde tel quel : le rendre a Qt (false) lui ferait refaire le calcul par-dessus.
			const LRESULT defaultResult = DefWindowProcW(msg->hwnd, msg->message, msg->wParam, msg->lParam);
			clientRect->top = originalTop + mClientTopShift;
			if (IsZoomed(msg->hwnd)) clientRect->top += frameThickness(GetDpiForWindow(msg->hwnd));
			*result = defaultResult;
			return true;
		}
		case WM_NCHITTEST: {
			const LRESULT hit = DefWindowProcW(msg->hwnd, msg->message, msg->wParam, msg->lParam);
			if (hit != HTCLIENT) {
				*result = (!mResizable && isSizingHit(hit)) ? HTBORDER : hit;
				return true;
			}
			POINT point{GET_X_LPARAM(msg->lParam), GET_Y_LPARAM(msg->lParam)};
			ScreenToClient(msg->hwnd, &point);
			RECT clientRect;
			GetClientRect(msg->hwnd, &clientRect);
			const int border = frameThickness(GetDpiForWindow(msg->hwnd));
			// Bord du haut : il n'existe plus nativement, on le recree dans la zone cliente.
			if (mResizable && !IsZoomed(msg->hwnd) && point.y < border) {
				*result = point.x < 2 * border                       ? HTTOPLEFT
				          : point.x >= clientRect.right - 2 * border ? HTTOPRIGHT
				                                                     : HTTOP;
				return true;
			}
			const qreal dpr = mWindow->devicePixelRatio();
			const QPointF scenePos(point.x / dpr, point.y / dpr);
			if (mResizable && itemContains(mMaximizeButton, scenePos)) {
				*result = HTMAXBUTTON;
				return true;
			}
			if (itemContains(mTitleBar, scenePos) && !isInteractiveAt(scenePos)) {
				*result = HTCAPTION;
				return true;
			}
			return false;
		}
		// Bouton agrandir : survol, appui et clic arrivent comme messages de la zone non cliente.
		case WM_NCMOUSEMOVE: {
			const bool overMaximize = msg->wParam == HTMAXBUTTON;
			setMaximizeHovered(overMaximize);
			if (!overMaximize) {
				setMaximizePressed(false);
				return false;
			}
			TRACKMOUSEEVENT tracking{sizeof(TRACKMOUSEEVENT), TME_LEAVE | TME_NONCLIENT, msg->hwnd, 0};
			TrackMouseEvent(&tracking);
			*result = 0;
			return true;
		}
		case WM_NCMOUSELEAVE:
			setMaximizeHovered(false);
			setMaximizePressed(false);
			return false;
		case WM_MOUSEMOVE:
			if (mMaximizeHovered || mMaximizePressed) {
				setMaximizeHovered(false);
				setMaximizePressed(false);
			}
			return false;
		case WM_NCLBUTTONDOWN:
		case WM_NCLBUTTONDBLCLK:
			if (msg->wParam != HTMAXBUTTON) return false;
			setMaximizePressed(true);
			*result = 0;
			return true;
		case WM_NCLBUTTONUP: {
			if (msg->wParam != HTMAXBUTTON) return false;
			const bool wasPressed = mMaximizePressed;
			setMaximizePressed(false);
			if (wasPressed) QMetaObject::invokeMethod(this, &WindowFrame::toggleMaximized, Qt::QueuedConnection);
			*result = 0;
			return true;
		}
		default:
			return false;
	}
#else
	Q_UNUSED(eventType)
	Q_UNUSED(message)
	Q_UNUSED(result)
	return false;
#endif
}
