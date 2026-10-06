<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { money as formatMoney, date as formatDate, inputClass, message } from './definitions';
const props = defineProps({ assignmentId: { type: [Number, String], default: '' }, initialPeriod: { type: Object, default: () => ({}) } });
const emit = defineEmits(['loaded']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const context = ref(null);
const error = ref('');
const from = ref(props.initialPeriod.period_from?.slice(0, 10) || '');
const to = ref(props.initialPeriod.period_to?.slice(0, 10) || '');
let generation = 0;
let controller;
watch([() => props.assignmentId, () => route.params.accountId, () => store.getters.getCurrentUserID, from, to], async () => {
  const version = ++generation;
  controller?.abort();
  controller = new AbortController();
  context.value = null;
  error.value = '';
  emit('loaded', null);
  if (!props.assignmentId) return;
  try {
    const params = from.value ? { from: from.value, to: to.value || from.value } : {};
    const { data } = await API.workContext(route.params.accountId, props.assignmentId, params, { signal: controller.signal });
    if (version !== generation) return;
    context.value = data;
    emit('loaded', data);
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED') error.value = message(err);
  }
}, { immediate: true });
onBeforeUnmount(() => { generation += 1; controller?.abort(); });
const money = value => formatMoney(value, context.value?.formatting);
const date = value => formatDate(value, context.value?.formatting);
</script>
<template>
  <section class="my-4 rounded-xl border border-n-weak p-4" data-testid="work-context">
    <h4 class="mb-2 font-semibold">{{ t('RELATIONSHIP.WORK_CONTEXT') }}</h4>
    <div class="mb-3 flex gap-3">
      <label>{{ t('RELATIONSHIP.FIELDS.from') }}<input v-model="from" type="date" :class="inputClass"></label>
      <label>{{ t('RELATIONSHIP.FIELDS.to') }}<input v-model="to" type="date" :class="inputClass"></label>
    </div>
    <p v-if="error" role="alert">{{ error }}</p>
    <template v-if="context">
      <p class="text-sm">{{ context.executive_summary }}</p>
      <p class="mt-2 text-sm">{{ t('RELATIONSHIP.METRICS.mrr_cents') }}: {{ money(context.mrr_cents) }} · {{ t('RELATIONSHIP.METRICS.health_average') }}: {{ context.health?.score ?? '—' }}</p>
      <p class="text-sm">{{ t('RELATIONSHIP.FIELDS.from') }}: {{ date(context.period.from) }} · {{ t('RELATIONSHIP.FIELDS.to') }}: {{ date(context.period.to) }}</p>
      <ul class="mt-2 text-sm"><li v-for="risk in context.risks" :key="risk[0]">{{ risk[1] }}</li></ul>
      <ul class="mt-2 text-sm"><li v-for="plan in context.plan_summaries || []" :key="plan.id">{{ plan.summary }}</li></ul>
      <ul class="mt-2 text-sm"><li v-for="contract in context.contracts || []" :key="contract.id">{{ contract.number }} · {{ money(contract.monthly_cents) }} · {{ date(contract.ends_on) }}</li></ul>
      <ul class="mt-2 text-sm"><li v-for="project in context.projects || []" :key="project[0]">{{ project[1] }} · {{ t(`RELATIONSHIP.STATES.${project[2]}`) }} · {{ date(project[3]) }}</li></ul>
    </template>
  </section>
</template>
