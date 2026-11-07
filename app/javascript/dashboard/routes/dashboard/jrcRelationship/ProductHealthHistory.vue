<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import HealthStabilityNote from './HealthStabilityNote.vue';
import HealthCoverageNote from './HealthCoverageNote.vue';
import { buttonClass, date } from './definitions';

const props = defineProps({
  assignmentId: { type: [Number, String], required: true },
  productId: { type: [Number, String], required: true },
  formatting: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const route = useRoute();
const store = useStore();
const result = ref(null);
const busy = ref(false);
const error = ref(false);
const opened = ref(false);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.assignmentId,
    props.productId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
  ])
);
let generation = 0;
watch(identity, () => {
  generation += 1;
  result.value = null;
  error.value = false;
  opened.value = false;
  busy.value = false;
});
onBeforeUnmount(() => {
  generation += 1;
});
const load = async (page = 1) => {
  if (busy.value) return;
  const token = generation;
  const context = identity.value;
  opened.value = true;
  busy.value = true;
  error.value = false;
  // Do not leave previously authorized evidence visible during a new access check.
  result.value = null;
  try {
    const { data } = await API.productHealthHistory(
      route.params.accountId,
      props.assignmentId,
      { product_id: props.productId, page, per_page: 10 }
    );
    if (generation === token && context === identity.value) result.value = data;
  } catch {
    if (generation === token) error.value = true;
  } finally {
    if (generation === token) busy.value = false;
  }
};
</script>

<template>
  <section class="mt-3 min-w-0 space-y-2">
    <button
      type="button"
      :class="buttonClass"
      :disabled="busy"
      :aria-expanded="opened"
      @click="load(1)"
    >
      {{ t('RELATIONSHIP.PRODUCT_HISTORY.TITLE') }}
    </button>
    <p
      v-if="busy"
      role="status"
      class="text-xs text-n-slate-11"
    >
      {{ t('RELATIONSHIP.PRODUCT_HISTORY.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('RELATIONSHIP.PRODUCT_HISTORY.ERROR') }}
    </p>
    <template v-if="opened && result">
      <p class="text-xs text-n-slate-11">
        {{ t('RELATIONSHIP.PRODUCT_HISTORY.NOTE') }}
      </p>
      <p
        v-if="!result.payload.length"
        class="text-sm text-n-slate-11"
      >
        {{ t('RELATIONSHIP.PRODUCT_HISTORY.EMPTY') }}
      </p>
      <ol class="space-y-2">
        <li
          v-for="row in result.payload"
          :key="row.id"
          class="min-w-0 space-y-1 rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm"
        >
          <p class="break-words">{{ date(row.calculated_at, formatting) }}</p>
          <p>
            {{
              t('RELATIONSHIP.PRODUCT_HISTORY.MEASUREMENT', {
                score: row.health.score ?? t('RELATIONSHIP.UNAVAILABLE'),
                band: t(`RELATIONSHIP.BANDS.${row.health.band}`),
              })
            }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{
              t('RELATIONSHIP.VERSION', { version: row.health.config_version })
            }}
          </p>
          <HealthStabilityNote :health="row.health" />
          <HealthCoverageNote
            :health="row.health"
            :formatting="formatting"
          />
          <p
            v-if="row.change"
            class="text-xs"
          >
            {{ t('RELATIONSHIP.HEALTH_CHANGE', { delta: row.change.delta }) }}
          </p>
          <p
            v-if="row.change?.configuration_changed"
            class="text-xs text-n-amber-11"
          >
            {{ t('RELATIONSHIP.CONFIGURATION_CHANGE') }}
          </p>
          <details>
            <summary class="cursor-pointer text-xs font-semibold">
              {{ t('RELATIONSHIP.PRODUCT_HISTORY.FACTORS') }}
            </summary>
            <ul class="space-y-1 text-xs">
              <li
                v-for="factor in row.health.factors || []"
                :key="factor.factor"
                class="break-words"
              >
                {{
                  t('RELATIONSHIP.PRODUCT_HISTORY.FACTOR_VALUE', {
                    factor: t(`RELATIONSHIP.FACTORS.${factor.factor}`),
                    score: factor.normalized ?? t('RELATIONSHIP.UNAVAILABLE'),
                    evidence: factor.evidence,
                  })
                }}
              </li>
            </ul>
          </details>
        </li>
      </ol>
      <nav
        class="flex flex-wrap items-center gap-2"
        :aria-label="t('RELATIONSHIP.PRODUCT_HISTORY.TITLE')"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || result.meta.page <= 1"
          @click="load(result.meta.page - 1)"
        >
          {{ t('RELATIONSHIP.PRODUCT_HISTORY.PREVIOUS') }}
        </button>
        <span class="text-xs">{{
          t('RELATIONSHIP.PRODUCT_HISTORY.PAGE', {
            page: result.meta.page,
            total: result.meta.total,
          })
        }}</span>
        <button
          type="button"
          :class="buttonClass"
          :disabled="
            busy || result.meta.page * result.meta.per_page >= result.meta.total
          "
          @click="load(result.meta.page + 1)"
        >
          {{ t('RELATIONSHIP.PRODUCT_HISTORY.NEXT') }}
        </button>
      </nav>
    </template>
  </section>
</template>
