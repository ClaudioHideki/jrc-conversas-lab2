<script setup>
import { onMounted, onBeforeUnmount, ref } from 'vue';
const props = defineProps({
  title: { type: String, required: true },
  wide: Boolean,
  busy: Boolean,
});
const emit = defineEmits(['close']);
const panel = ref(null);
let previousFocus;
function onKey(event) {
  if (event.key === 'Escape' && !props.busy) emit('close');
  if (event.key !== 'Tab') return;
  const elements = [
    ...panel.value.querySelectorAll(
      'button:not([disabled]),a[href],input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex="0"]'
    ),
  ];
  if (!elements.length) return;
  if (event.shiftKey && document.activeElement === elements[0]) {
    event.preventDefault();
    elements.at(-1).focus();
  } else if (!event.shiftKey && document.activeElement === elements.at(-1)) {
    event.preventDefault();
    elements[0].focus();
  }
}
onMounted(() => {
  previousFocus = document.activeElement;
  panel.value?.focus();
});
onBeforeUnmount(() => previousFocus?.focus?.());
</script>

<template>
  <Teleport to="body">
    <div
      class="text-n-slate-12 [&_button:focus-visible]:outline [&_button:focus-visible]:outline-2 [&_button:focus-visible]:outline-n-blue-9 [&_h1]:text-2xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold fixed inset-0 z-[1000] bg-black/50 flex items-center justify-center p-4"
      @click.self="!busy && emit('close')"
      @keydown="onKey"
    >
      <section
        ref="panel"
        class="max-h-[90vh] w-full overflow-auto rounded-xl bg-n-solid-1 text-n-slate-12 p-5"
        :class="wide ? 'max-w-5xl' : 'max-w-3xl'"
        role="dialog"
        aria-modal="true"
        :aria-label="title"
        tabindex="-1"
      >
        <div class="flex items-center justify-between gap-4 pb-4">
          <h2>{{ title }}</h2>
          <button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
            :disabled="busy"
            type="button"
            aria-label="Fechar janela"
            @click="emit('close')"
          >
            Fechar
          </button>
        </div>
        <slot />
      </section>
    </div>
  </Teleport>
</template>
