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

#include "FluidityProbe.hpp"

#include "tool/Utils.hpp"

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX 1
#endif
#include <windows.h>
// windows.h avant psapi.h.
#include <psapi.h>
#endif

namespace {
// Memoire privee du processus en Mo, -1 si indisponible. K32GetProcessMemoryInfo est dans kernel32 :
// pas de bibliotheque supplementaire a lier.
qint64 privateMemoryMb() {
#ifdef Q_OS_WIN
	PROCESS_MEMORY_COUNTERS_EX counters;
	if (K32GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&counters),
	                            sizeof(counters)))
		return static_cast<qint64>(counters.PrivateUsage / (1024 * 1024));
#endif
	return -1;
}
} // namespace

FluidityProbe::FluidityProbe(const QString &threadName, bool reportMemory, QObject *parent)
    : QObject(parent), mThreadName(threadName), mReportMemory(reportMemory) {
	setObjectName(QStringLiteral("fluidityProbe"));
	mTimer.setInterval(TickMs);
	connect(&mTimer, &QTimer::timeout, this, [this] { onTick(); });
	mTickClock.start();
	mReportClock.start();
	mTimer.start();
}

void FluidityProbe::onTick() {
	const qint64 lateMs = mTickClock.restart() - TickMs;
	if (lateMs >= SleepThresholdMs) {
		lInfo() << QStringLiteral("[Sonde] Fil %1 : reprise apres %2 s sans activite (mise en veille ?)")
		               .arg(mThreadName)
		               .arg(lateMs / 1000);
	} else if (lateMs >= BlockThresholdMs) {
		++mBlockCount;
		mBlockTotalMs += lateMs;
		mBlockMaxMs = qMax(mBlockMaxMs, lateMs);
		lWarning() << QStringLiteral("[Sonde] Fil %1 bloque pendant %2 ms").arg(mThreadName).arg(lateMs);
	}
	if (mReportClock.elapsed() >= ReportPeriodMs) report();
}

void FluidityProbe::report() {
	QString memory;
	if (mReportMemory) {
		const qint64 mb = privateMemoryMb();
		if (mb >= 0) memory = QStringLiteral(", memoire %1 Mo").arg(mb);
	}
	lInfo() << QStringLiteral("[Sonde] Fil %1, 10 dernieres minutes : %2 blocage(s), %3 ms au total, pire %4 ms%5")
	               .arg(mThreadName)
	               .arg(mBlockCount)
	               .arg(mBlockTotalMs)
	               .arg(mBlockMaxMs)
	               .arg(memory);
	mBlockCount = 0;
	mBlockTotalMs = 0;
	mBlockMaxMs = 0;
	mReportClock.restart();
}
