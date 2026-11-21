import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';
import {
  calendarDefinitionSignature,
  newCalendarDefinition,
  normalizedCalendarDefinition,
  validCalendarDefinition,
} from '../helpers/calendarForm';

const digest = value =>
  typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const snapshot = value => JSON.parse(JSON.stringify(value));
const unauthorized = problem =>
  [401, 403, 404].includes(problem?.response?.status);

export const useUnitCalendarEditor = ({
  accountId,
  unitId,
  timezone,
  contextKey,
  canManage,
  onDenied,
  onSaved,
}) => {
  const dialog = ref(null);
  const active = ref(false);
  const existing = ref(false);
  const draft = ref(null);
  const opening = ref(false);
  const saving = ref(false);
  const error = ref('');
  const reviewed = ref(false);
  const uncertain = ref(false);
  let generation = 0;
  const busy = computed(() => opening.value || saving.value);
  const admitted = (response, account, unit) => {
    const data = response.data;
    if (
      data.account_id !== String(account) ||
      data.unit_id !== unit ||
      !digest(data.revision) ||
      data.local_only !== true ||
      data.pabx_confirmed !== false
    )
      throw new Error('Invalid native calendar scope receipt');
    return data;
  };
  const source = (data, id) => {
    const row = data.item || data.items.find(item => item.id === id);
    if (
      row &&
      (row.id !== id ||
        ![true, false].includes(row.active) ||
        !validCalendarDefinition(row.definition))
    )
      throw new Error('Invalid native calendar definition receipt');
    return row
      ? { ...row, revision: data.revision, present: true }
      : { id, revision: data.revision, present: false };
  };
  let revision;
  const clear = () => {
    generation += 1;
    active.value = false;
    opening.value = false;
    saving.value = false;
    existing.value = false;
    draft.value = null;
    error.value = '';
    reviewed.value = false;
    uncertain.value = false;
    revision?.capture(null);
  };
  const forget = () => {
    clear();
    dialog.value?.close();
  };
  const reloadRecord = async (account, id) => {
    const unit = unitId.value;
    const response = await API.unitCalendars(account, unit, {
      page: 1,
      per_page: 100,
    });
    const data = admitted(response, account, unit);
    if (
      !Array.isArray(data.items) ||
      data.meta.total !== data.items.length ||
      data.items.length > 100
    )
      throw new Error('Incomplete bounded calendar catalog');
    return { data: { ...data, item: source(data, id) } };
  };
  revision = useConfigurationRevision({
    accountId,
    resource: computed(() => 'unit_calendars'),
    draft,
    reloadRecord,
    onDenied: () => {
      forget();
      onDenied();
    },
  });
  const canSave = computed(
    () =>
      active.value &&
      canManage.value &&
      !busy.value &&
      reviewed.value &&
      draft.value &&
      validCalendarDefinition(draft.value.definition) &&
      revision.state.required &&
      revision.state.id === draft.value.id &&
      revision.canSave.value &&
      error.value !== 'IDENTITY_CONFLICT'
  );

  const open = async (id = null) => {
    if (!canManage.value || active.value || busy.value) return;
    clear();
    const current = generation;
    const account = accountId.value;
    const unit = unitId.value;
    opening.value = true;
    try {
      const response = id
        ? await API.unitCalendar(account, unit, id)
        : await API.unitCalendars(account, unit, { page: 1, per_page: 1 });
      if (current !== generation) return;
      const data = admitted(response, account, unit);
      if (!id && data.unit_timezone !== timezone.value)
        throw new Error(
          'Native unit timezone changed; reload the current unit before creating a draft'
        );
      const identity = id || crypto.randomUUID();
      const row = id ? source(data, id) : null;
      if (id && !row?.present) throw new Error('Missing native calendar');
      existing.value = Boolean(id);
      draft.value = row
        ? {
            id: row.id,
            active: row.active,
            definition: snapshot(row.definition),
          }
        : {
            id: identity,
            active: false,
            definition: newCalendarDefinition(timezone.value),
          };
      revision.capture({ id: identity, revision: data.revision });
      active.value = true;
      dialog.value?.open();
    } catch (problem) {
      if (current === generation) {
        if (unauthorized(problem)) {
          forget();
          onDenied();
        } else error.value = 'LOAD_ERROR';
      }
    } finally {
      if (current === generation) opening.value = false;
    }
  };
  const save = async () => {
    if (!canSave.value) return;
    const current = generation;
    const body = snapshot(draft.value);
    body.definition = normalizedCalendarDefinition(body.definition);
    saving.value = true;
    error.value = '';
    try {
      const response = await API.saveUnitCalendar(
        accountId.value,
        unitId.value,
        body,
        revision.options().expected_revision,
        existing.value
      );
      if (current !== generation) return;
      const data = admitted(response, accountId.value, unitId.value);
      const received = source(data, body.id);
      if (
        !received.present ||
        calendarDefinitionSignature(received.definition) !==
          calendarDefinitionSignature(body.definition) ||
        received.active !== body.active
      )
        throw new Error('Unconfirmed native calendar content');
      forget();
      onSaved(received);
    } catch (problem) {
      if (current === generation) {
        if (unauthorized(problem)) {
          forget();
          onDenied();
        } else {
          reviewed.value = false;
          if (!revision.handleError(problem)) {
            error.value =
              problem?.response?.data?.error === 'calendar_identity_conflict'
                ? 'IDENTITY_CONFLICT'
                : 'SAVE_ERROR';
            uncertain.value = ![409, 422, 428].includes(
              problem?.response?.status
            );
            if (uncertain.value) {
              revision.state.conflict = true;
              revision.state.latest = null;
              revision.review(false);
            }
          }
        }
      }
    } finally {
      if (current === generation) saving.value = false;
    }
  };
  watch(
    () => JSON.stringify(draft.value),
    () => {
      reviewed.value = false;
    },
    { flush: 'sync' }
  );
  watch([accountId, unitId, contextKey, canManage], forget, { flush: 'sync' });
  onBeforeUnmount(clear);
  return {
    dialog,
    active,
    existing,
    draft,
    opening,
    saving,
    busy,
    error,
    reviewed,
    uncertain,
    revision,
    canSave,
    open,
    save,
    clear,
    forget,
  };
};
