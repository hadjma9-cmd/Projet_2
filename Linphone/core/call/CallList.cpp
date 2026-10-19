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

#include "CallList.hpp"
#include "CallCore.hpp"
#include "CallGui.hpp"
#include "core/App.hpp"
#include "model/tool/ToolModel.hpp"
#include <QSharedPointer>
#include <linphone++/linphone.hh>

// =============================================================================

DEFINE_ABSTRACT_OBJECT(CallList)

QSharedPointer<CallList> CallList::create() {
	auto model = QSharedPointer<CallList>(new CallList(), &QObject::deleteLater);
	model->moveToThread(App::getInstance()->thread());
	model->setSelf(model);
	return model;
}

QSharedPointer<CallCore> CallList::createCallCore(const std::shared_ptr<linphone::Call> &call) {
	auto callCore = CallCore::create(call);
	connect(callCore.get(), &CallCore::stateChanged, this, &CallList::onStateChanged);
	return callCore;
}

CallList::CallList(QObject *parent) : ListProxy(parent) {
	mustBeInMainThread(getClassName());
	App::getInstance()->mEngine->setObjectOwnership(this, QQmlEngine::CppOwnership);
}

CallList::~CallList() {
	mustBeInMainThread("~" + getClassName());
	mModelConnection = nullptr;
}

void CallList::setSelf(QSharedPointer<CallList> me) {
	mModelConnection = SafeConnection<CallList, CoreModel>::create(me, CoreModel::getInstance());

	mModelConnection->makeConnectToCore(&CallList::lUpdate, [this]() {
		mModelConnection->invokeToModel([this]() {
			// Avoid copy to lambdas
			QList<QSharedPointer<CallCore>> *calls = new QList<QSharedPointer<CallCore>>();
			mustBeInLinphoneThread(getClassName());
			auto linphoneCalls = CoreModel::getInstance()->getCore()->getCalls();
			auto currentCall = CoreModel::getInstance()->getCore()->getCurrentCall();
			QSharedPointer<CallCore> currentCallCore;
			bool haveNonAdminMeeting = false;
			for (auto it : linphoneCalls) {
				auto model = createCallCore(it);
				if (it == currentCall) currentCallCore = model;
				if (auto isConf = it->getConference()) {
					if (isConf->getMe() && !isConf->getMe()->isAdmin()) haveNonAdminMeeting = true;
				}
				calls->push_back(model);
			}
			mModelConnection->invokeToCore([this, calls, currentCallCore, haveNonAdminMeeting]() {
				mustBeInMainThread(getClassName());
				resetData<CallCore>(*calls);
				setHaveCall(calls->size() > 0);
				setHaveNonAdminMeeting(haveNonAdminMeeting);
				setCurrentCallCore(currentCallCore);
				delete calls;
			});
		});
	});
	mModelConnection->makeConnectToCore(&CallList::lMergeAll, [this]() {
		mModelConnection->invokeToModel([this]() {
			auto core = CoreModel::getInstance()->getCore();
			// Seulement les appels decroches (en cours ou en attente) : un appel qui sonne encore, ou qui se termine,
			// n'est pas mis en conference.
			std::list<std::shared_ptr<linphone::Call>> currentCalls;
			for (auto call : core->getCalls()) {
				switch (call->getState()) {
					case linphone::Call::State::Connected:
					case linphone::Call::State::StreamsRunning:
					case linphone::Call::State::Pausing:
					case linphone::Call::State::Paused:
					case linphone::Call::State::PausedByRemote:
					case linphone::Call::State::Resuming:
					case linphone::Call::State::Updating:
					case linphone::Call::State::UpdatedByRemote:
						currentCalls.push_back(call);
						break;
					default:
						break;
				}
			}
			if (currentCalls.size() < 2) {
				lWarning() << log().arg("Merge requested with less than two answered calls");
				return;
			}
			// Appels internes seulement : jamais un appel exterieur ni un appel venu d'une file.
			for (const auto &call : currentCalls) {
				if (!ToolModel::isInternalCall(call)) {
					lWarning() << log().arg("Merge refused: not an internal call");
					return;
				}
			}
			std::shared_ptr<linphone::Conference> conference = nullptr;

			// Search a managable conference from calls
			for (auto call : currentCalls) {
				auto dbConference = call->getConference();
				auto me = dbConference ? dbConference->getMe() : nullptr;
				if (me && me->isAdmin()) {
					conference = dbConference;
					break;
				}
			}

			// Video seulement si ma camera est allumee dans l'appel en cours. La video negociee ne suffit pas : avec
			// FusionPBX elle l'est presque toujours (en reception), et chaque participant recevrait une proposition de
			// video.
			auto currentCall = core->getCurrentCall();
			bool enablingVideo = false;
			if (auto params = currentCall ? currentCall->getParams() : nullptr) {
				const auto direction = params->getVideoDirection();
				enablingVideo = params->cameraEnabled() && (direction == linphone::MediaDirection::SendOnly ||
				                                            direction == linphone::MediaDirection::SendRecv);
			}
			// Sans compte par defaut, pas de conference possible : message d'echec ci-dessous.
			auto account = core->getDefaultAccount();
			if (!conference && account) {
				auto audioVideoConfFactoryUri = account->getParams()->getAudioVideoConferenceFactoryAddress();
				QString subject = audioVideoConfFactoryUri
				                      //: Remote group call
				                      ? tr("remote_group_call")
				                      //: "Local group call"
				                      : tr("local_group_call");
				conference = ToolModel::createConference(subject, nullptr, enablingVideo);
			}
			if (!conference) {
				lWarning() << log().arg("Failed to merge calls");
				mModelConnection->invokeToCore([] {
					Utils::showInformationPopup(tr("info_popup_error_title"),
					                            //: Failed to merge calls !
					                            tr("info_popup_merge_calls_failed_message"), false,
					                            App::getInstance()->getCallsWindow());
				});
				return;
			} else {
				conference->addParticipants(currentCalls);
				// Sans cela, on n'entre dans la conference que si un des appels ajoutes est deja etabli (doc du SDK).
				if (!conference->isIn()) conference->enter();
			}
		});
	});

	mModelConnection->makeConnectToModel(&CoreModel::lastCallEnded, [this]() {
		mModelConnection->invokeToCore([this]() {
			setHaveCall(false);
			setHaveNonAdminMeeting(false);
			setCurrentCall(nullptr);
		});
	});
	mModelConnection->makeConnectToModel(&CoreModel::callCreated, [this](const std::shared_ptr<linphone::Call> &call) {
		auto model = createCallCore(call);
		mModelConnection->invokeToCore([this, model]() {
			// We set the current here and not on firstCallStarted event because we don't want to add unicity check
			// while keeping the same model between list and current call.
			if (mList.size() == 0) {
				setCurrentCallCore(model);
			}
			setHaveCall(mList.size() > 0);
			updateHaveNonAdminMeeting();
			add(model);
		});
	});
	lUpdate();
}

