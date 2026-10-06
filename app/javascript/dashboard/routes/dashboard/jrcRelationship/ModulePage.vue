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
import SlaSummary from './SlaSummary.vue';
import SurveyDeliveryPanel from './SurveyDeliveryPanel.vue';
import CompanyPicker from '../jrcCustomers/components/CompanyPicker.vue';
import {
  STATES,
  buttonClass,
  inputClass,
  date as formatDate,
  message,
  money as formatMoney,
} from './definitions';
const props = defineProps({ screen: { type: String, required: true } });
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
const opportunity = ref(null);
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
  score_min: '', score_max: '', mrr_min_cents: '', mrr_max_cents: '', band: '', status: '',
  renewal_days: '',
});
const portfolioOperation = reactive({ operation: 'activity', owner_id: '', title: '', due_at: '', playbook_id: '', request_id: crypto.randomUUID() });
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
  priority: 50,
});
const commercial = reactive({ pipeline_id: '', stage_id: '' });
const portfolioScreen = computed(() =>
  ['overview', 'portfolio', 'health', 'reports'].includes(props.screen)
);
const configScreen = computed(() =>
  ['settings', 'playbooks'].includes(props.screen)
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
  page: pagination.value.page,
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
  selected.value = [];
  try {
    const meta = await API.metadata(accountId, options);
    if (version !== generation) return;
    metadata.value = meta.data;
    if (configScreen.value) return;
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
    if (route.query.create && metadata.value.can_manage) editing.value = { assignment_id: Number(route.query.assignment_id) };
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
      if (route.query.create) await router.replace({ query: { ...route.query, create: undefined } });
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
const completeBatch = () =>
  mutate(() =>
    API.batch(route.params.accountId, selected.value, {
      ...batch,
      due_at: batch.due_at ? new Date(batch.due_at).toISOString() : undefined,
    })
  );
const updatePortfolioBatch = () => mutate(() => API.portfolioBatch(route.params.accountId, selected.value, {
  ...portfolioOperation, due_at: portfolioOperation.due_at ? new Date(portfolioOperation.due_at).toISOString() : undefined,
}));
const exportPortfolio = async (history = false) => {
  const version = generation;
  error.value = '';
  try {
    const { data } = await (history === true ? API.exportHistory : API.exportPortfolio)(route.params.accountId, scope());
    if (version !== generation) return;
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url; link.download = history === true ? 'relationship-history.json' : 'relationship-portfolio.csv'; link.click();
    URL.revokeObjectURL(url);
  } catch (err) { if (version === generation) error.value = message(err); }
};
const getSurveyLink = async row => {
  const version = generation;
  try { const { data } = await API.surveyLink(route.params.accountId, row.id); if (version === generation) surveyLink.value = data.url; }
  catch (err) { if (version === generation) error.value = message(err); }
};
const quick = ({ kind, assignmentId }) => router.push({ name: `jrc_relationship_${kind}`, params: { accountId: route.params.accountId }, query: { assignment_id: assignmentId, create: '1' } });
const metricFilter = key => {
  if (typeof key === 'object' && key.renewal_days) { filters.mode = 'renewals'; filters.renewal_days = key.renewal_days; }
  else if (typeof key === 'object') filters.band = key.band;
  else if (['at_risk', 'mrr_at_risk_cents'].includes(key)) filters.mode = 'critical';
  else if (key === 'active') filters.status = 'active';
  else if (key === 'churned') filters.status = 'churned';
  else if (key === 'without_contact') filters.mode = 'without_contact';
  else if (key === 'overdue_actions' || key === 'actions_today') {
    router.push({ name: 'jrc_relationship_actions', params: { accountId: route.params.accountId },
      query: key === 'overdue_actions' ? { overdue: 'true' } : { from: new Date().toLocaleDateString('en-CA'), to: new Date().toLocaleDateString('en-CA') } }); return;
  }
  else if (key === 'waiting_customer_actions') {
    router.push({ name: 'jrc_relationship_actions', params: { accountId: route.params.accountId }, query: { status: 'waiting_customer' } }); return;
  } else return;
  refresh();
};
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
    () => route.query.assignment_id,
    () => route.query.create,
    () => route.query.overdue,
    () => route.query.from,
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
      settings: { segment_id: '', product_id: '', complexity: '' },
    });
    surveyLink.value = '';
    surveyDelivery.value = null;
    filters.record_status = route.query.status || '';
    filters.overdue = route.query.overdue === 'true';
    filters.from = route.query.from || ''; filters.to = route.query.to || '';
    Object.assign(portfolioOperation, { operation: 'assign', owner_id: '', title: '', due_at: '', playbook_id: '', request_id: crypto.randomUUID() });
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
        ><button v-if="metadata?.can_team && portfolioScreen" type="button" :class="buttonClass" @click="exportPortfolio">{{ t('RELATIONSHIP.EXPORT') }}</button><button v-if="metadata?.can_export_history && screen === 'reports'" :class="buttonClass" :disabled="saving" @click="exportPortfolio(true)">{{t('RELATIONSHIP.EXPORT_HISTORY')}}</button
        ><button
          v-if="
            metadata?.can_manage &&
            !portfolioScreen &&
            !configScreen &&
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
                v-for="mode in [
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
            <label v-for="key in ['score_min', 'score_max', 'mrr_min_cents', 'mrr_max_cents']" :key="key" class="text-xs">{{ t(`RELATIONSHIP.FIELDS.${key}`) }}<input v-model="filters[key]" type="number" min="0" :class="inputClass" /></label>
            <label class="text-xs">{{ t('RELATIONSHIP.FIELDS.health') }}<select v-model="filters.band" :class="inputClass"><option value="">{{ t('RELATIONSHIP.ALL') }}</option><option v-for="band in ['healthy', 'attention', 'risk', 'critical']" :key="band" :value="band">{{ t(`RELATIONSHIP.BANDS.${band}`) }}</option></select></label>
            <label class="text-xs">{{ t('RELATIONSHIP.FIELDS.status') }}<select v-model="filters.status" :class="inputClass"><option value="">{{ t('RELATIONSHIP.ALL') }}</option><option v-for="status in ['onboarding', 'active', 'at_risk', 'churned', 'inactive']" :key="status" :value="status">{{ t(`RELATIONSHIP.STATES.${status}`) }}</option></select></label>
          </template>
          <template v-if="['reports', 'actions', 'overview'].includes(screen)"
            ><label
              v-for="key in ['from', 'to']"
              :key="key"
              class="text-xs"
              >{{ t(`RELATIONSHIP.FIELDS.${key}`)
              }}<input
                v-model="filters[key]"
                type="date"
                :class="inputClass" /></label
          ></template>
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
                    'post_ticket', 'recurring_ticket', 'expansion', 'retention',
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
          v-if="metrics && ['overview', 'reports', 'actions'].includes(screen)"
          :metrics="metrics" :metadata="metadata"
          @filter="metricFilter"
        />
        <NicoSummaryPanel v-if="screen === 'overview' && metrics" :metrics="metrics" :enabled="metadata.can_nico" @customer="selectedCustomer = $event" />
        <RecordEditor
          v-if="editing"
          :key="`${screen}:${editing.id || 'new'}`"
          :kind="screen"
          :record="editing"
          :customers="customers"
          :metadata="metadata"
          :busy="saving"
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
        <SurveyDeliveryPanel v-if="surveyDelivery" :assignment-id="surveyDelivery.assignment_id" :survey-id="surveyDelivery.id" @sent="surveyDelivery = null; load()" @close="surveyDelivery = null" />
        <PortfolioTable
          v-if="portfolioScreen && rows.length"
          :rows="rows"
          v-model:selected="selected"
          :metadata="metadata"
          :can-manage="metadata.can_manage"
          @open="selectedCustomer = $event"
          @quick="quick"
        />
        <form v-if="portfolioScreen && metadata.can_manage && selected.length" class="rounded-xl border border-n-weak p-4" @submit.prevent="updatePortfolioBatch">
          <h3 class="mb-3 font-semibold">{{ t('RELATIONSHIP.PORTFOLIO_BATCH', { count: selected.length }) }}</h3>
          <div class="flex flex-wrap items-end gap-3">
            <label>{{ t('RELATIONSHIP.FIELDS.actions') }}<select v-model="portfolioOperation.operation" :class="inputClass"><option v-if="metadata.can_team" value="assign">{{ t('RELATIONSHIP.ASSIGN') }}</option><option value="activity">{{ t('RELATIONSHIP.NEW_ACTIVITY') }}</option><option value="playbook">{{ t('RELATIONSHIP.APPLY_PLAYBOOK') }}</option></select></label>
            <label v-if="portfolioOperation.operation === 'assign'">{{ t('RELATIONSHIP.FIELDS.owner_id') }}<select v-model="portfolioOperation.owner_id" :class="inputClass"><option value="">{{ t('RELATIONSHIP.UNASSIGNED') }}</option><option v-for="owner in metadata.owners" :key="owner[0]" :value="owner[0]">{{ owner[1] }}</option></select></label>
            <template v-if="portfolioOperation.operation === 'activity'"><label>{{ t('RELATIONSHIP.FIELDS.title') }}<input v-model="portfolioOperation.title" required :class="inputClass" /></label><label>{{ t('RELATIONSHIP.FIELDS.due_at') }}<input v-model="portfolioOperation.due_at" type="datetime-local" required :class="inputClass" /></label></template>
            <label v-if="portfolioOperation.operation === 'playbook'">{{ t('RELATIONSHIP.SCREENS.playbooks') }}<select v-model="portfolioOperation.playbook_id" required :class="inputClass"><option value="">{{ t('RELATIONSHIP.SELECT') }}</option><option v-for="book in metadata.playbooks" :key="book[0]" :value="book[0]">{{ book[1] }}</option></select></label>
            <button type="submit" :class="buttonClass" :disabled="saving || selected.length > 50">{{ t('RELATIONSHIP.SAVE') }}</button>
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
                :class="inputClass"
              >
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
                v-model="batch.result"
                :class="inputClass"
                :required="batch.status === 'completed'" /></label
            ><label class="text-sm"
              >{{ t('RELATIONSHIP.FIELDS.due_at')
              }}<input
                v-model="batch.due_at"
                type="datetime-local"
                :class="inputClass" /></label
            ><button
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
                    v-for="key in [
                      'customer',
                      'title',
                      'status',
                      'owner_id',
                      'due_at',
                      'actions',
                    ]"
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
                    <p v-if="screen === 'risks'" class="text-xs">{{ t('RELATIONSHIP.METRICS.mrr_at_risk_cents') }}: {{ money(row.mrr_cents) }}</p>
                    <p v-if="screen === 'surveys' && row.responded_at" class="text-xs">{{ row.score }} · {{ row.comment }}</p>
                    <div v-if="row.commercial_context" class="mt-2 text-xs"><p>{{ row.commercial_context.contract_number }} · {{ money(row.commercial_context.current_mrr_cents) }} → {{ money(row.proposed_mrr_cents) }}</p><p>{{ t('RELATIONSHIP.ADJUSTMENT', { percent: row.commercial_context.adjustment_percent ?? '—' }) }}</p><p>{{ row.commercial_context.products.join(', ') }}</p><p>{{ t('RELATIONSHIP.COMMERCIAL_TRACE', { proposals: row.commercial_context.proposal_ids.join(', ') || '—', orders: row.commercial_context.order_ids.join(', ') || '—' }) }}</p></div>
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
                    <SlaSummary v-if="['actions', 'risks'].includes(screen)" :sla="row.sla" :metadata="metadata" />
                  </td>
                  <td class="p-3">
                    <div class="flex flex-wrap gap-2">
                      <template v-if="screen === 'surveys' && !row.responded_at">
                        <button type="button" :class="buttonClass" @click="getSurveyLink(row)">{{ t('RELATIONSHIP.SURVEY_LINK') }}</button>
                        <button v-if="metadata.can_manage" type="button" :class="buttonClass" @click="surveyDelivery = row">{{ t('RELATIONSHIP.SEND_SURVEY') }}</button>
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
                          !row.deal_id
                        "
                        type="button"
                        :class="buttonClass"
                        @click="opportunity = row"
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
