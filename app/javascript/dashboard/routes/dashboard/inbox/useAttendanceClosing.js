import { computed, onBeforeUnmount, ref, watch } from 'vue';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';
import { useQualificationDraft } from './useQualificationDraft';
import { useQualificationForms } from './useQualificationForms';

export const useAttendanceClosing = ({
  props,
  supportsClosing,
  authorityKey = computed(() => ''),
  enabled = computed(() => true),
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
  const writeFailure = ref('');
  const saving = ref(false);
  const loading = ref(false);
  const blocked = ref(false);
  const reason = ref('');
  const result = ref('');
  const note = ref('');
  const formAnswers = ref({});
  const draft = useQualificationDraft({ reason, result, note, formAnswers });
  let generation = 0;
  let request = 0;
  let disposed = false;
  const identity = () =>
    JSON.stringify([
      props.accountId,
      props.currentCallId,
      props.currentConversationId,
      authorityKey.value,
      enabled.value,
      supportsClosing.value,
    ]);
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
  const unverified = computed(
    () => enabled.value && !agent.value && (loading.value || error.value)
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

  const clearObserved = () => {
    records.value = [];
    attendance.value = null;
    agent.value = null;
    policy.value = null;
    blocked.value = false;
  };
  const clearDraft = () => {
    reason.value = '';
    result.value = '';
    note.value = '';
    draft.reset();
    writeFailure.value = '';
  };
  const rejectUnauthorized = failure => {
    if ([401, 403, 404].includes(failure?.response?.status)) {
      generation += 1;
      request += 1;
      clearObserved();
      clearDraft();
      loading.value = false;
      saving.value = false;
    }
    error.value = true;
  };

  const forms = useQualificationForms({
    pending,
    reason,
    answers: formAnswers,
    accountId: computed(() => props.accountId),
    authorityKey: computed(identity),
    onDenied: failure => rejectUnauthorized(failure),
  });

  const load = async () => {
    if (!enabled.value) return;
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
        if (
          response.data.items.some(
            record => record.acw_form_context_unavailable
          )
        ) {
          rejectUnauthorized({ response: { status: 403 } });
          return;
        }
        attendance.value = response.data.attendance;
        agent.value = response.data.agent;
        records.value = response.data.items;
        policy.value = response.data.policy;
        draft.observe(pending.value);
      } else {
        clearObserved();
        agent.value = response.data.item;
      }
      if (pending.value) showClosing();
      const awaiting = pendingAttendance.value;
      if (awaiting && !pending.value) restoreSelection(awaiting);
    } catch (failure) {
      if (current(version, key) && requestId === request) {
        clearObserved();
        rejectUnauthorized(failure);
      }
    } finally {
      if (current(version, key) && requestId === request) loading.value = false;
    }
  };

  const start = async () => {
    if (
      saving.value ||
      !enabled.value ||
      !supportsClosing.value ||
      unverified.value
    )
      return;
    const version = generation;
    const key = identity();
    request += 1;
    loading.value = false;
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
      draft.observe(response.data.item);
      showClosing();
      await load();
    } catch (failure) {
      if (current(version, key)) rejectUnauthorized(failure);
    } finally {
      if (current(version, key)) saving.value = false;
    }
  };

  const rejectWrite = async failure => {
    rejectUnauthorized(failure);
    if (failure?.response?.status !== 409) return;
    const code = failure.response.data?.error;
    if (['conflicting_acw_rules', 'attendance_cycle_conflict'].includes(code)) {
      writeFailure.value = code;
      return;
    }
    if (
      [
        'stale_configuration_revision',
        'qualification_already_completed',
      ].includes(code)
    ) {
      draft.markConflict();
      await load();
    }
  };

  const saveDraft = async () => {
    if (
      saving.value ||
      !enabled.value ||
      !supportsClosing.value ||
      unverified.value ||
      !pending.value ||
      forms.loading.value ||
      forms.error.value ||
      !draft.canSave.value
    )
      return false;
    const version = generation;
    const key = identity();
    const record = pending.value;
    const submitted = draft.localValues();
    request += 1;
    loading.value = false;
    saving.value = true;
    error.value = false;
    writeFailure.value = '';
    try {
      const response = await ContactCenterAPI.saveQualificationDraft(
        props.accountId,
        record.id,
        {
          reason_code: submitted[0],
          outcome_code: submitted[1],
          notes: submitted[2],
          ...(submitted.length === 4 ? { acw_form_answers: submitted[3] } : {}),
        },
        draft.revision.value
      );
      if (!current(version, key)) return false;
      const updated = response.data.item;
      if (
        String(updated?.account_id) !== String(props.accountId) ||
        String(updated?.account_user_id) !== String(record.account_user_id)
      )
        throw new Error('Invalid native qualification context');
      draft.accept(updated, submitted);
      records.value = [
        updated,
        ...records.value.filter(item => item.id !== updated.id),
      ];
      agent.value = response.data.agent;
      return true;
    } catch (failure) {
      if (current(version, key)) {
        await rejectWrite(failure);
      }
      return false;
    } finally {
      if (current(version, key)) saving.value = false;
    }
  };

  const complete = async () => {
    if (
      saving.value ||
      !enabled.value ||
      !supportsClosing.value ||
      draft.conflict.value ||
      !pending.value ||
      !forms.ready.value ||
      !reason.value.trim() ||
      !result.value.trim()
    )
      return false;
    const version = generation;
    const key = identity();
    const options = draft.revision.value
      ? [{ expected_draft_revision: draft.revision.value }]
      : [];
    request += 1;
    loading.value = false;
    saving.value = true;
    error.value = false;
    writeFailure.value = '';
    try {
      const response = await ContactCenterAPI.completeQualification(
        props.accountId,
        pending.value.id,
        {
          reason_code: reason.value,
          outcome_code: result.value,
          notes: note.value,
          ...(forms.present.value
            ? {
                acw_form_answers: JSON.parse(JSON.stringify(formAnswers.value)),
              }
            : {}),
        },
        ...options
      );
      if (!current(version, key)) return false;
      records.value = [
        response.data.item,
        ...records.value.filter(record => record.id !== response.data.item.id),
      ];
      agent.value = response.data.agent;
      clearDraft();
      blocked.value = false;
      return true;
    } catch (failure) {
      if (current(version, key)) {
        await rejectWrite(failure);
      }
      return false;
    } finally {
      if (current(version, key)) saving.value = false;
    }
  };

  const allowSelection = (kind, id) => {
    const selected =
      kind === 'voice' ? props.currentCallId : props.currentConversationId;
    if (unverified.value && String(selected) !== String(id)) {
      blocked.value = true;
      showClosing();
      return false;
    }
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
    identity,
    () => {
      generation += 1;
      clearObserved();
      clearDraft();
      saving.value = false;
      loading.value = false;
      error.value = false;
      load();
    },
    { immediate: true }
  );
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
    unverified,
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
    writeFailure,
    draft,
    forms,
    load,
    start,
    saveDraft,
    complete,
    allowSelection,
  };
};
