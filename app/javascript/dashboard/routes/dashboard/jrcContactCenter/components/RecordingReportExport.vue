<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import Button from 'dashboard/components-next/button/Button.vue';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  actorScope: { type: String, required: true },
  criteria: { type: Object, default: null },
  authorized: { type: Boolean, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const labels = computed(() => ({
  BUTTON: t('JRC_CONTACT_CENTER.RECORDING_EXPORT.BUTTON'),
  APPLIED_FILTERS: t('JRC_CONTACT_CENTER.RECORDING_EXPORT.APPLIED_FILTERS'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDING_EXPORT.DENIED'),
  LIMIT: t('JRC_CONTACT_CENTER.RECORDING_EXPORT.LIMIT'),
  INVALID_RANGE: t('JRC_CONTACT_CENTER.RECORDING_EXPORT.INVALID_RANGE'),
  INTEGRITY: t('JRC_CONTACT_CENTER.RECORDING_EXPORT.INTEGRITY'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDING_EXPORT.ERROR'),
}));
const text = key => labels.value[key];
const busy = ref(false);
const error = ref('');
const ready = computed(
  () => props.authorized && props.criteria !== null && !props.disabled
);
const identity = computed(() =>
  JSON.stringify([
    String(props.accountId),
    props.actorScope,
    props.criteria,
    props.authorized,
    props.disabled,
  ])
);
let generation = 0;
let controller;
let downloadUrl = '';
let downloadTimer;
const releaseDownload = () => {
  clearTimeout(downloadTimer);
  if (downloadUrl) URL.revokeObjectURL(downloadUrl);
  downloadUrl = '';
};
const reset = () => {
  generation += 1;
  controller?.abort();
  controller = null;
  releaseDownload();
  busy.value = false;
  error.value = '';
};
const errorKey = async failure => {
  if ([401, 403, 404].includes(failure?.response?.status)) return 'DENIED';
  let value = failure?.response?.data;
  if (value instanceof Blob) {
    try {
      value = JSON.parse(await value.text());
    } catch {
      value = null;
    }
  }
  if (value?.error === 'recording_export_limit_exceeded') return 'LIMIT';
  if (value?.error === 'invalid_recording_range') return 'INVALID_RANGE';
  return failure?.message === 'recording_export_integrity'
    ? 'INTEGRITY'
    : 'ERROR';
};
const download = async () => {
  if (!ready.value || busy.value) return;
  const version = generation;
  const account = String(props.accountId);
  const request = { ...props.criteria };
  const active = () => version === generation && ready.value;
  busy.value = true;
  error.value = '';
  controller = new AbortController();
  releaseDownload();
  try {
    const response = await API.exportRecordingsReport(
      account,
      request,
      controller.signal
    );
    if (!active()) return;
    const count = response.headers?.['x-jrc-recording-count'];
    const expected = response.headers?.['x-content-sha256'];
    const valid =
      response.headers?.['x-jrc-recording-account'] === account &&
      typeof count === 'string' &&
      /^(?:0|[1-9]\d{0,3})$/.test(count) &&
      Number(count) <= 1000 &&
      typeof expected === 'string' &&
      /^[a-f0-9]{64}$/.test(expected) &&
      response.data instanceof Blob &&
      response.data.size > 0 &&
      response.data.type.startsWith('text/csv');
    if (!valid) throw new Error('recording_export_integrity');
    const digest = await crypto.subtle.digest(
      'SHA-256',
      await response.data.arrayBuffer()
    );
    const observed = Array.from(new Uint8Array(digest), byte =>
      byte.toString(16).padStart(2, '0')
    ).join('');
    if (observed !== expected) throw new Error('recording_export_integrity');
    if (!active()) return;
    const link = downloadCsvFile('call-center-gravacoes.csv', response.data);
    downloadUrl = link.href;
    link.remove();
    downloadTimer = setTimeout(releaseDownload, 1000);
  } catch (failure) {
    const key = await errorKey(failure);
    if (!active()) return;
    error.value = key;
    if (key === 'DENIED') emit('denied');
  } finally {
    if (version === generation) {
      busy.value = false;
      controller = null;
    }
  }
};
watch(identity, reset, { flush: 'sync' });
onBeforeUnmount(reset);
</script>

<template>
  <div class="min-w-0 space-y-2" data-recording-report-export>
    <template v-if="authorized">
      <Button
        :label="text('BUTTON')"
        icon="i-lucide-download"
        :disabled="!ready || busy"
        :is-loading="busy"
        data-export-recording-report
        @click="download"
      />
      <p class="max-w-prose break-words text-xs text-n-slate-11">
        {{ text('APPLIED_FILTERS') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="max-w-prose break-words text-sm text-n-ruby-11"
        data-recording-report-export-error
      >
        {{ text(error) }}
      </p>
    </template>
  </div>
</template>
