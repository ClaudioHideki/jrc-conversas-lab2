import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';

export const useRoutingDraftEditor = ({
  accountId,
  allowed,
  dialog,
  t,
  saved,
}) => {
  const draft = ref({});
  const editing = ref(null);
  const referenceUnit = ref('');
  const opening = ref(false);
  const saving = ref(false);
  const error = ref('');
  const visible = ref(false);
  const resource = computed(() => 'routing_rules');
  const revision = useConfigurationRevision({ accountId, resource, draft });
  let generation = 0;
  const close = () => {
    generation += 1;
    opening.value = false;
    editing.value = null;
    draft.value = {};
    referenceUnit.value = '';
    revision.capture(null);
    error.value = '';
    visible.value = false;
  };
  const current = version =>
    version.generation === generation &&
    version.account === String(accountId.value) &&
    allowed.value;
  const open = async id => {
    if (!allowed.value || opening.value || saving.value) return;
    close();
    const version = { generation, account: String(accountId.value) };
    opening.value = true;
    try {
      let record;
      if (id) {
        const response = await API.configurationRecord(
          accountId.value,
          resource.value,
          id
        );
        if (!current(version)) return;
        record = response.data.item;
        if (String(record.id) !== String(id))
          throw new Error('Invalid routing identity');
        if (!record.target_unit_id && record.target_queue_id) {
          const queue = await API.ivrReference(
            accountId.value,
            'queues',
            record.target_queue_id
          );
          if (!current(version)) return;
          referenceUnit.value = String(queue.data.item.unit_id);
        }
      }
      if (!current(version)) return;
      editing.value = record || null;
      draft.value = record
        ? Object.fromEntries(
            [
              'version',
              'rule_key',
              'kind',
              'source_value',
              'priority',
              'state',
              'target_unit_id',
              'target_queue_id',
            ].map(key => [key, record[key]])
          )
        : {
            version: 1,
            rule_key: '',
            kind: 'ddd',
            source_value: '',
            priority: 1,
            state: 'draft',
            target_unit_id: null,
            target_queue_id: null,
          };
      revision.capture(record);
      await nextTick();
      if (current(version)) {
        visible.value = true;
        dialog.value?.open();
      }
    } catch {
      if (current(version)) error.value = t('JRC_CONTACT_CENTER.COMMON.ERROR');
    } finally {
      if (current(version)) opening.value = false;
    }
  };
  const save = async () => {
    if (
      !allowed.value ||
      saving.value ||
      opening.value ||
      !revision.canSave.value ||
      editing.value?.state === 'published'
    )
      return;
    if (!draft.value.target_unit_id && !draft.value.target_queue_id) {
      error.value = t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.TARGET_REQUIRED');
      return;
    }
    const version = { generation, account: String(accountId.value) };
    const id = editing.value?.id;
    if (
      id &&
      (!revision.state.required || String(revision.state.id) !== String(id))
    )
      return;
    saving.value = true;
    error.value = '';
    try {
      const payload = {
        ...draft.value,
        version: Number(draft.value.version),
        priority: Number(draft.value.priority),
      };
      await API.saveRoutingRule(
        accountId.value,
        payload,
        id,
        revision.options()
      );
      if (!current(version)) return;
      dialog.value?.close();
      close();
      saved();
    } catch (failure) {
      if (current(version) && !revision.handleError(failure)) {
        error.value = [401, 403, 404].includes(failure?.response?.status)
          ? t('JRC_CONTACT_CENTER.ADMIN.DENIED')
          : t('JRC_CONTACT_CENTER.ROUTING_DRAFTS.SAVE_ERROR');
      }
    } finally {
      saving.value = false;
    }
  };
  watch([accountId, allowed], () => {
    dialog.value?.close();
    close();
  });
  onBeforeUnmount(close);
  return {
    draft,
    editing,
    referenceUnit,
    opening,
    saving,
    error,
    visible,
    revision,
    open,
    close,
    save,
  };
};
