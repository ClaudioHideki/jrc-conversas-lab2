<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { beginSurveyModelPresentation } from '../surveys/presentation';
const props = defineProps({
  open: Boolean,
  busy: Boolean,
  dirty: Boolean,
  title: { type: String, required: true },
  steps: { type: Array, required: true },
  step: { type: Number, default: 0 },
  maxStep: { type: Number, default: 0 },
});
const emit = defineEmits(['close', 'update:step']);
const { t } = useI18n();
const tr = key => t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.${key}`);
const dialog = ref(null);
const confirmDiscard = ref(false);
let previousFocus;
let releasePresentation;
function askClose() {
  if (props.busy) return;
  if (props.dirty) confirmDiscard.value = true;
  else emit('close');
}
watch(
  () => props.open,
  async value => {
    await nextTick();
    confirmDiscard.value = false;
    if (value) {
      previousFocus = document.activeElement;
      releasePresentation ||= beginSurveyModelPresentation();
      if (!dialog.value?.open) dialog.value?.showModal?.();
    } else {
      dialog.value?.close?.();
      releasePresentation?.();
      releasePresentation = null;
      previousFocus?.focus?.();
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  dialog.value?.close?.();
  releasePresentation?.();
  previousFocus?.focus?.();
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
            <h2 class="text-xl font-semibold">{{ title }}</h2>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ tr('context_notice') }}
            </p>
          </div>
          <button
            type="button"
            class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-xs disabled:opacity-50"
            :disabled="busy"
            @click="askClose"
          >
            {{ tr('close') }}
          </button>
        </header>
        <nav
          class="grid shrink-0 grid-cols-2 gap-2 border-b border-n-weak p-3 sm:grid-cols-3 lg:flex"
          :aria-label="tr('steps')"
        >
          <button
            v-for="(name, index) in steps"
            :key="name"
            type="button"
            class="flex min-w-0 flex-1 items-center gap-2 rounded-lg px-3 py-2 text-left text-xs disabled:opacity-50"
            :class="
              step === index
                ? 'bg-n-blue-9 text-white'
                : 'bg-n-blue-2 text-n-blue-11'
            "
            :aria-current="step === index ? 'step' : undefined"
            :disabled="busy || index > maxStep"
            @click="emit('update:step', index)"
          >
            <span class="shrink-0 rounded-full border border-current px-2 py-1">
              {{ index + 1 }}
            </span>
            <span>{{ name }}</span>
          </button>
        </nav>
        <div
          v-if="confirmDiscard"
          role="alert"
          class="m-3 rounded-xl border border-n-amber-5 bg-n-amber-2 p-4 text-sm"
        >
          <p>{{ tr('discard_notice') }}</p>
          <div class="mt-3 flex gap-3">
            <button
              type="button"
              class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2"
              @click="confirmDiscard = false"
            >
              {{ tr('keep_editing') }}
            </button>
            <button
              type="button"
              class="rounded-lg bg-n-ruby-9 px-3 py-2 text-white"
              @click="emit('close')"
            >
              {{ tr('discard') }}
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
