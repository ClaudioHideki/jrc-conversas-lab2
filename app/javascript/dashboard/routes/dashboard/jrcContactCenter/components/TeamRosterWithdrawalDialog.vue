<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TeamRosterWithdrawalConfirmation from './TeamRosterWithdrawalConfirmation.vue';

const props = defineProps({
  state: { type: Object, required: true },
  busy: { type: Boolean, default: false },
});
const emit = defineEmits(['confirm', 'submit', 'cancel']);
const { t } = useI18n();
const dialog = ref(null);
const visible = computed(() =>
  Boolean(props.state.review || props.state.error)
);
let generation = 0;
let disposed = false;
watch(
  visible,
  async (current, previous) => {
    generation += 1;
    const version = generation;
    if (!current && previous === undefined) return;
    await nextTick();
    if (disposed || version !== generation) return;
    if (current) dialog.value.open();
    else dialog.value.close();
  },
  { immediate: true }
);
const cancelled = () => {
  if (visible.value) emit('cancel');
};
onBeforeUnmount(() => {
  disposed = true;
  generation += 1;
});
</script>

<template>
  <Dialog
    ref="dialog"
    contained
    overflow-y-auto
    width="2xl"
    :title="t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.MODAL_TITLE')"
    :use-form="false"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!busy"
    :close-on-click-outside="false"
    show-close-button
    @close="cancelled"
  >
    <TeamRosterWithdrawalConfirmation
      :state="state"
      :busy="busy"
      show-submit
      @confirm="emit('confirm', $event)"
      @submit="emit('submit')"
      @cancel="emit('cancel')"
    />
  </Dialog>
</template>
