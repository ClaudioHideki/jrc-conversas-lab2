<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import API from 'dashboard/api/jrcContactCenter';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();
const labels = computed(() => ({
  OPEN: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.OPEN'),
  TITLE: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.TITLE'),
  LOCAL_ONLY: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.LOCAL_ONLY'),
  SELECT_UNIT: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SELECT_UNIT'),
  SELECT: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SELECT'),
  MODE: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.MODE'),
  AUTOMATIC: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.AUTOMATIC'),
  ON_DEMAND: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.ON_DEMAND'),
  SCOPE: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SCOPE'),
  WHOLE_UNIT: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.WHOLE_UNIT'),
  SELECTED_QUEUES: t(
    'JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SELECTED_QUEUES'
  ),
  SEARCH_QUEUES: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SEARCH_QUEUES'),
  SEARCH: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SEARCH'),
  SELECTED_COUNT: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SELECTED_COUNT'),
  QUEUE_ERROR: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.QUEUE_ERROR'),
  QUEUE_ID: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.QUEUE_ID'),
  REMOVE: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.REMOVE'),
  NOTICE: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.NOTICE'),
  RETENTION: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.RETENTION'),
  RETENTION_HELP: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.RETENTION_HELP'),
  RELOAD: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.RELOAD'),
  SAVE: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SAVE'),
  SAVED: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.SAVED'),
  LOAD_ERROR: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.LOAD_ERROR'),
  CONFLICT: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.CONFLICT'),
  INVALID: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.INVALID'),
  UNKNOWN_RESULT: t('JRC_CONTACT_CENTER.RECORDING_POLICY_DRAFT.UNKNOWN_RESULT'),
}));
const text = key => labels.value[key];
const user = useMapGetter('getCurrentUser');
const units = computed(() => props.context.units || []);
const membership = computed(() =>
  user.value?.accounts?.find(row => String(row.id) === String(props.accountId))
);
const allowed = computed(
  () =>
    Boolean(user.value?.id && membership.value) &&
    props.context.capabilities?.configure === true
);
const authority = computed(() =>
  JSON.stringify([
    String(props.accountId),
    user.value?.id,
    membership.value?.role,
    membership.value?.custom_role_id,
    membership.value?.contact_center_eligible,
    [...(membership.value?.permissions || [])].sort(),
    allowed.value,
    units.value.map(row => String(row.id)).sort(),
    (props.context.queues || []).map(row => String(row.id)).sort(),
  ])
);
const popup = ref(null);
const active = ref(false);
const unitId = ref('');
const revision = ref('');
const draft = ref(null);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const reloadRequired = ref(false);
const saved = ref(false);
const queues = ref([]);
const queuePage = ref(1);
const queuePages = ref(0);
const queueQuery = ref('');
const queueLoading = ref(false);
const queueError = ref(false);
const queueName = id =>
  (props.context.queues || []).find(row => String(row.id) === id)?.name ||
  queues.value.find(row => String(row.id) === id)?.name ||
  `${text('QUEUE_ID')} ${id}`;
