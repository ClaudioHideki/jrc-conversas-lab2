import { computed, ref } from 'vue';

// Memory belongs to the caller's authenticated attendance context. No browser storage or automatic overwrite.
const canonical = value => {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object')
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map(key => [key, canonical(value[key])])
    );
  return value;
};
const clone = value => JSON.parse(JSON.stringify(value));

export const useQualificationDraft = ({
  reason,
  result,
  note,
  formAnswers = null,
}) => {
  const baseline = ref(null);
  const remote = ref(null);
  const revision = ref(null);
  const conflict = ref(false);
  const reviewLoaded = ref(false);
  const savedOnce = ref(false);
  const localValues = () => [
    reason.value,
    result.value,
    note.value,
    ...(formAnswers && baseline.value?.forms
      ? [canonical(formAnswers.value)]
      : []),
  ];
  const values = record => [
    record?.reason_code ?? '',
    record?.outcome_code ?? '',
    record?.notes ?? '',
    ...(formAnswers && record?.acw_form_context
      ? [canonical(record.acw_form_context.answers)]
      : []),
  ];
  const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
  const dirty = computed(
    () => !same(localValues(), baseline.value?.values || ['', '', ''])
  );
  const saved = computed(
    () => savedOnce.value && !dirty.value && !conflict.value
  );
  const canSave = computed(
    () => dirty.value && Boolean(revision.value) && !conflict.value
  );
  const canReapply = computed(
    () =>
      reviewLoaded.value &&
      Boolean(remote.value?.draft_revision) &&
      !remote.value?.completed_at &&
      String(remote.value?.id) === String(baseline.value?.id)
  );
  const setBaseline = record => {
    baseline.value = {
      id: record.id,
      values: values(record),
      forms: Boolean(record.acw_form_context),
    };
    revision.value =
      typeof record.draft_revision === 'string' ? record.draft_revision : null;
    remote.value = record;
    reviewLoaded.value = true;
  };
  const hydrate = record => {
    setBaseline(record);
    [reason.value, result.value, note.value] = values(record);
    if (formAnswers)
      formAnswers.value = clone(record.acw_form_context?.answers || {});
    conflict.value = false;
    const manual = values(record).slice(0, 3).some(Boolean);
    const persistedAnswers = Object.values(
      record.acw_form_context?.answers || {}
    ).some(fields =>
      Object.values(fields).some(
        value => ![null, undefined, ''].includes(value)
      )
    );
    savedOnce.value = manual || Boolean(formAnswers && persistedAnswers);
  };
  const reset = () => {
    baseline.value = null;
    if (formAnswers) formAnswers.value = {};
    remote.value = null;
    revision.value = null;
    conflict.value = false;
    reviewLoaded.value = false;
    savedOnce.value = false;
  };
  const observe = record => {
    if (conflict.value) {
      remote.value = record || null;
      reviewLoaded.value = true;
      return;
    }
    if (!record) {
      if (dirty.value) {
        conflict.value = true;
        remote.value = null;
        reviewLoaded.value = true;
      } else {
        [reason.value, result.value, note.value] = ['', '', ''];
        reset();
      }
      return;
    }
    const sameRecord = String(baseline.value?.id) === String(record.id);
    if (sameRecord && revision.value === (record.draft_revision || null)) {
      remote.value = record;
      return;
    }
    if (baseline.value && dirty.value) {
      conflict.value = true;
      remote.value = record;
      reviewLoaded.value = true;
    } else hydrate(record);
  };
  const markConflict = () => {
    conflict.value = true;
    remote.value = null;
    reviewLoaded.value = false;
  };
  const accept = (record, submitted) => {
    if (
      String(record?.id) !== String(baseline.value?.id) ||
      typeof record?.draft_revision !== 'string' ||
      !record.draft_revision ||
      record.completed_at ||
      Boolean(record.acw_form_context) !== baseline.value?.forms
    )
      throw new Error('Invalid native pending draft response');
    const unchanged = same(localValues(), submitted);
    setBaseline(record);
    conflict.value = false;
    if (unchanged) hydrate(record);
    else savedOnce.value = false;
  };
  const useRemote = () => {
    if (!conflict.value || !reviewLoaded.value) return false;
    if (remote.value) hydrate(remote.value);
    else {
      [reason.value, result.value, note.value] = ['', '', ''];
      reset();
    }
    return true;
  };
  const reapply = () => {
    if (!conflict.value || !canReapply.value) return false;
    setBaseline(remote.value);
    conflict.value = false;
    savedOnce.value = false;
    return true;
  };
  return {
    revision,
    remote,
    conflict,
    dirty,
    saved,
    canSave,
    canReapply,
    canUseRemote: computed(() => conflict.value && reviewLoaded.value),
    localValues,
    values,
    observe,
    reset,
    markConflict,
    accept,
    useRemote,
    reapply,
  };
};
