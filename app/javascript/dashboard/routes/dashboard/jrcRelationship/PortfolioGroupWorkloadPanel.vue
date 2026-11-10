<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, message } from './definitions';
const props = defineProps({ group: { type: Object, required: true } });
const route = useRoute();
const store = useStore();
const { t, n } = useI18n();
const snapshot = ref(null);
const loading = ref(false);
const error = ref('');
const refresh = ref(0);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
  ])
);
const labels = computed(() => ({
  customers: t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.customers'),
  points: t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.points'),
  hours: t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.hours'),
}));
const unavailable = computed(() =>
  snapshot.value?.state === 'controlled_review_required'
    ? t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.CONTROLLED_REVIEW')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.SCOPE_DENIED')
);
watch(
  [identity, () => props.group, refresh],
  async (_, __, cleanup) => {
    const controller = new AbortController();
    cleanup(() => controller.abort());
    snapshot.value = null;
    loading.value = true;
    error.value = '';
    try {
      const { data } = await API.portfolioGroupWorkload(
        route.params.accountId,
        props.group.id,
        { signal: controller.signal }
      );
      if (!controller.signal.aborted) snapshot.value = data;
    } catch (err) {
      if (!controller.signal.aborted)
        error.value =
          message(err) ||
          t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.UNAVAILABLE');
    } finally {
      if (!controller.signal.aborted) loading.value = false;
    }
  },
  { immediate: true }
);
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-xl border border-n-amber-6 bg-n-solid-2 p-4"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h3 class="font-semibold">
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.TITLE') }}
      </h3>
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading"
        @click="refresh += 1"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.REFRESH') }}
      </button>
    </div>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.HELP') }}
    </p>
    <p
      v-if="loading"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="break-words text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="snapshot && snapshot.state !== 'observed'"
      role="status"
      class="rounded-lg bg-n-amber-2 p-3 text-n-amber-11"
    >
      {{ unavailable }}
    </p>
    <dl
      v-if="snapshot?.state === 'observed'"
      class="grid min-w-0 gap-3 sm:grid-cols-3"
    >
      <div
        v-for="measure in snapshot.measures"
        :key="measure.unit"
        class="min-w-0 space-y-2 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3"
      >
        <dt class="text-sm font-medium">{{ labels[measure.unit] }}</dt>
        <dd
          v-if="measure.state === 'available' && Number.isFinite(measure.value)"
          class="break-words text-xl font-semibold"
        >
          {{ n(measure.value) }}
        </dd>
        <dd
          v-else
          class="break-words text-sm text-n-amber-11"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.WORKLOAD.MISSING') }}
        </dd>
      </div>
    </dl>
  </section>
</template>
