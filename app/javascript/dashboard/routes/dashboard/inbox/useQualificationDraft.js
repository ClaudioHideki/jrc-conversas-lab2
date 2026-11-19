import { computed, ref } from 'vue';

// Memory belongs to the caller's authenticated attendance context. No browser storage or automatic overwrite.
export const useQualificationDraft = ({ reason, result, note }) => {
  const baseline = ref(null);
  const remote = ref(null);
  const revision = ref(null);
  const conflict = ref(false);
  const reviewLoaded = ref(false);
  const savedOnce = ref(false);
  const localValues = () => [reason.value, result.value, note.value];
  const values = record => [
    record?.reason_code ?? '',
    record?.outcome_code ?? '',
    record?.notes ?? '',
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
    baseline.value = { id: record.id, values: values(record) };
    revision.value =
      typeof record.draft_revision === 'string' ? record.draft_revision : null;
    remote.value = record;
    reviewLoaded.value = true;
  };
  const hydrate = record => {
    setBaseline(record);
    [reason.value, result.value, note.value] = values(record);
    conflict.value = false;
    savedOnce.value = values(record).some(Boolean);
  };
  const reset = () => {
    baseline.value = null;
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
      record.completed_at
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
