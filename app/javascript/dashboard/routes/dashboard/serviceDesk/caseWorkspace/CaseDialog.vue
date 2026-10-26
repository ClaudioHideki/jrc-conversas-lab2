<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { beginSurveyModelPresentation } from '../surveys/presentation';
const props = defineProps({
  open: Boolean,
  busy: Boolean,
  dirty: Boolean,
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  tabs: { type: Array, default: () => [] },
  tab: { type: String, default: '' },
});
const emit = defineEmits(['close', 'update:tab']);
const { t } = useI18n();
const tr = key => t(`JRC_SERVICE_DESK.CASES.${key}`);
const dialog = ref(null);
const discard = ref(false);
let release;
let previous;
function askClose() {
  if (props.busy) return;
  if (props.dirty) discard.value = true;
  else emit('close');
}
watch(
  () => props.open,
  async value => {
    await nextTick();
    discard.value = false;
    if (value) {
      previous = document.activeElement;
      release ||= beginSurveyModelPresentation();
      dialog.value?.showModal?.();
    } else {
      dialog.value?.close?.();
      release?.();
      release = null;
      previous?.focus?.();
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  dialog.value?.close?.();
  release?.();
  previous?.focus?.();
});
</script>

<template>
  <Teleport to="body">
    <dialog
      ref="dialog"
      :aria-label="title"
      class="m-auto w-[calc(100%-1rem)] max-w-6xl max-h-[94dvh] overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 p-0 text-n-slate-12 shadow-2xl backdrop:bg-black/50"
      @cancel.prevent="askClose"
    >
      <div
        v-if="open"
        class="flex max-h-[94dvh] min-h-0 flex-col"
      >
        <header
          class="flex shrink-0 items-start justify-between gap-3 border-b border-n-weak bg-gradient-to-r from-n-blue-2 via-n-violet-2 to-n-ruby-2 px-5 py-4"
        >
          <div class="min-w-0">
            <h2 class="break-words text-lg font-semibold">{{ title }}</h2>
            <p class="mt-1 text-xs text-n-slate-11">{{ subtitle }}</p>
          </div>
          <button
            type="button"
            class="shrink-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs disabled:opacity-50"
            :disabled="busy"
            @click="askClose"
          >
            {{ tr('close') }}
          </button>
        </header>
        <nav
          v-if="tabs.length"
          role="tablist"
          :aria-label="tr('sections')"
          class="grid shrink-0 grid-cols-2 gap-1 border-b border-n-weak p-3 sm:grid-cols-3 lg:flex"
        >
          <button
            v-for="item in tabs"
            :key="item.key"
            role="tab"
            type="button"
            class="min-w-0 flex-1 rounded-lg px-3 py-2 text-xs disabled:opacity-40"
            :class="
              tab === item.key
                ? 'bg-n-blue-9 text-white'
                : 'bg-n-blue-2 text-n-blue-11'
            "
            :aria-selected="tab === item.key"
            :disabled="busy || item.disabled"
            @click="emit('update:tab', item.key)"
          >
            {{ item.label }}
          </button>
        </nav>
        <div
          v-if="discard"
          role="alert"
          class="m-3 rounded-xl border border-n-amber-5 bg-n-amber-2 p-4 text-sm"
        >
          <p>{{ tr('discard_warning') }}</p>
          <div class="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              class="rounded-lg border px-3 py-2"
              @click="discard = false"
            >
              {{ tr('continue_edit') }}
            </button>
            <button
              type="button"
              class="rounded-lg bg-n-ruby-9 px-3 py-2 text-white"
              @click="emit('close')"
            >
              {{ tr('discard_close') }}
            </button>
          </div>
        </div>
        <main
          class="min-h-0 flex-1 overflow-y-auto overscroll-contain p-4 sm:p-5"
        >
          <slot />
        </main>
        <footer
          class="flex shrink-0 flex-wrap items-center justify-between gap-2 border-t border-n-weak bg-n-solid-1 px-4 py-3"
        >
          <slot name="footer" />
        </footer>
      </div>
    </dialog>
  </Teleport>
</template>
