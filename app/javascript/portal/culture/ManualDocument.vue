<script setup>
import { onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url';

const props = defineProps({ src: { type: String, required: true } });
const emit = defineEmits(['expired']);
const { t } = useI18n();
const frame = ref(null);
const canvas = ref(null);
const width = ref(0);
const pageNumber = ref(1);
const document = shallowRef(null);
const pageText = ref('');
const loading = ref(true);
const failed = ref(false);
let loadingTask;
let renderTask;
let resize;
let generation = 0;
let disposed = false;

function reportFailure(error) {
  if (error?.status === 401) emit('expired');
  loading.value = false;
  failed.value = true;
}

onMounted(async () => {
  resize = new ResizeObserver(() => {
    width.value = Math.floor(frame.value?.clientWidth || 0);
  });
  resize.observe(frame.value);
  try {
    const { GlobalWorkerOptions, getDocument } = await import('pdfjs-dist');
    if (disposed) return;
    GlobalWorkerOptions.workerSrc = workerUrl;
    loadingTask = getDocument({
      url: props.src,
      withCredentials: true,
      useWasm: false,
      isEvalSupported: false,
    });
    const pdf = await loadingTask.promise;
    if (!disposed) document.value = pdf;
  } catch (error) {
    if (!disposed) reportFailure(error);
  }
});

watch([document, pageNumber, width], async ([pdf, number, available]) => {
  if (!pdf || !available) return;
  generation += 1;
  const request = generation;
  renderTask?.cancel();
  loading.value = true;
  failed.value = false;
  pageText.value = '';
  try {
    const page = await pdf.getPage(number);
    if (request !== generation) return;
    const scale =
      Math.min(available, 900) / page.getViewport({ scale: 1 }).width;
    const viewport = page.getViewport({ scale });
    const density = Math.min(window.devicePixelRatio || 1, 2);
    const surface = canvas.value;
    surface.width = Math.ceil(viewport.width * density);
    surface.height = Math.ceil(viewport.height * density);
    renderTask = page.render({
      canvas: surface,
      viewport,
      transform: [density, 0, 0, density, 0, 0],
    });
    await renderTask.promise;
    if (request !== generation) return;
    loading.value = false;
    const text = await page.getTextContent();
    if (request === generation)
      pageText.value = text.items.map(item => item.str || '').join(' ');
  } catch (error) {
    if (request === generation) reportFailure(error);
  }
});

onBeforeUnmount(() => {
  disposed = true;
  generation += 1;
  resize?.disconnect();
  renderTask?.cancel();
  loadingTask?.destroy().catch(() => {});
});
</script>

<template>
  <div class="min-w-0">
    <div ref="frame" class="min-w-0 bg-white p-0 dark:bg-n-solid-2">
      <p v-if="loading" class="p-4 text-sm text-n-slate-11" role="status">
        {{ t('loading') }}
      </p>
      <p v-if="failed" class="p-4 text-sm text-n-ruby-11" role="alert">
        {{ t('document_error') }}
      </p>
      <canvas
        v-show="!loading && !failed"
        ref="canvas"
        class="mx-auto block w-full max-w-[900px]"
        aria-hidden="true"
      />
      <p v-if="pageText" class="sr-only">{{ pageText }}</p>
    </div>
    <nav
      v-if="document && document.numPages > 1"
      class="flex flex-wrap items-center justify-between gap-2 border-t border-n-weak px-3 py-2 text-sm"
      :aria-label="t('read_title')"
    >
      <button
        type="button"
        class="min-h-11 rounded-lg border border-n-weak px-3 disabled:opacity-50"
        :disabled="pageNumber === 1"
        @click="pageNumber -= 1"
      >
        {{ t('previous') }}
      </button>
      <span aria-live="polite">
        {{ t('pages', { page: pageNumber, pages: document.numPages }) }}
      </span>
      <button
        type="button"
        class="min-h-11 rounded-lg border border-n-weak px-3 disabled:opacity-50"
        :disabled="pageNumber === document.numPages"
        @click="pageNumber += 1"
      >
        {{ t('next') }}
      </button>
    </nav>
  </div>
</template>
