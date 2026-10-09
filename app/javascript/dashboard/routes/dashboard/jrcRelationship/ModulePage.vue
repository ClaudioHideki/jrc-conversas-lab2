<script setup>
import { computed, ref, reactive, watch, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import MetricsPanel from './MetricsPanel.vue';
import NicoSummaryPanel from './NicoSummaryPanel.vue';
import PortfolioTable from './PortfolioTable.vue';
import RecordEditor from './RecordEditor.vue';
import CustomerPanel from './CustomerPanel.vue';
import ConfigurationPanel from './ConfigurationPanel.vue';
import SurveyAdministrationPanel from './SurveyAdministrationPanel.vue';
import HandoffPanel from './HandoffPanel.vue';
import SurveyResponseBox from './SurveyResponseBox.vue';
import SurveyReportFilters from './SurveyReportFilters.vue';
import SurveyReportSummary from './SurveyReportSummary.vue';
import SurveyPreparationPanel from './SurveyPreparationPanel.vue';
import SlaSummary from './SlaSummary.vue';
import SurveyDeliveryPanel from './SurveyDeliveryPanel.vue';
import HealthScorePanel from './HealthScorePanel.vue';
import RenewalPipeline from './RenewalPipeline.vue';
import MetricDrilldownPanel from './MetricDrilldownPanel.vue';
import CompanyPicker from '../jrcCustomers/components/CompanyPicker.vue';
import { fixedSurveyScope as normalizeFixedSurveyScope } from './fixedSurveyScope';
import {
  STATES,
  buttonClass,
  inputClass,
  date as formatDate,
  message,
  money as formatMoney,
} from './definitions';
const props = defineProps({
  screen: { type: String, required: true },
  fixedSurveyScope: { type: Object, default: null },
});
const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const metadata = ref(null);
const metrics = ref(null);
const rows = ref([]);
const customers = ref([]);
const pagination = ref({ page: 1, total: 0, per_page: 25 });
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const editing = ref(null);
const selectedCustomer = ref(null);
const selected = ref([]);
const newAssignment = ref(false);
const surveyLink = ref('');
const surveyDelivery = ref(null);
const surveyPreparation = ref(null);
const commercialContacts = ref([]);
const opportunity = ref(null);
const drilldown = ref(null);
const batchMode = ref(false);
const filters = reactive({
  q: '',
  mode: '',
  owner_id: '',
  team_id: '',
  business_unit_id: '',
  segment_id: '',
  product_id: '',
  complexity: '',
  record_status: '',
  type: '',
  priority: '',
  overdue: false,
  from: '',
  to: '',
  period_basis: 'response',
  score_min: '',
  score_max: '',
  mrr_min_cents: '',
  mrr_max_cents: '',
  band: '',
  status: '',
  renewal_days: '',
  renewal_window: '',
  factor: '',
  factor_direction: '',
  classification: '',
  treatment_status: '',
  source_type: '',
  unit_id: '',
  channel: '',
  definition_id: '',
  rule_id: '',
  contract_id: '',
  portfolio_owner_id: '',
  portfolio_status: '',
});
const portfolioOperation = reactive({
  operation: 'activity',
  owner_id: '',
  title: '',
  due_at: '',
  playbook_id: '',
  request_id: crypto.randomUUID(),
});
const assignment = reactive({
  company_id: null,
  owner_id: '',
  team_id: '',
  business_unit_id: '',
  settings: { segment_id: '', product_id: '', complexity: '' },
});
const batch = reactive({
  status: 'completed',
  result: '',
  due_at: '',
  priority: '',
  owner_id: '',
});
const commercial = reactive({ pipeline_id: '', stage_id: '', contact_id: '' });
const portfolioScreen = computed(() =>
  ['overview', 'portfolio', 'health', 'reports'].includes(props.screen)
);
const configScreen = computed(() =>
  ['settings', 'playbooks'].includes(props.screen)
);
const dedicatedScreen = computed(() =>
  ['survey_admin', 'handoffs'].includes(props.screen)
);
const stageOptions = computed(
  () =>
    metadata.value?.pipelines.find(
      row => String(row.id) === String(commercial.pipeline_id)
    )?.stages || []
);
const scope = () => ({
  ...Object.fromEntries(
    Object.entries(filters).filter(
      ([, value]) => value !== '' && value !== false
    )
  ),
  assignment_id: route.query.assignment_id || undefined,
  record_id: route.query.record_id || undefined,
  page: pagination.value.page,
  ...normalizeFixedSurveyScope(props.fixedSurveyScope, props.screen),
});
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  const accountId = route.params.accountId;
  const options = { signal: controller.signal };
  error.value = '';
  loading.value = true;
  rows.value = [];
  drilldown.value = null;
  selected.value = [];
  try {
    const fixed = normalizeFixedSurveyScope(
      props.fixedSurveyScope,
      props.screen
    );
    const meta = await API.metadata(accountId, options);
    if (version !== generation) return;
    metadata.value = meta.data;
    if (configScreen.value || dedicatedScreen.value) return;
    if (fixed) {
      const result = await API.records(
        accountId,
        props.screen,
        scope(),
        options
      );
      if (version !== generation) return;
      rows.value = result.data.payload;
      pagination.value = result.data.meta;
      metrics.value = null;
      customers.value = [];
      return;
    }
    const results = await Promise.all([
      API.dashboard(accountId, scope(), options),
      portfolioScreen.value
        ? API.portfolio(accountId, scope(), options)
        : API.records(accountId, props.screen, scope(), options),
      API.portfolio(
        accountId,
        { per_page: 50, assignment_id: route.query.assignment_id || undefined },
        options
      ),
    ]);
    if (version !== generation) return;
    metrics.value = results[0].data;
    rows.value = results[1].data.payload;
    pagination.value = results[1].data.meta;
    customers.value = results[2].data.payload;
    if (route.query.customer)
      selectedCustomer.value = Number(route.query.customer);
    if (route.query.create && metadata.value.can_manage)
      editing.value = { assignment_id: Number(route.query.assignment_id) };
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED') {
      error.value = message(err);
      metadata.value = null;
      metrics.value = null;
    }
  } finally {
    if (version === generation) loading.value = false;
  }
};
const refresh = () => {
  pagination.value.page = 1;
  load();
};
const mutate = async operation => {
  const version = generation;
  saving.value = true;
  error.value = '';
  try {
    await operation();
    if (version === generation) {
      editing.value = null;
      opportunity.value = null;
      batchMode.value = false;
      newAssignment.value = false;
      if (route.query.create)
        await router.replace({ query: { ...route.query, create: undefined } });
      await load();
    }
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) saving.value = false;
  }
};
const save = fields => {
  const version = generation;
  return mutate(async () => {
    const { data } = await API.saveRecord(
      route.params.accountId,
      props.screen,
      fields,
      editing.value?.id
    );
    if (version === generation && data.survey_token)
      surveyLink.value = `${window.location.origin}/jrc/relacionamento/pesquisas/${data.survey_token}`;
  });
};
const saveAssignment = () =>
  mutate(() =>
    API.saveAssignment(route.params.accountId, {
      ...assignment,
      owner_id: assignment.owner_id || null,
      team_id: assignment.team_id || null,
      business_unit_id: assignment.business_unit_id || null,
    })
  );
