import { computed, onBeforeUnmount, ref, watch } from 'vue';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';

export const useAttendanceClosing = ({
  props,
  supportsClosing,
  isVoice,
  now,
  showClosing,
  restoreSelection,
}) => {
  const records = ref([]);
  const attendance = ref(null);
  const agent = ref(null);
  const policy = ref(null);
  const error = ref(false);
  const saving = ref(false);
  const loading = ref(false);
  const blocked = ref(false);
  const reason = ref('');
  const result = ref('');
  const note = ref('');
  let generation = 0;
  let request = 0;
  let disposed = false;
  const identity = () =>
    [props.accountId, props.currentCallId, props.currentConversationId].join(
      ':'
    );
  const current = (version, key) =>
    !disposed && version === generation && key === identity();
  const target = () =>
    isVoice.value
      ? { call_session_id: props.currentCallId }
      : { conversation_id: props.currentConversationId };
  const pending = computed(() =>
    records.value.find(
      record =>
        !record.completed_at &&
        String(record.account_user_id) === String(agent.value?.account_user_id)
    )
  );
  const pendingAttendance = computed(
    () => agent.value?.pending_qualifications?.[0]
  );
  const elapsed = computed(() =>
    pending.value
      ? Math.max(
          0,
          Math.floor((now.value - Date.parse(pending.value.started_at)) / 1000)
        )
      : 0
  );
  const limit = computed(
    () =>
      pending.value?.acw_limit_seconds ||
      policy.value?.limits?.[isVoice.value ? 'voice' : 'whatsapp']
  );
  const overdue = computed(() =>
    Boolean(
      pending.value && (pending.value.overdue || elapsed.value >= limit.value)
    )
  );

  const load = async () => {
    const version = generation;
    const key = identity();
    request += 1;
    const requestId = request;
    loading.value = true;
    try {
      const response =
        supportsClosing.value &&
        (props.currentCallId || props.currentConversationId)
          ? await ContactCenterAPI.qualifications(props.accountId, target())
          : await ContactCenterAPI.agentState(props.accountId);
      if (!current(version, key) || requestId !== request) return;
      error.value = false;
      if (response.data.agent) {
        attendance.value = response.data.attendance;
        agent.value = response.data.agent;
        records.value = response.data.items;
        policy.value = response.data.policy;
      } else {
        agent.value = response.data.item;
      }
      if (pending.value) showClosing();
      const awaiting = pendingAttendance.value;
      if (awaiting && !pending.value) restoreSelection(awaiting);
    } catch {
      if (current(version, key) && requestId === request) error.value = true;
    } finally {
      if (current(version, key) && requestId === request) loading.value = false;
    }
  };

  const start = async () => {
    const version = generation;
    const key = identity();
    saving.value = true;
    error.value = false;
    try {
      const response = await ContactCenterAPI.startQualification(
        props.accountId,
        target()
      );
      if (!current(version, key)) return;
      records.value = [
        response.data.item,
        ...records.value.filter(record => record.id !== response.data.item.id),
      ];
      showClosing();
      await load();
    } catch {
      if (current(version, key)) error.value = true;
    } finally {
      if (current(version, key)) saving.value = false;
    }
  };

  const complete = async () => {
    if (
      saving.value ||
      !pending.value ||
      !reason.value.trim() ||
      !result.value.trim()
    )
      return false;
    const version = generation;
    const key = identity();
    saving.value = true;
    error.value = false;
    try {
      const response = await ContactCenterAPI.completeQualification(
        props.accountId,
        pending.value.id,
        {
          reason_code: reason.value,
          outcome_code: result.value,
          notes: note.value,
        }
      );
      if (!current(version, key)) return false;
      records.value = [
        response.data.item,
        ...records.value.filter(record => record.id !== response.data.item.id),
      ];
      agent.value = response.data.agent;
      reason.value = '';
      result.value = '';
      note.value = '';
      blocked.value = false;
      return true;
    } catch {
      if (current(version, key)) error.value = true;
      return false;
    } finally {
      if (current(version, key)) saving.value = false;
    }
  };

  const allowSelection = (kind, id) => {
    const waiting = pendingAttendance.value || pending.value;
    if (!waiting) return true;
    const same =
      kind === 'voice'
        ? Number(waiting.call_session_id) === Number(id)
        : Number(waiting.conversation_display_id) === Number(id);
    if (same) return true;
    blocked.value = true;
    showClosing();
    return false;
  };
  watch(
    () => [props.accountId, props.currentCallId, props.currentConversationId],
    () => {
      generation += 1;
      records.value = [];
      attendance.value = null;
      agent.value = null;
      policy.value = null;
      reason.value = '';
      result.value = '';
      note.value = '';
      saving.value = false;
      blocked.value = false;
      error.value = false;
      load();
    },
    { immediate: true }
  );
  watch(supportsClosing, load);
  const poll = setInterval(() => {
    if (!saving.value && !loading.value && props.ready) load();
  }, 5000);
  onBeforeUnmount(() => {
    disposed = true;
    generation += 1;
    clearInterval(poll);
  });
  return {
    records,
    attendance,
    agent,
    policy,
    pending,
    pendingAttendance,
    elapsed,
    limit,
    overdue,
    reason,
    result,
    note,
    error,
    saving,
    loading,
    blocked,
    load,
    start,
    complete,
    allowSelection,
  };
};
