<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { approvalClient } from 'dashboard/api/approvals';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  request: { type: Object, required: true },
  context: { type: Object, required: true },
});
const { t } = useI18n();
const busy = ref(false);
const error = ref(false);
const identity = computed(() =>
  JSON.stringify([
    props.context.account_id,
    props.context.member_id,
    props.request.id,
    props.request.lock_version,
  ])
);
let generation = 0;
watch(identity, () => {
  generation += 1;
  busy.value = false;
  error.value = false;
});
onBeforeUnmount(() => {
  generation += 1;
});
const download = async () => {
  if (busy.value) return;
  const token = generation;
  const context = identity.value;
  const id = props.request.id;
  busy.value = true;
  error.value = false;
  try {
    const { data } = await approvalClient(props.context.account_id).report(id);
    if (token !== generation || context !== identity.value) return;
    const url = URL.createObjectURL(data);
    try {
      const link = document.createElement('a');
      link.href = url;
      link.download = `approval-${id}-report.json`;
      link.click();
    } finally {
      URL.revokeObjectURL(url);
    }
  } catch {
    if (token === generation) error.value = true;
  } finally {
    if (token === generation) busy.value = false;
  }
};
</script>

<template>
  <section
    class="min-w-0 space-y-2 rounded-xl border border-n-weak bg-n-solid-2 p-3"
  >
    <p class="text-sm text-n-slate-11">{{ t('JRC_APPROVALS.reportNote') }}</p>
    <Button
      :label="
        busy ? t('JRC_APPROVALS.loading') : t('JRC_APPROVALS.reportDownload')
      "
      :disabled="busy"
      variant="faded"
      @click="download"
    />
    <p
      v-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_APPROVALS.reportError') }}
    </p>
  </section>
</template>
