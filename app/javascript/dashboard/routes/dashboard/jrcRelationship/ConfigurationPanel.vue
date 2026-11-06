<script setup>
import { ref, watch, computed, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import {
  buttonClass,
  inputClass,
  message,
  date as formatDate,
} from './definitions';
import RequiredDocumentsForm from './RequiredDocumentsForm.vue';
import OperationsSettingsPanel from './OperationsSettingsPanel.vue';
import PlaybookExecutionPanel from './PlaybookExecutionPanel.vue';
import PlaybookDesignPreview from './PlaybookDesignPreview.vue';
import PlaybookFlowPolicyForm from './PlaybookFlowPolicyForm.vue';
import PortfolioCapacityLimitsForm from './PortfolioCapacityLimitsForm.vue';
import HealthConfigurationPreview from './HealthConfigurationPreview.vue';
import PriorityBandsForm from './PriorityBandsForm.vue';
import ConfigurationRestoreDialog from './ConfigurationRestoreDialog.vue';
import PlaybookRestoreDialog from './PlaybookRestoreDialog.vue';
import PlaybookHistoryPanel from './PlaybookHistoryPanel.vue';
const props = defineProps({
  screen: { type: String, default: 'settings' },
  allowed: Boolean,
  metadata: { type: Object, default: () => ({}) },
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const config = ref(null);
const books = ref([]);
const bookPage = ref(1);
const bookMeta = ref({ per_page: 25, total: 0 });
const bookPages = computed(() =>
  Math.max(1, Math.ceil(bookMeta.value.total / bookMeta.value.per_page))
);
const book = ref(null);
const error = ref('');
const busy = ref(false);
const restoring = ref(null);
const restorePreparing = ref(false);
const restored = ref(null);
const restoringPlaybook = ref(null);
const restoredPlaybook = ref(null);
const scopeKey = ref('account');
const restoreIdentity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    scopeKey.value,
    props.screen,
    props.allowed,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
  ])
);
const invalidFlowPolicy = ref(false);
const invalidCapacity = ref(false);
const invalidPriorityBands = ref(false);
const distributionOnly = computed(() => scopeKey.value.startsWith('team:'));
const ordinaryRules = computed(() =>
  Object.fromEntries(
    Object.entries(config.value?.rules || {}).filter(
      ([key]) =>
        ![
          'playbook_flow_policy',
          'required_documents',
          'portfolio_capacity_limits',
          'priority_bands',
        ].includes(key) &&
        (key !== 'automatic_action_daily_limit' ||
          scopeKey.value === 'account') &&
        (!distributionOnly.value ||
          [
            'portfolio_transfer_approval_required',
            'portfolio_review_validity_minutes',
          ].includes(key))
    )
  )
);
const scopeOptions = computed(() => [
  ['account', t('RELATIONSHIP.ACCOUNT_SCOPE')],
  ...(props.metadata.configuration_teams || []).map(row => [
    `team:${row[0]}`,
    `${t('RELATIONSHIP.DISTRIBUTION.PORTFOLIO_TEAM')}: ${row[1]}`,
  ]),
  ...(props.metadata.segments || []).map(row => [
    `segment:${row[0]}`,
    `${t('RELATIONSHIP.FIELDS.segment_id')}: ${row[1]}`,
  ]),
  ...(props.metadata.products || []).map(row => [
    `product:${row[0]}`,
    `${t('RELATIONSHIP.FIELDS.product_id')}: ${row[1]}`,
  ]),
  ...(props.metadata.configuration_companies || []).map(row => [
    `company:${row[0]}`,
    `${t('RELATIONSHIP.FIELDS.customer')}: ${row[1]}`,
  ]),
  ...(props.metadata.units || []).map(row => [
    `unit:${row[0]}`,
    `${t('RELATIONSHIP.FIELDS.business_unit_id')}: ${row[1]}`,
  ]),
]);
let generation = 0;
const load = async () => {
  generation += 1;
  const v = generation;
  config.value = null;
  restoring.value = null;
  restorePreparing.value = false;
  restored.value = null;
  restoringPlaybook.value = null;
  restoredPlaybook.value = null;
  books.value = [];
  book.value = null;
  error.value = '';
  busy.value = false;
  invalidFlowPolicy.value = false;
  invalidCapacity.value = false;
  invalidPriorityBands.value = false;
  if (!props.allowed) return;
  busy.value = true;
  try {
    const { data } = await (props.screen === 'settings'
      ? API.configuration(route.params.accountId, {
          params: { scope_key: scopeKey.value },
        })
      : API.playbooks(route.params.accountId, {
          params: { page: bookPage.value, per_page: 25 },
        }));
    if (v === generation) {
      if (props.screen === 'settings') config.value = data;
      else {
        books.value = data.payload;
        bookMeta.value = data.meta;
      }
    }
  } catch (err) {
    if (v === generation) error.value = message(err);
  } finally {
    if (v === generation) busy.value = false;
  }
};
const changeBookPage = async page => {
  if (
    busy.value ||
    restorePreparing.value ||
    !props.allowed ||
    book.value ||
    page < 1 ||
    page > bookPages.value
  )
    return;
  bookPage.value = page;
  await load();
};
const save = async () => {
  if (
    busy.value ||
    !props.allowed ||
    invalidFlowPolicy.value ||
    invalidCapacity.value ||
    invalidPriorityBands.value
  )
    return;
  const version = generation;
  const accountId = route.params.accountId;
  busy.value = true;
  error.value = '';
  try {
    if (props.screen === 'settings')
      await API.saveConfiguration(accountId, {
        scope_key: config.value.scope_key,
        version: config.value.version,
        weights: config.value.weights,
        rules: config.value.rules,
      });
    else {
      await API.savePlaybook(accountId, book.value, book.value.id);
      if (version === generation) book.value = null;
    }
    if (version === generation) await load();
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const edit = row => {
  if (busy.value || restorePreparing.value || !props.allowed) return;
  book.value = row
    ? JSON.parse(JSON.stringify(row))
    : {
        name: '',
        trigger_kind: 'onboarded',
        active: false,
        steps: [],
        conditions: [],
      };
  book.value.conditions ||= [];
  book.value.steps = book.value.steps.map((step, index) => ({
    ...step,
    step_key: step.step_key || String(index),
  }));
};
const openRestore = async sourceVersion => {
  if (busy.value || restorePreparing.value || !props.allowed || !config.value)
    return;
  const token = generation;
  const scope = scopeKey.value;
  restorePreparing.value = true;
  error.value = '';
  try {
    const { data } = await API.configuration(route.params.accountId, {
      params: { scope_key: scope },
    });
    if (token !== generation) return;
    const historical = data.history?.find(row => row.version === sourceVersion);
    if (
      data.scope_key !== scope ||
      !historical ||
      historical.version >= data.version
    ) {
      throw new Error(t('RELATIONSHIP.CONFIG_RESTORE.UNCONFIRMED'));
    }
    restoring.value = {
      current: data,
      historical,
      scopeLabel:
        scopeOptions.value.find(row => row[0] === scope)?.[1] ||
        t('RELATIONSHIP.CONFIG_SCOPE'),
    };
  } catch (err) {
    if (token === generation) {
      error.value = message(err);
      if ([401, 403, 404].includes(err.response?.status)) config.value = null;
    }
  } finally {
    if (token === generation) restorePreparing.value = false;
  }
};
const restorationSaved = async receipt => {
  const identity = restoreIdentity.value;
  restoring.value = null;
  await load();
  if (
    identity === restoreIdentity.value &&
    config.value?.scope_key === receipt.scope_key &&
    config.value.version === receipt.version
  )
    restored.value = receipt;
};
const openPlaybookRestore = async (id, sourceVersion) => {
  if (busy.value || restorePreparing.value || !props.allowed) return;
  const token = generation;
  restorePreparing.value = true;
  error.value = '';
  try {
    const { data } = await API.playbookHistory(route.params.accountId, id, {
      source_version: sourceVersion,
    });
    if (token !== generation) return;
    const current = data.current;
    const historical = data.payload.find(row => row.version === sourceVersion);
    if (
      current?.id !== id ||
      !historical ||
      historical.version >= current.version
    )
      throw new Error(t('RELATIONSHIP.PLAYBOOK_RESTORE.UNCONFIRMED'));
    restoringPlaybook.value = { current, historical };
  } catch (err) {
    if (token === generation) {
      error.value = message(err);
      if ([401, 403, 404].includes(err.response?.status)) {
        books.value = [];
        book.value = null;
      }
    }
  } finally {
    if (token === generation) restorePreparing.value = false;
  }
};
const playbookRestored = async receipt => {
  const identity = restoreIdentity.value;
  restoringPlaybook.value = null;
  await load();
  if (
    identity === restoreIdentity.value &&
    books.value.some(
      row => row.id === receipt.id && row.version === receipt.version
    )
  )
    restoredPlaybook.value = receipt;
};
watch(
  () => route.params.accountId,
  () => {
    scopeKey.value = 'account';
  }
);
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => store.getters.getCurrentRole,
    () => JSON.stringify(store.getters.getCurrentUser?.accounts),
    () => props.screen,
    () => props.allowed,
  ],
  () => {
    bookPage.value = 1;
    bookMeta.value = { per_page: 25, total: 0 };
    load();
  },
  { immediate: true }
);
watch(scopeKey, load);
onBeforeUnmount(() => {
  generation += 1;
});
const conditionReferences = field =>
  ({
    segment_id: props.metadata.segments,
    product_id: props.metadata.products,
    business_unit_id: props.metadata.units,
  })[field];
