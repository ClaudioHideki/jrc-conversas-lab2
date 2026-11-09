// Reviewed outbound details stay in session memory until a server session exists.
// They are drafts, never a claim that the PBX persisted or confirmed a call.
const drafts = new Map();
const key = ({ accountId, userId, sessionId }) =>
  `${Number(accountId)}:${Number(userId)}:${sessionId}`;
export const setOutboundVoiceDraft = value => {
  if (value.sessionId) drafts.set(key(value), { ...value });
};
export const getOutboundVoiceDraft = identity => drafts.get(key(identity));
export const clearOutboundVoiceDrafts = () => drafts.clear();
