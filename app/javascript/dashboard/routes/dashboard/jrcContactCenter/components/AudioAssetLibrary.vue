<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import API from 'dashboard/api/jrcContactCenter';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import AudioFolderPicker from './AudioFolderPicker.vue';
import AudioInspectionHistory from './AudioInspectionHistory.vue';
import AudioLibraryPreview from './AudioLibraryPreview.vue';
import AudioCaptureDraft from './AudioCaptureDraft.vue';
import AudioIvrUsages from './AudioIvrUsages.vue';
import AudioSelectedMoveDialog from './AudioSelectedMoveDialog.vue';
import AudioSelectedCopiesDialog from './AudioSelectedCopiesDialog.vue';
import { useAudioAssetEditor } from '../composables/useAudioAssetEditor';
import { useAudioArchive } from '../composables/useAudioArchive';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
  unitId: { type: String, required: true },
  folderId: { type: String, default: '' },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const { uid } = getCurrentInstance();
const filterIds = {
  source: `audio-source-${uid}`,
  purpose: `audio-purpose-${uid}`,
  format: `audio-format-${uid}`,
  size: `audio-size-${uid}`,
  inspection: `audio-inspection-${uid}`,
  selection: `audio-selection-purpose-${uid}`,
};
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.AUDIO_FILES.TITLE'),
  LIMITS: t('JRC_CONTACT_CENTER.AUDIO_FILES.LIMITS'),
  SEARCH: t('JRC_CONTACT_CENTER.AUDIO_FILES.SEARCH'),
  FILTER: t('JRC_CONTACT_CENTER.AUDIO_FILES.FILTER'),
  CLEAR: t('JRC_CONTACT_CENTER.AUDIO_FILES.CLEAR'),
  NEW: t('JRC_CONTACT_CENTER.AUDIO_FILES.NEW'),
  RECORD_NEW: t('JRC_CONTACT_CENTER.AUDIO_FILES.RECORD_NEW'),
  LOADING: t('JRC_CONTACT_CENTER.AUDIO_FILES.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_FILES.ERROR'),
  EMPTY: t('JRC_CONTACT_CENTER.AUDIO_FILES.EMPTY'),
  NO_ACCESS: t('JRC_CONTACT_CENTER.AUDIO_FILES.NO_ACCESS'),
  VERSION: t('JRC_CONTACT_CENTER.AUDIO_FILES.VERSION'),
  BYTES: t('JRC_CONTACT_CENTER.AUDIO_FILES.BYTES'),
  EDIT: t('JRC_CONTACT_CENTER.AUDIO_FILES.EDIT'),
  REPLACE: t('JRC_CONTACT_CENTER.AUDIO_FILES.REPLACE'),
  COPY: t('JRC_CONTACT_CENTER.AUDIO_FILES.COPY'),
  COPY_REVIEW: t('JRC_CONTACT_CENTER.AUDIO_FILES.COPY_REVIEW'),
  COPY_SOURCE: t('JRC_CONTACT_CENTER.AUDIO_FILES.COPY_SOURCE'),
  COPY_SOURCE_NOT_READY: t(
    'JRC_CONTACT_CENTER.AUDIO_FILES.COPY_SOURCE_NOT_READY'
  ),
  SOURCE_ID: t('JRC_CONTACT_CENTER.AUDIO_FILES.SOURCE_ID'),
  SOURCE_VERSION_ID: t('JRC_CONTACT_CENTER.AUDIO_FILES.SOURCE_VERSION_ID'),
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
  DURATION: t('JRC_CONTACT_CENTER.AUDIO_FILES.DURATION'),
  DURATION_UNKNOWN: t('JRC_CONTACT_CENTER.AUDIO_FILES.DURATION_UNKNOWN'),
  SOURCE_METHOD: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.SOURCE_METHOD'),
  IMPORT: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.IMPORT'),
  RECORD: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.RECORD'),
  NICO_PENDING: t('JRC_CONTACT_CENTER.AUDIO_CAPTURE.NICO_PENDING'),
  ALL_SOURCES: t('JRC_CONTACT_CENTER.AUDIO_FILES.ALL_SOURCES'),
  INSPECTION_FILTER: t('JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_FILTER'),
  ALL_INSPECTIONS: t('JRC_CONTACT_CENTER.AUDIO_FILES.ALL_INSPECTIONS'),
  INSPECTION_NO_FILE: t('JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_NO_FILE'),
  INSPECTION_UNINSPECTED: t(
    'JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_UNINSPECTED'
  ),
  INSPECTION_CLEAN: t('JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_CLEAN'),
  INSPECTION_INFECTED: t('JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_INFECTED'),
  INSPECTION_CHECKSUM: t('JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_CHECKSUM'),
  INSPECTION_FILTER_NOTE: t(
    'JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_FILTER_NOTE'
  ),
  INSPECTION_FILTER_UNAVAILABLE: t(
    'JRC_CONTACT_CENTER.AUDIO_FILES.INSPECTION_FILTER_UNAVAILABLE'
  ),
  ALL_FORMATS: t('JRC_CONTACT_CENTER.AUDIO_FILES.ALL_FORMATS'),
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
const actorScope = computed(() => {
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
});
const details = ref(null);
const lastCopy = ref(null);
const lastMoveCount = ref(0);
const lastSelectedCopies = ref(null);
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
const duration = version => {
  const proof = version?.technical_verification;
  const ms = proof?.metadata?.duration_ms;
  if (proof?.ready !== true || !Number.isSafeInteger(ms) || ms <= 0)
    return label('DURATION_UNKNOWN');
  const seconds = Math.floor(ms / 1000);
  const hours = Math.floor(seconds / 3600);
  const minutes = String(Math.floor(seconds / 60) % 60).padStart(2, '0');
  const remainder = String(seconds % 60).padStart(2, '0');
  const fraction = ms % 1000 ? `.${String(ms % 1000).padStart(3, '0')}` : '';
  return `${hours ? `${hours}:` : ''}${minutes}:${remainder}${fraction}`;
};
const items = ref([]);
const meta = ref({ total: 0, pages: 0 });
const maxBytes = ref(0);
const archiveLimits = ref({ max_entries: 0, max_bytes: 0 });
const metadataLimits = ref({ max_entries: 0 });
const selectionPurpose = ref('download');
const loading = ref(false);
const error = ref(false);
const q = ref('');
const sourceFilter = ref('');
const purposeFilter = ref('');
const formatFilter = ref('');
const inspectionFilter = ref('');
const inspectionStates = [
  { value: 'no_file', label: 'INSPECTION_NO_FILE' },
  { value: 'uninspected', label: 'INSPECTION_UNINSPECTED' },
  { value: 'clean', label: 'INSPECTION_CLEAN' },
  { value: 'infected', label: 'INSPECTION_INFECTED' },
  { value: 'unavailable', label: 'INSPECTION_FILTER_UNAVAILABLE' },
  { value: 'checksum_mismatch', label: 'INSPECTION_CHECKSUM' },
];
const formats = [
  'audio/wav',
  'audio/mpeg',
  'audio/ogg',
  'audio/mp4',
  'audio/webm',
];
const history = ref([]);
const historyMeta = ref({ total: 0, pages: 0 });
const historyPage = ref(1);
const historyItem = ref(null);
const historyLoading = ref(false);
const historyError = ref(false);
const historyDialog = ref(null);
const previewItem = ref(null);
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
let archive;
let archiveDialog;
const applyVerification = event => {
  if (
    event.accountId !== String(props.accountId) ||
    event.unitId !== props.unitId
  )
    return;
  const assign = asset => {
    const version = asset?.latest_version;
    if (
      !version ||
      asset?.id !== event.assetId ||
      version.id !== event.versionId
    )
      return;
    const record = event.proof;
    const valid =
      record?.audio_version_id === version.id &&
      record?.unit_id === props.unitId &&
      record?.expected_sha256 === version.sha256;
    version.technical_verification = valid
      ? {
          id: record.id,
          audio_version_id: record.audio_version_id,
          state: record.state,
          probe_state: record.probe_state,
          observed_at: record.observed_at,
          ready: record.ready === true,
          metadata: record.ready === true ? record.metadata : {},
        }
      : null;
  };
  items.value.forEach(assign);
  assign(details.value);
};
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
  previewItem.value = null;
  archive.close();
  archiveLimits.value = { max_entries: 0, max_bytes: 0 };
  metadataLimits.value = { max_entries: 0 };
  generation += 1;
  lastCopy.value = null;
  lastMoveCount.value = 0;
  lastSelectedCopies.value = null;
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
archive = useAudioArchive({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  canManage,
  contextKey: actorScope,
  limits: archiveLimits,
  selectionPurpose,
  metadataLimits,
  onDenied: denied,
});
archiveDialog = archive.dialog;
const selectionLabel = row =>
  archive.organizing.value
    ? t('JRC_CONTACT_CENTER.AUDIO_SELECTION.SELECT', { name: row.name })
    : t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.SELECT', { name: row.name });
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
  previewItem.value = null;
  archive.close();
  archiveLimits.value = { max_entries: 0, max_bytes: 0 };
  metadataLimits.value = { max_entries: 0 };
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
      ...(route.query.audio_file_purpose
        ? { purpose: route.query.audio_file_purpose }
        : {}),
      page: page.value,
      per_page: perPage.value,
      ...(route.query.audio_file_source
        ? { source_kind: route.query.audio_file_source }
        : {}),
      ...(route.query.audio_file_inspection
        ? { inspection_state: route.query.audio_file_inspection }
        : {}),
      ...(route.query.audio_file_format
        ? { content_type: route.query.audio_file_format }
        : {}),
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
    metadataLimits.value = response.data.move_limits || { max_entries: 0 };
    archiveLimits.value = response.data.archive_limits || {
      max_entries: 0,
      max_bytes: 0,
    };
  } catch (failure) {
    if (version === generation) {
      if ([401, 403, 404].includes(failure?.response?.status)) denied();
      else error.value = true;
    }
  } finally {
    if (version === generation) loading.value = false;
  }
};
const selectedCopiesSettled = outcome => {
  lastSelectedCopies.value = outcome;
  return load();
};
const selectedMoveSaved = rows => {
  lastMoveCount.value = rows.length;
  return load();
};
editor = useAudioAssetEditor({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  folderId: computed(() => props.folderId),
  canManage,
  maxBytes,
  onSaved: copied => {
    lastCopy.value = copied || null;
    return load();
  },
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
const sourceMethod = ref('upload');
const captureBusy = ref(false);
const captureContext = computed(() =>
  JSON.stringify([
    props.accountId,
    props.unitId,
    props.folderId,
    editor.session.value,
  ])
);
watch(editor.session, () => {
  sourceMethod.value = 'upload';
  captureBusy.value = false;
});
const chooseSource = method => {
  if (saving.value || submission.value || sourceMethod.value === method) return;
  editor.chooseFile({ target: { files: [] } });
  captureBusy.value = false;
  sourceMethod.value = method;
};
const openCapture = async () => {
  if (
    !canManage.value ||
    loading.value ||
    !maxBytes.value ||
    saving.value ||
    opening.value
  )
    return;
  const session = editor.session.value;
  await editor.open('upload');
  if (
    editor.session.value !== session + 1 ||
    editorError.value ||
    !canManage.value ||
    mode.value !== 'upload'
  )
    return;
  chooseSource('capture');
};
const captureState = value => {
  captureBusy.value = value;
  if (value) editor.chooseFile({ target: { files: [] } });
};
const saveEditor = () => {
  if (captureBusy.value) return;
  if (mode.value !== 'replace' && folderLoading.value) return;
  editor.save();
};
const filter = values =>
  router.replace({ query: { ...route.query, ...values } });
const openCopied = () => {
  const item = lastCopy.value;
  if (!item || !canManage.value || item.unit_id !== props.unitId) return;
  filter({
    audio_unit: props.unitId,
    audio_parent: item.folder_id || undefined,
    audio_file_q: item.name,
    audio_file_page: 1,
    audio_file_source: undefined,
    ...(route.query.audio_file_purpose !== undefined
      ? { audio_file_purpose: undefined }
      : {}),
    audio_file_format: undefined,
    ...(route.query.audio_file_inspection !== undefined
      ? { audio_file_inspection: undefined }
      : {}),
  });
};
const applyFilters = () => {
  const values = { audio_file_q: q.value || undefined, audio_file_page: 1 };
  Object.entries({
    audio_file_source: sourceFilter.value,
    audio_file_purpose: purposeFilter.value,
    audio_file_format: formatFilter.value,
    audio_file_inspection: inspectionFilter.value,
  }).forEach(([key, value]) => {
    if (value || route.query[key] !== undefined)
      values[key] = value || undefined;
  });
  return filter(values);
};
const clearFilters = () => {
  q.value = '';
  sourceFilter.value = '';
  purposeFilter.value = '';
  formatFilter.value = '';
  inspectionFilter.value = '';
  applyFilters();
};
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
    () => route.query.audio_file_source,
    () => route.query.audio_file_purpose,
    () => route.query.audio_file_format,
    () => route.query.audio_file_inspection,
    actorScope,
  ],
  () => {
    forget();
    editor.clear();
    q.value = route.query.audio_file_q || '';
    sourceFilter.value = route.query.audio_file_source || '';
    purposeFilter.value = route.query.audio_file_purpose || '';
    formatFilter.value = route.query.audio_file_format || '';
    inspectionFilter.value = route.query.audio_file_inspection || '';
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
    <AudioLibraryPreview
      v-if="previewItem && canManage"
      :key="`${accountId}:${unitId}:${previewItem.id}`"
      :account-id="accountId"
      :unit-id="unitId"
      :asset="previewItem"
      :can-manage="canManage"
      @close="previewItem = null"
      @denied="denied"
    />
    <p
      role="status"
      class="rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
      data-audio-file-limits
    >
      {{ label('LIMITS') }}
    </p>
    <form
      v-if="canManage"
      class="grid min-w-0 grid-cols-1 items-end gap-4 sm:grid-cols-2 xl:grid-cols-3"
      data-audio-filter-form
      @submit.prevent="applyFilters"
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
      <div class="w-full min-w-0 text-sm text-n-slate-12 sm:flex-1">
        <label :for="filterIds.purpose">{{ label('PURPOSE') }}</label>
        <input
          :id="filterIds.purpose"
          v-model="purposeFilter"
          type="search"
          maxlength="160"
          data-audio-file-purpose-filter
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </div>
      <div class="block min-w-0 max-w-full text-sm text-n-slate-12">
        <label :for="filterIds.source">{{ label('SOURCE') }}</label>
        <select
          :id="filterIds.source"
          v-model="sourceFilter"
          data-audio-file-source-filter
          class="mt-1 w-full max-w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ label('ALL_SOURCES') }}</option>
          <option value="user_upload">{{ label('SOURCE_UPLOAD') }}</option>
          <option value="browser_capture">{{ label('SOURCE_CAPTURE') }}</option>
        </select>
      </div>
      <div class="block min-w-0 max-w-full text-sm text-n-slate-12">
        <label :for="filterIds.format">{{ label('FORMAT') }}</label>
        <select
          :id="filterIds.format"
          v-model="formatFilter"
          data-audio-file-format-filter
          class="mt-1 w-full max-w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ label('ALL_FORMATS') }}</option>
          <option v-for="format in formats" :key="format" :value="format">
            {{ format }}
          </option>
        </select>
      </div>
      <div class="block min-w-0 max-w-full text-sm text-n-slate-12">
        <label :for="filterIds.inspection">{{
          label('INSPECTION_FILTER')
        }}</label>
        <select
          :id="filterIds.inspection"
          v-model="inspectionFilter"
          data-audio-file-inspection-filter
          class="mt-1 w-full max-w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ label('ALL_INSPECTIONS') }}</option>
          <option
            v-for="state in inspectionStates"
            :key="state.value"
            :value="state.value"
          >
            {{ label(state.label) }}
          </option>
        </select>
      </div>
      <div class="block min-w-0 text-sm text-n-slate-12">
        <label :for="filterIds.size">{{ label('PAGE_SIZE') }}</label>
        <select
          :id="filterIds.size"
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
      </div>
      <div
        class="flex flex-wrap items-center gap-3 sm:col-span-2 xl:col-span-3"
      >
        <button
          type="submit"
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
        >
          {{ label('FILTER') }}
        </button>
        <button
          type="button"
          class="rounded-lg px-3 py-2 text-sm text-n-blue-11"
          @click="clearFilters"
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
        <button
          type="button"
          :disabled="loading || !maxBytes || saving || opening"
          data-new-audio-capture
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
          @click="openCapture"
        >
          {{ label('RECORD_NEW') }}
        </button>
      </div>
    </form>
    <p
      v-if="canManage"
      class="break-words text-sm text-n-slate-11"
      data-audio-inspection-filter-note
    >
      {{ label('INSPECTION_FILTER_NOTE') }}
    </p>
    <section
      v-if="lastCopy && canManage"
      role="status"
      class="min-w-0 space-y-2 rounded-lg border border-n-teal-6 bg-n-teal-2 p-3 text-sm text-n-slate-12"
      :data-audio-copy-receipt="lastCopy.id"
    >
      <p class="break-words">
        {{
          t('JRC_CONTACT_CENTER.AUDIO_FILES.COPY_SAVED', {
            name: lastCopy.name,
            id: lastCopy.id,
          })
        }}
      </p>
      <button
        type="button"
        :disabled="loading || saving || opening"
        data-open-copied-audio
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11 disabled:opacity-40"
        @click="openCopied"
      >
        {{ t('JRC_CONTACT_CENTER.AUDIO_FILES.OPEN_COPY') }}
      </button>
    </section>
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
        <table
          role="table"
          class="block w-full table-fixed text-left text-sm text-n-slate-12 sm:table"
        >
          <caption class="sr-only">
            {{
              label('TITLE')
            }}
          </caption>
          <thead
            role="rowgroup"
            class="sr-only sm:not-sr-only sm:sticky sm:top-0 sm:bg-n-solid-2"
          >
            <tr role="row">
              <th scope="col" class="w-1/2 p-3 sm:w-2/5">
                {{ label('NAME') }}
              </th>
              <th scope="col" class="hidden w-1/5 p-3 sm:table-cell">
                {{ label('DURATION') }}
              </th>
              <th scope="col" class="w-1/4 p-3 sm:w-1/5">
                {{ label('VERSION') }}
              </th>
              <th scope="col" class="w-1/4 p-3 sm:w-1/5">
                {{ label('ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody
            role="rowgroup"
            class="block divide-y divide-n-weak bg-n-solid-1 sm:table-row-group"
          >
            <tr
              v-for="row in items"
              :key="row.id"
              role="row"
              class="grid grid-cols-1 sm:table-row"
              :data-audio-asset="row.id"
              :aria-selected="details?.id === row.id"
              :class="details?.id === row.id ? 'bg-n-blue-2' : ''"
            >
              <td
                role="cell"
                class="block min-w-0 break-words p-3 align-top sm:table-cell"
              >
                <label
                  class="mr-1 inline-flex min-h-11 min-w-11 items-center justify-center align-middle"
                >
                  <input
                    type="checkbox"
                    :checked="archive.selected(row)"
                    :disabled="
                      !archive.selectable(row) || loading || saving || opening
                    "
                    :data-audio-archive-select="row.id"
                    :aria-label="selectionLabel(row)"
                    class="size-4 shrink-0"
                    @change="archive.toggle(row)"
                  />
                </label>
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
                  v-if="row.purpose"
                  class="mt-1 break-words text-n-slate-11"
                  data-audio-asset-purpose-summary
                >
                  {{ [label('PURPOSE'), row.purpose].join(': ') }}
                </p>
                <p
                  v-if="row.description"
                  class="mt-1 break-words text-n-slate-11"
                >
                  {{ row.description }}
                </p>
                <p class="mt-1 break-words text-n-slate-11 sm:hidden">
                  {{ label('DURATION') }}
                  <span :data-mobile-audio-file-duration="row.id">{{
                    duration(row.latest_version)
                  }}</span>
                </p>
              </td>
              <td
                role="cell"
                class="hidden min-w-0 break-words p-3 align-top text-n-slate-11 sm:table-cell"
                :data-audio-file-duration="row.id"
              >
                {{ duration(row.latest_version) }}
              </td>
              <td
                role="cell"
                class="block min-w-0 break-words p-3 align-top text-n-slate-11 sm:table-cell"
              >
                <p class="mb-1 font-semibold text-n-slate-12 sm:hidden">
                  {{ label('VERSION') }}
                </p>
                <p v-if="row.latest_version">
                  {{ versionDescription(row.latest_version) }}
                </p>
                <p v-if="row.latest_version" class="mt-1 break-words">
                  {{ row.latest_version.content_type }}
                </p>
                <p
                  v-if="row.latest_version"
                  :data-audio-file-source="row.id"
                  class="mt-1 break-words"
                >
                  {{
                    `${label('SOURCE')}: ${sourceLabel(row.latest_version.source_kind)}`
                  }}
                </p>
                <p class="mt-2 text-n-amber-11">{{ label('PRIVATE') }}</p>
              </td>
              <td
                role="cell"
                class="block min-w-0 break-words p-3 align-top sm:table-cell"
              >
                <p class="mb-1 font-semibold sm:hidden">
                  {{ label('ACTIONS') }}
                </p>
                <div class="flex flex-wrap gap-2">
                  <button
                    type="button"
                    :disabled="
                      saving ||
                      opening ||
                      row.latest_version?.technical_verification?.ready !== true
                    "
                    :data-preview-audio-asset="row.id"
                    class="inline-flex max-w-full items-center gap-2 rounded-lg border border-n-blue-6 px-2 py-2 text-n-blue-11 disabled:opacity-40"
                    @click="previewItem = row"
                  >
                    <Icon icon="i-lucide-play" class="size-4 shrink-0" />
                    {{ t('JRC_CONTACT_CENTER.AUDIO_ROW_PREVIEW.OPEN') }}
                  </button>
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
                    :disabled="
                      saving ||
                      opening ||
                      row.latest_version?.technical_verification?.ready !== true
                    "
                    :data-copy-audio-asset="row.id"
                    class="max-w-full break-words rounded-lg border border-n-blue-6 px-2 py-2 text-n-blue-11 disabled:opacity-40"
                    @click="editor.open('copy', row)"
                  >
                    {{ label('COPY') }}
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
              <dt class="text-n-slate-11">{{ label('DURATION') }}</dt>
              <dd data-audio-details-duration>
                {{ duration(details.latest_version) }}
              </dd>
            </div>
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
        <AudioIvrUsages
          :key="`usages:${details.id}`"
          :account-id="accountId"
          :asset-id="details.id"
          :unit-id="unitId"
          :can-manage="canManage"
          @denied="denied"
        />
        <AudioInspectionHistory
          v-if="details.latest_version"
          :key="`${details.id}:${details.latest_version.id}`"
          :account-id="accountId"
          :asset-id="details.id"
          :version="details.latest_version"
          :can-manage="canManage"
          @denied="denied"
          @latest="applyVerification"
        />
      </aside>
    </div>
    <p v-if="detailsLoading" role="status" class="text-sm text-n-slate-11">
      {{ label('LOADING') }}
    </p>
    <p v-if="detailsError" role="alert" class="text-sm text-n-ruby-11">
      {{ label('ERROR') }}
    </p>
    <section
      v-if="
        canManage &&
        (archiveLimits.max_entries > 0 || metadataLimits.max_entries > 0)
      "
      class="flex min-w-0 flex-wrap items-center gap-3 rounded-lg border border-n-blue-6 bg-n-blue-2 p-3 text-sm text-n-slate-12"
      data-audio-archive-controls
    >
      <label :for="filterIds.selection" class="block min-w-0">
        <span>{{ t('JRC_CONTACT_CENTER.AUDIO_SELECTION.PURPOSE') }}</span>
        <select
          :id="filterIds.selection"
          v-model="selectionPurpose"
          data-audio-selection-purpose
          :disabled="archive.busy.value || loading || saving || opening"
          class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="download" :disabled="archiveLimits.max_entries <= 0">
            {{ t('JRC_CONTACT_CENTER.AUDIO_SELECTION.DOWNLOAD') }}
          </option>
          <option value="organize" :disabled="metadataLimits.max_entries <= 0">
            {{ t('JRC_CONTACT_CENTER.AUDIO_SELECTION.ORGANIZE') }}
          </option>
        </select>
      </label>
      <p
        v-if="archive.organizing.value"
        class="min-w-0 break-words"
        data-audio-organization-selection
        :data-count="archive.items.value.length"
      >
        {{
          t('JRC_CONTACT_CENTER.AUDIO_SELECTION.COUNT', {
            count: archive.items.value.length,
            max: metadataLimits.max_entries,
          })
        }}
      </p>
      <p v-else class="min-w-0 break-words">
        {{
          t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.SELECTION', {
            count: archive.items.value.length,
            bytes: archive.total.value,
            max: archiveLimits.max_entries,
            limit: archiveLimits.max_bytes,
          })
        }}
      </p>
      <button
        type="button"
        :disabled="
          !archive.admitted.value ||
          archive.busy.value ||
          loading ||
          saving ||
          opening
        "
        data-open-audio-archive
        :title="
          archive.organizing.value
            ? t('JRC_CONTACT_CENTER.AUDIO_SELECTION.NO_BYTES')
            : undefined
        "
        class="rounded-lg border border-n-blue-6 bg-n-solid-1 px-3 py-2 text-n-blue-11 disabled:opacity-40"
        @click="archive.open"
      >
        <Icon
          icon="i-lucide-download"
          class="mr-2 inline-block size-4"
          aria-hidden="true"
        />{{ t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.OPEN') }}
      </button>
      <AudioSelectedCopiesDialog
        :account-id="accountId"
        :unit-id="unitId"
        :context-key="actorScope"
        :can-manage="canManage"
        :selection="archive.items.value"
        :folder-id="folderId"
        :admitted="
          archive.admitted.value &&
          !archive.busy.value &&
          !loading &&
          !saving &&
          !opening
        "
        @denied="denied"
        @settled="selectedCopiesSettled"
      />
      <AudioSelectedMoveDialog
        :account-id="accountId"
        :unit-id="unitId"
        :context-key="actorScope"
        :can-manage="canManage"
        :selection="archive.items.value"
        :disabled="archive.busy.value || loading || saving || opening"
        @denied="denied"
        @saved="selectedMoveSaved"
      />
      <button
        type="button"
        :disabled="!archive.items.value.length || archive.busy.value"
        data-clear-audio-selection
        class="rounded-lg px-3 py-2 text-n-blue-11 disabled:opacity-40"
        @click="archive.close"
      >
        {{ t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.CLEAR') }}
      </button>
    </section>
    <p
      v-if="lastSelectedCopies && canManage"
      role="status"
      data-audio-selected-copies-settled
      :data-confirmed="lastSelectedCopies.confirmed.length"
      :data-uncertain="lastSelectedCopies.uncertain"
      class="break-words rounded-lg border border-n-blue-6 bg-n-blue-2 p-3 text-sm text-n-slate-12"
    >
      {{
        t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.AFTER_CLOSE', {
          confirmed: lastSelectedCopies.confirmed.length,
          uncertain: lastSelectedCopies.uncertain,
          blocked: lastSelectedCopies.blocked,
          pending: lastSelectedCopies.pending,
        })
      }}
    </p>
    <p
      v-if="lastMoveCount"
      role="status"
      :data-count="lastMoveCount"
      data-audio-selected-move-saved
      class="break-words rounded-lg border border-n-teal-6 bg-n-teal-2 p-3 text-sm text-n-teal-11"
    >
      {{ t('JRC_CONTACT_CENTER.AUDIO_MOVE.SAVED', { count: lastMoveCount }) }}
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
        label(
          { upload: 'NEW', edit: 'EDIT', replace: 'REPLACE', copy: 'COPY' }[
            mode
          ]
        )
      "
      :confirm-button-label="label('SAVE')"
      :cancel-button-label="label('CANCEL')"
      :disable-confirm-button="
        !canSave || captureBusy || (mode !== 'replace' && folderLoading)
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
        <section
          v-if="mode === 'copy' && editor.copyVersion.value"
          class="min-w-0 space-y-2 rounded-lg border border-n-blue-6 bg-n-blue-2 p-3"
          data-audio-copy-source
        >
          <h4 class="font-semibold">{{ label('COPY_SOURCE') }}</h4>
          <p class="break-words">{{ editor.selected.value?.name }}</p>
          <p class="break-all">
            {{ [label('SOURCE_ID'), editor.selected.value?.id].join(': ') }}
          </p>
          <p class="break-all">
            {{
              [label('SOURCE_VERSION_ID'), editor.copyVersion.value.id].join(
                ': '
              )
            }}
          </p>
          <p class="break-words">
            {{ versionDescription(editor.copyVersion.value) }}
          </p>
          <p class="break-all">{{ editor.copyVersion.value.sha256 }}</p>
          <p>{{ label('COPY_REVIEW') }}</p>
        </section>
        <template v-if="['upload', 'replace'].includes(mode)">
          <div
            role="group"
            :aria-label="label('SOURCE_METHOD')"
            class="flex min-w-0 flex-wrap gap-2"
          >
            <button
              type="button"
              :aria-pressed="sourceMethod === 'upload'"
              :disabled="saving || Boolean(submission)"
              data-audio-source-upload
              class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11 disabled:opacity-40"
              :class="
                sourceMethod === 'upload' ? 'bg-n-blue-3' : 'bg-n-solid-1'
              "
              @click="chooseSource('upload')"
            >
              <Icon
                icon="i-lucide-upload"
                class="mr-2 inline-block size-4"
                aria-hidden="true"
              />{{ label('IMPORT') }}
            </button>
            <button
              type="button"
              :aria-pressed="sourceMethod === 'capture'"
              :disabled="saving || Boolean(submission)"
              data-audio-source-capture
              class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11 disabled:opacity-40"
              :class="
                sourceMethod === 'capture' ? 'bg-n-blue-3' : 'bg-n-solid-1'
              "
              @click="chooseSource('capture')"
            >
              <Icon
                icon="i-lucide-mic"
                class="mr-2 inline-block size-4"
                aria-hidden="true"
              />{{ label('RECORD') }}
            </button>
            <span
              class="max-w-full break-words rounded-lg border border-n-weak px-3 py-2 text-n-slate-11"
            >
              {{ label('NICO_PENDING') }}
            </span>
          </div>
          <label
            v-if="sourceMethod === 'upload'"
            class="block min-w-0 break-words"
          >
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
          <AudioCaptureDraft
            v-if="sourceMethod === 'capture' && editor.openedScope.value"
            :key="editor.session.value"
            :context-key="captureContext"
            :max-bytes="maxBytes"
            :disabled="saving || Boolean(submission) || !canManage"
            @selected="editor.chooseCapturedFile"
            @busy="captureState"
            @discard="editor.chooseFile({ target: { files: [] } })"
          />
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
      ref="archiveDialog"
      contained
      use-form
      :title="t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.TITLE')"
      :confirm-button-label="t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.DOWNLOAD')"
      :cancel-button-label="label('CANCEL')"
      :disable-confirm-button="!archive.canDownload.value"
      :is-loading="archive.downloading.value"
      :dismissible="!archive.busy.value"
      @confirm="archive.download"
      @close="archive.clear"
    >
      <div
        class="min-w-0 space-y-3 text-sm text-n-slate-12"
        data-audio-archive-dialog
      >
        <p>{{ t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.EXPLANATION') }}</p>
        <p v-if="archive.opening.value" role="status">{{ label('LOADING') }}</p>
        <p
          v-if="archive.error.value"
          role="alert"
          class="break-words text-n-ruby-11"
        >
          {{
            archive.error.value === 'SOURCE_CHANGED'
              ? t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.SOURCE_CHANGED')
              : t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.ERROR')
          }}
        </p>
        <p
          v-if="archive.delivered.value"
          role="status"
          class="break-words text-n-teal-11"
          data-audio-archive-delivered
        >
          {{ t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.DELIVERED') }}
        </p>
        <ul
          class="max-h-64 min-w-0 space-y-3 overflow-y-auto overscroll-contain"
        >
          <li
            v-for="item in archive.items.value"
            :key="item.assetId"
            class="min-w-0 space-y-1 rounded-lg border border-n-weak p-3"
            :data-audio-archive-item="item.assetId"
          >
            <p class="break-words font-semibold">{{ item.name }}</p>
            <p>
              {{
                t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.VERSION_BYTES', {
                  version: item.number,
                  bytes: item.byteSize,
                })
              }}
            </p>
            <p class="break-all">{{ item.sha256 }}</p>
            <p
              v-if="archive.usages.value[item.assetId] !== undefined"
              class="break-words"
            >
              {{
                t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.LOCAL_USAGES', {
                  count: archive.usages.value[item.assetId],
                })
              }}
            </p>
          </li>
        </ul>
        <label
          class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3"
        >
          <input
            v-model="archive.reviewed.value"
            type="checkbox"
            :disabled="!archive.verified.value || archive.busy.value"
            data-review-audio-archive
          />
          <span>{{ t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.REVIEW') }}</span>
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
            @latest="applyVerification"
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
