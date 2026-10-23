<script setup>
import { onMounted, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import en from '../../jrcProjects/en.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/jrcProjects.json';
const props = defineProps({
  title: { type: String, required: true },
  wide: Boolean,
  drawer: Boolean,
  busy: Boolean,
});
const emit = defineEmits(['close']);
const { t } = useI18n({
  useScope: 'local',
  messages: { en, pt_BR },
  fallbackLocale: false,
  fallbackRoot: false,
});
const panel = ref(null);
const expanded = ref(false);
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
      class="text-n-slate-12 [&_button:focus-visible]:outline [&_button:focus-visible]:outline-2 [&_button:focus-visible]:outline-n-blue-9 [&_h1]:text-2xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold fixed inset-0 z-[1000] bg-modal-backdrop-light dark:bg-modal-backdrop-dark flex"
      :class="[
        drawer
          ? 'items-stretch justify-end'
          : 'items-center justify-center p-4',
        drawer
          ? '[&_input:not([type=checkbox])]:rounded-lg [&_input:not([type=checkbox])]:border [&_input:not([type=checkbox])]:border-n-weak [&_input:not([type=checkbox])]:bg-n-solid-1 [&_input:not([type=checkbox])]:p-2 [&_select]:rounded-lg [&_select]:border [&_select]:border-n-weak [&_select]:bg-n-solid-1 [&_select]:p-2 [&_textarea]:rounded-lg [&_textarea]:border [&_textarea]:border-n-weak [&_textarea]:bg-n-solid-1 [&_textarea]:p-2'
          : '',
      ]"
      @click.self="!busy && emit('close')"
      @keydown="onKey"
    >
      <section
        ref="panel"
        class="w-full overflow-auto bg-n-solid-1 text-n-slate-12 p-5 shadow-xl"
        :class="
          drawer
            ? ['h-dvh', expanded ? 'max-w-6xl' : 'max-w-[620px]']
            : ['max-h-[90vh] rounded-xl', wide ? 'max-w-5xl' : 'max-w-3xl']
        "
        role="dialog"
        aria-modal="true"
        :aria-label="title"
        tabindex="-1"
      >
        <div class="flex items-center justify-between gap-4 pb-4">
          <h2 class="min-w-0 flex-1 break-words">{{ title }}</h2>
          <button
            v-if="drawer"
            type="button"
            class="rounded-lg border border-n-weak p-2"
            :aria-label="
              expanded
                ? t('COLLAPSE_PANEL', 'Recolher painel')
                : t('EXPAND_PANEL', 'Expandir painel')
            "
            @click="expanded = !expanded"
          >
            <span
              class="block size-4"
              :class="expanded ? 'i-lucide-minimize-2' : 'i-lucide-maximize-2'"
            />
          </button>
          <button
            class="rounded-md border border-n-weak px-3 py-2 disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
            :disabled="busy"
            type="button"
            :aria-label="t('CLOSE_WINDOW', 'Fechar janela')"
            @click="emit('close')"
          >
            {{ t('CLOSE', 'Fechar') }}
          </button>
        </div>
        <slot />
      </section>
    </div>
  </Teleport>
</template>