const conditionFields = [
  'segment_id',
  'product_id',
  'business_unit_id',
  'health_score',
  'mrr_cents',
  'days_without_contact',
  'critical_tickets',
  'sla_breached',
  'nps',
  'csat',
  'overdue_cents',
  'delayed_projects',
];
const date = value => formatDate(value, props.metadata?.formatting);
const historyValue = value => {
  if (typeof value === 'boolean')
    return value ? t('RELATIONSHIP.YES') : t('RELATIONSHIP.NO');
  if (Array.isArray(value))
    return value
      .map(item =>
        item && typeof item === 'object' ? JSON.stringify(item) : String(item)
      )
      .join(', ');
  return value && typeof value === 'object' ? JSON.stringify(value) : value;
};
</script>

<template>
  <p
    v-if="!allowed"
    role="status"
  >
    {{ t('RELATIONSHIP.RESTRICTED') }}
  </p>
  <section v-else>
    <p
      v-if="restored"
      role="status"
      class="mb-4 rounded-lg bg-n-teal-2 p-3 text-n-teal-11"
    >
      {{
        t('RELATIONSHIP.CONFIG_RESTORE.SAVED', {
          source: restored.restored_from_version,
          version: restored.version,
        })
      }}
    </p>
    <label
      v-if="screen === 'settings'"
      class="mb-4 block text-sm"
      >{{ t('RELATIONSHIP.CONFIG_SCOPE')
      }}<select
        v-model="scopeKey"
        :class="inputClass"
      >
        <option
          v-for="item in scopeOptions"
          :key="item[0]"
          :value="item[0]"
        >
          {{ item[1] }}
        </option>
      </select></label
    >
    <p
      v-if="busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ error }}
    </p>
    <form
      v-if="config"
      @submit.prevent="save"
    >
      <p class="mb-4 text-sm">
        {{ t('RELATIONSHIP.VERSION', { version: config.version }) }}
      </p>
      <h3
        v-if="!distributionOnly"
        class="mb-3 font-semibold"
      >
        {{ t('RELATIONSHIP.WEIGHTS') }}
      </h3>
      <div
        v-if="!distributionOnly"
        class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4"
      >
        <label
          v-for="(_, key) in config.weights"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.FACTORS.${key}`)
          }}<input
            v-model.number="config.weights[key]"
            type="number"
            step="0.1"
            min="0"
            :class="inputClass"
        /></label>
      </div>
      <h3 class="mb-3 mt-5 font-semibold">{{ t('RELATIONSHIP.RULES') }}</h3>
      <p
        v-if="!distributionOnly"
        class="mb-3 text-sm"
      >
        {{ t('RELATIONSHIP.AUTOMATIC_ACTION_NOTICE') }}
      </p>
      <p
        v-if="!distributionOnly"
        class="mb-3 text-sm"
      >
        {{ t('RELATIONSHIP.PRIORITY_SIGNAL_NOTICE') }}
      </p>
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <label
          v-for="(_, key) in ordinaryRules"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.RULE_LABELS.${key}`)
          }}<input
            v-if="typeof config.rules[key] === 'boolean'"
            v-model="config.rules[key]"
            type="checkbox"
          /><select
            v-else-if="key === 'missing_factor_policy'"
            v-model="config.rules[key]"
            :class="inputClass"
          >
            <option
              v-for="policy in ['renormalize', 'neutral', 'block']"
              :key="policy"
              :value="policy"
            >
              {{ t(`RELATIONSHIP.MISSING_POLICIES.${policy}`) }}
            </option></select
          ><select
            v-else-if="key === 'eligibility_mode'"
            v-model="config.rules[key]"
            :class="inputClass"
          >
            <option
              v-for="mode in ['legacy_order', 'active_contract_product']"
              :key="mode"
              :value="mode"
            >
              {{ t(`RELATIONSHIP.ELIGIBILITY_MODES.${mode}`) }}
            </option></select
          ><input
            v-else-if="typeof config.rules[key] === 'number'"
            v-model.number="config.rules[key]"
            :data-testid="`relationship-rule-${key}`"
            type="number"
            :step="
              ['priority_trend', 'priority_sla'].includes(key)
                ? 'any'
                : [
                      'satisfaction_window_days',
                      'sentiment_window_days',
                      'health_trend_window_days',
                      'automatic_action_daily_limit',
                    ].includes(key)
                  ? 1
                  : 0.1
            "
            :min="
              [
                'health_hysteresis_points',
                'automatic_action_cooldown_hours',
                'automatic_action_daily_limit',
                'priority_trend',
                'priority_sla',
              ].includes(key)
                ? 0
                : [
                      'satisfaction_window_days',
                      'sentiment_window_days',
                      'health_trend_window_days',
                    ].includes(key)
                  ? 1
                  : 0.01
            "
            :max="
              key === 'health_hysteresis_points'
                ? 100 - config.rules.healthy_threshold
                : [
                      'satisfaction_window_days',
                      'sentiment_window_days',
                      'health_trend_window_days',
                    ].includes(key)
                  ? 3650
                  : key === 'automatic_action_cooldown_hours'
                    ? 8760
                    : undefined
            "
            :class="inputClass"
          /><input
            v-else-if="key === 'renewal_window_days'"
            :value="config.rules[key].join(', ')"
            :class="inputClass"
            @change="
              config.rules[key] = $event.target.value
                .split(',')
                .map(value => Number(value.trim()))
            "
          /><input
            v-else-if="Array.isArray(config.rules[key])"
            :value="config.rules[key].join(', ')"
            :class="inputClass"
            @change="
              config.rules[key] = $event.target.value
                .split(',')
                .map(value => value.trim())
                .filter(Boolean)
            "
          /><textarea
            v-else
            v-model="config.rules[key]"
            :class="inputClass"
          />
        </label>
      </div>
      <PortfolioCapacityLimitsForm
        v-model="config.rules.portfolio_capacity_limits"
        :owners="metadata.owners || []"
        :disabled="busy"
        @validity="invalidCapacity = !$event"
      />
      <RequiredDocumentsForm
        v-if="!distributionOnly"
        v-model="config.rules.required_documents"
        :disabled="busy"
      />
      <PriorityBandsForm
        v-if="!distributionOnly"
        v-model="config.rules.priority_bands"
        :disabled="busy"
        @validity="invalidPriorityBands = !$event"
      />
      <PlaybookFlowPolicyForm
        v-if="!distributionOnly && config.rules.playbook_flow_policy"
        v-model="config.rules.playbook_flow_policy"
        :disabled="busy"
        @validity="invalidFlowPolicy = !$event"
      />
      <button
        type="submit"
        :class="buttonClass"
        class="mt-5"
        :disabled="
          busy || invalidFlowPolicy || invalidCapacity || invalidPriorityBands
        "
      >
        {{ t('RELATIONSHIP.SAVE') }}
      </button>
    </form>
    <HealthConfigurationPreview
      v-if="config && screen === 'settings' && !distributionOnly"
      :configuration="config"
      :formatting="metadata.formatting"
      :disabled="
        busy || invalidFlowPolicy || invalidCapacity || invalidPriorityBands
      "
    />
    <section
      v-if="config"
      class="mt-6"
      aria-labelledby="configuration-history-title"
    >
      <h3
        id="configuration-history-title"
        class="mb-3 font-semibold"
      >
        {{ t('RELATIONSHIP.CONFIG_HISTORY') }}
      </h3>
      <p v-if="!config.history?.length">
        {{ t('RELATIONSHIP.CONFIG_HISTORY_EMPTY') }}
      </p>
      <details
        v-for="version in config.history || []"
        :key="version.version"
        class="mb-2 rounded-xl border border-n-weak p-3"
      >
        <summary class="cursor-pointer text-sm">
          {{ t('RELATIONSHIP.VERSION', { version: version.version }) }} ·
          {{ date(version.created_at) }} ·
          {{
            metadata.owners?.find(
              owner => owner[0] === version.actor_id
            )?.[1] ||
            (version.actor_id
              ? t('RELATIONSHIP.CONFIG_ACTOR', { id: version.actor_id })
              : t('RELATIONSHIP.SYSTEM'))
          }}
        </summary>
        <button
          v-if="version.version < config.version"
          type="button"
          :class="buttonClass"
          :disabled="busy || restorePreparing"
          @click="openRestore(version.version)"
        >
          {{ t('RELATIONSHIP.CONFIG_RESTORE.OPEN') }}
        </button>
        <h4 class="mt-3 font-semibold">{{ t('RELATIONSHIP.WEIGHTS') }}</h4>
        <dl class="grid gap-2 sm:grid-cols-2">
          <div
            v-for="(value, key) in version.weights"
            :key="key"
            class="flex min-w-0 justify-between gap-3 text-sm"
          >
            <dt>{{ t(`RELATIONSHIP.FACTORS.${key}`) }}</dt>
            <dd>{{ value }}</dd>
          </div>
        </dl>
        <h4 class="mt-3 font-semibold">{{ t('RELATIONSHIP.RULES') }}</h4>
        <dl class="grid gap-2 sm:grid-cols-2">
          <div
            v-for="(value, key) in version.rules"
            :key="key"
            class="flex min-w-0 justify-between gap-3 text-sm"
          >
            <dt>{{ t(`RELATIONSHIP.RULE_LABELS.${key}`) }}</dt>
            <dd class="min-w-0 break-words">
              {{ historyValue(value) }}
            </dd>
          </div>
        </dl>
      </details>
      <ConfigurationRestoreDialog
        v-if="restoring"
        :current="restoring.current"
        :historical="restoring.historical"
        :scope-label="restoring.scopeLabel"
        :allowed="allowed"
        :formatting="metadata.formatting"
        @close="restoring = null"
        @saved="restorationSaved"
      />
    </section>
    <OperationsSettingsPanel
      v-if="screen === 'settings'"
      :allowed="allowed && metadata.can_configure_operations"
      :metadata="metadata"
    />
    <template v-if="screen === 'playbooks'">
      <p
        v-if="restoredPlaybook"
        role="status"
        class="mb-4 rounded-lg bg-n-teal-2 p-3 text-n-teal-11"
      >
        {{
          t('RELATIONSHIP.PLAYBOOK_RESTORE.SAVED', {
            source: restoredPlaybook.restored_from_version,
            version: restoredPlaybook.version,
          })
        }}
      </p>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="edit(null)"
      >
        {{ t('RELATIONSHIP.NEW') }}
      </button>
      <ul class="mt-4 divide-y divide-n-weak">
        <li
          v-for="row in books"
          :key="row.id"
          class="min-w-0 space-y-3 py-3"
        >
          <div
            class="flex min-w-0 flex-wrap items-center justify-between gap-3"
          >
            <span
              >{{ row.name }} ·
              {{ t(`RELATIONSHIP.TRIGGERS.${row.trigger_kind}`) }}</span
            ><button
              type="button"
              :class="buttonClass"
              :disabled="busy"
              @click="edit(row)"
            >
              {{ t('RELATIONSHIP.EDIT') }}
            </button>
          </div>
          <PlaybookHistoryPanel
            :book="row"
            :allowed="allowed"
            :disabled="busy || restorePreparing || Boolean(book)"
            @restore="openPlaybookRestore"
          />
        </li>
      </ul>
      <footer class="mt-4 flex flex-wrap items-center justify-end gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || restorePreparing || Boolean(book) || bookPage <= 1"
          @click="changeBookPage(bookPage - 1)"
        >
          {{ t('RELATIONSHIP.PREVIOUS') }}
        </button>
        <span class="text-sm">{{
          t('RELATIONSHIP.PAGE', { page: bookPage, total: bookMeta.total })
        }}</span>
        <button
          type="button"
          :class="buttonClass"
          :disabled="
            busy || restorePreparing || Boolean(book) || bookPage >= bookPages
          "
          @click="changeBookPage(bookPage + 1)"
        >
          {{ t('RELATIONSHIP.NEXT') }}
        </button>
      </footer>
      <PlaybookRestoreDialog
        v-if="restoringPlaybook"
        :current="restoringPlaybook.current"
        :historical="restoringPlaybook.historical"
        :allowed="allowed"
        @close="restoringPlaybook = null"
        @saved="playbookRestored"
      />
      <PlaybookExecutionPanel
        v-if="metadata.playbook_versions_available"
        :allowed="allowed"
      />
      <form
        v-if="book"
        class="mt-4 rounded-xl border border-n-weak p-4"
        @submit.prevent="save"
      >
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.FIELDS.title')
          }}<input
            v-model="book.name"
            required
            :class="inputClass"
        /></label>
        <label class="mt-3 block text-sm"
          >{{ t('RELATIONSHIP.FIELDS.kind')
          }}<select
            v-model="book.trigger_kind"
            :class="inputClass"
          >
            <option
              v-for="trigger in [
                'onboarded',
                'health',
                'satisfaction',
                'no_contact',
                'renewal',
                'ticket',
                'expansion',
                'cancellation',
              ]"
              :key="trigger"
              :value="trigger"
            >
              {{ t(`RELATIONSHIP.TRIGGERS.${trigger}`) }}
            </option>
          </select></label
        >
        <label class="mt-3 block text-sm"
          ><input
            v-model="book.active"
            type="checkbox"
          />
          {{ t('RELATIONSHIP.STATES.active') }}</label
        >
        <h4 class="mt-4 font-semibold">{{ t('RELATIONSHIP.CONDITIONS') }}</h4>
        <div
          v-for="(condition, index) in book.conditions"
          :key="index"
          class="mt-2 flex gap-2"
        >
          <select
            v-model="condition.field"
            :class="inputClass"
            :aria-label="t('RELATIONSHIP.FIELDS.metric')"
            @change="
              condition.operator = 'eq';
              condition.value =
                conditionReferences(condition.field)?.[0]?.[0] || 0;
            "
          >
            <option
              v-for="field in conditionFields"
              :key="field"
              :value="field"
            >
              {{ t(`RELATIONSHIP.CONDITION_FIELDS.${field}`) }}
            </option>
          </select>
          <select
            v-model="condition.operator"
            :class="inputClass"
            :aria-label="t('RELATIONSHIP.OPERATOR')"
          >
            <option
              v-for="operator in conditionReferences(condition.field)
                ? ['eq']
                : ['lt', 'lte', 'eq', 'gte', 'gt']"
              :key="operator"
              :value="operator"
            >
              {{ t(`RELATIONSHIP.OPERATORS.${operator}`) }}
            </option>
          </select>
          <select
            v-if="conditionReferences(condition.field)"
            v-model="condition.value"
            :class="inputClass"
            required
            :aria-label="t('RELATIONSHIP.FIELDS.target')"
          >
            <option
              v-for="reference in conditionReferences(condition.field)"
              :key="reference[0]"
              :value="reference[0]"
            >
              {{ reference[1] }}
            </option>
          </select>
          <input
            v-else
            v-model.number="condition.value"
            type="number"
            step="any"
            required
            :class="inputClass"
            :aria-label="t('RELATIONSHIP.FIELDS.target')"
          />
          <button
            type="button"
            :class="buttonClass"
            @click="book.conditions.splice(index, 1)"
          >
            {{ t('RELATIONSHIP.REMOVE_ITEM') }}
          </button>
        </div>
        <button
          type="button"
          :class="buttonClass"
          class="mt-2"
          :disabled="book.conditions.length >= 20"
          @click="
            book.conditions.push({
              field: 'health_score',
              operator: 'lt',
              value: 60,
            })
          "
        >
          {{ t('RELATIONSHIP.ADD_CONDITION') }}
        </button>
        <div
          v-for="(step, index) in book.steps"
          :key="index"
          class="mt-3 flex flex-wrap gap-2"
        >
          <label class="flex-1 text-xs"
            >{{ t('RELATIONSHIP.FIELDS.title')
            }}<input
              v-model="step.title"
              required
              :class="inputClass" /></label
          ><label class="text-xs"
            >{{ t('RELATIONSHIP.FIELDS.kind')
            }}<select
              v-model="step.kind"
              :class="inputClass"
            >
              <option
                v-for="kind in metadata.playbook_step_kinds || [
                  'activity',
                  'action',
                  'meeting',
                  'success_plan',
                  'risk',
                ]"
                :key="kind"
                :value="kind"
              >
                {{ t(`RELATIONSHIP.PLAYBOOK_STEPS.${kind}`) }}
              </option>
            </select></label
          ><label class="text-xs"
            >{{ t('RELATIONSHIP.AFTER_DAYS')
            }}<input
              v-model.number="step.after_days"
              :disabled="step.kind === 'flow'"
              type="number"
              min="0"
              max="365"
              :class="inputClass" /></label
          ><button
            type="button"
            :class="buttonClass"
            @click="book.steps.splice(index, 1)"
          >
            {{ t('RELATIONSHIP.REMOVE_ITEM') }}
          </button>
        </div>
        <PlaybookDesignPreview
          :book="book"
          @update-step="(index, step) => (book.steps[index] = step)"
        />
        <button
          type="button"
          :class="buttonClass"
          class="mt-3"
          :disabled="book.steps.length >= 50 || busy"
          @click="
            book.steps.push({
              kind: 'activity',
              title: '',
              after_days: 0,
              step_key: crypto.randomUUID(),
            })
          "
        >
          {{ t('RELATIONSHIP.ADD_ITEM') }}</button
        ><button
          type="submit"
          :class="buttonClass"
          class="ml-2"
          :disabled="busy || !book.steps.length"
        >
          {{ t('RELATIONSHIP.SAVE') }}
        </button>
      </form>
    </template>
  </section>
</template>
