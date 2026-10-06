<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { inputClass, buttonClass, message } from './definitions';

const props = defineProps({
  allowed: Boolean,
  metadata: { type: Object, default: () => ({}) },
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const queues = ref([]);
const policies = ref([]);
const queue = ref(null);
const policy = ref(null);
const busy = ref(false);
const error = ref('');
const scopes = [
  'relationship',
  'backoffice',
  'service_desk',
  'crm',
  'implementation',
];
const strategies = ['manual', 'round_robin', 'least_load', 'specialty'];
const weekdays = [1, 2, 3, 4, 5, 6, 0];
const references = {
  business_unit_ids: 'units',
  team_ids: 'teams',
  segment_ids: 'segments',
  product_ids: 'products',
};
const queueReferences = {
  operating_company_id: 'operating_companies',
  business_unit_id: 'units',
  team_id: 'teams',
};
let generation = 0;
let controller;
const clone = value => JSON.parse(JSON.stringify(value));
const list = value =>
  String(value)
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);
const matchingQueues = computed(() =>
  queues.value.filter(row =>
    (row.settings.scopes?.length
      ? row.settings.scopes
      : ['backoffice']
    ).includes(policy.value?.scope_kind)
  )
);

const load = async () => {
  const version = ++generation;
  controller?.abort();
  controller = new AbortController();
  queues.value = [];
  policies.value = [];
  queue.value = null;
  policy.value = null;
  error.value = '';
  busy.value = false;
  if (!props.allowed) return;
  busy.value = true;
  const accountId = route.params.accountId;
  try {
    const [queueResponse, policyResponse] = await Promise.all([
      API.operationsQueues(accountId, { signal: controller.signal }),
      API.operationsPolicies(accountId, { signal: controller.signal }),
    ]);
    if (version !== generation) return;
    queues.value = queueResponse.data;
    policies.value = policyResponse.data;
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
const editQueue = row => {
  policy.value = null;
  queue.value = {
    id: row?.id,
    name: row?.name || '',
    code: row?.code || '',
    operating_company_id: row?.operating_company?.id || '',
    business_unit_id: row?.business_unit?.id || '',
    team_id: row?.team?.id || '',
    assignment_strategy: row?.assignment_strategy || 'manual',
    specialty: row?.specialty || '',
    active: row?.active ?? true,
    settings: {
      user_ids: [],
      specialty_user_ids: [],
      business_unit_ids: [],
      team_ids: [],
      segment_ids: [],
      product_ids: [],
      ...clone(row?.settings || { scopes: ['relationship'] }),
    },
  };
  if (!queue.value.settings.scopes?.length)
    queue.value.settings.scopes = ['backoffice'];
};
const editPolicy = row => {
  queue.value = null;
  policy.value = {
    id: row?.id,
    name: row?.name || '',
    scope_kind: row?.scope_kind || 'relationship',
    operations_queue_id: row?.queue?.id || '',
    request_kind: row?.request_kind || '',
    priority: row?.priority || '',
    first_action_minutes: row ? (row.first_action_minutes ?? '') : 60,
    stage_minutes: row?.stage_minutes ?? '',
    total_minutes: row ? (row.total_minutes ?? '') : 1440,
    active: row?.active ?? true,
    conditions: {
      business_unit_ids: [],
      team_ids: [],
      segment_ids: [],
      product_ids: [],
      ...clone(row?.conditions || {}),
    },
    business_hours: {
      enabled: false,
      weekdays: [1, 2, 3, 4, 5],
      start: '08:00',
      end: '18:00',
      holidays: [],
      ...clone(row?.business_hours || {}),
    },
    pause_statuses: clone(row?.pause_statuses || ['waiting_customer']),
    alert_thresholds: clone(row?.alert_thresholds || [50, 75, 90, 100]),
    escalation: clone(row?.escalation || {}),
  };
};
const normalizeCriteria = values => {
  const result = clone(values);
  ['min_mrr_cents', 'max_mrr_cents'].forEach(key => {
    if (result[key] === '' || result[key] === null) delete result[key];
  });
  return result;
};
const save = async kind => {
  const version = generation;
  const accountId = route.params.accountId;
  const source = kind === 'queue' ? queue.value : policy.value;
  const payload = clone(source);
  const id = payload.id;
  delete payload.id;
  busy.value = true;
  error.value = '';
  try {
    if (kind === 'queue') {
      Object.keys(queueReferences).forEach(key => {
        payload[key] = payload[key] === '' ? null : Number(payload[key]);
      });
      payload.settings = normalizeCriteria(payload.settings);
      await API.saveOperationsQueue(accountId, payload, id);
    } else {
      [
        'operations_queue_id',
        'first_action_minutes',
        'stage_minutes',
        'total_minutes',
      ].forEach(key => {
        payload[key] =
          payload[key] === '' || payload[key] === null
            ? null
            : Number(payload[key]);
      });
      payload.conditions = normalizeCriteria(payload.conditions);
      if (!payload.escalation.user_id) delete payload.escalation.user_id;
      else payload.escalation.user_id = Number(payload.escalation.user_id);
      if (
        !payload.alert_thresholds.every(
          value => Number.isFinite(value) && value > 0
        )
      )
        throw new Error(t('RELATIONSHIP.OPERATIONS.INVALID_THRESHOLDS'));
      await API.saveOperationsPolicy(accountId, payload, id);
    }
    if (version === generation) await load();
  } catch (err) {
    if (version === generation) error.value = message(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.allowed,
  ],
  load,
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section
    class="mt-6 rounded-xl border border-n-weak p-4"
    aria-labelledby="operations-title"
  >
    <h3
      id="operations-title"
      class="mb-3 font-semibold"
    >
      {{ t('RELATIONSHIP.OPERATIONS.TITLE') }}
    </h3>
    <p
      v-if="!allowed"
      role="status"
    >
      {{ t('RELATIONSHIP.OPERATIONS.RESTRICTED') }}
    </p>
    <template v-else>
      <p
        v-if="error"
        role="alert"
        class="mb-3 text-n-ruby-11"
      >
        {{ error }}
      </p>
      <div class="mb-3 flex gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          data-testid="new-queue"
          @click="editQueue(null)"
        >
          {{ t('RELATIONSHIP.OPERATIONS.NEW_QUEUE') }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          data-testid="new-policy"
          @click="editPolicy(null)"
        >
          {{ t('RELATIONSHIP.OPERATIONS.NEW_POLICY') }}
        </button>
      </div>
      <h4 class="font-semibold">{{ t('RELATIONSHIP.OPERATIONS.QUEUES') }}</h4>
      <ul class="divide-y divide-n-weak">
        <li
          v-for="row in queues"
          :key="row.id"
          class="flex flex-wrap items-center justify-between gap-2 py-2"
        >
          <span
            >{{ row.name }} · {{ row.code }} ·
            {{
              t(`RELATIONSHIP.OPERATIONS.STRATEGIES.${row.assignment_strategy}`)
            }}
            ·
            {{
              t(
                row.active
                  ? 'RELATIONSHIP.STATES.active'
                  : 'RELATIONSHIP.STATES.inactive'
              )
            }}</span
          >
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="editQueue(row)"
          >
            {{ t('RELATIONSHIP.EDIT') }}
          </button>
        </li>
      </ul>
      <form
        v-if="queue"
        class="mt-4 grid gap-3 rounded-xl border border-n-weak p-4 sm:grid-cols-2"
        data-testid="queue-form"
        @submit.prevent="save('queue')"
      >
        <label
          v-for="key in ['name', 'code', 'specialty']"
          :key="key"
          class="text-sm"
        >
          {{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
          }}<input
            v-model="queue[key]"
            :required="key !== 'specialty'"
            :class="inputClass"
            :data-testid="`queue-${key}`"
          />
        </label>
        <label class="text-sm"
          >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.assignment_strategy') }}
          <select
            v-model="queue.assignment_strategy"
            :class="inputClass"
          >
            <option
              v-for="value in strategies"
              :key="value"
              :value="value"
            >
              {{ t(`RELATIONSHIP.OPERATIONS.STRATEGIES.${value}`) }}
            </option>
          </select>
        </label>
        <label
          v-for="(collection, key) in queueReferences"
          :key="key"
          class="text-sm"
        >
          {{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`) }}
          <select
            v-model="queue[key]"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
            <option
              v-for="item in metadata[collection] || []"
              :key="item[0]"
              :value="item[0]"
            >
              {{ item[1] }}
            </option>
          </select>
        </label>
        <label class="text-sm"
          >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.scopes') }}
          <select
            v-model="queue.settings.scopes"
            multiple
            required
            :class="inputClass"
          >
            <option
              v-for="value in scopes"
              :key="value"
              :value="value"
            >
              {{ t(`RELATIONSHIP.OPERATIONS.SCOPES.${value}`) }}
            </option>
          </select>
        </label>
        <label
          v-for="key in ['user_ids', 'specialty_user_ids']"
          :key="key"
          class="text-sm"
        >
          {{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`) }}
          <select
            v-model="queue.settings[key]"
            multiple
            :class="inputClass"
          >
            <option
              v-for="item in metadata.owners || []"
              :key="item[0]"
              :value="item[0]"
            >
              {{ item[1] }}
            </option>
          </select>
        </label>
        <label
          v-for="(collection, key) in references"
          :key="key"
          class="text-sm"
        >
          {{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`) }}
          <select
            v-model="queue.settings[key]"
            multiple
            :class="inputClass"
          >
            <option
              v-for="item in metadata[collection] || []"
              :key="item[0]"
              :value="item[0]"
            >
              {{ item[1] }}
            </option>
          </select>
        </label>
        <label
          v-for="key in [
            'kinds',
            'request_kinds',
            'priorities',
            'order_origins',
          ]"
          :key="key"
          class="text-sm"
        >
          {{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
          }}<input
            :value="queue.settings[key]?.join(', ') || ''"
            :class="inputClass"
            @input="queue.settings[key] = list($event.target.value)"
          />
        </label>
        <label
          v-for="key in ['min_mrr_cents', 'max_mrr_cents']"
          :key="key"
          class="text-sm"
        >
          {{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
          }}<input
            v-model.number="queue.settings[key]"
            type="number"
            min="0"
            :class="inputClass"
          />
        </label>
        <label class="text-sm"
          ><input
            v-model="queue.active"
            type="checkbox"
          />
          {{ t('RELATIONSHIP.STATES.active') }}</label
        >
        <div class="flex gap-2 sm:col-span-2">
          <button
            type="submit"
            :class="buttonClass"
            :disabled="busy"
          >
            {{ t('RELATIONSHIP.SAVE') }}</button
          ><button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="queue = null"
          >
            {{ t('RELATIONSHIP.CANCEL') }}
          </button>
        </div>
      </form>
      <h4 class="mt-5 font-semibold">
        {{ t('RELATIONSHIP.OPERATIONS.POLICIES') }}
      </h4>
      <ul class="divide-y divide-n-weak">
        <li
          v-for="row in policies"
          :key="row.id"
          class="flex flex-wrap items-center justify-between gap-2 py-2"
        >
          <span
            >{{ row.name }} ·
            {{ t(`RELATIONSHIP.OPERATIONS.SCOPES.${row.scope_kind}`) }} ·
            {{
              t('RELATIONSHIP.OPERATIONS.POLICY_SUMMARY', {
                first: row.first_action_minutes ?? '—',
                total: row.total_minutes ?? '—',
              })
            }}</span
          >
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="editPolicy(row)"
          >
            {{ t('RELATIONSHIP.EDIT') }}
          </button>
        </li>
      </ul>
      <form
        v-if="policy"
        class="mt-4 grid gap-3 rounded-xl border border-n-weak p-4 sm:grid-cols-2"
        data-testid="policy-form"
        @submit.prevent="save('policy')"
      >
        <label class="text-sm"
          >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.name')
          }}<input
            v-model="policy.name"
            required
            :class="inputClass"
            data-testid="policy-name"
        /></label>
        <label class="text-sm"
          >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.scope_kind')
          }}<select
            v-model="policy.scope_kind"
            :class="inputClass"
            @change="policy.operations_queue_id = ''"
          >
            <option
              v-for="value in scopes"
              :key="value"
              :value="value"
            >
              {{ t(`RELATIONSHIP.OPERATIONS.SCOPES.${value}`) }}
            </option>
          </select></label
        >
        <label class="text-sm"
          >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.operations_queue_id')
          }}<select
            v-model="policy.operations_queue_id"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.ALL') }}</option>
            <option
              v-for="row in matchingQueues"
              :key="row.id"
              :value="row.id"
            >
              {{ row.name }}
            </option>
          </select></label
        >
        <label
          v-for="key in ['request_kind', 'priority']"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
          }}<input
            v-model="policy[key]"
            :class="inputClass"
        /></label>
        <label
          v-for="key in [
            'first_action_minutes',
            'stage_minutes',
            'total_minutes',
          ]"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
          }}<input
            v-model.number="policy[key]"
            type="number"
            min="1"
            step="1"
            :class="inputClass"
            :data-testid="`policy-${key}`"
        /></label>
        <label
          v-for="(collection, key) in references"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
          }}<select
            v-model="policy.conditions[key]"
            multiple
            :class="inputClass"
          >
            <option
              v-for="item in metadata[collection] || []"
              :key="item[0]"
              :value="item[0]"
            >
              {{ item[1] }}
            </option>
          </select></label
        >
        <label
          v-for="key in ['kinds', 'order_origins']"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
          }}<input
            :value="policy.conditions[key]?.join(', ') || ''"
            :class="inputClass"
            @input="policy.conditions[key] = list($event.target.value)"
        /></label>
        <label
          v-for="key in ['min_mrr_cents', 'max_mrr_cents']"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
          }}<input
            v-model.number="policy.conditions[key]"
            type="number"
            min="0"
            :class="inputClass"
        /></label>
        <fieldset class="rounded-lg border border-n-weak p-3 sm:col-span-2">
          <legend>{{ t('RELATIONSHIP.OPERATIONS.CALENDAR') }}</legend>
          <label class="text-sm"
            ><input
              v-model="policy.business_hours.enabled"
              type="checkbox"
            />
            {{ t('RELATIONSHIP.OPERATIONS.BUSINESS_HOURS') }}</label
          >
          <div
            v-if="policy.business_hours.enabled"
            class="mt-3 grid gap-3 sm:grid-cols-2"
          >
            <label
              v-for="key in ['start', 'end']"
              :key="key"
              class="text-sm"
              >{{ t(`RELATIONSHIP.OPERATIONS.FIELDS.${key}`)
              }}<input
                v-model="policy.business_hours[key]"
                type="time"
                required
                :class="inputClass"
            /></label>
            <label class="text-sm"
              >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.weekdays')
              }}<select
                v-model="policy.business_hours.weekdays"
                multiple
                required
                :class="inputClass"
              >
                <option
                  v-for="day in weekdays"
                  :key="day"
                  :value="day"
                >
                  {{ t(`RELATIONSHIP.OPERATIONS.WEEKDAYS.${day}`) }}
                </option>
              </select></label
            >
            <label class="text-sm"
              >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.holidays')
              }}<input
                :value="policy.business_hours.holidays?.join(', ') || ''"
                :class="inputClass"
                placeholder="2026-12-25, 2027-01-01"
                @input="
                  policy.business_hours.holidays = list($event.target.value)
                "
            /></label>
          </div>
        </fieldset>
        <label class="text-sm"
          >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.pause_statuses')
          }}<input
            :value="policy.pause_statuses.join(', ')"
            :class="inputClass"
            data-testid="policy-pause"
            @input="policy.pause_statuses = list($event.target.value)"
        /></label>
        <label class="text-sm"
          >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.alert_thresholds')
          }}<input
            :value="policy.alert_thresholds.join(', ')"
            :class="inputClass"
            data-testid="policy-alerts"
            @input="
              policy.alert_thresholds = list($event.target.value).map(Number)
            "
        /></label>
        <label class="text-sm"
          >{{ t('RELATIONSHIP.OPERATIONS.FIELDS.escalation_user_id')
          }}<select
            v-model="policy.escalation.user_id"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.UNASSIGNED') }}</option>
            <option
              v-for="item in metadata.owners || []"
              :key="item[0]"
              :value="item[0]"
            >
              {{ item[1] }}
            </option>
          </select></label
        >
        <label class="text-sm"
          ><input
            v-model="policy.active"
            type="checkbox"
          />
          {{ t('RELATIONSHIP.STATES.active') }}</label
        >
        <div class="flex gap-2 sm:col-span-2">
          <button
            type="submit"
            :class="buttonClass"
            :disabled="busy"
          >
            {{ t('RELATIONSHIP.SAVE') }}</button
          ><button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="policy = null"
          >
            {{ t('RELATIONSHIP.CANCEL') }}
          </button>
        </div>
      </form>
    </template>
  </section>
</template>
