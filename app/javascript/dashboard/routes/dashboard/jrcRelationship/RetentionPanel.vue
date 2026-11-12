<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass } from './definitions';
import { createRetentionState } from './approvedRulesState';
const props = defineProps({
  metadata: { type: Object, required: true },
  portfolioGroupId: { type: [Number, String], default: null },
});
const { t } = useI18n();
const route = useRoute();
const store = useStore();
const period = ref('monthly');
const reference = ref('');
const from = ref('');
const to = ref('');
const reason = ref('');
const confirmed = ref(false);
const baseline = ref(null);
const startBusy = ref(false);
const baselineError = ref('');
const state = ref({ data: null, busy: false, error: '' });
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
    props.metadata,
    props.portfolioGroupId,
  ])
);
const requestState = createRetentionState({
  identity: () => identity.value,
  read: API.retention,
  publish: value => {
    state.value = value;
  },
});
let generation = 0;
const status = async () => {
  generation += 1;
  const token = generation;
  const access = identity.value;
  baseline.value = null;
  baselineError.value = '';
  try {
    const { data } = await API.retentionStatus(route.params.accountId);
    if (token === generation && access === identity.value)
      baseline.value = data;
  } catch {
    if (token === generation) baselineError.value = 'UNAVAILABLE';
  }
};
watch(
  identity,
  () => {
    requestState.clear();
    reason.value = '';
    confirmed.value = false;
    startBusy.value = false;
    status();
  },
  { immediate: true }
);
watch([period, reference, from, to], () => requestState.clear());
const load = () =>
  requestState.load(route.params.accountId, {
    period: period.value,
    reference: reference.value,
    from: from.value,
    to: to.value,
    portfolio_group_id: props.portfolioGroupId || undefined,
  });
const start = async () => {
  if (
    startBusy.value ||
    !baseline.value?.can_start ||
    !confirmed.value ||
    !reason.value.trim()
  )
    return;
  generation += 1;
  const token = generation;
  const access = identity.value;
  startBusy.value = true;
  baselineError.value = '';
  try {
    const { data } = await API.startRetentionHistory(
      route.params.accountId,
      reason.value.trim()
    );
    if (token !== generation || access !== identity.value) return;
    if (!data.started_at) throw new Error('UNCONFIRMED');
    if (token === generation && access === identity.value && data.started_at) {
      baseline.value = { ...baseline.value, started_at: data.started_at };
      reason.value = '';
      confirmed.value = false;
    }
  } catch {
    if (token === generation) {
      baseline.value = null;
      baselineError.value = 'UNAVAILABLE';
    }
  } finally {
    if (token === generation && access === identity.value)
      startBusy.value = false;
  }
};
onBeforeUnmount(() => {
  generation += 1;
  requestState.dispose();
});
</script>

<template>
  <section class="my-4 space-y-4 rounded-xl border p-4">
    <h3 class="font-semibold">{{ t('RELATIONSHIP.RETENTION.TITLE') }}</h3>
    <p class="text-sm">{{ t('RELATIONSHIP.RETENTION.DEFINITION') }}</p>
    <form
      class="flex flex-wrap items-end gap-3"
      @submit.prevent="load"
    >
      <label class="text-sm"
        >{{ t('RELATIONSHIP.RETENTION.PERIOD')
        }}<select
          v-model="period"
          :class="inputClass"
        >
          <option
            v-for="key in ['monthly', 'quarterly', 'annual', 'custom']"
            :key="key"
            :value="key"
          >
            {{ t(`RELATIONSHIP.RETENTION.PERIODS.${key}`) }}
          </option>
        </select></label
      >
      <label
        v-if="period !== 'custom'"
        class="text-sm"
        >{{ t('RELATIONSHIP.RETENTION.REFERENCE')
        }}<input
          v-model="reference"
          type="date"
          required
          :class="inputClass"
      /></label>
      <template v-else>
        <label class="text-sm"
          >{{ t('RELATIONSHIP.RETENTION.FROM')
          }}<input
            v-model="from"
            type="date"
            required
            :class="inputClass" /></label
        ><label class="text-sm"
          >{{ t('RELATIONSHIP.RETENTION.TO')
          }}<input
            v-model="to"
            type="date"
            required
            :class="inputClass"
        /></label>
      </template>
      <button
        type="submit"
        :class="buttonClass"
        :disabled="state.busy"
      >
        {{ t('RELATIONSHIP.RETENTION.CALCULATE') }}
      </button>
    </form>
    <p
      v-if="state.busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="state.error"
      role="alert"
    >
      {{ t(`RELATIONSHIP.RETENTION.${state.error}`) }}
    </p>
    <div v-if="state.data">
      <p class="text-2xl font-semibold">
        {{ state.data.available ? `${state.data.value}%` : '—' }}
      </p>
      <p v-if="!state.data.available">
        {{ t(`RELATIONSHIP.RETENTION.CODES.${state.data.code}`) }}
      </p>
      <dl
        v-else
        class="grid grid-cols-2 gap-3 sm:grid-cols-4"
      >
        <div
          v-for="key in ['initial', 'retained', 'exits', 'target_percent']"
          :key="key"
        >
          <dt>{{ t(`RELATIONSHIP.RETENTION.COUNTS.${key}`) }}</dt>
          <dd>{{ state.data[key] ?? '—' }}</dd>
        </div>
      </dl>
      <p v-if="state.data.previous?.available">
        {{ t('RELATIONSHIP.RETENTION.PREVIOUS') }}:
        {{ state.data.previous.value }}%
      </p>
      <p v-if="state.data.change_percentage_points !== undefined">
        {{ t('RELATIONSHIP.RETENTION.CHANGE') }}:
        {{ state.data.change_percentage_points }}
      </p>
      <p class="text-sm">
        {{ state.data.from }} — {{ state.data.to }} ({{ state.data.timezone }})
      </p>
    </div>
    <p
      v-if="baselineError"
      role="alert"
    >
      {{ t('RELATIONSHIP.RETENTION.UNAVAILABLE') }}
    </p>
    <p
      v-if="baseline?.started_at"
      class="text-sm"
    >
      {{ t('RELATIONSHIP.RETENTION.HISTORY_SINCE') }}: {{ baseline.started_at }}
    </p>
    <form
      v-else-if="baseline?.can_start"
      class="space-y-2 rounded border p-3"
      @submit.prevent="start"
    >
      <p>{{ t('RELATIONSHIP.RETENTION.START_HELP') }}</p>
      <label class="block"
        >{{ t('RELATIONSHIP.RETENTION.REASON')
        }}<textarea
          v-model="reason"
          required
          maxlength="2000"
          :disabled="startBusy"
          :class="inputClass"
        />
      </label>
      <label
        ><input
          v-model="confirmed"
          type="checkbox"
          :disabled="startBusy"
        />
        {{ t('RELATIONSHIP.RETENTION.CONFIRM') }}</label
      >
      <button
        :class="buttonClass"
        :disabled="startBusy || !confirmed || !reason.trim()"
      >
        {{ t('RELATIONSHIP.RETENTION.START') }}
      </button>
    </form>
  </section>
</template>
