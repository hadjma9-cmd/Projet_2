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

#ifndef WINDOW_FRAME_H_
#define WINDOW_FRAME_H_

#include <QAbstractNativeEventFilter>
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>

// Cadre de fenetre personnalise (Windows) : la barre de titre de Windows est retiree et remplacee par une barre
// dessinee en QML (titleBar), en gardant ce que fournit le cadre natif : ombre, coins arrondis, redimensionnement par
// les bords, ancrage aux bords de l'ecran, menu systeme, et menu d'ancrage de Windows 11 au survol du bouton
// agrandir (maximizeButton). Ailleurs que sous Windows, rien ne change (active vaut faux) : la barre QML est masquee
// et la fenetre garde son cadre habituel.
//
// A declarer dans la fenetre elle-meme : la marge qui retire la barre de titre doit etre posee avant la creation de
// la fenetre native.
class WindowFrame : public QObject, public QAbstractNativeEventFilter {
	Q_OBJECT
	Q_PROPERTY(QQuickWindow *window READ getWindow WRITE setWindow NOTIFY windowChanged)
	// Zone qui sert a deplacer la fenetre ; ses elements cliquables (boutons) restent cliquables.
	Q_PROPERTY(QQuickItem *titleBar READ getTitleBar WRITE setTitleBar NOTIFY titleBarChanged)
	// Bouton agrandir dessine en QML : declare a Windows pour le menu d'ancrage. Ses clics et son survol passent par
	// Windows, d'ou maximizeHovered et maximizePressed pour son apparence.
	Q_PROPERTY(QQuickItem *maximizeButton READ getMaximizeButton WRITE setMaximizeButton NOTIFY maximizeButtonChanged)
	Q_PROPERTY(bool resizable READ isResizable WRITE setResizable NOTIFY resizableChanged)
	Q_PROPERTY(bool stayOnTop READ isStayOnTop WRITE setStayOnTop NOTIFY stayOnTopChanged)
	Q_PROPERTY(bool active READ isActive CONSTANT)
	Q_PROPERTY(bool maximizeHovered READ isMaximizeHovered NOTIFY maximizeHoveredChanged)
	Q_PROPERTY(bool maximizePressed READ isMaximizePressed NOTIFY maximizePressedChanged)

public:
	explicit WindowFrame(QObject *parent = nullptr);
	~WindowFrame() override;

	QQuickWindow *getWindow() const;
	void setWindow(QQuickWindow *window);
	QQuickItem *getTitleBar() const;
	void setTitleBar(QQuickItem *item);
	QQuickItem *getMaximizeButton() const;
	void setMaximizeButton(QQuickItem *item);
	bool isResizable() const;
	void setResizable(bool resizable);
	bool isStayOnTop() const;
	void setStayOnTop(bool stayOnTop);
	bool isActive() const;
	bool isMaximizeHovered() const;
	bool isMaximizePressed() const;

	Q_INVOKABLE void toggleMaximized();

	bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override;
	bool eventFilter(QObject *watched, QEvent *event) override;

signals:
	void windowChanged();
	void titleBarChanged();
	void maximizeButtonChanged();
	void resizableChanged();
	void stayOnTopChanged();
	void maximizeHoveredChanged();
	void maximizePressedChanged();

private:
	bool isInteractiveAt(const QPointF &scenePos) const;
	void setMaximizeHovered(bool hovered);
	void setMaximizePressed(bool pressed);
	void applyNativeStyle();
	void applyStayOnTop();
	void nudgeClientArea();
	void setClientTopShift(int shift);

	QPointer<QQuickWindow> mWindow;
	QPointer<QQuickItem> mTitleBar;
	QPointer<QQuickItem> mMaximizeButton;
	bool mResizable = true;
	bool mStayOnTop = false;
	bool mMaximizeHovered = false;
	bool mMaximizePressed = false;
	int mClientTopShift = 0;
};

#endif // WINDOW_FRAME_H_
