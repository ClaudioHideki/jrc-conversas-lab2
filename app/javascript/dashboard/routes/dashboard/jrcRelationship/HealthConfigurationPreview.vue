<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import HealthCoverageNote from './HealthCoverageNote.vue';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  configuration: { type: Object, required: true },
  formatting: { type: Object, default: () => ({}) },
  disabled: Boolean,
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const query = ref('');
const customers = ref([]);
const selected = ref('');
const meta = ref(null);
const result = ref(null);
const error = ref('');
const busy = ref(false);
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
  ])
);
const invalidate = (clearCustomers = false) => {
  generation += 1;
  controller?.abort();
  result.value = null;
  busy.value = false;
  error.value = '';
  if (clearCustomers) {
    customers.value = [];
    selected.value = '';
    meta.value = null;
  }
};
const begin = () => {
  invalidate();
  controller = new AbortController();
  busy.value = true;
  return { token: generation, signal: controller.signal };
};
const fail = err => {
  if ([403, 404].includes(err.response?.status)) invalidate(true);
  error.value = message(err);
};
const search = async (page = 1) => {
  if (props.disabled) return;
  invalidate(true);
  const { token, signal } = begin();
  try {
    const { data } = await API.portfolio(
      route.params.accountId,
      { q: query.value.trim(), page, per_page: 10 },
      { signal }
    );
    if (token !== generation) return;
    customers.value = data.payload;
    meta.value = data.meta;
  } catch (err) {
    if (token === generation) fail(err);
  } finally {
    if (token === generation) busy.value = false;
  }
};
const simulate = async () => {
  if (props.disabled || !selected.value) return;
  const { token, signal } = begin();
  try {
    const { scope_key, version, weights, rules } = props.configuration;
    const { data } = await API.previewHealthConfiguration(
      route.params.accountId,
      {
        assignment_id: Number(selected.value),
        scope_key,
        version,
        weights,
        rules,
      },
      { signal }
    );
    if (token === generation) result.value = data;
  } catch (err) {
    if (token === generation) fail(err);
  } finally {
    if (token === generation) busy.value = false;
  }
};
watch(identity, () => invalidate(true));
watch(
  () => props.configuration,
  () => invalidate(),
  { deep: true }
);
watch(
  () => props.disabled,
  () => invalidate()
);
watch(query, () => invalidate(true));
onBeforeUnmount(() => invalidate(true));
</script>

<template>
  <section
    class="mt-6 min-w-0 space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-4"
  >
    <h3 class="font-semibold">{{ t('RELATIONSHIP.HEALTH_PREVIEW.TITLE') }}</h3>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.HEALTH_PREVIEW.NOTE') }}
    </p>
    <div class="flex flex-wrap items-end gap-3">
      <label class="min-w-0 flex-1 text-sm">
        {{ t('RELATIONSHIP.SEARCH') }}
        <input
          v-model="query"
          data-testid="health-preview-search"
          :class="inputClass"
          :disabled="disabled"
          maxlength="100"
          @keyup.enter.prevent="search()"
        />
      </label>
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled || busy"
        data-testid="health-preview-find"
        @click="search()"
      >
        {{ t('RELATIONSHIP.SEARCH') }}
      </button>
    </div>
    <div
      v-if="meta"
      class="flex flex-wrap items-center gap-3 text-sm"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled || busy || meta.page <= 1"
        data-testid="health-preview-previous"
        @click="search(meta.page - 1)"
      >
        {{ t('RELATIONSHIP.HEALTH_PREVIEW.PREVIOUS') }}
      </button>
      <span>{{
        t('RELATIONSHIP.HEALTH_PREVIEW.PAGE', {
          page: meta.page,
          total: meta.total,
        })
      }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled || busy || meta.page * meta.per_page >= meta.total"
        data-testid="health-preview-next"
        @click="search(meta.page + 1)"
      >
        {{ t('RELATIONSHIP.HEALTH_PREVIEW.NEXT') }}
      </button>
    </div>
    <label
      v-if="customers.length"
      class="block text-sm"
    >
      {{ t('RELATIONSHIP.FIELDS.customer') }}
      <select
        v-model="selected"
        :class="inputClass"
        :disabled="disabled || busy"
        data-testid="health-preview-customer"
        @change="invalidate()"
      >
        <option value="">{{ t('RELATIONSHIP.HEALTH_PREVIEW.CHOOSE') }}</option>
        <option
          v-for="customer in customers"
          :key="customer.id"
          :value="customer.id"
        >
          {{ customer.name }}
        </option>
      </select>
    </label>
    <p
      v-else-if="meta"
      role="status"
    >
      {{ t('RELATIONSHIP.HEALTH_PREVIEW.EMPTY') }}
    </p>
    <button
      type="button"
      :class="buttonClass"
      :disabled="disabled || busy || !selected"
      data-testid="health-preview-run"
      @click="simulate"
    >
      {{ t('RELATIONSHIP.HEALTH_PREVIEW.RUN') }}
    </button>
    <p
      v-if="busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
    <template v-if="result">
      <p
        v-if="!result.draft_effective"
        role="status"
        class="rounded-lg bg-n-amber-3 p-3 text-sm text-n-amber-11"
      >
        {{ t('RELATIONSHIP.HEALTH_PREVIEW.PRECEDENCE') }}
      </p>
      <p class="font-semibold">{{ result.customer.name }}</p>
      <div class="grid min-w-0 gap-4 md:grid-cols-2">
        <article
          v-for="mode in ['current', 'proposed']"
          :key="mode"
          :data-testid="`health-preview-${mode}`"
          class="min-w-0 rounded-lg border border-n-weak bg-n-alpha-2 p-3"
        >
          <h4 class="font-semibold">
            {{ t(`RELATIONSHIP.HEALTH_PREVIEW.${mode.toUpperCase()}`) }}
          </h4>
          <p>{{ result[mode].scope_key }} · {{ result[mode].version }}</p>
          <p class="text-xl font-semibold">
            {{ result[mode].health.score ?? t('RELATIONSHIP.UNAVAILABLE') }}
          </p>
          <p>{{ t(`RELATIONSHIP.BANDS.${result[mode].health.band}`) }}</p>
          <HealthCoverageNote
            :health="result[mode].health"
            :formatting="formatting"
          />
          <dl class="mt-3 space-y-2 text-sm">
            <div
              v-for="factor in result[mode].health.factors"
              :key="factor.factor"
              class="min-w-0 break-words border-t border-n-weak pt-2"
            >
              <dt class="font-medium">
                {{ t(`RELATIONSHIP.FACTORS.${factor.factor}`) }}
              </dt>
              <dd>
                {{ factor.normalized ?? t('RELATIONSHIP.UNAVAILABLE') }} ·
                {{ t('RELATIONSHIP.V2.WEIGHT', { value: factor.weight }) }}
              </dd>
              <dd>{{ factor.evidence }}</dd>
            </div>
          </dl>
        </article>
      </div>
    </template>
  </section>
</template>
