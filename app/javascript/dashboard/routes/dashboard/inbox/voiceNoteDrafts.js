// Session memory only: notes never enter localStorage, logs or another tenant.
import { shallowReactive } from 'vue';
const drafts = shallowReactive(new Map());
const key = (accountId, userId, callId) => {
  const scope = [accountId, userId].map(Number);
  if (!scope.every(value => Number.isSafeInteger(value) && value > 0))
    return null;
  if (Number.isSafeInteger(Number(callId)) && Number(callId) > 0)
    return [...scope, Number(callId)].join(':');
  return typeof callId === 'string' &&
    callId.startsWith('sip:') &&
    callId.length > 4 &&
    callId.length < 512
    ? [...scope, callId].join(':')
    : null;
};

export const readVoiceNoteDraft = (accountId, userId, callId) =>
  drafts.get(key(accountId, userId, callId));

export const writeVoiceNoteDraft = (accountId, userId, callId, draft) => {
  const identity = key(accountId, userId, callId);
  if (identity) drafts.set(identity, { ...draft });
};

export const clearVoiceNoteDrafts = () => drafts.clear();
export const deleteVoiceNoteDraft = (accountId, userId, callId) =>
  drafts.delete(key(accountId, userId, callId));
