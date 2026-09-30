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

#ifndef FLUIDITY_PROBE_H_
#define FLUIDITY_PROBE_H_

#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QTimer>

// Sonde de fluidite : detecte les blocages du fil qui la cree (interface ou moteur SIP).
// Un minuteur de 100 ms mesure son propre retard : un retard de plus de 200 ms signifie que le fil
// n'a pas pu traiter ses evenements pendant ce temps (interface figee, SIP en attente). Chaque
// blocage est ecrit dans le journal, avec un bilan toutes les 10 minutes (et la memoire du
// processus pour la sonde de l'interface), pour mesurer l'effet de chaque correction.
class FluidityProbe : public QObject {
public:
	FluidityProbe(const QString &threadName, bool reportMemory, QObject *parent);

	static constexpr int TickMs = 100;
	static constexpr qint64 BlockThresholdMs = 200;
	static constexpr qint64 SleepThresholdMs = 30 * 1000; // Au-dela : mise en veille du PC, pas un blocage.
	static constexpr qint64 ReportPeriodMs = 10 * 60 * 1000;

private:
	void onTick();
	void report();

	QString mThreadName;
	bool mReportMemory = false;
	QTimer mTimer;
	QElapsedTimer mTickClock;
	QElapsedTimer mReportClock;
	int mBlockCount = 0;
	qint64 mBlockTotalMs = 0;
	qint64 mBlockMaxMs = 0;
};

#endif
