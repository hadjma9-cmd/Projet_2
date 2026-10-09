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

#include "CallHistoryProxy.hpp"
#include "CallHistoryGui.hpp"
#include "CallHistoryList.hpp"
#include "core/App.hpp"

DEFINE_ABSTRACT_OBJECT(CallHistoryProxy)

CallHistoryProxy::CallHistoryProxy(QObject *parent) : LimitProxy(parent) {
	// Une seule liste d'historique, partagee par toutes les vues. Chaque vue en creait auparavant une
	// seconde, aussitot jetee, qui relisait pourtant tout l'historique sur le fil du SDK (gel en appel).
	mHistoryList = App::getInstance()->getCallHistoryList();
	if (!mHistoryList) {
		mHistoryList = CallHistoryList::create();
		App::getInstance()->setCallHistoryList(mHistoryList);
	}
	connect(mHistoryList.get(), &CallHistoryList::listAboutToBeReset, this, &CallHistoryProxy::listAboutToBeReset);
	setSourceModels(new SortFilterList(mHistoryList.get(), Qt::DescendingOrder));
	connect(App::getInstance(), &App::currentDateChanged, this, [this] { emit mHistoryList->lUpdate(); });
}

CallHistoryProxy::~CallHistoryProxy() {
}

void CallHistoryProxy::removeAllEntries() {
	mHistoryList->removeAllEntries();
}

void CallHistoryProxy::removeEntriesWithFilter(QString filter) {
	mHistoryList->removeEntriesWithFilter(filter);
}

void CallHistoryProxy::reload() {
	emit mHistoryList->lUpdate();
}

int CallHistoryProxy::getCallFilter() const {
	auto list = dynamic_cast<SortFilterList *>(sourceModel());
	return list ? list->mCallFilter : 0;
}

void CallHistoryProxy::setCallFilter(int filter) {
	auto list = dynamic_cast<SortFilterList *>(sourceModel());
	if (list && list->mCallFilter != filter) {
		list->mCallFilter = filter;
		list->invalidate();
		emit callFilterChanged();
	}
}

//------------------------------------------------------------------------------------------

bool CallHistoryProxy::SortFilterList::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const {
	bool show = (mFilterText.isEmpty() || mFilterText == "*");
	auto callLog = getItemAtSource<CallHistoryList, CallHistoryCore>(sourceRow);

	if (!show) {
		QRegularExpression search(QRegularExpression::escape(mFilterText),
		                          QRegularExpression::CaseInsensitiveOption |
		                              QRegularExpression::UseUnicodePropertiesOption);
		show = callLog && (callLog->mDisplayName.contains(search) || callLog->mRemoteAddress.contains(search));
	}
	// Type d'appel : manque (entrant sans reponse), entrant decroche, sortant.
	if (show && mCallFilter != (int)CallFilter::All) {
		if (!callLog) return false;
		const bool missed = callLog->mStatus == LinphoneEnums::CallStatus::Missed;
		switch (mCallFilter) {
			case (int)CallFilter::Missed:
				show = missed;
				break;
			case (int)CallFilter::Incoming:
				show = !callLog->mIsOutgoing && !missed;
				break;
			case (int)CallFilter::Outgoing:
				show = callLog->mIsOutgoing;
				break;
			default:
				break;
		}
	}
	return show;
}

bool CallHistoryProxy::SortFilterList::lessThan(const QModelIndex &sourceLeft, const QModelIndex &sourceRight) const {
	// Ordre chronologique, affiche en decroissant (le plus recent en haut). Le comparateur renvoyait toujours
	// vrai : ordre non garanti, et une ligne ajoutee a la volee pouvait se placer n'importe ou.
	auto left = getItemAtSource<CallHistoryList, CallHistoryCore>(sourceLeft.row());
	auto right = getItemAtSource<CallHistoryList, CallHistoryCore>(sourceRight.row());
	if (left && right && left->mDate != right->mDate) return left->mDate < right->mDate;
	return sourceLeft.row() < sourceRight.row();
}
