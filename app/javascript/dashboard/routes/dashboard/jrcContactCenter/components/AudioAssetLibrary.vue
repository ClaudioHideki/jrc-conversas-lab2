<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import AudioFolderPicker from './AudioFolderPicker.vue';
import AudioInspectionHistory from './AudioInspectionHistory.vue';
import { useAudioAssetEditor } from '../composables/useAudioAssetEditor';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
  unitId: { type: String, required: true },
  folderId: { type: String, default: '' },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.AUDIO_FILES.TITLE'),
  LIMITS: t('JRC_CONTACT_CENTER.AUDIO_FILES.LIMITS'),
  SEARCH: t('JRC_CONTACT_CENTER.AUDIO_FILES.SEARCH'),
  FILTER: t('JRC_CONTACT_CENTER.AUDIO_FILES.FILTER'),
  CLEAR: t('JRC_CONTACT_CENTER.AUDIO_FILES.CLEAR'),
  NEW: t('JRC_CONTACT_CENTER.AUDIO_FILES.NEW'),
  LOADING: t('JRC_CONTACT_CENTER.AUDIO_FILES.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_FILES.ERROR'),
  EMPTY: t('JRC_CONTACT_CENTER.AUDIO_FILES.EMPTY'),
  NO_ACCESS: t('JRC_CONTACT_CENTER.AUDIO_FILES.NO_ACCESS'),
  VERSION: t('JRC_CONTACT_CENTER.AUDIO_FILES.VERSION'),
  BYTES: t('JRC_CONTACT_CENTER.AUDIO_FILES.BYTES'),
  EDIT: t('JRC_CONTACT_CENTER.AUDIO_FILES.EDIT'),
  REPLACE: t('JRC_CONTACT_CENTER.AUDIO_FILES.REPLACE'),
  HISTORY: t('JRC_CONTACT_CENTER.AUDIO_FILES.HISTORY'),
  NOT_VERIFIED: t('JRC_CONTACT_CENTER.AUDIO_FILES.NOT_VERIFIED'),
  PAGINATION: t('JRC_CONTACT_CENTER.AUDIO_FILES.PAGINATION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.AUDIO_FILES.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.AUDIO_FILES.NEXT'),
  TOTAL: t('JRC_CONTACT_CENTER.AUDIO_FILES.TOTAL'),
  PAGE: t('JRC_CONTACT_CENTER.AUDIO_FILES.PAGE'),
  SAVE: t('JRC_CONTACT_CENTER.AUDIO_FILES.SAVE'),
  CANCEL: t('JRC_CONTACT_CENTER.AUDIO_FILES.CANCEL'),
  NAME: t('JRC_CONTACT_CENTER.AUDIO_FILES.NAME'),
  DESCRIPTION: t('JRC_CONTACT_CENTER.AUDIO_FILES.DESCRIPTION'),
  PURPOSE: t('JRC_CONTACT_CENTER.AUDIO_FILES.PURPOSE'),
  FILE: t('JRC_CONTACT_CENTER.AUDIO_FILES.FILE'),
  MAX_BYTES: t('JRC_CONTACT_CENTER.AUDIO_FILES.MAX_BYTES'),
  FORMAT: t('JRC_CONTACT_CENTER.AUDIO_FILES.FORMAT'),
  SOURCE: t('JRC_CONTACT_CENTER.AUDIO_FILES.SOURCE'),
  CHECKSUM: t('JRC_CONTACT_CENTER.AUDIO_FILES.CHECKSUM'),
  PAGE_SIZE: t('JRC_CONTACT_CENTER.AUDIO_FILES.PAGE_SIZE'),
  INVALID_FILE: t('JRC_CONTACT_CENTER.AUDIO_FILES.INVALID_FILE'),
  REVIEW: t('JRC_CONTACT_CENTER.AUDIO_FILES.REVIEW'),
  SAVE_ERROR: t('JRC_CONTACT_CENTER.AUDIO_FILES.SAVE_ERROR'),
  RECEIPT_ERROR: t('JRC_CONTACT_CENTER.AUDIO_FILES.RECEIPT_ERROR'),
  INSPECTION_UNAVAILABLE: t(
    'JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_UNAVAILABLE'
  ),
  DETAILS: t('JRC_CONTACT_CENTER.AUDIO_FILES.DETAILS'),
  CLOSE_DETAILS: t('JRC_CONTACT_CENTER.AUDIO_FILES.CLOSE_DETAILS'),
  FOLDER: t('JRC_CONTACT_CENTER.AUDIO_FILES.FOLDER'),
  ROOT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.ROOT'),
  ACTIONS: t('JRC_CONTACT_CENTER.AUDIO_FILES.ACTIONS'),
  PRIVATE: t('JRC_CONTACT_CENTER.AUDIO_FILES.PRIVATE'),
  SOURCE_UPLOAD: t('JRC_CONTACT_CENTER.AUDIO_FILES.SOURCE_UPLOAD'),
  SOURCE_CAPTURE: t('JRC_CONTACT_CENTER.AUDIO_FILES.SOURCE_CAPTURE'),
  UNKNOWN_SOURCE: t('JRC_CONTACT_CENTER.AUDIO_FILES.UNKNOWN_SOURCE'),
}));
const label = key => labels.value[key];
const route = useRoute();
const router = useRouter();
const sourceLabel = kind =>
  ({
    user_upload: label('SOURCE_UPLOAD'),
    browser_capture: label('SOURCE_CAPTURE'),
  })[kind] || label('UNKNOWN_SOURCE');