const selectedUnit = computed(() =>
  units.value.some(row => String(row.id) === unitId.value)
);
const busy = computed(() => loading.value || saving.value);
const validRetention = computed(
  () =>
    draft.value?.retention_days === '' ||
    (/^[1-9]\d*$/.test(draft.value?.retention_days) &&
      Number.isSafeInteger(Number(draft.value.retention_days)))
);
const canSave = computed(
  () =>
    allowed.value &&
    selectedUnit.value &&
    !busy.value &&
    !reloadRequired.value &&
    /^[a-f0-9]{64}$/.test(revision.value) &&
    draft.value &&
    ['automatic', 'on_demand'].includes(draft.value.mode) &&
    ['unit', 'selected_queues'].includes(draft.value.queue_scope) &&
    (draft.value.queue_scope === 'unit' || draft.value.queue_ids.length > 0) &&
    validRetention.value
);
let generation = 0;
let queueGeneration = 0;
let request = null;
const clear = () => {
  generation += 1;
  queueGeneration += 1;
  request?.abort();
  active.value = false;
  unitId.value = '';
  revision.value = '';
  draft.value = null;
  loading.value = false;
  saving.value = false;
  queues.value = [];
  queueQuery.value = '';
  queuePage.value = 1;
  queuePages.value = 0;
  queueLoading.value = false;
  queueError.value = false;
  reloadRequired.value = false;
  error.value = '';
  saved.value = false;
};
const denied = () => {
  clear();
  popup.value?.close();
};
const checked = data => {
  if (
    data.account_id !== String(props.accountId) ||
    data.unit_id !== unitId.value ||
    data.applied !== false ||
    data.provider_state !== 'not_verified' ||
    !/^[a-f0-9]{64}$/.test(data.revision)
  )
    throw new Error('Invalid recording policy identity');
  const value = data.draft;
  if (
    value !== null &&
    (!value ||
      value.scope_snapshot?.account_id !== String(props.accountId) ||
      value.scope_snapshot?.unit_id !== unitId.value ||
      value.schema_version !== 1 ||
      !['automatic', 'on_demand'].includes(value.mode) ||
      !['unit', 'selected_queues'].includes(value.queue_scope) ||
      !Array.isArray(value.queue_ids) ||
      !value.queue_ids.every(
        id => typeof id === 'string' && /^[1-9]\d*$/.test(id)
      ) ||
      typeof value.notice !== 'string' ||
      !(
        value.retention_days === null ||
        (Number.isSafeInteger(value.retention_days) && value.retention_days > 0)
      ))
  )
    throw new Error('Invalid recording policy draft');
  return data;
};
const load = async () => {
  generation += 1;
  const current = generation;
  request?.abort();
  revision.value = '';
  draft.value = null;
  saved.value = false;
  error.value = '';
  reloadRequired.value = false;
  if (!active.value || !allowed.value || !selectedUnit.value) return;
  loading.value = true;
  request = new AbortController();
  try {
    const response = await API.unitRecordingPolicyDraft(
      props.accountId,
      unitId.value,
      { signal: request.signal }
    );
    if (current !== generation) return;
    const data = checked(response.data);
    revision.value = data.revision;
    draft.value = data.draft
      ? {
          ...data.draft,
          queue_ids: [...data.draft.queue_ids],
          retention_days:
            data.draft.retention_days === null
              ? ''
              : String(data.draft.retention_days),
        }
      : {
          mode: '',
          queue_scope: '',
          queue_ids: [],
          notice: '',
          retention_days: '',
        };
  } catch (failure) {
    if (current !== generation) return;
    if ([401, 403, 404].includes(failure?.response?.status)) denied();
    else error.value = 'LOAD_ERROR';
  } finally {
    if (current === generation) loading.value = false;
  }
};
const loadQueues = async () => {
  queueGeneration += 1;
  const current = queueGeneration;
  queues.value = [];
  queueError.value = false;
  queueLoading.value = false;
  if (
    !active.value ||
    !allowed.value ||
    !selectedUnit.value ||
    draft.value?.queue_scope !== 'selected_queues'
  )
    return;
  queueLoading.value = true;
  try {
    const response = await API.queues(props.accountId, {
      unit_id: unitId.value,
      page: queuePage.value,
      per_page: 20,
      q: queueQuery.value,
    });
    if (current !== queueGeneration) return;
    const data = response.data;
    if (
      data.account_id !== String(props.accountId) ||
      !Array.isArray(data.items) ||
      !data.items.every(row => String(row.unit_id) === unitId.value) ||
      data.meta?.page !== queuePage.value ||
      data.meta?.per_page !== 20 ||
      !Number.isInteger(data.meta.pages) ||
      data.meta.pages < 0
    )
      throw new Error('Invalid native queue page');
    queues.value = data.items;
    queuePages.value = data.meta.pages;
  } catch (failure) {
    if (current !== queueGeneration) return;
    if ([401, 403, 404].includes(failure?.response?.status)) denied();
    else queueError.value = true;
  } finally {
    if (current === queueGeneration) queueLoading.value = false;
  }
};
const open = () => {
  if (!allowed.value) return;
  clear();
  active.value = true;
  popup.value?.open();
};
const save = async () => {
  if (!canSave.value) return;
  const current = generation;
  const value = {
    mode: draft.value.mode,
    queue_scope: draft.value.queue_scope,
    queue_ids:
      draft.value.queue_scope === 'unit' ? [] : [...draft.value.queue_ids],
    notice: draft.value.notice,
    retention_days:
      draft.value.retention_days === ''
        ? null
        : Number(draft.value.retention_days),
  };
  saving.value = true;
  error.value = '';
  saved.value = false;
  try {
    const response = await API.updateUnitRecordingPolicyDraft(
      props.accountId,
      unitId.value,
      value,
      revision.value
    );
    if (current !== generation) return;
    const data = checked(response.data);
    if (
      !data.draft ||
      ['mode', 'queue_scope', 'notice', 'retention_days'].some(
        key => data.draft[key] !== value[key]
      ) ||
      JSON.stringify([...data.draft.queue_ids].sort()) !==
        JSON.stringify([...value.queue_ids].sort())
    )
      throw new Error('Saved draft differs');
    revision.value = data.revision;
    saved.value = true;
    emit('changed');
  } catch (failure) {
    if (current !== generation) return;
    const status = failure?.response?.status;
    if ([401, 403, 404].includes(status)) denied();
    else {
      reloadRequired.value = status !== 422;
      const message = status === 422 ? 'INVALID' : 'UNKNOWN_RESULT';
      error.value = [409, 428].includes(status) ? 'CONFLICT' : message;
    }
  } finally {
    if (current === generation) saving.value = false;
  }
};
watch(authority, denied, { flush: 'sync' });
watch(
  unitId,
  () => {
    queues.value = [];
    queuePage.value = 1;
    load();
  },
  { flush: 'sync' }
);
watch(
  () => draft.value?.queue_scope,
  () => {
    queuePage.value = 1;
    loadQueues();
  },
  { flush: 'sync' }
);
onBeforeUnmount(clear);
</script>

