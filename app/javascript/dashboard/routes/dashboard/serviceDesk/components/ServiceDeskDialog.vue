<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  open: Boolean,
  title: { type: String, required: true },
  busy: Boolean,
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const dialog = ref(null);
let previousFocus;
const close = () => {
  if (!props.busy) emit('close');
};
watch(
  () => props.open,
  async open => {
    await nextTick();
    if (open && !dialog.value?.open) {
      previousFocus = document.activeElement;
      dialog.value?.showModal?.();
    } else if (!open && dialog.value?.open) {
      dialog.value.close?.();
      previousFocus?.focus?.();
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  dialog.value?.close?.();
  previousFocus?.focus?.();
});
</script>

<template>
  <Teleport to="body">
    <dialog
      ref="dialog"
      :aria-label="title"
      class="m-auto w-[calc(100%-2rem)] max-w-3xl max-h-[90vh] overflow-y-auto rounded-2xl border border-n-weak bg-n-background p-0 text-n-slate-12 shadow-xl backdrop:bg-black/50"
      @cancel.prevent="close"
    >
      <header
        class="sticky top-0 z-10 flex items-center justify-between gap-4 border-b border-n-weak bg-n-solid-1 px-5 py-4"
      >
        <h2 class="text-base font-semibold">{{ title }}</h2>
        <Button
          type="button"
          variant="ghost"
          color="slate"
          size="xs"
          icon="i-lucide-x"
          :label="t('JRC_SERVICE_DESK.COMMON.close')"
          :disabled="busy"
          @click="close"
        />
      </header>
      <div v-if="open" class="p-5"><slot /></div>
    </dialog>
  </Teleport>
</template>
