<script setup>
import { computed, onMounted, onBeforeUnmount, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import IvrReferencePicker from './IvrReferencePicker.vue';
import IvrFlowEditor from './IvrFlowEditor.vue';
import { useIvrDraftEditor } from '../composables/useIvrDraftEditor';
import { IVR_BYTES_LIMIT } from '../helpers/ivrDraft';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  draftId: { type: [String, Number], default: null },
});
const emit = defineEmits(['close', 'saved']);
const { t, te } = useI18n();
const accountId = computed(() => props.accountId);
const editor = useIvrDraftEditor({ accountId, initialId: props.draftId });
const { draft, recordId, state, jsonText, jsonPending, revision, dirty, busy } =
  editor;
const dialog = ref(null);
const tab = ref('BUILDER');
const secondaryBusy = ref(false);
const discard = ref(false);
const archive = ref(false);
const notice = ref('');
const dtmf = ref('');
const simulation = ref(null);
const simulationLocal = ref('');
const simulationZone = ref('');
const calendarNodes = computed(() =>
  draft.value.definition.nodes.filter(node => node.type === 'calendar')
);
const simulationZones = computed(() => [
  ...new Set([
    ...calendarNodes.value
      .map(node => node.calendar_reference?.snapshot?.definition?.timezone)
      .filter(Boolean),
    'UTC',
  ]),
]);
const effectiveZone = computed({
  get: () =>
    simulationZones.value.includes(simulationZone.value)
      ? simulationZone.value
      : simulationZones.value[0],
  set: value => {
    simulationZone.value = value;
  },
});
const calendarInstant = () =>
  calendarNodes.value.length
    ? { local: simulationLocal.value, timezone: effectiveZone.value }
    : null;

const history = reactive({
  items: [],
  page: 1,
  pages: 0,
  loading: false,
  failed: false,
});
const deny = () => {
  state.denied = true;
  state.loaded = false;
  state.error = 'DENIED';
  simulation.value = null;
  history.items = [];
};
const locked = computed(() => editor.locked.value || secondaryBusy.value);
const canSave = computed(() => editor.canSave.value && !secondaryBusy.value);
const simulationFingerprint = () =>
  JSON.stringify([
    draft.value.unit_id,
    draft.value.definition,
    dtmf.value,
    recordId.value,
    calendarInstant(),
  ]);
const currentSimulation = computed(() =>
  !jsonPending.value &&
  simulation.value?.fingerprint === simulationFingerprint()
    ? simulation.value.data
    : null
);
const calText = key =>
  ({
    INSTANT: t('JRC_CONTACT_CENTER.IVR_CALENDAR.INSTANT'),
    TIMEZONE: t('JRC_CONTACT_CENTER.IVR_CALENDAR.TIMEZONE'),
  })[key];
const precedenceLabel = value =>
  ({
    exception: t('JRC_CONTACT_CENTER.IVR_CALENDAR.PRECEDENCES.exception'),
    holiday: t('JRC_CONTACT_CENTER.IVR_CALENDAR.PRECEDENCES.holiday'),
    weekly: t('JRC_CONTACT_CENTER.IVR_CALENDAR.PRECEDENCES.weekly'),
  })[value];
const date = value =>
  state.timezone
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
        timeZone: state.timezone,
      }).format(new Date(value))
    : value;
const text = (key, params = {}) =>
  t(`JRC_CONTACT_CENTER.LOCAL_IVR.${key}`, params);