const currentUser = useMapGetter('getCurrentUser');
const details = ref(null);
const detailsLoading = ref(false);
const detailsError = ref(false);
let detailsGeneration = 0;
const clearDetails = () => {
  detailsGeneration += 1;
  details.value = null;
  detailsLoading.value = false;
  detailsError.value = false;
};
const fileDescription = (name, size) =>
  [name, `${size} ${label('BYTES')}`].join(' · ');
const versionDescription = version =>
  [
    `${label('VERSION')} ${version.number}`,
    fileDescription(version.file_name, version.byte_size),
  ].join(' · ');
const versionOrigin = version =>
  [version.content_type, version.created_at, version.created_by_name].join(
    ' · '
  );
const pageDescription = (count, number) =>
  `${label('TOTAL')} ${count} · ${label('PAGE')} ${number}`;
const items = ref([]);
const meta = ref({ total: 0, pages: 0 });
const maxBytes = ref(0);
const loading = ref(false);
const error = ref(false);
const q = ref('');
const history = ref([]);
const historyMeta = ref({ total: 0, pages: 0 });
const historyPage = ref(1);
const historyItem = ref(null);
const historyLoading = ref(false);
const historyError = ref(false);
const historyDialog = ref(null);
const page = computed(() =>
  Math.max(
    1,
    Math.min(1000000, Math.floor(Number(route.query.audio_file_page)) || 1)
  )
);
const pageSizes = [5, 10, 20, 50];
const perPage = computed(() => {
  const size = Number(route.query.audio_file_size);
  return pageSizes.includes(size) ? size : 20;
});
const canManage = computed(
  () =>
    props.context.capabilities?.configure === true &&
    (props.context.units || []).some(row => String(row.id) === props.unitId)
);
let generation = 0;
let historyGeneration = 0;
const clearHistory = () => {
  historyGeneration += 1;
  history.value = [];
  historyItem.value = null;
  historyMeta.value = { total: 0, pages: 0 };
  historyLoading.value = false;
};
const forget = () => {
  generation += 1;
  clearDetails();
  items.value = [];
  meta.value = { total: 0, pages: 0 };
  maxBytes.value = 0;
  loading.value = false;
  historyDialog.value?.close();
  clearHistory();
};
let editor;
const denied = () => {
  forget();
  editor.clear();
  error.value = true;
  emit('denied');
};
const openDetails = async row => {
  if (!canManage.value) return;
  clearDetails();
  const current = detailsGeneration;
  const origin = JSON.stringify([
    props.accountId,
    props.unitId,
    props.folderId,
  ]);
  detailsLoading.value = true;
  try {
    const response = await API.audioAsset(props.accountId, row.id);
    if (
      current !== detailsGeneration ||
      origin !==
        JSON.stringify([props.accountId, props.unitId, props.folderId]) ||
      !canManage.value
    )
      return;
    const record = response.data.item;
    if (
      String(response.data.account_id) !== String(props.accountId) ||
      record?.id !== row.id ||
      record.unit_id !== props.unitId
    )
      throw new Error('Invalid current institutional audio details');
    details.value = record;
  } catch (failure) {
    if (current !== detailsGeneration) return;
    if ([401, 403, 404].includes(failure?.response?.status)) denied();
    else detailsError.value = true;
  } finally {
    if (current === detailsGeneration) detailsLoading.value = false;
  }
};
const load = async () => {
  clearDetails();
  generation += 1;
  const version = generation;
  items.value = [];
  meta.value = { total: 0, pages: 0 };
  maxBytes.value = 0;
  loading.value = false;
  error.value = false;
  if (!canManage.value) return;
  loading.value = true;
  try {
    const response = await API.audioAssets(props.accountId, {
      unit_id: props.unitId,
      folder_id: props.folderId,
      q: route.query.audio_file_q || '',
      page: page.value,
      per_page: perPage.value,
    });
    if (version !== generation) return;
    const lastPage = Math.max(1, response.data.meta.pages);
    if (page.value > lastPage) {
      await router.replace({
        query: { ...route.query, audio_file_page: lastPage },
      });
      return;
    }
    items.value = response.data.items;
    meta.value = response.data.meta;
    maxBytes.value = response.data.max_upload_bytes;
  } catch (failure) {
    if (version === generation) {
      if ([401, 403, 404].includes(failure?.response?.status)) denied();
      else error.value = true;
    }
  } finally {
    if (version === generation) loading.value = false;
  }
};
editor = useAudioAssetEditor({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  folderId: computed(() => props.folderId),
  canManage,
  maxBytes,
  onSaved: load,
  onDenied: denied,
});
const {
  dialog,
  mode,
  draft,
  file,
  submission,
  saving,
  opening,
  error: editorError,
  reviewedDraft,
  reviewed,
  canSave,
} = editor;
const revision = editor.revision;
const folderLoading = ref(false);
const saveEditor = () => {
  if (mode.value !== 'replace' && folderLoading.value) return;
  editor.save();
};
const filter = values =>
  router.replace({ query: { ...route.query, ...values } });
