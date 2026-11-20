import { computed, onBeforeUnmount, ref, watch } from 'vue';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';
import {
  acwFormAnswers,
  acwFormDefinition,
} from '../jrcContactCenter/helpers/acwForms';

const clone = value => JSON.parse(JSON.stringify(value));
const invalid = () => {
  throw new TypeError('Invalid native qualification form context');
};

export const endingReasonContext = value => {
  if (value === undefined) return null;
  if (
    !value ||
    typeof value !== 'object' ||
    !Number.isInteger(value.revision) ||
    value.revision < 1 ||
    !/^[0-9a-f]{64}$/.test(value.integrity_sha256) ||
    typeof value.required !== 'boolean' ||
    !Array.isArray(value.options) ||
    value.options.length > 100
  )
    invalid();
  const codes = new Set();
  value.options.forEach(row => {
    if (
      !row ||
      typeof row.code !== 'string' ||
      !row.code.trim() ||
      row.code.length > 100 ||
      typeof row.name !== 'string' ||
      !row.name.trim() ||
      row.name.length > 120 ||
      codes.has(row.code)
    )
      invalid();
    codes.add(row.code);
  });
  if (value.required && !value.options.length) invalid();
  return clone(value);
};

// Read-only schema lookup for the current own attendance. Never requests the manager catalogue.
export const useQualificationForms = ({
  pending,
  reason,
  answers,
  accountId,
  authorityKey,
  onDenied,
}) => {
  const selected = ref(null);
  const loading = ref(false);
  const error = ref(false);
  let generation = 0;
  let disposed = false;
  const ending = computed(() => {
    try {
      return {
        valid: true,
        value: endingReasonContext(pending.value?.ending_reason_context),
      };
    } catch {
      return { valid: false, value: null };
    }
  });
  const reasonOptions = computed(() => ending.value.value?.options || []);
  const reasonRequired = computed(() => ending.value.value?.required === true);
  const reasonRevision = computed(() => ending.value.value?.revision);
  const present = computed(() => Boolean(pending.value?.acw_form_context));
  const contextAvailable = computed(
    () => present.value || Boolean(ending.value.value) || !ending.value.valid
  );
  const reasonCodes = computed(() =>
    Array.isArray(pending.value?.acw_form_context?.reason_codes)
      ? [...pending.value.acw_form_context.reason_codes]
      : []
  );
  const identity = () =>
    JSON.stringify([
      accountId.value,
      authorityKey.value,
      pending.value?.id,
      pending.value?.account_user_id,
      reason.value,
    ]);
  const values = computed(() => {
    const key = selected.value?.rule_id;
    return key && Object.hasOwn(answers.value, key) ? answers.value[key] : {};
  });
  const ready = computed(() => {
    if (!ending.value.valid) return false;
    if (
      reasonRequired.value &&
      !reasonOptions.value.some(row => row.code === reason.value)
    )
      return false;
    if (!contextAvailable.value) return true;
    if (loading.value || error.value) return false;
    if (!selected.value) return true;
    try {
      acwFormAnswers(selected.value.definition, values.value, {
        complete: true,
      });
      return true;
    } catch {
      return false;
    }
  });
  const update = value => {
    if (!selected.value || loading.value || error.value) return;
    const validated = acwFormAnswers(selected.value.definition, value, {
      complete: false,
    });
    answers.value = { ...answers.value, [selected.value.rule_id]: validated };
  };
  const accept = value => {
    if (value === null) {
      selected.value = null;
      return;
    }
    if (
      !value ||
      typeof value !== 'object' ||
      typeof value.rule_id !== 'string' ||
      !value.rule_id.trim() ||
      typeof value.form_id !== 'string' ||
      !/^[1-9]\d{0,18}$/.test(value.form_id) ||
      !Number.isInteger(value.revision) ||
      value.revision < 1 ||
      !/^[0-9a-f]{64}$/.test(value.integrity_sha256) ||
      typeof value.name !== 'string'
    )
      invalid();
    acwFormDefinition(value.definition);
    selected.value = clone(value);
  };
  const load = async () => {
    generation += 1;
    const version = generation;
    const key = identity();
    selected.value = null;
    loading.value = false;
    error.value = false;
    if (!contextAvailable.value || !reason.value.trim()) return;
    loading.value = true;
    try {
      const response = await ContactCenterAPI.qualificationFormContext(
        accountId.value,
        pending.value.id,
        reason.value
      );
      if (disposed || version !== generation || key !== identity()) return;
      const item = response.data.item;
      if (
        String(item?.account_id) !== String(accountId.value) ||
        String(item?.id) !== String(pending.value.id) ||
        String(item?.account_user_id) !==
          String(pending.value.account_user_id) ||
        item?.reason_code !== reason.value ||
        (present.value &&
          (!item.acw_form_context ||
            !Object.hasOwn(item.acw_form_context, 'selected'))) ||
        JSON.stringify(endingReasonContext(item.ending_reason_context)) !==
          JSON.stringify(ending.value.value)
      )
        invalid();
      accept(item.acw_form_context?.selected ?? null);
    } catch (failure) {
      if (!disposed && version === generation && key === identity()) {
        error.value = true;
        selected.value = null;
        if ([401, 403, 404].includes(failure?.response?.status))
          onDenied(failure);
      }
    } finally {
      if (!disposed && version === generation && key === identity())
        loading.value = false;
    }
  };
  watch([identity, present, contextAvailable], load, { immediate: true });
  onBeforeUnmount(() => {
    disposed = true;
    generation += 1;
    selected.value = null;
  });
  return {
    selected,
    present,
    reasonCodes,
    reasonOptions,
    reasonRequired,
    reasonRevision,
    values,
    loading,
    error,
    ready,
    update,
    load,
  };
};
