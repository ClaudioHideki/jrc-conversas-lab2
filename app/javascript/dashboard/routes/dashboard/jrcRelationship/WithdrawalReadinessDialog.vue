<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
const props = defineProps({ analystId: { type: Number, required: true } });
const emit = defineEmits(['close']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const result = ref(null);
const error = ref(false);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.analystId,
    store.getters.getCurrentUser,
    store.getters.getCurrentRole,
  ])
);
let generation = 0;
let controller;
const clear = () => {
  generation += 1;
  controller?.abort();
  result.value = null;
};
const load = async () => {
  clear();
  const token = generation;
  controller = new AbortController();
  error.value = false;
  try {
    const { data } = await API.withdrawalReadiness(
      route.params.accountId,
      props.analystId,
      { signal: controller.signal }
    );
    if (token === generation) result.value = data;
  } catch {
    if (token === generation) error.value = true;
  }
};
watch(identity, () => {
  clear();
  emit('close');
});
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(clear);
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('RELATIONSHIP.WITHDRAWAL.TITLE')"
    :description="t('RELATIONSHIP.WITHDRAWAL.NOTE')"
    :show-confirm-button="false"
    :use-form="false"
    show-close-button
    width="xl"
    @close="emit('close')"
  >
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ t('RELATIONSHIP.WITHDRAWAL.UNAVAILABLE') }}
    </p>
    <p
      v-else-if="!result"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <section
      v-if="result"
      class="min-w-0 space-y-3"
    >
      <p class="rounded-lg bg-n-amber-3 p-3 text-sm text-n-amber-12">
        {{ t(`RELATIONSHIP.WITHDRAWAL.${result.state}`) }}
      </p>
      <dl class="grid gap-3 sm:grid-cols-2">
        <div
          v-for="(count, kind) in result.counts"
          :key="kind"
          class="rounded-lg border border-n-weak p-3"
        >
          <dt class="text-sm">
            {{ t(`RELATIONSHIP.WITHDRAWAL.KINDS.${kind}`) }}
          </dt>
          <dd class="font-bold">{{ count }}</dd>
        </div>
      </dl>
      <p class="text-sm text-n-slate-11">
        {{ t('RELATIONSHIP.WITHDRAWAL.FINAL_REVIEW') }}
      </p>
    </section>
  </Dialog>
</template>