const loadHistory = async () => {
  historyGeneration += 1;
  const version = historyGeneration;
  history.value = [];
  historyError.value = false;
  if (!historyItem.value || !canManage.value) return;
  historyLoading.value = true;
  try {
    const response = await API.audioVersions(
      props.accountId,
      historyItem.value.id,
      { page: historyPage.value, per_page: 10 }
    );
    if (version !== historyGeneration) return;
    history.value = response.data.items;
    historyMeta.value = response.data.meta;
  } catch (failure) {
    if (version === historyGeneration) {
      if ([401, 403, 404].includes(failure?.response?.status)) denied();
      else historyError.value = true;
    }
  } finally {
    if (version === historyGeneration) historyLoading.value = false;
  }
};
const openHistory = row => {
  if (!canManage.value || saving.value || opening.value) return;
  clearDetails();
  clearHistory();
  historyItem.value = row;
  const firstPage = historyPage.value === 1;
  historyPage.value = 1;
  historyDialog.value.open();
  if (firstPage) loadHistory();
};
watch(historyPage, loadHistory);
watch(
  [
    () => props.accountId,
    () => props.unitId,
    () => props.folderId,
    canManage,
    page,
    perPage,
    () => route.query.audio_file_q,
    () => {
      const user = currentUser.value;
      const member = user?.accounts?.find(
        row => String(row.id) === String(props.accountId)
      );
      return JSON.stringify([
        user?.id,
        member?.role,
        member?.custom_role_id,
        member?.contact_center_eligible,
        [...(member?.permissions || [])].sort(),
        (props.context.units || []).map(row => String(row.id)).sort(),
      ]);
    },
  ],
  () => {
    forget();
    editor.clear();
    q.value = route.query.audio_file_q || '';
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  forget();
  editor.close();
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 border-t border-n-weak pt-5"
    data-audio-asset-library
  >
    <h3 class="text-lg font-semibold text-n-slate-12">{{ label('TITLE') }}</h3>
    <p
      role="status"
      class="rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
      data-audio-file-limits
    >
      {{ label('LIMITS') }}
    </p>
    <form
      v-if="canManage"
      class="flex flex-wrap items-end gap-3"
      @submit.prevent="
        filter({ audio_file_q: q || undefined, audio_file_page: 1 })
      "
    >
      <label class="w-full min-w-0 text-sm text-n-slate-12 sm:flex-1">
        <span>{{ label('SEARCH') }}</span>
        <input
          v-model="q"
          maxlength="100"
          data-audio-file-search
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <button
        type="submit"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
      >
        {{ label('FILTER') }}
      </button>
      <label class="block min-w-0 text-sm text-n-slate-12">
        <span>{{ label('PAGE_SIZE') }}</span>
        <select
          :value="perPage"
          data-audio-file-size
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          @change="
            filter({
              audio_file_size: Number($event.target.value),
              audio_file_page: 1,
            })
          "
        >
          <option v-for="size in pageSizes" :key="size" :value="size">
            {{ size }}
          </option>
        </select>
      </label>
      <button
        type="button"
        class="rounded-lg px-3 py-2 text-sm text-n-blue-11"
        @click="filter({ audio_file_q: undefined, audio_file_page: 1 })"
      >
        {{ label('CLEAR') }}
      </button>
      <button
        type="button"
        :disabled="loading || !maxBytes || saving || opening"
        data-new-audio-asset
        class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm text-white"
        @click="editor.open('upload')"
      >
        {{ label('NEW') }}
      </button>
    </form>
    <p v-if="!canManage" class="text-sm text-n-slate-11">
      {{ label('NO_ACCESS') }}
    </p>
    <p
      v-else-if="loading || opening"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ label('LOADING') }}
    </p>
    <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ label('ERROR') }}
    </p>
    <p v-else-if="!items.length" class="text-sm text-n-slate-11">
      {{ label('EMPTY') }}
    </p>
    <div
      v-else
      class="grid min-w-0 grid-cols-1 items-start gap-4"
      :class="details ? 'xl:grid-cols-[minmax(0,1fr)_minmax(0,20rem)]' : ''"
      data-audio-files-and-details
    >
      <div
        class="max-h-[36rem] min-w-0 overflow-auto overscroll-contain rounded-xl border border-n-weak"
        data-audio-file-scroll
      >
        <table class="w-full table-fixed text-left text-sm text-n-slate-12">
          <caption class="sr-only">
            {{
              label('TITLE')
            }}
          </caption>
          <thead class="sticky top-0 bg-n-solid-2">
            <tr>
              <th scope="col" class="w-1/2 p-3">{{ label('NAME') }}</th>
              <th scope="col" class="w-1/4 p-3">{{ label('VERSION') }}</th>
              <th scope="col" class="w-1/4 p-3">{{ label('ACTIONS') }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak bg-n-solid-1">
            <tr
              v-for="row in items"
              :key="row.id"
              :data-audio-asset="row.id"
              :aria-selected="details?.id === row.id"
              :class="details?.id === row.id ? 'bg-n-blue-2' : ''"
            >
              <td class="min-w-0 break-words p-3 align-top">
                <button
                  type="button"
                  :data-audio-asset-details-open="row.id"
                  class="max-w-full break-words text-left font-semibold text-n-blue-11"
                  @click="openDetails(row)"
                >
                  {{ row.name }}
                </button>
                <p class="mt-1 break-words text-n-slate-11">
                  {{ row.folder_name || label('ROOT') }}
                </p>
                <p
                  v-if="row.description"
                  class="mt-1 break-words text-n-slate-11"
                >
                  {{ row.description }}
                </p>
              </td>
              <td class="min-w-0 break-words p-3 align-top text-n-slate-11">
                <p v-if="row.latest_version">
                  {{ versionDescription(row.latest_version) }}
                </p>
                <p v-if="row.latest_version" class="mt-1 break-words">
                  {{ row.latest_version.content_type }}
                </p>
                <p class="mt-2 text-n-amber-11">{{ label('PRIVATE') }}</p>
              </td>
              <td class="min-w-0 break-words p-3 align-top">
                <div class="flex flex-wrap gap-2">
                  <button
                    type="button"
                    :disabled="saving || opening"
                    :data-edit-audio-asset="row.id"
                    class="max-w-full break-words rounded-lg border border-n-blue-6 px-2 py-2 text-n-blue-11"
                    @click="editor.open('edit', row)"
                  >
                    {{ label('EDIT') }}
                  </button>
                  <button
                    type="button"
                    :disabled="saving || opening"
                    :data-replace-audio-asset="row.id"
                    class="max-w-full break-words rounded-lg border border-n-blue-6 px-2 py-2 text-n-blue-11"
                    @click="editor.open('replace', row)"
                  >
                    {{ label('REPLACE') }}
                  </button>
                  <button
                    type="button"
                    :disabled="saving || opening"
                    :data-audio-asset-history="row.id"
                    class="max-w-full break-words rounded-lg border border-n-blue-6 px-2 py-2 text-n-blue-11"
                    @click="openHistory(row)"
                  >
                    {{ label('HISTORY') }}
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <aside
        v-if="details"
        class="max-h-[48rem] min-w-0 space-y-4 overflow-y-auto overscroll-contain rounded-xl border border-n-weak bg-n-solid-1 p-4 text-sm text-n-slate-12"
        data-audio-asset-details
        :aria-label="label('DETAILS')"
      >
        <div class="flex items-start justify-between gap-3">
          <h4 class="break-words font-semibold">{{ label('DETAILS') }}</h4>
          <button
            type="button"
            class="shrink-0 text-n-blue-11"
            data-close-audio-details
            @click="clearDetails"
          >
            {{ label('CLOSE_DETAILS') }}
          </button>
        </div>
        <dl class="min-w-0 space-y-3">
          <div>
            <dt class="text-n-slate-11">{{ label('NAME') }}</dt>
            <dd class="break-words">{{ details.name }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-11">{{ label('FOLDER') }}</dt>
            <dd class="break-words">
              {{ details.folder_name || label('ROOT') }}
            </dd>
          </div>
          <div v-if="details.description">
            <dt class="text-n-slate-11">{{ label('DESCRIPTION') }}</dt>
            <dd class="break-words">{{ details.description }}</dd>
          </div>
          <div v-if="details.purpose">
            <dt class="text-n-slate-11">{{ label('PURPOSE') }}</dt>
            <dd class="break-words">{{ details.purpose }}</dd>
          </div>
          <template v-if="details.latest_version">
            <div>
              <dt class="text-n-slate-11">{{ label('SOURCE') }}</dt>
              <dd class="break-words">
                {{ sourceLabel(details.latest_version.source_kind) }}
              </dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ label('VERSION') }}</dt>
              <dd class="break-words">
                {{ versionDescription(details.latest_version) }}
              </dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ label('FORMAT') }}</dt>
              <dd class="break-words">
                {{ details.latest_version.content_type }}
              </dd>
            </div>
            <div>
              <dt class="text-n-slate-11">{{ label('CHECKSUM') }}</dt>
              <dd class="break-all">{{ details.latest_version.sha256 }}</dd>
            </div>
          </template>
        </dl>
        <p class="break-words text-n-amber-11">{{ label('NOT_VERIFIED') }}</p>
        <AudioInspectionHistory
          v-if="details.latest_version"
          :key="`${details.id}:${details.latest_version.id}`"
          :account-id="accountId"
          :asset-id="details.id"
          :version="details.latest_version"
          :can-manage="canManage"
          @denied="denied"
        />
      </aside>
    </div>
    <p v-if="detailsLoading" role="status" class="text-sm text-n-slate-11">
      {{ label('LOADING') }}
    </p>
    <p v-if="detailsError" role="alert" class="text-sm text-n-ruby-11">
      {{ label('ERROR') }}
    </p>
    <nav
      v-if="meta.pages > 1"
      :aria-label="label('PAGINATION')"
      class="flex flex-wrap gap-3 text-sm text-n-slate-12"
    >
      <button
        type="button"
        :disabled="loading || page <= 1"
        @click="filter({ audio_file_page: page - 1 })"
      >
        {{ label('PREVIOUS') }}
      </button>
      <span data-audio-file-total>{{ pageDescription(meta.total, page) }}</span>
      <button
        type="button"
        :disabled="loading || page >= meta.pages"
        @click="filter({ audio_file_page: page + 1 })"
      >
        {{ label('NEXT') }}
      </button>
    </nav>
    <Dialog
      ref="dialog"
      contained
      use-form
      :title="
        label(mode === 'upload' ? 'NEW' : mode === 'edit' ? 'EDIT' : 'REPLACE')
      "
      :confirm-button-label="label('SAVE')"
      :cancel-button-label="label('CANCEL')"
      :disable-confirm-button="
        !canSave || (mode !== 'replace' && folderLoading)
      "
      :is-loading="saving"
      :dismissible="!saving"
      @confirm="saveEditor"
      @close="editor.close"
    >
      <div
        class="min-w-0 space-y-4 text-sm text-n-slate-12"
        data-audio-asset-editor
      >
        <p class="break-words text-n-amber-11">{{ label('LIMITS') }}</p>
        <p v-if="editorError" role="alert" class="text-n-ruby-11">
          {{ label(editorError) }}
        </p>
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="draft"
          resource="audio_assets"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="revision.review"
        />
        <template v-if="mode !== 'replace'">
          <label class="block min-w-0">
            <span>{{ label('NAME') }}</span>
            <input
              v-model="draft.name"
              :disabled="saving || Boolean(submission)"
              maxlength="120"
              required
              data-audio-asset-name
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
          <label class="block min-w-0">
            <span>{{ label('DESCRIPTION') }}</span>
            <textarea
              v-model="draft.description"
              :disabled="saving || Boolean(submission)"
              maxlength="1000"
              rows="3"
              data-audio-asset-description
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
          <label class="block min-w-0">
            <span>{{ label('PURPOSE') }}</span>
            <input
              v-model="draft.purpose"
              :disabled="saving || Boolean(submission)"
              maxlength="160"
              data-audio-asset-purpose
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
          <AudioFolderPicker
            v-model="draft.folder_id"
            :account-id="accountId"
            :unit-id="unitId"
            :current-name="editor.selected.value?.folder_name || ''"
            :disabled="saving || Boolean(submission)"
            @loading="folderLoading = $event"
            @denied="denied"
          />
        </template>
        <template v-if="mode !== 'edit'">
          <label class="block min-w-0 break-words">
            <span>{{ label('FILE') }}</span>
            <input
              type="file"
              accept="audio/wav,audio/x-wav,audio/mpeg,audio/ogg,audio/mp4,.wav,.mp3,.ogg,.m4a"
              :disabled="saving || Boolean(submission)"
              data-audio-asset-file
              class="mt-1 block w-full min-w-0 max-w-full text-sm"
              @change="editor.chooseFile"
            />
          </label>
          <p class="break-words">{{ label('MAX_BYTES') }} {{ maxBytes }}</p>
          <p v-if="file" class="break-words" data-audio-selected-file>
            {{ fileDescription(file.name, file.size) }}
          </p>
        </template>
        <label
          class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3"
        >
          <input
            type="checkbox"
            :checked="reviewed"
            data-review-audio-asset
            @change="
              reviewedDraft = $event.target.checked ? editor.fingerprint() : ''
            "
          />
          <span>{{ label('REVIEW') }}</span>
        </label>
      </div>
    </Dialog>
    <Dialog
      ref="historyDialog"
      contained
      :show-confirm-button="false"
      :title="label('HISTORY')"
      :cancel-button-label="label('CANCEL')"
      @close="clearHistory"
    >
      <div
        class="min-w-0 space-y-3 text-sm text-n-slate-12"
        data-audio-version-history
      >
        <p v-if="historyLoading" role="status">{{ label('LOADING') }}</p>
        <p v-if="historyError" role="alert" class="text-n-ruby-11">
          {{ label('ERROR') }}
        </p>
        <article
          v-for="version in history"
          :key="version.id"
          class="min-w-0 space-y-1 rounded-lg border border-n-weak p-3"
          :data-audio-version="version.number"
        >
          <p class="font-semibold">
            {{ label('VERSION') }} {{ version.number }}
          </p>
          <p class="break-words">
            {{ fileDescription(version.file_name, version.byte_size) }}
          </p>
          <p class="break-words">
            {{ versionOrigin(version) }}
          </p>
          <p class="break-all">
            {{ [label('CHECKSUM'), version.sha256].join(': ') }}
          </p>
          <p class="text-n-amber-11">{{ label('NOT_VERIFIED') }}</p>
          <AudioInspectionHistory
            v-if="historyItem"
            :account-id="accountId"
            :asset-id="historyItem.id"
            :version="version"
            :can-manage="canManage"
            @denied="denied"
          />
        </article>
        <nav
          v-if="historyMeta.pages > 1"
          :aria-label="label('PAGINATION')"
          class="flex flex-wrap gap-3"
        >
          <button
            type="button"
            :disabled="historyLoading || historyPage <= 1"
            @click="historyPage -= 1"
          >
            {{ label('PREVIOUS') }}
          </button>
          <span>{{ pageDescription(historyMeta.total, historyPage) }}</span>
          <button
            type="button"
            :disabled="historyLoading || historyPage >= historyMeta.pages"
            @click="historyPage += 1"
          >
            {{ label('NEXT') }}
          </button>
        </nav>
      </div>
    </Dialog>
  </section>
</template>