QSharedPointer<CallCore> CallList::getCurrentCallCore() const {
	return mCurrentCall;
}

CallGui *CallList::getCurrentCall() const {
	auto call = getCurrentCallCore();
	if (call) return new CallGui(call);
	else return nullptr;
}

void CallList::setCurrentCall(CallGui *callGui) {
	setCurrentCallCore(callGui ? callGui->mCore : nullptr);
}

void CallList::setCurrentCallCore(QSharedPointer<CallCore> call) {
	if (mCurrentCall != call) {
		mCurrentCall = call;
		emit currentCallChanged();
	}
}

bool CallList::getHaveCall() const {
	return mHaveCall;
}

void CallList::setHaveCall(bool haveCall) {
	if (mHaveCall != haveCall) {
		mHaveCall = haveCall;
		emit haveCallChanged();
	}
}

void CallList::updateHaveNonAdminMeeting() {
	bool haveNonAdminMeeting = false;
	for (auto &call : getSharedList<CallCore>()) {
		if (auto conf = call->getConferenceCore()) {
			qDebug() << "call is conference, me admin :" << conf->getMe()
			         << (conf->getMe() && conf->getMe()->isAdmin() ? "true" : "false");
			if (call->getConferenceCore()->getMe() && !call->getConferenceCore()->getMe()->isAdmin())
				haveNonAdminMeeting = true;
		}
	}
	setHaveNonAdminMeeting(haveNonAdminMeeting);
}

bool CallList::getHaveNonAdminMeeting() const {
	return mHaveNonAdminMeeting;
}

void CallList::setHaveNonAdminMeeting(bool haveNonAdminMeeting) {
	if (mHaveNonAdminMeeting != haveNonAdminMeeting) {
		mHaveNonAdminMeeting = haveNonAdminMeeting;
		emit haveNonAdminMeetingChanged();
	}
}

QSharedPointer<CallCore> CallList::getNextCall() {
	auto currentCall = getCurrentCallCore();
	for (auto &item : getSharedList<CallCore>()) {
		if (item != currentCall) return item;
	}
	return nullptr;
}

QSharedPointer<CallCore> CallList::getFirstIncommingPendingCall() {
	auto callList = getSharedList<CallCore>();
	auto it = std::find_if(callList.begin(), callList.end(), [](const QSharedPointer<CallCore> call) {
		return call->getState() == LinphoneEnums::CallState::IncomingReceived;
	});
	if (it == callList.end()) return nullptr;
	return *it;
}

void CallList::onStateChanged() {
	auto call = dynamic_cast<CallCore *>(sender());
	switch (call->getState()) {
		case LinphoneEnums::CallState::StreamsRunning:
		case LinphoneEnums::CallState::Resuming: {
			auto sharedCall = get(call);
			setCurrentCallCore(sharedCall ? sharedCall.objectCast<CallCore>() : nullptr);
			break;
		}
		case LinphoneEnums::CallState::Released: {
			auto sharedCall = get(call);
			if (sharedCall) {
				auto currentCall = getCurrentCallCore();
				sharedCall->disconnect(this);
				// Update current call
				if (currentCall == sharedCall) {
					auto nextCall = getNextCall();
					if (nextCall) {
						// Unpause the next call. The current call will change on resume.
						// Assumption: All calls that are not the current are paused.
						nextCall->lSetPaused(false);
					}
					setCurrentCallCore(nextCall);
				}
				bool removed = remove(sharedCall);
			}
			break;
		}
		case LinphoneEnums::CallState::OutgoingProgress: {
			auto sharedCall = get(call);
			setCurrentCallCore(sharedCall ? sharedCall.objectCast<CallCore>() : nullptr);
			break;
		}
		default: {
		}
	}
}

QVariant CallList::data(const QModelIndex &index, int role) const {
	int row = index.row();
	if (!index.isValid() || row < 0 || row >= mList.count()) return QVariant();
	if (role == Qt::DisplayRole) return QVariant::fromValue(new CallGui(mList[row].objectCast<CallCore>()));
	return QVariant();
}
