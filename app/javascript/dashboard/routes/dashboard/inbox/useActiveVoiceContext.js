import { onBeforeUnmount, readonly, shallowRef, watch } from 'vue';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';

const attendance = shallowRef(null);
export const activeVoiceAttendance = readonly(attendance);

// The browser never creates a CallSession or guesses a customer from a SIP URI.
// A signed provider event must have created an authorized server-side session.
export async function resolveVoiceAttendance(identity, api = ContactCenterAPI) {
  const { accountId, provider, sessionId } = identity;
  const matches = item =>
    Number.isSafeInteger(Number(item?.id)) &&
    Number(item.id) > 0 &&
    item.external_session_id === sessionId &&
    item.provider === provider;
  const scoped = body => String(body?.account_id) === String(accountId);
  const response = await api.calls(accountId, {
    external_session_id: sessionId,
    provider,
    limit: 2,
  });
  const body = response.data;
  if (!scoped(body) || !Array.isArray(body.items) || !body.items.every(matches))
    throw new Error('voice_context_identity_mismatch');
  if (!body.items.length) return { status: 'pending' };
  if (body.items.length > 1) return { status: 'ambiguous' };
  const detail = (await api.call(accountId, Number(body.items[0].id))).data;
  if (
    !scoped(detail) ||
    !matches(detail.item) ||
    Number(detail.item.id) !== Number(body.items[0].id)
  )
    throw new Error('voice_context_identity_mismatch');
  return {
    status: 'linked',
    record: detail.item,
    customer: detail.item.customer,
  };
}

export function useActiveVoiceContext(identity, enabled) {
  let generation = 0;
  let timer;
  watch(
    [identity, enabled],
    ([current, allowed]) => {
      generation += 1;
      const version = generation;
      clearTimeout(timer);
      attendance.value = null;
      if (
        !allowed ||
        !current?.accountId ||
        !current.provider ||
        !current.sessionId
      )
        return;
      const refresh = async () => {
        let retry = true;
        try {
          const result = await resolveVoiceAttendance(current);
          if (version === generation)
            attendance.value = { ...current, ...result };
          retry =
            result.status !== 'ambiguous' &&
            !['ended', 'failed'].includes(result.record?.status);
        } catch (error) {
          const status = [401, 403, 404].includes(error.response?.status)
            ? 'restricted'
            : 'error';
          if (version === generation) attendance.value = { ...current, status };
          retry =
            status !== 'restricted' &&
            error.message !== 'voice_context_identity_mismatch';
        }
        if (version === generation && retry) timer = setTimeout(refresh, 5000);
      };
      refresh();
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    generation += 1;
    clearTimeout(timer);
    attendance.value = null;
  });
  return activeVoiceAttendance;
}