const errorText = computed(() => {
  const key = state.error || notice.value;
  if (!key) return '';
  if (te(`JRC_CONTACT_CENTER.LOCAL_IVR.${key}`)) return text(key);
  if (te(`JRC_CONTACT_CENTER.LOCAL_IVR.ERRORS.${key}`))
    return text(`ERRORS.${key}`);
  return text('SAVE_FAILED');
});
let alive = true;
let downloadUrl = null;
const close = () => {
  if (busy.value || secondaryBusy.value) return;
  if (!discard.value && (dirty.value || state.uncertain)) {
    discard.value = true;
    return;
  }
  dialog.value.close();
};
const applyJson = () => {
  try {
    editor.applyJson(jsonText.value);
    notice.value = '';
  } catch {
    notice.value = 'IMPORT_ERROR';
  }
};
const importJson = async event => {
  const file = event.target.files?.[0];
  if (!file || locked.value) return;
  secondaryBusy.value = true;
  notice.value = '';
  try {
    if (file.size > IVR_BYTES_LIMIT || !/\.json$/i.test(file.name))
      throw new Error('invalid_ivr_graph');
    const content = await file.text();
    if (alive) editor.applyJson(content);
  } catch {
    if (alive) notice.value = 'IMPORT_ERROR';
  } finally {
    if (alive) {
      secondaryBusy.value = false;
      event.target.value = '';
    }
  }
};
const save = async (status = 'draft', retry = false) => {
  if (secondaryBusy.value) return;
  notice.value = '';
  archive.value = false;
  if (await editor.save(status, retry)) {
    if (alive) emit('saved');
  }
};
const preview = async () => {
  if (locked.value || jsonPending.value) return;
  const fingerprint = simulationFingerprint();
  secondaryBusy.value = true;
  notice.value = '';
  simulation.value = null;
  try {
    const payload = {
      unit_id: draft.value.unit_id,
      definition: draft.value.definition,
      dtmf: dtmf.value,
    };
    if (calendarNodes.value.length) {
      payload.at = calendarInstant();
      if (recordId.value) payload.origin_draft_id = recordId.value;
    }
    const response = await API.previewIvrDraft(props.accountId, payload);
    if (alive && fingerprint === simulationFingerprint())
      simulation.value = { fingerprint, data: response.data.simulation };
  } catch (error) {
    if (alive && [401, 403, 404].includes(error?.response?.status)) deny();
    else if (alive)
      notice.value = error?.response?.data?.error || 'SAVE_FAILED';
  } finally {
    if (alive) secondaryBusy.value = false;
  }
};
const loadHistory = async (page = 1) => {
  if (!recordId.value || history.loading) return;
  history.loading = true;
  history.failed = false;
  history.items = [];
  try {
    const response = await API.ivrHistory(
      props.accountId,
      recordId.value,
      page
    );
    if (!alive) return;
    history.items = response.data.items;
    history.page = response.data.meta.page;
    history.pages = response.data.meta.pages;
  } catch {
    if (alive) history.failed = true;
  } finally {
    if (alive) history.loading = false;
  }
};
const useVersion = async version => {
  if (locked.value || jsonPending.value) return;
  secondaryBusy.value = true;
  notice.value = '';
  try {
    const response = await API.ivrVersion(
      props.accountId,
      recordId.value,
      version.revision
    );
    if (!alive) return;
    editor.applyJson(JSON.stringify(response.data.item.definition));
    draft.value.name = response.data.item.name;
    tab.value = 'BUILDER';
  } catch {
    if (alive) notice.value = 'IMPORT_ERROR';
  } finally {
    if (alive) secondaryBusy.value = false;
  }
};
const exportVersion = async version => {
  if (locked.value) return;
  secondaryBusy.value = true;
  notice.value = '';
  try {
    const response = await API.exportIvrDraft(
      props.accountId,
      recordId.value,
      version.revision
    );
    if (!alive) return;
    if (downloadUrl) URL.revokeObjectURL(downloadUrl);
    downloadUrl = URL.createObjectURL(response.data);
    const link = document.createElement('a');
    link.href = downloadUrl;
    link.download = `ura-local-${recordId.value}-v${version.revision}.json`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    const url = downloadUrl;
    setTimeout(() => {
      URL.revokeObjectURL(url);
      if (downloadUrl === url) downloadUrl = null;
    }, 500);
  } catch {
    if (alive) notice.value = 'SAVE_FAILED';
  } finally {
    if (alive) secondaryBusy.value = false;
  }
};
const chooseTab = value => {
  tab.value = value;
  if (value === 'HISTORY') loadHistory();
};
onMounted(() => {
  dialog.value.open();
  if (props.draftId) editor.load();
});
onBeforeUnmount(() => {
  alive = false;
  if (downloadUrl) URL.revokeObjectURL(downloadUrl);
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="text('OPEN')"
    :description="text('LOCAL_ONLY')"
    width="5xl"
    contained
    :use-form="false"
    :dismissible="!busy && !secondaryBusy && !dirty && !state.uncertain"
    :close-on-click-outside="false"
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-4 text-n-slate-12" data-ivr-editor>
      <p
        v-if="errorText"
        role="alert"
        class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
      >
        {{ errorText }}
      </p>
      <p
        v-if="state.saved"
        data-ivr-saved
        role="status"
        class="rounded-lg bg-n-teal-2 p-3 text-sm text-n-teal-11"
      >
        {{ text('SAVED') }}
      </p>
      <p v-if="state.loading" role="status" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <button
        v-if="recordId && !state.loaded"
        type="button"
        :disabled="busy"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
        @click="editor.load"
      >
        {{ text('RELOAD') }}
      </button>
      <template v-if="state.loaded">
        <fieldset :disabled="locked" class="grid min-w-0 gap-3 sm:grid-cols-2">
          <div class="min-w-0">
            <label
              for="ivr-name"
              class="mb-1 block w-full text-sm text-n-slate-12"
              >{{ text('NAME') }} </label
            ><input
              id="ivr-name"
              v-model="draft.name"
              type="text"
              maxlength="160"
              required
              class="mt-1 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-n-slate-12"
              @input="editor.changed"
            />
          </div>
          <div class="min-w-0">
            <label for="ivr-unit" class="mb-1 block text-sm text-n-slate-12">{{
              t('JRC_CONTACT_CENTER.ADMIN.UNIT')
            }}</label>
            <IvrReferencePicker
              :account-id="accountId"
              resource="units"
              input-id="ivr-unit"
              :model-value="draft.unit_id"
              :disabled="locked || Boolean(recordId)"
              @update:model-value="editor.setUnit"
            />
          </div>
        </fieldset>
        <nav class="flex flex-wrap gap-2" :aria-label="text('TITLE')">
          <button
            v-for="name in ['BUILDER', 'JSON', 'SIMULATION', 'HISTORY']"
            :key="name"
            type="button"
            role="tab"
            :aria-selected="tab === name"
            :disabled="name === 'HISTORY' && !recordId"
            class="rounded-lg border px-3 py-2 text-sm disabled:opacity-50"
            :class="
              tab === name
                ? 'border-n-blue-7 bg-n-blue-2 text-n-blue-11'
                : 'border-n-weak bg-n-solid-1 text-n-slate-11'
            "
            @click="chooseTab(name)"
          >
            {{ text(name) }}
          </button>
        </nav>
        <p
          v-if="jsonPending"
          role="status"
          class="rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11"
        >
          {{ text('JSON_PENDING') }}
        </p>
        <IvrFlowEditor
          v-show="tab === 'BUILDER'"
          :account-id="accountId"
          :unit-id="draft.unit_id"
          :model-value="draft.definition"
          :disabled="locked || jsonPending"
          @update:model-value="editor.setGraph"
          @denied="deny"
        />
        <section v-show="tab === 'JSON'" class="min-w-0 space-y-3">
          <label for="ivr-json" class="block text-sm text-n-slate-12">{{
            text('DEFINITION')
          }}</label>
          <textarea
            id="ivr-json"
            v-model="jsonText"
            rows="14"
            spellcheck="false"
            :disabled="locked"
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-3 font-mono text-xs text-n-slate-12"
            @input="
              jsonPending = true;
              editor.changed();
            "
          />
          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              :disabled="locked || !jsonPending"
              class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
              @click="applyJson"
            >
              {{ text('APPLY_JSON') }}
            </button>
            <button
              type="button"
              :disabled="locked || !jsonPending"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
              @click="editor.discardJson"
            >
              {{ text('DISCARD_JSON') }}
            </button>
            <label
              for="ivr-import"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
              >{{ text('IMPORT') }}</label
            >
            <input
              id="ivr-import"
              type="file"
              accept=".json,application/json"
              :disabled="locked"
              class="max-w-full text-sm text-n-slate-12"
              @change="importJson"
            />
          </div>
          <p class="text-xs text-n-slate-11">{{ text('IMPORT_HINT') }}</p>
        </section>
        <section v-show="tab === 'SIMULATION'" class="min-w-0 space-y-3">
          <p class="text-sm text-n-slate-11">{{ text('SIMULATION_HINT') }}</p>
          <section
            v-if="calendarNodes.length"
            class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 bg-n-blue-2 p-3"
            data-ivr-calendar-instant
          >
            <p class="break-words text-sm text-n-slate-11">
              {{ t('JRC_CONTACT_CENTER.IVR_CALENDAR.INSTANT_HINT') }}
            </p>
            <label
              for="ivr-simulation-local"
              class="block text-sm text-n-slate-12"
            >
              {{ calText('INSTANT') }}
            </label>
            <input
              id="ivr-simulation-local"
              v-model="simulationLocal"
              type="datetime-local"
              step="1"
              :disabled="locked"
              required
              class="h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12 [color-scheme:light] dark:[color-scheme:dark]"
            />
            <label
              for="ivr-simulation-zone"
              class="block text-sm text-n-slate-12"
            >
              {{ calText('TIMEZONE') }}
            </label>
            <select
              id="ivr-simulation-zone"
              v-model="effectiveZone"
              :disabled="locked"
              class="h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
            >
              <option v-for="zone in simulationZones" :key="zone" :value="zone">
                {{ zone }}
              </option>
            </select>
          </section>
          <label for="ivr-dtmf" class="block text-sm text-n-slate-12">{{
            text('DTMF')
          }}</label>
          <input
            id="ivr-dtmf"
            v-model="dtmf"
            type="text"
            maxlength="128"
            :disabled="locked"
            inputmode="tel"
            class="h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 text-n-slate-12"
            @input="simulation = null"
          />
          <button
            type="button"
            :disabled="locked || jsonPending"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
            data-ivr-simulate
            @click="preview"
          >
            {{ text('SIMULATE') }}
          </button>
          <div
            v-if="currentSimulation"
            role="status"
            class="space-y-2 rounded-lg border border-n-teal-6 bg-n-teal-2 p-3 text-sm text-n-slate-12"
            data-ivr-simulation
          >
            <p>{{ text(`OUTCOMES.${currentSimulation.outcome}`) }}</p>
            <p v-if="currentSimulation.queue_id">
              {{ t('JRC_CONTACT_CENTER.ADMIN.QUEUE') }} #{{
                currentSimulation.queue_id
              }}
            </p>
            <ol class="space-y-1">
              <li
                v-for="(row, index) in currentSimulation.trace"
                :key="index"
                class="break-all"
              >
                {{ row.node_id }} · {{ text(`TYPES.${row.type}`)
                }}<span v-if="row.event">
                  · {{ text(`EVENTS.${row.event}`) }}</span
                >
                <p
                  v-if="row.calendar"
                  class="break-words text-xs"
                  data-ivr-calendar-decision
                >
                  {{
                    t('JRC_CONTACT_CENTER.IVR_CALENDAR.DECISION', {
                      state: row.calendar.open
                        ? t('JRC_CONTACT_CENTER.IVR_CALENDAR.OPEN')
                        : t('JRC_CONTACT_CENTER.IVR_CALENDAR.CLOSED'),
                      instant: row.calendar.instant,
                      timezone: row.calendar.timezone,
                      precedence: precedenceLabel(row.calendar.precedence),
                    })
                  }}
                </p>
              </li>
            </ol>
            <p>{{ text('LOCAL_ONLY') }}</p>
          </div>
        </section>
        <section v-show="tab === 'HISTORY'" class="min-w-0 space-y-3">
          <p class="text-sm text-n-slate-11">{{ text('HISTORY_HINT') }}</p>
          <p v-if="history.loading" role="status">
            {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
          </p>
          <p v-if="history.failed" role="alert" class="text-n-ruby-11">
            {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
          </p>
          <article
            v-for="row in history.items"
            :key="row.revision"
            :data-ivr-history-revision="row.revision"
            class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3 text-sm text-n-slate-12"
          >
            <p class="break-words">
              {{ row.name }} · {{ text(`STATES.${row.status}`) }} ·
              {{ t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION') }}
              {{ row.revision }}
            </p>
            <p>
              {{ text('HISTORY_ACTOR', { id: row.actor_user_id }) }} ·
              {{ date(row.created_at) }}
            </p>
            <p class="break-all text-xs text-n-slate-11">
              {{ text('INTEGRITY') }}: {{ row.integrity_sha256 }}
            </p>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                :disabled="locked || jsonPending"
                class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
                @click="useVersion(row)"
              >
                {{ text('LOAD_VERSION') }}
              </button>
              <button
                type="button"
                :disabled="locked"
                class="rounded-lg border border-n-weak px-3 py-2"
                @click="exportVersion(row)"
              >
                {{ text('EXPORT') }}
              </button>
            </div>
          </article>
          <div
            class="flex flex-wrap items-center gap-2 text-sm text-n-slate-12"
          >
            <button
              type="button"
              :disabled="history.loading || history.page <= 1"
              class="rounded-lg border border-n-weak px-3 py-2"
              @click="loadHistory(history.page - 1)"
            >
              {{ text('PREVIOUS') }}
            </button>
            <span>{{
              text('PAGE', { page: history.page, pages: history.pages })
            }}</span>
            <button
              type="button"
              :disabled="history.loading || history.page >= history.pages"
              class="rounded-lg border border-n-weak px-3 py-2"
              @click="loadHistory(history.page + 1)"
            >
              {{ text('NEXT') }}
            </button>
            <button
              v-if="history.failed"
              type="button"
              :disabled="history.loading"
              class="rounded-lg border border-n-weak px-3 py-2"
              @click="loadHistory(history.page)"
            >
              {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
            </button>
          </div>
        </section>
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="draft"
          resource="ivr_drafts"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="revision.review"
        />
      </template>
      <section
        v-if="discard || archive"
        data-ivr-confirmation
        class="space-y-3 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-slate-12"
      >
        <p>{{ text(discard ? 'CONFIRM_DISCARD' : 'ARCHIVE_HINT') }}</p>
        <button
          type="button"
          :disabled="busy || secondaryBusy"
          class="rounded-lg border border-n-ruby-6 px-3 py-2 text-n-ruby-11"
          @click="discard ? close() : save('archived')"
        >
          {{ text(discard ? 'DISCARD' : 'ARCHIVE') }}
        </button>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="
            discard = false;
            archive = false;
          "
        >
          {{ text('CANCEL') }}
        </button>
      </section>
    </div>
    <template #footer>
      <div class="flex w-full flex-wrap items-center justify-between gap-2">
        <button
          type="button"
          :disabled="busy || secondaryBusy"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
          @click="close"
        >
          {{ text('CLOSE') }}
        </button>
        <button
          v-if="recordId && draft.status === 'draft'"
          type="button"
          :disabled="!canSave || dirty"
          class="rounded-lg border border-n-amber-6 px-3 py-2 text-sm text-n-amber-11"
          @click="archive = true"
        >
          {{ text('ARCHIVE') }}
        </button>
        <button
          v-if="state.uncertain"
          type="button"
          :disabled="busy || secondaryBusy"
          class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white"
          @click="save('draft', true)"
        >
          {{ text('RETRY_SAVE') }}
        </button>
        <button
          v-else
          type="button"
          :disabled="!canSave"
          class="rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
          data-ivr-save
          @click="save()"
        >
          {{ text(draft.status === 'archived' ? 'RESTORE' : 'SAVE') }}
        </button>
      </div>
    </template>
  </Dialog>
</template>