const convert = () =>
  mutate(() =>
    API.opportunity(
      route.params.accountId,
      props.screen,
      opportunity.value.id,
      commercial
    )
  );
const chooseOpportunity = async row => {
  const version = generation;
  opportunity.value = row;
  commercialContacts.value = [];
  Object.assign(commercial, { pipeline_id: '', stage_id: '', contact_id: '' });
  try {
    const { data } = await API.workContext(
      route.params.accountId,
      row.assignment_id,
      {},
      { signal: controller.signal }
    );
    if (version === generation && opportunity.value?.id === row.id)
      commercialContacts.value = data.contacts || [];
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED')
      error.value = message(err);
  }
};
const completeBatch = () =>
  mutate(() =>
    API.batch(route.params.accountId, selected.value, {
      ...batch,
      status: batch.status || undefined,
      result: batch.result || undefined,
      priority: batch.priority === '' ? undefined : Number(batch.priority),
      owner_id: batch.owner_id === '' ? undefined : Number(batch.owner_id),
      due_at: batch.due_at ? new Date(batch.due_at).toISOString() : undefined,
    })
  );
const updatePortfolioBatch = () =>
  mutate(() =>
    API.portfolioBatch(route.params.accountId, selected.value, {
      ...portfolioOperation,
      due_at: portfolioOperation.due_at
        ? new Date(portfolioOperation.due_at).toISOString()
        : undefined,
    })
  );
const exportPortfolio = async (history = false) => {
  const version = generation;
  error.value = '';
  try {
    let exporter = history === true ? API.exportHistory : API.exportPortfolio;
    let filename =
      history === true
        ? 'relationship-history.json'
        : 'relationship-portfolio.csv';
    if (props.screen === 'surveys') {
      exporter = API.exportSurveyResponses;
      filename = 'survey-responses.csv';
    }
    const { data } = await exporter(route.params.accountId, scope());
    if (version !== generation) return;
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  } catch (err) {
    if (version === generation) error.value = message(err);
  }
};
const getSurveyLink = async row => {
  const version = generation;
  try {
    const { data } = await API.surveyLink(route.params.accountId, row.id);
    if (version === generation) surveyLink.value = data.url;
  } catch (err) {
    if (version === generation) error.value = message(err);
  }
};
const quick = ({ kind, assignmentId }) =>
  router.push({
    name: `jrc_relationship_${kind}`,
    params: { accountId: route.params.accountId },
    query: { assignment_id: assignmentId, create: '1' },
  });