<template>
  <Button
    v-if="allowed"
    type="button"
    icon="i-lucide-settings-2"
    data-open-recording-policy-draft
    :label="text('OPEN')"
    @click="open"
  />
  <Dialog
    ref="popup"
    contained
    use-form
    :title="text('TITLE')"
    :dismissible="!saving"
    @confirm="save"
    @close="clear"
  >
    <div
      v-if="active"
      class="min-w-0 space-y-4 text-sm text-n-slate-12"
      data-recording-policy-draft
    >
      <p
        class="break-words rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-n-amber-11"
      >
        {{ text('LOCAL_ONLY') }}
      </p>
      <p v-if="error" role="alert" class="break-words text-n-ruby-11">
        {{ text(error) }}
      </p>
      <p
        v-if="saved"
        role="status"
        class="text-n-teal-11"
        data-recording-policy-saved
      >
        {{ text('SAVED') }}
      </p>
      <label class="block min-w-0">
        <span class="block">{{ t('JRC_CONTACT_CENTER.ADMIN.UNIT') }}</span>

        <select
          v-model="unitId"
          class="mt-1 w-full min-w-0"
          :disabled="busy"
          data-recording-policy-unit
        >
          <option value="">{{ text('SELECT_UNIT') }}</option>
          <option v-for="row in units" :key="row.id" :value="String(row.id)">
            {{ row.name }}
          </option>
        </select>
      </label>
      <p v-if="loading" role="status">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <fieldset
        v-if="draft"
        class="min-w-0 space-y-4"
        :disabled="busy || reloadRequired"
        @input="saved = false"
      >
        <label class="block">
          <span class="block">{{ text('MODE') }}</span>
          <select
            v-model="draft.mode"
            class="mt-1 w-full min-w-0"
            data-recording-policy-mode
          >
            <option value="">{{ text('SELECT') }}</option>
            <option value="automatic">{{ text('AUTOMATIC') }}</option>
            <option value="on_demand">{{ text('ON_DEMAND') }}</option>
          </select>
        </label>
        <label class="block">
          <span class="block">{{ text('SCOPE') }}</span>
          <select
            v-model="draft.queue_scope"
            class="mt-1 w-full min-w-0"
            data-recording-policy-scope
          >
            <option value="">{{ text('SELECT') }}</option>
            <option value="unit">{{ text('WHOLE_UNIT') }}</option>
            <option value="selected_queues">
              {{ text('SELECTED_QUEUES') }}
            </option>
          </select>
        </label>
        <section
          v-if="draft.queue_scope === 'selected_queues'"
          class="min-w-0 space-y-3"
          data-recording-policy-queues
        >
          <label class="block">
            <span class="block">{{ text('SEARCH_QUEUES') }}</span>
            <input
              v-model="queueQuery"
              type="search"
              maxlength="100"
              class="mt-1 w-full min-w-0"
              data-recording-policy-queue-query
              @keydown.enter.prevent="
                queuePage = 1;
                loadQueues();
              "
          /></label>
          <Button
            type="button"
            :label="text('SEARCH')"
            :disabled="queueLoading"
            data-recording-policy-queue-search
            @click="
              queuePage = 1;
              loadQueues();
            "
          />
          <p v-if="queueError" role="alert">{{ text('QUEUE_ERROR') }}</p>
          <p v-if="queueLoading" role="status">
            {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
          </p>
          <label
            v-for="row in queues"
            :key="row.id"
            class="flex min-w-0 items-start gap-2"
            ><input
              v-model="draft.queue_ids"
              type="checkbox"
              :value="String(row.id)"
              class="mt-1 shrink-0"
              :data-recording-policy-queue="row.id"
            /><span class="break-words">{{ row.name }}</span>
          </label>
          <p>{{ text('SELECTED_COUNT') }} {{ draft.queue_ids.length }}</p>
          <div
            v-for="id in draft.queue_ids"
            :key="id"
            class="flex min-w-0 items-start justify-between gap-2 rounded-lg border border-n-weak p-2"
          >
            <span class="min-w-0 break-words">{{ queueName(id) }}</span>
            <Button
              type="button"
              variant="faded"
              icon="i-lucide-x"
              :label="text('REMOVE')"
              :aria-label="`${text('REMOVE')} ${queueName(id)}`"
              :data-remove-recording-policy-queue="id"
              @click="
                draft.queue_ids = draft.queue_ids.filter(value => value !== id);
                saved = false;
              "
            />
          </div>
          <div class="flex flex-wrap gap-2">
            <Button
              type="button"
              :label="t('JRC_CONTACT_CENTER.ADMIN.PREVIOUS')"
              :disabled="queueLoading || queuePage <= 1"
              data-recording-policy-queue-previous
              @click="
                queuePage -= 1;
                loadQueues();
              "
            /><Button
              type="button"
              :label="t('JRC_CONTACT_CENTER.ADMIN.NEXT')"
              :disabled="queueLoading || queuePage >= queuePages"
              data-recording-policy-queue-next
              @click="
                queuePage += 1;
                loadQueues();
              "
            />
          </div>
        </section>
        <label class="block">
          <span class="block">{{ text('NOTICE') }}</span>
          <textarea
            v-model="draft.notice"
            maxlength="1000"
            rows="3"
            class="mt-1 w-full min-w-0"
            data-recording-policy-notice
          />
        </label>
        <label class="block">
          <span class="block">{{ text('RETENTION') }}</span>
          <input
            v-model="draft.retention_days"
            type="text"
            inputmode="numeric"
            class="mt-1 w-full min-w-0"
            data-recording-policy-retention
          /><span class="mt-1 block break-words text-n-slate-11">{{
            text('RETENTION_HELP')
          }}</span>
        </label>
      </fieldset>
      <Button
        v-if="unitId"
        type="button"
        variant="faded"
        :label="text('RELOAD')"
        :disabled="busy"
        data-reload-recording-policy-draft
        @click="load"
      />
    </div>
    <template #footer>
      <div class="flex w-full flex-wrap gap-3">
        <Button
          type="button"
          color="slate"
          variant="faded"
          class="flex-1"
          :label="t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CLOSE')"
          :disabled="saving"
          data-close-recording-policy-draft
          @click="popup.close()"
        /><Button
          type="button"
          class="flex-1"
          :label="text('SAVE')"
          :disabled="!canSave"
          :is-loading="saving"
          data-save-recording-policy-draft
          @click="save"
        />
      </div>
    </template>
  </Dialog>
</template>
