<script setup>
import { onMounted, ref } from 'vue';
import TicketFormView from './TicketFormView.vue';

defineProps({ screen: { type: String, default: 'new' } });
const dialog = ref(null);
const form = ref(null);
// Keep the route, session, draft, receipt and API of the existing form.
const cancel = () => {
  if (!form.value?.busy) form.value?.cancel();
};
onMounted(() => dialog.value?.showModal());
</script>

<template>
  <TicketFormView v-if="screen === 'edit'" :screen="screen" />
  <dialog
    v-else
    ref="dialog"
    aria-labelledby="sd-ticket-form-title"
    class="w-[calc(100%-2rem)] max-w-6xl max-h-[90vh] overflow-y-auto rounded-2xl border border-n-weak bg-n-background p-0 text-n-slate-12 shadow-xl backdrop:bg-black/50 backdrop:backdrop-blur-sm"
    @cancel.prevent="cancel"
  >
    <div class="jrc-service-desk-root block p-4 sm:p-6">
      <TicketFormView ref="form" :screen="screen" />
    </div>
  </dialog>
</template>
