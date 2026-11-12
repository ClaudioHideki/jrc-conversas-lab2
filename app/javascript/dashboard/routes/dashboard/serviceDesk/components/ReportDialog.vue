<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
defineProps({
  title: { type: String, required: true },
  canExport: { type: Boolean, default: false },
});
const emit = defineEmits(['close', 'export']);
const { t } = useI18n();
const dialog = ref(null);
onMounted(() => dialog.value.showModal());
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="sd-report-title"
    class="m-auto max-h-[94dvh] w-[calc(100%-1rem)] max-w-[1600px] overflow-y-auto rounded-2xl border border-blue-200 bg-gradient-to-br from-blue-100 via-sky-50 to-indigo-100 p-0 text-n-slate-12 shadow-2xl backdrop:bg-slate-950/60 backdrop:backdrop-blur-sm dark:from-n-solid-1 dark:via-n-solid-2 dark:to-n-solid-1"
    data-testid="report-dialog"
    @cancel.prevent="emit('close')"
  >
    <header
      class="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-3 border-b border-blue-200 bg-gradient-to-r from-[#031a3a] via-[#073f82] to-blue-800 p-4 text-white shadow-md sm:px-6"
    >
      <h2
        id="sd-report-title"
        class="m-0 flex min-w-0 items-center gap-3 text-lg font-bold !text-white"
      >
        <span
          aria-hidden="true"
          class="i-lucide-chart-column size-6 shrink-0"
        />{{ title }}
      </h2>
      <div class="flex items-center gap-2">
        <button
          type="button"
          :disabled="!canExport"
          class="flex items-center gap-2 rounded-xl border border-white/40 bg-white/10 px-4 py-2 text-sm font-semibold hover:bg-white/20 disabled:opacity-40"
          @click="emit('export')"
        >
          <span aria-hidden="true" class="i-lucide-download size-4" />{{
            t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.export_view')
          }}
        </button>
        <button
          type="button"
          autofocus
          class="flex items-center gap-2 rounded-xl border border-white/40 bg-white/10 px-4 py-2 text-sm font-semibold hover:bg-white/20"
          @click="emit('close')"
        >
          <span aria-hidden="true" class="i-lucide-x size-4" />{{
            t('JRC_SERVICE_DESK.COMMON.close')
          }}
        </button>
      </div>
    </header>
    <div class="jrc-service-desk-root block !bg-transparent p-3 sm:p-6">
      <slot />
    </div>
  </dialog>
</template>