const metricFilter = key => {
  if (typeof key === 'object' && key.renewal_days) {
    filters.mode = 'renewals';
    filters.renewal_days = key.renewal_days;
  } else if (typeof key === 'object' && key.factor) {
    filters.factor = key.factor;
    filters.factor_direction = key.direction;
  } else if (typeof key === 'object') filters.band = key.band;
  else if (['at_risk', 'mrr_at_risk_cents'].includes(key))
    filters.mode = 'critical';
  else if (key === 'active') filters.status = 'active';
  else if (key === 'churned') filters.status = 'churned';
  else if (key === 'without_contact') filters.mode = 'without_contact';
  else if (key === 'overdue_actions' || key === 'actions_today') {
    router.push({
      name: 'jrc_relationship_actions',
      params: { accountId: route.params.accountId },
      query:
        key === 'overdue_actions'
          ? { overdue: 'true' }
          : {
              from: new Date().toLocaleDateString('en-CA'),
              to: new Date().toLocaleDateString('en-CA'),
            },
    });
    return;
  } else if (
    ['waiting_customer_actions', 'waiting_finance_actions'].includes(key)
  ) {
    router.push({
      name: 'jrc_relationship_actions',
      params: { accountId: route.params.accountId },
      query: {
        status:
          key === 'waiting_finance_actions'
            ? 'waiting_finance'
            : 'waiting_customer',
      },
    });
    return;
  } else return;
  refresh();
};
const inspectMetric = async (metric, page = 1) => {
  const requested = typeof metric === 'object' ? metric : { metric };
  const version = generation;
  error.value = '';
  try {
    const { data } = await API.drilldown(
      route.params.accountId,
      { ...scope(), ...requested, page },
      { signal: controller?.signal }
    );
    if (version === generation) drilldown.value = data;
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED')
      error.value = message(err);
  }
};
const renewalFilter = window => {
  filters.renewal_window = window;
  refresh();
};
const recordColumns = computed(() => {
  if (props.screen === 'risks')
    return [
      'customer',
      'severity',
      'reason',
      'mrr_at_risk',
      'owner_id',
      'due_at',
      'status',
      'health',
      'origin',
      'updated_at',
      'actions',
    ];
  if (props.screen === 'expansion')
    return [
      'customer',
      'title',
      'expansion_kind',
      'product_id',
      'potential_cents',
      'evidence',
      'status',
      'deal_status',
      'expansion_won_cents',
      'owner_id',
      'actions',
    ];
  if (props.screen === 'surveys')
    return [
      'customer',
      'kind',
      'score',
      'comment',
      'channel',
      'status',
      'responded_at',
      'expires_at',
      'actions',
    ];
  if (props.screen === 'renewals')
    return [
      'customer',
      'contract',
      'renewal',
      'days_remaining',
      'current_mrr',
      'proposed_mrr_cents',
      'adjustment',
      'products',
      'risk',
      'owner_id',
      'status',
      'actions',
    ];
  return ['customer', 'title', 'status', 'owner_id', 'due_at', 'actions'];
});
const goPage = direction => {
  pagination.value.page += direction;
  load();
};
const openDeal = record =>
  router.push({
    name: 'crm_deals',
    params: { accountId: route.params.accountId },
    query: { dealId: record.deal_id },
  });
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.screen,
    () => props.fixedSurveyScope,
    () => props.fixedSurveyScope?.unit_id,
    () => props.fixedSurveyScope?.source_type,
    () => route.query.assignment_id,
    () => route.query.record_id,
    () => route.query.create,
    () => route.query.overdue,
    () => route.query.from,
    () => route.query.to,
    () => route.query.status,
    () => route.query.owner_id,
    () => route.query.agent_q,
    () => route.query.band,
    () => route.query.renewal_days,
    () => route.query.mode,
    () => route.query.segment_id,
    () => route.query.product_id,
    () => route.query.business_unit_id,
    () => route.query.complexity,
    () => route.query.factor,
    () => route.query.factor_direction,
    () => route.query.customer,
  ],
  () => {
    metadata.value = null;
    metrics.value = null;
    customers.value = [];
    editing.value = null;
    selectedCustomer.value = null;
    newAssignment.value = false;
    opportunity.value = null;
    batchMode.value = false;
    Object.assign(assignment, {
      company_id: null,
      owner_id: '',
      team_id: '',
      business_unit_id: '',
      exception_reason: '',
      settings: { segment_id: '', product_id: '', complexity: '' },
    });
    surveyLink.value = '';
    surveyDelivery.value = null;
    surveyPreparation.value = null;
    commercialContacts.value = [];
    filters.record_status = route.query.status || '';
    filters.overdue = route.query.overdue === 'true';
    filters.from = route.query.from || '';
    filters.to = route.query.to || '';
    if (props.fixedSurveyScope) {
      filters.source_type = props.fixedSurveyScope.source_type;
      filters.unit_id = props.fixedSurveyScope.unit_id;
    }
    [
      'owner_id',
      'agent_q',
      'band',
      'renewal_days',
      'mode',
      'segment_id',
      'product_id',
      'business_unit_id',
      'complexity',
      'factor',
      'factor_direction',
    ].forEach(key => {
      filters[key] = route.query[key] || '';
    });
    Object.assign(portfolioOperation, {
      operation: 'assign',
      owner_id: '',
      title: '',
      due_at: '',
      playbook_id: '',
      request_id: crypto.randomUUID(),
    });
    pagination.value.page = 1;
    load();
  },
  { immediate: true }
);
watch(
  () => commercial.pipeline_id,
  () => {
    commercial.stage_id = '';
  }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
const date = value => formatDate(value, metadata.value?.formatting);
const money = value => formatMoney(value, metadata.value?.formatting);
</script>

<template>
  <div class="flex-1 space-y-5 overflow-y-auto p-5 md:p-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2 class="text-lg font-semibold">
        {{ t(`RELATIONSHIP.SCREENS.${screen}`) }}
      </h2>
      <div class="flex gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="loading"
          @click="load"
        >
          {{ t('RELATIONSHIP.REFRESH') }}</button
        ><button
          v-if="metadata?.can_team && portfolioScreen"
          type="button"
          :class="buttonClass"
          @click="exportPortfolio"
        >
          {{ t('RELATIONSHIP.EXPORT') }}</button
        ><button
          v-if="metadata && screen === 'surveys'"
          type="button"
          :class="buttonClass"
          :disabled="loading"
          data-testid="export-survey-responses"
          @click="exportPortfolio"
        >
          {{ t('RELATIONSHIP.EXPORT') }}</button
        ><button
          v-if="metadata?.can_export_history && screen === 'reports'"
          :class="buttonClass"
          :disabled="saving"
          @click="exportPortfolio(true)"
        >
          {{ t('RELATIONSHIP.EXPORT_HISTORY') }}</button
        ><button
          v-if="
            metadata?.can_manage &&
            !fixedSurveyScope &&
            !portfolioScreen &&
            !configScreen &&
            !dedicatedScreen &&
            screen !== 'renewals' &&
            (!['expansion'].includes(screen) || metadata.can_crm)
          "
          type="button"
          :class="buttonClass"
          @click="editing = {}"
        >
          {{ t('RELATIONSHIP.NEW') }}</button
        ><button
          v-if="metadata?.can_team && screen === 'portfolio'"
          type="button"
          :class="buttonClass"
          @click="newAssignment = !newAssignment"
        >
          {{ t('RELATIONSHIP.ADD_CUSTOMER') }}
        </button>
      </div>
    </div>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="loading"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <template v-if="metadata">
      <ConfigurationPanel
        v-if="configScreen"
        :screen="screen"
        :allowed="metadata.can_configure"
        :metadata="metadata"
      />
      <SurveyAdministrationPanel
        v-else-if="screen === 'survey_admin'"
        :allowed="metadata.can_administer_surveys"
        :metadata="metadata"
      />
      <HandoffPanel
        v-else-if="screen === 'handoffs'"
        :allowed="metadata.can_team"
      />
      <template v-else>
        <form
          class="flex flex-wrap items-end gap-3 rounded-xl border border-n-weak p-4"
          @submit.prevent="refresh"
        >
          <label class="min-w-40 flex-1 text-xs"
            >{{ t('RELATIONSHIP.SEARCH')
            }}<input
              v-model="filters.q"
              type="search"
              :class="inputClass"
          /></label>
          <label class="text-xs"
            >{{ t('RELATIONSHIP.FIELDS.mode')
            }}<select
              v-model="filters.mode"
              :class="inputClass"
            >
              <option value="">{{ t('RELATIONSHIP.AUTHORIZED') }}</option>
              <option
                v-for="mode in screen === 'surveys'
                  ? ['mine', 'unassigned']
                  : [
                      'mine',
                      'unassigned',
                      'team',
                      'critical',
                      'renewals',
                      'expansion',
                    ]"
                :key="mode"
                :value="mode"
              >
                {{ t(`RELATIONSHIP.MODES.${mode}`) }}
              </option>
            </select></label
          >
          <label class="text-xs"
            >{{ t('RELATIONSHIP.FIELDS.owner_id')
            }}<select
              v-model="filters.owner_id"
              :class="inputClass"
            >
              <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
              <option
                v-for="owner in metadata.owners"
                :key="owner[0]"
                :value="owner[0]"
              >
                {{ owner[1] }}
              </option>
            </select></label
          >
          <label class="text-xs"
            >{{ t('RELATIONSHIP.FIELDS.team_id')
            }}<select
              v-model="filters.team_id"
              :class="inputClass"
            >
              <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
              <option
                v-for="team in metadata.teams"
                :key="team[0]"
                :value="team[0]"
              >
                {{ team[1] }}
              </option>
            </select></label
          >
          <label class="text-xs"
            >{{ t('RELATIONSHIP.FIELDS.business_unit_id')
            }}<select
              v-model="filters.business_unit_id"
              :class="inputClass"
            >
              <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
              <option
                v-for="unit in metadata.units"
                :key="unit[0]"
                :value="unit[0]"
              >
                {{ unit[1] }}
              </option>
            </select></label
          >
          <label
            v-if="STATES[screen]"
            class="text-xs"
            >{{ t('RELATIONSHIP.FIELDS.status')
            }}<select
              v-model="filters.record_status"
              :class="inputClass"
            >
              <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
              <option
                v-for="status in STATES[screen]"
                :key="status"
                :value="status"
              >
                {{ t(`RELATIONSHIP.STATES.${status}`) }}
              </option>
            </select></label
          >
          <label
            v-for="key in ['segment_id', 'product_id']"
            :key="key"
            class="text-xs"
            >{{ t(`RELATIONSHIP.FIELDS.${key}`)
            }}<select
              v-model="filters[key]"
              :class="inputClass"
            >
              <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
              <option
                v-for="item in metadata[
                  key === 'segment_id' ? 'segments' : 'products'
                ] || []"
                :key="item[0]"
                :value="item[0]"
              >
                {{ item[1] }}
              </option>
            </select></label
          >
          <label class="text-xs"
            >{{ t('RELATIONSHIP.FIELDS.complexity')
            }}<input
              v-model="filters.complexity"
              :class="inputClass"
          /></label>
          <template v-if="portfolioScreen">
            <label
              v-for="key in [
                'score_min',
                'score_max',
                'mrr_min_cents',
                'mrr_max_cents',
              ]"
              :key="key"
              class="text-xs"
              >{{ t(`RELATIONSHIP.FIELDS.${key}`)
              }}<input
                v-model="filters[key]"
                type="number"
                min="0"
                :class="inputClass"
            /></label>
            <label class="text-xs"
              >{{ t('RELATIONSHIP.FIELDS.health')
              }}<select
                v-model="filters.band"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
                <option
                  v-for="band in ['healthy', 'attention', 'risk', 'critical']"
                  :key="band"
                  :value="band"
                >
                  {{ t(`RELATIONSHIP.BANDS.${band}`) }}
                </option>
              </select></label
            >
            <label class="text-xs"
              >{{ t('RELATIONSHIP.FIELDS.status')
              }}<select
                v-model="filters.status"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
                <option
                  v-for="status in [
                    'onboarding',
                    'active',
                    'at_risk',
                    'churned',
                    'inactive',
                  ]"
                  :key="status"
                  :value="status"
                >
                  {{ t(`RELATIONSHIP.STATES.${status}`) }}
                </option>
              </select></label
            >
          </template>
          <SurveyReportFilters
            v-if="screen === 'surveys'"
            :filters="filters"
            :metadata="metadata"
            :report="pagination.survey_report || {}"
            :fixed-scope="!!fixedSurveyScope"
            @update="Object.assign(filters, $event)"
          />
          <template
            v-if="
              ['reports', 'actions', 'overview', 'surveys'].includes(screen)
            "
          >
            <label
              v-for="key in ['from', 'to']"
              :key="key"
              class="text-xs"
              >{{ t(`RELATIONSHIP.FIELDS.${key}`)
              }}<input
                v-model="filters[key]"
                type="date"
                :class="inputClass"
            /></label>
          </template>
          <template v-if="screen === 'actions'">
            <label class="text-xs"
              >{{ t('RELATIONSHIP.FIELDS.kind')
              }}<select
                v-model="filters.type"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
                <option
                  v-for="kind in [
                    'manual',
                    'health',
                    'health_drop',
                    'no_contact',
                    'ticket',
                    'finance',
                    'satisfaction',
                    'renewal',
                    'onboarding',
                    'activity',
                    'post_ticket',
                    'recurring_ticket',
                    'expansion',
                    'retention',
                  ]"
                  :key="kind"
                  :value="kind"
                >
                  {{ t(`RELATIONSHIP.TRIGGERS.${kind}`) }}
                </option>
              </select></label
            ><label class="text-xs"
              >{{ t('RELATIONSHIP.FIELDS.priority')
              }}<input
                v-model="filters.priority"
                type="number"
                min="0"
                max="100"
                :class="inputClass" /></label
            ><label class="text-xs"
              ><input
                v-model="filters.overdue"
                type="checkbox"
              />
              {{ t('RELATIONSHIP.OVERDUE') }}</label
            >
          </template>
          <button
            type="submit"
            :class="buttonClass"
            :disabled="loading"
          >
            {{ t('RELATIONSHIP.FILTER') }}
          </button>
        </form>
        <button
          v-if="filters.factor"
          :class="buttonClass"
          @click="
            filters.factor = '';
            filters.factor_direction = '';
            refresh();
          "
        >
          {{ t('RELATIONSHIP.FACTORS.' + filters.factor) }} ·
          {{ t('RELATIONSHIP.CLEAR_FACTOR_FILTER') }}
        </button>
        <form
          v-if="newAssignment"
          class="rounded-xl border border-n-weak p-4"
          @submit.prevent="saveAssignment"
        >
          <h3 class="mb-3 font-semibold">
            {{ t('RELATIONSHIP.ADD_CUSTOMER') }}
          </h3>
          <CompanyPicker
            v-model="assignment.company_id"
            :disabled="saving"
          />
          <div class="mt-3 flex gap-3">
            <label class="flex-1 text-sm"
              >{{ t('RELATIONSHIP.FIELDS.owner_id')
              }}<select
                v-model="assignment.owner_id"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.UNASSIGNED') }}</option>
                <option
                  v-for="owner in metadata.owners"
                  :key="owner[0]"
                  :value="owner[0]"
                >
                  {{ owner[1] }}
                </option>
              </select></label
            ><label class="flex-1 text-sm"
              >{{ t('RELATIONSHIP.FIELDS.team_id')
              }}<select
                v-model="assignment.team_id"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
                <option
                  v-for="team in metadata.teams"
                  :key="team[0]"
                  :value="team[0]"
                >
                  {{ team[1] }}
                </option>
              </select></label
            >
          </div>
          <div class="mt-3 grid gap-3 md:grid-cols-3">
            <label class="text-sm"
              >{{ t('RELATIONSHIP.FIELDS.business_unit_id')
              }}<select
                v-model="assignment.business_unit_id"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
                <option
                  v-for="unit in metadata.units"
                  :key="unit[0]"
                  :value="unit[0]"
                >
                  {{ unit[1] }}
                </option>
              </select></label
            >
            <label
              v-for="key in ['segment_id', 'product_id']"
              :key="key"
              class="text-sm"
              >{{ t(`RELATIONSHIP.FIELDS.${key}`)
              }}<select
                v-model="assignment.settings[key]"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
                <option
                  v-for="item in metadata[
                    key === 'segment_id' ? 'segments' : 'products'
                  ] || []"
                  :key="item[0]"
                  :value="item[0]"
                >
                  {{ item[1] }}
                </option>
              </select></label
            >
          </div>
          <label class="mt-3 block text-sm"
            >{{ t('RELATIONSHIP.FIELDS.complexity')
            }}<input
              v-model="assignment.settings.complexity"
              :class="inputClass"
          /></label>
          <label class="mt-3 block text-sm"
            >{{ t('RELATIONSHIP.ELIGIBILITY_EXCEPTION_REASON')
            }}<textarea
              v-model="assignment.exception_reason"
              maxlength="2000"
              :class="inputClass"
              data-testid="eligibility-exception-reason"
            />
            <span class="text-xs text-n-slate-11">{{
              t('RELATIONSHIP.ELIGIBILITY_EXCEPTION_GUIDANCE')
            }}</span></label
          >
          <button
            type="submit"
            :class="buttonClass"
            class="mt-3"
            :disabled="saving || !assignment.company_id"
          >
            {{ t('RELATIONSHIP.SAVE') }}
          </button>
        </form>
        <MetricsPanel
          v-if="
            metrics &&
            [
              'overview',
              'reports',
              'actions',
              'portfolio',
              'expansion',
              'surveys',
            ].includes(screen)
          "
          :metrics="metrics"
          :metadata="metadata"
          :mode="
            ['portfolio', 'actions', 'expansion', 'surveys'].includes(screen)
              ? screen
              : 'all'
          "
          inspect
          @filter="metricFilter"
          @inspect="inspectMetric"
        />
        <MetricDrilldownPanel
          v-if="drilldown"
          :data="drilldown"
          :metadata="metadata"
          @close="drilldown = null"
          @page="
            inspectMetric(
              { metric: drilldown.metric, day: drilldown.day },
              $event
            )
          "
        />
        <HealthScorePanel
          v-if="screen === 'health' && metrics"
          :metrics="metrics"
          :rows="rows"
          :metadata="metadata"
          @open="selectedCustomer = $event"
          @filter="metricFilter"
          @inspect="inspectMetric"
        />
        <RenewalPipeline
          v-if="screen === 'renewals'"
          :windows="pagination.renewal_windows || {}"
          :ranges="pagination.renewal_ranges || {}"
          :selected="filters.renewal_window"
          @filter="renewalFilter"
        />
        <SurveyReportSummary
          v-if="screen === 'surveys' && pagination.survey_report"
          :report="pagination.survey_report"
        />
        <NicoSummaryPanel
          v-if="screen === 'overview' && metrics"
          :metrics="metrics"
          :enabled="metadata.can_nico"
          :metadata="metadata"
          @customer="selectedCustomer = $event"
        />
        <p
          v-if="screen === 'surveys'"
          class="text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIP.NATIVE_CSAT_GUIDANCE') }}
        </p>
        <RecordEditor
          v-if="editing"
          :key="`${screen}:${editing.id || 'new'}`"
          :kind="screen"
          :record="editing"
          :customers="customers"
          :metadata="metadata"
          :busy="saving"
          :read-only="!metadata.can_manage"
          @save="save"
          @close="editing = null"
        />
        <p
          v-if="surveyLink"
          class="rounded-lg border border-n-weak p-3 text-sm"
        >
          <a
            :href="surveyLink"
            target="_blank"
            rel="noopener noreferrer"
            class="text-n-brand underline"
            >{{ t('RELATIONSHIP.SURVEY_LINK') }}</a
          >
        </p>
        <CustomerPanel
          v-if="selectedCustomer"
          :assignment-id="selectedCustomer"
          :metadata="metadata"
          @changed="load"
          @close="selectedCustomer = null"
        />
        <SurveyPreparationPanel
          v-if="surveyPreparation"
          :survey="surveyPreparation"
          @close="surveyPreparation = null"
        />
        <SurveyDeliveryPanel
          v-if="surveyDelivery"
          :assignment-id="surveyDelivery.assignment_id"
          :survey-id="surveyDelivery.id"
          @sent="
            surveyDelivery = null;
            load();
          "
          @close="surveyDelivery = null"
        />
        <PortfolioTable
          v-if="portfolioScreen && screen !== 'health' && rows.length"
          v-model:selected="selected"
          :rows="rows"
          :metadata="metadata"
          :can-manage="metadata.can_manage"
          @open="selectedCustomer = $event"
          @quick="quick"
        />
        <form
          v-if="portfolioScreen && metadata.can_manage && selected.length"
          class="rounded-xl border border-n-weak p-4"
          @submit.prevent="updatePortfolioBatch"
        >
          <h3 class="mb-3 font-semibold">
            {{ t('RELATIONSHIP.PORTFOLIO_BATCH', { count: selected.length }) }}
          </h3>
          <div class="flex flex-wrap items-end gap-3">
            <label
              >{{ t('RELATIONSHIP.FIELDS.actions')
              }}<select
                v-model="portfolioOperation.operation"
                :class="inputClass"
              >
                <option
                  v-if="metadata.can_team"
                  value="assign"
                >
                  {{ t('RELATIONSHIP.ASSIGN') }}
                </option>
                <option value="activity">
                  {{ t('RELATIONSHIP.NEW_ACTIVITY') }}
                </option>
                <option value="playbook">
                  {{ t('RELATIONSHIP.APPLY_PLAYBOOK') }}
                </option>
              </select></label
            >
            <label v-if="portfolioOperation.operation === 'assign'"
              >{{ t('RELATIONSHIP.FIELDS.owner_id')
              }}<select
                v-model="portfolioOperation.owner_id"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.UNASSIGNED') }}</option>
                <option
                  v-for="owner in metadata.owners"
                  :key="owner[0]"
                  :value="owner[0]"
                >
                  {{ owner[1] }}
                </option>
              </select></label
            >
            <template v-if="portfolioOperation.operation === 'activity'">
              <label
                >{{ t('RELATIONSHIP.FIELDS.title')
                }}<input
                  v-model="portfolioOperation.title"
                  required
                  :class="inputClass" /></label
              ><label
                >{{ t('RELATIONSHIP.FIELDS.due_at')
                }}<input
                  v-model="portfolioOperation.due_at"
                  type="datetime-local"
                  required
                  :class="inputClass"
              /></label>
            </template>
            <label v-if="portfolioOperation.operation === 'playbook'"
              >{{ t('RELATIONSHIP.SCREENS.playbooks')
              }}<select
                v-model="portfolioOperation.playbook_id"
                required
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
                <option
                  v-for="book in metadata.playbooks"
                  :key="book[0]"
                  :value="book[0]"
                >
                  {{ book[1] }}
                </option>
              </select></label
            >
            <button
              type="submit"
              :class="buttonClass"
              :disabled="saving || selected.length > 50"
            >
              {{ t('RELATIONSHIP.SAVE') }}
            </button>
          </div>
        </form>
        <template v-if="!portfolioScreen && rows.length">
          <button
            v-if="
              screen === 'actions' && metadata.can_manage && selected.length
            "
            type="button"
            :class="buttonClass"
            @click="batchMode = !batchMode"
          >
            {{ t('RELATIONSHIP.BATCH', { count: selected.length }) }}
          </button>
          <form
            v-if="batchMode"
            class="mt-3 flex flex-wrap items-end gap-2 rounded-xl border border-n-weak p-4"
            @submit.prevent="completeBatch"
          >
            <label class="text-sm"
              >{{ t('RELATIONSHIP.FIELDS.status')
              }}<select
                v-model="batch.status"
                data-testid="batch-status"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.KEEP_CURRENT') }}</option>
                <option
                  v-for="status in STATES.actions"
                  :key="status"
                  :value="status"
                >
                  {{ t(`RELATIONSHIP.STATES.${status}`) }}
                </option>
              </select></label
            ><label class="flex-1 text-sm"
              >{{ t('RELATIONSHIP.FIELDS.result')
              }}<input
                data-testid="batch-result"
                v-model="batch.result"
                :class="inputClass"
                :required="batch.status === 'completed'" /></label
            ><label class="text-sm"
              >{{ t('RELATIONSHIP.FIELDS.due_at')
              }}<input
                v-model="batch.due_at"
                type="datetime-local"
                :class="inputClass"
            /></label>
            <label class="text-sm"
              >{{ t('RELATIONSHIP.FIELDS.priority')
              }}<input
                v-model="batch.priority"
                data-testid="batch-priority"
                type="number"
                min="0"
                max="100"
                :class="inputClass"
                :placeholder="t('RELATIONSHIP.KEEP_CURRENT')"
            /></label>
            <label
              v-if="metadata.can_team"
              class="text-sm"
              >{{ t('RELATIONSHIP.FIELDS.owner_id')
              }}<select
                v-model="batch.owner_id"
                data-testid="batch-owner"
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.KEEP_CURRENT') }}</option>
                <option
                  v-for="owner in metadata.owners"
                  :key="owner[0]"
                  :value="owner[0]"
                >
                  {{ owner[1] }}
                </option>
              </select></label
            >
            <button
              type="submit"
              :class="buttonClass"
              :disabled="saving"
            >
              {{ t('RELATIONSHIP.SAVE') }}
            </button>
          </form>
          <div class="overflow-x-auto rounded-xl border border-n-weak">
            <table class="w-full text-left text-sm">
              <thead class="bg-n-alpha-2 text-xs text-n-slate-11">
                <tr>
                  <th
                    v-if="screen === 'actions'"
                    class="p-3"
                  >
                    {{ t('RELATIONSHIP.SELECT') }}
                  </th>
                  <th
                    v-for="key in recordColumns"
                    :key="key"
                    class="p-3"
                  >
                    {{ t(`RELATIONSHIP.FIELDS.${key}`) }}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="row in rows"
                  :key="row.id"
                >
                  <td
                    v-if="screen === 'actions'"
                    class="p-3"
                  >
                    <input
                      v-model="selected"
                      :value="row.id"
                      type="checkbox"
                      :aria-label="row.reason"
                    />
                  </td>
                  <td class="p-3">
                    <button
                      type="button"
                      class="text-n-brand"
                      @click="selectedCustomer = row.assignment_id"
                    >
                      {{ row.customer_name }}
                    </button>
                  </td>
                  <template v-if="screen === 'risks'">
                    <td class="p-3 font-semibold">
                      {{ t(`RELATIONSHIP.STATES.${row.severity}`) }}
                    </td>
                    <td class="p-3">
                      <button
                        class="text-n-brand"
                        @click="editing = row"
                      >
                        {{ row.reason }}
                      </button>
                    </td>
                    <td class="p-3">{{ money(row.mrr_cents) }}</td>
                    <td class="p-3">
                      {{ row.owner_name || t('RELATIONSHIP.UNASSIGNED') }}
                    </td>
                    <td class="p-3">
                      {{ date(row.due_at)
                      }}<SlaSummary
                        :sla="row.sla"
                        :metadata="metadata"
                      />
                    </td>
                    <td class="p-3">
                      {{ t(`RELATIONSHIP.STATES.${row.status}`) }}
                    </td>
                    <td class="p-3">{{ row.health?.score ?? '—' }}</td>
                    <td class="p-3">
                      {{ t(`RELATIONSHIP.TRIGGERS.${row.origin}`) }}
                    </td>
                    <td class="p-3">{{ date(row.updated_at) }}</td>
                  </template>
                  <template v-else-if="screen === 'renewals'">
                    <td class="p-3">
                      <RouterLink
                        :to="{
                          name: 'crm_contracts',
                          params: { accountId: route.params.accountId },
                          query: { contractId: row.contract_id },
                        }"
                        class="text-n-brand"
                      >
                        {{ row.commercial_context?.contract_number }}
                      </RouterLink>
                    </td>
                    <td class="p-3">{{ date(row.renewal_on) }}</td>
                    <td class="p-3">
                      {{ row.commercial_context?.days_remaining ?? '—' }}
                    </td>
                    <td class="p-3">
                      {{ money(row.commercial_context?.current_mrr_cents) }}
                    </td>
                    <td class="p-3">{{ money(row.proposed_mrr_cents) }}</td>
                    <td class="p-3">
                      {{ row.commercial_context?.adjustment_percent ?? '—' }}%
                    </td>
                    <td class="p-3">
                      {{ row.commercial_context?.products.join(', ') }}
                    </td>
                    <td class="p-3">
                      {{ row.commercial_context?.health?.score ?? '—' }}
                      <p
                        v-for="risk in row.commercial_context?.risks || []"
                        :key="risk.id"
                      >
                        {{ t(`RELATIONSHIP.STATES.${risk.severity}`) }} ·
                        {{ risk.reason }}
                      </p>
                    </td>
                    <td class="p-3">
                      {{ row.owner_name || t('RELATIONSHIP.UNASSIGNED') }}
                    </td>
                    <td class="p-3">
                      {{ t(`RELATIONSHIP.STATES.${row.status}`) }}
                    </td>
                  </template>
                  <template v-else-if="screen === 'expansion'">
                    <td class="p-3">{{ row.title }}</td>
                    <td class="p-3">
                      {{
                        t(
                          `RELATIONSHIP.STATES.${row.commercial_context?.expansion_kind || 'upsell'}`
                        )
                      }}
                    </td>
                    <td class="p-3">
                      {{ row.commercial_context?.product_name || '—' }}
                    </td>
                    <td class="p-3">{{ money(row.potential_cents) }}</td>
                    <td class="p-3">{{ row.evidence || '—' }}</td>
                    <td class="p-3">
                      {{ t(`RELATIONSHIP.STATES.${row.status}`) }}
                    </td>
                    <td class="p-3">
                      {{
                        row.commercial_context?.deal
                          ? t(
                              `RELATIONSHIP.DEAL_STATES.${row.commercial_context.deal.status}`
                            )
                          : '—'
                      }}
                    </td>
                    <td class="p-3">
                      {{ money(row.commercial_context?.won_cents) }}
                      <RouterLink
                        v-for="result in row.commercial_context
                          ?.commercial_returns || []"
                        :key="result.contract_id"
                        class="mt-1 block text-xs text-n-brand underline"
                        :to="{
                          name: 'crm_contracts',
                          params: { accountId: route.params.accountId },
                          query: { contractId: result.contract_id },
                        }"
                      >
                        {{ t('RELATIONSHIP.COMMERCIAL_RETURN') }} ·
                        {{ money(result.monthly_cents) }}
                      </RouterLink>
                    </td>
                    <td class="p-3">
                      {{ row.owner_name || t('RELATIONSHIP.UNASSIGNED') }}
                    </td>
                  </template>
                  <template v-else-if="screen === 'surveys'">
                    <td class="p-3">{{ row.kind.toUpperCase() }}</td>
                    <td class="p-3">{{ row.score ?? '—' }}</td>
                    <td class="p-3">
                      {{ row.comment || '—'
                      }}<SurveyResponseBox
                        :survey="row"
                        :can-manage="metadata.can_manage"
                        @changed="load"
                      />
                    </td>
                    <td class="p-3">
                      {{
                        t(
                          `RELATIONSHIP.SURVEY_CHANNELS.${row.channel || 'public_link'}`
                        )
                      }}
                    </td>
                    <td class="p-3">
                      {{
                        t(
                          `RELATIONSHIP.STATES.${row.delivery_status || (row.responded_at ? 'responded' : 'awaiting')}`
                        )
                      }}
                    </td>
                    <td class="p-3">{{ date(row.responded_at) }}</td>
                    <td class="p-3">{{ date(row.expires_at) }}</td>
                  </template>
                  <template v-else>
                    <td class="p-3">
                      {{
                        row.title ||
                        row.reason ||
                        t(`RELATIONSHIP.STATES.${row.kind}`)
                      }}
                      <p
                        v-if="row.priority !== undefined"
                        class="text-xs text-n-slate-11"
                      >
                        {{
                          t('RELATIONSHIP.PRIORITY_VALUE', {
                            priority: row.priority,
                          })
                        }}
                      </p>
                      <p
                        v-if="row.potential_cents !== undefined"
                        class="text-xs"
                      >
                        {{ money(row.potential_cents) }}
                      </p>
                      <p
                        v-if="screen === 'surveys' && row.responded_at"
                        class="text-xs"
                      >
                        {{ row.score }} · {{ row.comment }}
                      </p>
                      <div
                        v-if="screen === 'actions'"
                        class="mt-2 flex flex-wrap gap-2"
                      >
                        <RouterLink
                          v-for="source in row.source_links || []"
                          :key="`${source.kind}:${source.id}`"
                          :to="source.route"
                          class="text-xs text-n-brand underline"
                        >
                          {{ t(`RELATIONSHIP.SOURCES.${source.kind}`) }} #{{
                            source.id
                          }}
                        </RouterLink>
                      </div>
                    </td>
                    <td class="p-3">
                      {{
                        row.status
                          ? t(`RELATIONSHIP.STATES.${row.status}`)
                          : row.responded_at
                            ? t('RELATIONSHIP.RESPONDED')
                            : t('RELATIONSHIP.AWAITING')
                      }}
                    </td>
                    <td class="p-3">
                      {{ row.owner_name || t('RELATIONSHIP.UNASSIGNED') }}
                    </td>
                    <td class="p-3">
                      {{
                        date(
                          row.due_at ||
                            row.scheduled_at ||
                            row.target_on ||
                            row.renewal_on ||
                            row.expires_at
                        )
                      }}
                      <SlaSummary
                        v-if="['actions', 'risks'].includes(screen)"
                        :sla="row.sla"
                        :metadata="metadata"
                      />
                    </td>
                  </template>
                  <td class="p-3">
                    <div class="flex flex-wrap gap-2">
                      <template
                        v-if="
                          screen === 'surveys' &&
                          !row.responded_at &&
                          row.delivery_status !== 'expired' &&
                          (!row.source_type ||
                            ['available', 'sent', 'delivered'].includes(
                              row.delivery_status
                            ))
                        "
                      >
                        <button
                          type="button"
                          :class="buttonClass"
                          @click="getSurveyLink(row)"
                        >
                          {{ t('RELATIONSHIP.SURVEY_LINK') }}
                        </button>
                        <button
                          v-if="!fixedSurveyScope"
                          type="button"
                          :class="buttonClass"
                          @click="surveyPreparation = row"
                        >
                          {{ t('RELATIONSHIP.SURVEY_PREPARATION.TITLE') }}
                        </button>
                        <button
                          v-if="
                            metadata.can_manage &&
                            (!row.source_type ||
                              ['available', 'sent', 'delivered'].includes(
                                row.status
                              ))
                          "
                          type="button"
                          :class="buttonClass"
                          @click="surveyDelivery = row"
                        >
                          {{ t('RELATIONSHIP.SEND_SURVEY') }}
                        </button>
                      </template>
                      <button
                        v-if="metadata.can_manage && screen !== 'surveys'"
                        type="button"
                        :class="buttonClass"
                        @click="editing = row"
                      >
                        {{ t('RELATIONSHIP.EDIT') }}</button
                      ><button
                        v-if="
                          metadata.can_manage &&
                          metadata.can_crm &&
                          ['expansion', 'renewals'].includes(screen) &&
                          !row.deal_id &&
                          row.status !== 'rejected'
                        "
                        type="button"
                        :class="buttonClass"
                        @click="chooseOpportunity(row)"
                      >
                        {{ t('RELATIONSHIP.CREATE_OPPORTUNITY') }}</button
                      ><button
                        v-if="row.deal_id && metadata.can_crm"
                        type="button"
                        :class="buttonClass"
                        @click="openDeal(row)"
                      >
                        {{ t('RELATIONSHIP.OPEN_CRM') }}</button
                      ><RouterLink
                        v-if="row.activity_id"
                        :class="buttonClass"
                        :to="{
                          name: 'crm_activities',
                          params: { accountId: route.params.accountId },
                          query: { activityId: row.activity_id },
                        }"
                      >
                        {{ t('RELATIONSHIP.NEW_ACTIVITY') }}
                      </RouterLink>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
        <form
          v-if="opportunity"
          class="rounded-xl border border-n-weak p-4"
          @submit.prevent="convert"
        >
          <h3 class="mb-3 font-semibold">
            {{ t('RELATIONSHIP.CREATE_OPPORTUNITY') }} ·
            {{ opportunity.title || opportunity.customer_name }}
          </h3>
          <div class="flex flex-wrap items-end gap-3">
            <label class="flex-1 text-sm"
              >{{ t('RELATIONSHIP.FIELDS.contact_id') }}
              <select
                v-model="commercial.contact_id"
                required
                :class="inputClass"
                data-testid="opportunity-contact"
              >
                <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
                <option
                  v-for="contact in commercialContacts"
                  :key="contact[0]"
                  :value="contact[0]"
                >
                  {{ contact[1] }}
                </option>
              </select>
            </label>
            <label class="flex-1 text-sm"
              >{{ t('RELATIONSHIP.PIPELINE')
              }}<select
                v-model="commercial.pipeline_id"
                required
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
                <option
                  v-for="pipeline in metadata.pipelines"
                  :key="pipeline.id"
                  :value="pipeline.id"
                >
                  {{ pipeline.name }}
                </option>
              </select></label
            ><label class="flex-1 text-sm"
              >{{ t('RELATIONSHIP.STAGE')
              }}<select
                v-model="commercial.stage_id"
                required
                :class="inputClass"
              >
                <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
                <option
                  v-for="stage in stageOptions"
                  :key="stage.id"
                  :value="stage.id"
                >
                  {{ stage.name }}
                </option>
              </select></label
            ><button
              type="submit"
              :class="buttonClass"
              :disabled="saving"
            >
              {{ t('RELATIONSHIP.APPROVE_CRM') }}</button
            ><button
              type="button"
              :class="buttonClass"
              @click="opportunity = null"
            >
              {{ t('RELATIONSHIP.CLOSE') }}
            </button>
          </div>
        </form>
        <p
          v-if="!loading && !rows.length"
          class="rounded-xl border border-n-weak p-6 text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIP.EMPTY') }}
          <span
            v-if="screen === 'portfolio'"
            class="mt-2 block"
            >{{ t('RELATIONSHIP.EMPTY_PORTFOLIO_GUIDANCE') }}</span
          >
        </p>
        <div
          v-if="pagination.total"
          class="flex items-center justify-between"
        >
          <span class="text-xs text-n-slate-11">{{
            t('RELATIONSHIP.PAGE', {
              page: pagination.page,
              total: pagination.total,
            })
          }}</span>
          <div class="flex gap-2">
            <button
              type="button"
              :class="buttonClass"
              :disabled="loading || pagination.page <= 1"
              @click="goPage(-1)"
            >
              {{ t('RELATIONSHIP.PREVIOUS') }}</button
            ><button
              type="button"
              :class="buttonClass"
              :disabled="
                loading ||
                pagination.page * pagination.per_page >= pagination.total
              "
              @click="goPage(1)"
            >
              {{ t('RELATIONSHIP.NEXT') }}
            </button>
          </div>
        </div>
      </template>
    </template>
  </div>
</template>
