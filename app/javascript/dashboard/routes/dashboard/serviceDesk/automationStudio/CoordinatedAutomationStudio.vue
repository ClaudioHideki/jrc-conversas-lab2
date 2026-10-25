<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/serviceDeskAutomationPublications';
import Drafts from 'dashboard/api/serviceDeskAutomationDrafts';
import LifecycleAPI from 'dashboard/api/serviceDeskLifecycle';
import ScopeBar from '../components/ScopeBar.vue';
import ServiceSelect from '../components/ServiceDefinitionSelect.vue';
import LookupSelect from '../components/LookupSelect.vue';
import LifecycleVisualEditor from '../components/LifecycleVisualEditor.vue';
import LifecyclePolicyEditor from '../components/LifecyclePolicyEditor.vue';
import OperationalRulePanel from '../components/OperationalRulePanel.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import AutomationDialog from './AutomationDialog.vue';
import MetricCards from './MetricCards.vue';
import RuleConditionGroups from './RuleConditionGroups.vue';
import CompositionSlaTargets from './CompositionSlaTargets.vue';
import CompositionQueues from './CompositionQueues.vue';
import CompositionNotifications from './CompositionNotifications.vue';
import CompositionRoutingSteps from './CompositionRoutingSteps.vue';
import ServiceFormPredicate from './ServiceFormPredicate.vue';
import {
  blankComposition,
  clone,
  compositionPayload,
  emptyCalendar,
  emptyConditions,
  stable,
  publicationMatches,
} from './compositionForm';
import {
  useCompositionCopy,
  fieldClass,
  buttonClass,
  primaryClass,
} from './compositionCopy';
const props = defineProps({
  kind: { type: String, required: true },
  initialUnitId: { type: String, default: '' },
  initialServiceId: { type: String, default: '' },
});
const tr = useCompositionCopy();
const session = useServiceDesk();
const unitId = ref('');
const operatorId = ref('');
const items = ref([]);
const options = ref({ labels: [], inboxes: [] });
const page = ref(1);
const total = ref(0);
const counts = ref({ total: 0, enabled: 0, disabled: 0 });
const query = ref('');
const statusFilter = ref('all');
const open = ref(false);
const step = ref(0);
const busy = ref(false);
const feedback = ref('');
const legacyOpen = ref(false);
const attributes = ref(blankComposition(props.kind));
const version = ref(0);
const draftVersion = ref(-1);
const calendar = ref(emptyCalendar());
const calendarCode = ref('');
const calendarVersion = ref('');
const preview = ref(null);
const previewSignature = ref('');
const confirmed = ref(false);
const publication = ref(null);
const simulationFacts = ref({});
const simulationAt = ref('');
const simulationPriority = ref('');
const simulationForm = ref({ key: '', value: null });
const pendingCommand = ref(null);
const uncertain = ref(false);
const imported = ref([]);
const baseline = ref('');
let epoch = 0;
let controller = new AbortController();
const context = computed(() => session.state.context);
const account = computed(() => String(context.value?.account_id || ''));
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    (props.kind === 'lifecycle'
      ? context.value?.capabilities?.lifecycle_policies?.publish === true
      : context.value?.capabilities?.operational_rules?.routing === true)
);
const selectedUnit = computed(() =>
  context.value?.units?.find(row => row.id === unitId.value)
);
const steps = computed(() =>
  [0, 1, 2, 3, 4, 5].map(index => tr(`${props.kind}_steps.${index}`))
);
const title = computed(() => tr(`${props.kind}_title`));
const locked = computed(
  () => busy.value || uncertain.value || !!publication.value
);
function draftPayload() {
  return {
    attributes: clone(attributes.value),
    version: version.value,
    calendar: clone(calendar.value),
    calendarCode: calendarCode.value,
    calendarVersion: calendarVersion.value,
  };
}
const dirty = computed(() => stable(draftPayload()) !== baseline.value);
const lifecycleText = computed({
  get: () => JSON.stringify(attributes.value.definition.lifecycle),
  set: value => {
    attributes.value.definition.lifecycle = JSON.parse(value);
  },
});
const rule = computed(
  () => attributes.value.definition.families.routing?.rules[0]
);
const graphStates = computed(() => {
  const ids = new Set(
    (attributes.value.definition.lifecycle?.transitions || []).flatMap(row => [
      ...row.from_status_ids,
      row.to_status_id,
    ])
  );
  return (options.value.statuses || []).filter(row => ids.has(row.id));
});
const statusColors = {
  open: 'border-n-blue-5 bg-n-blue-2 text-n-blue-11',
  waiting: 'border-n-amber-5 bg-n-amber-2 text-n-amber-11',
  resolved: 'border-n-teal-5 bg-n-teal-2 text-n-teal-11',
  closed: 'border-n-weak bg-n-slate-2 text-n-slate-11',
  cancelled: 'border-n-ruby-5 bg-n-ruby-2 text-n-ruby-11',
};
const serviceId = computed({
  get: () => String(attributes.value.service_id || ''),
  set: value => {
    attributes.value.service_id = value ? Number(value) : null;
  },
});
const payload = computed(() =>
  compositionPayload(
    attributes.value,
    version.value,
    calendar.value,
    calendarCode.value,
    calendarVersion.value
  )
);
const previewCurrent = computed(
  () =>
    preview.value?.valid === true &&
    previewSignature.value === stable(payload.value)
);
const metrics = computed(() => [
  {
    label: tr('total_policies'),
    value: selectedUnit.value ? counts.value.total : null,
  },
  {
    label: tr('enabled_policies'),
    value: selectedUnit.value ? counts.value.enabled : null,
  },
  {
    label: tr('disabled_policies'),
    value: selectedUnit.value ? counts.value.disabled : null,
  },
  { label: tr('scope_units'), value: selectedUnit.value ? 1 : null },
]);
const routingDestination = computed(() => {
  if (rule.value?.output.queue_id)
    return tr('queue_reference', { id: rule.value.output.queue_id });
  return tr('unconfigured');
});
const summaryCards = computed(() => [
  {
    index: 0,
    label: steps.value[0],
    value: attributes.value.name || tr('unconfigured'),
  },
  {
    index: 1,
    label: steps.value[1],
    value:
      props.kind === 'lifecycle'
        ? tr('transition_count', {
            n: attributes.value.definition.lifecycle?.transitions.length || 0,
          })
        : tr('condition_count', {
            n:
              rule.value?.conditions?.groups.reduce(
                (n, group) => n + group.items.length,
                0
              ) || 0,
          }),
  },
  {
    index: 2,
    label: steps.value[2],
    value:
      props.kind === 'lifecycle'
        ? tr('sla_count', {
            n:
              attributes.value.definition.families.sla_selection?.rules
                .length || 0,
          })
        : routingDestination.value,
  },
  {
    index: 3,
    label: steps.value[3],
    value:
      props.kind === 'lifecycle'
        ? tr('queue_count', { n: attributes.value.definition.queues.length })
        : tr('matrix_count', {
            n:
              attributes.value.definition.families.priority_matrix?.rules
                .length || 0,
          }),
  },
  {
    index: 4,
    label: steps.value[4],
    value:
      props.kind === 'lifecycle'
        ? tr('notification_count', {
            n: attributes.value.definition.notifications.length,
          })
        : tr('precedence_value', {
            n: rule.value?.precedence ?? tr('unconfigured'),
          }),
  },
]);
const summaryDetails = computed(() => {
  const definition = attributes.value.definition;
  const scope = `${selectedUnit.value?.operator_company.name || ''} · ${selectedUnit.value?.name || ''}`;
  const rows = definition.families.sla_selection?.rules || [];
  const budgets = ['first_response', 'attendance', 'resolution'].flatMap(
    clock => {
      const values = rows
        .map(
          row =>
            row.output.snapshot.policy_conditions.clock_budgets_seconds[clock]
        )
        .filter(value => Number.isFinite(value));
      if (!values.length) return [];
      const minimum = Math.min(...values) / 60;
      const maximum = Math.max(...values) / 60;
      return [
        `${tr(`clocks.${clock}`)}: ${tr('minutes_value', { n: minimum === maximum ? minimum : `${minimum}–${maximum}` })}`,
      ];
    }
  );
  const lifecycle = definition.lifecycle;
  if (props.kind === 'lifecycle')
    return [
      [attributes.value.description, scope, options.value.service_name].filter(
        Boolean
      ),
      [
        tr('pause_count', { n: lifecycle?.pause_reasons?.length || 0 }),
        tr(lifecycle?.reopen?.allowed ? 'reopen_enabled' : 'reopen_disabled'),
      ],
      [...budgets, calendar.value.timezone, calendarCode.value].filter(Boolean),
      definition.queues.map(row =>
        tr('ola_queue_review', {
          id: row.id,
          n: Object.keys(row.attributes.ola_targets || {}).length,
        })
      ),
      definition.notifications.map(
        row =>
          `${tr(`events.${row.event_type}`)} · ${tr(row.channel)} · ${tr(row.enabled ? 'enabled' : 'published_disabled')}`
      ),
    ];
  return [
    [attributes.value.description, scope, options.value.service_name].filter(
      Boolean
    ),
    [
      tr(rule.value?.conditions?.operator || 'all'),
      ...(rule.value?.conditions?.groups || []).map(group =>
        tr(group.operator)
      ),
    ],
    [
      tr(`assignment_${rule.value?.output.assignment?.mode || 'queue'}`),
      tr('task_count', { n: rule.value?.output.task ? 1 : 0 }),
      tr('tag_count', { n: rule.value?.output.label_ids?.length || 0 }),
    ],
    Object.keys(rule.value?.output.classification || {}).map(key =>
      tr(`fields.${key}`)
    ),
    [
      rule.value?.window?.timezone,
      rule.value?.valid_from,
      rule.value?.valid_until,
      rule.value?.exceptions?.skip_assigned ? tr('skip_assigned') : '',
    ].filter(Boolean),
  ];
});

function current(lease) {
  return lease === epoch && allowed.value && selectedUnit.value;
}
async function load() {
  if (!allowed.value || !selectedUnit.value) return;
  const lease = epoch;
  busy.value = true;
  try {
    const response = await API.list(
      account.value,
      unitId.value,
      props.kind,
      controller.signal,
      { page: page.value, q: query.value, active: statusFilter.value }
    );
    if (!current(lease)) return;
    items.value = response.items;
    total.value = response.total;
    counts.value = response.counts;
  } catch {
    if (current(lease)) feedback.value = 'load_failed';
  } finally {
    if (current(lease)) busy.value = false;
  }
}
function adopt(row) {
  attributes.value = row
    ? clone(
        Object.fromEntries(
          [
            'kind',
            'code',
            'name',
            'description',
            'service_id',
            'enabled',
            'definition',
          ].map(key => [key, row[key]])
        )
      )
    : blankComposition(props.kind);
  version.value = row?.version || 0;
  draftVersion.value = -1;
  if (!row && props.initialServiceId)
    attributes.value.service_id = Number(props.initialServiceId);
  const snapshot =
    attributes.value.definition.families.sla_selection?.rules[0]?.output
      .snapshot;
  calendar.value = snapshot
    ? {
        timezone: snapshot.timezone,
        conditions: clone(snapshot.calendar_conditions),
      }
    : emptyCalendar();
  calendarCode.value = snapshot?.calendar_key || '';
  calendarVersion.value = snapshot?.calendar_version || '';
  if (rule.value && !rule.value.conditions)
    rule.value.conditions = emptyConditions();
  preview.value = null;
  previewSignature.value = '';
  confirmed.value = false;
  publication.value = null;
  pendingCommand.value = null;
  uncertain.value = false;
  feedback.value = '';
  step.value = 0;
  simulationFacts.value = {};
  simulationAt.value = '';
  simulationPriority.value = '';
  simulationForm.value = { key: '', value: null };
  baseline.value = stable(draftPayload());
  open.value = true;
}
async function start(row) {
  if (!allowed.value || !selectedUnit.value || busy.value) return;
  const lease = epoch;
  busy.value = true;
  try {
    const data = await API.options(
      account.value,
      unitId.value,
      props.kind,
      controller.signal,
      row?.service_id
    );
    if (!current(lease)) return;
    options.value = data;
    adopt(row);
    if (row) {
      const stored = await Drafts.read(
        account.value,
        unitId.value,
        props.kind,
        row.code
      );
      if (!current(lease)) return;
      if (Number.isInteger(stored?.lock_version) && stored.lock_version >= 0)
        draftVersion.value = stored.lock_version;
    }
    if (props.kind === 'lifecycle') {
      const legacy = await LifecycleAPI.policies(
        account.value,
        unitId.value,
        1,
        controller.signal
      );
      if (current(lease))
        imported.value = legacy.items || legacy.policies || [];
    }
  } catch {
    if (current(lease)) feedback.value = 'load_failed';
  } finally {
    if (current(lease)) busy.value = false;
  }
}
async function importLifecycle(id) {
  if (locked.value || !id) return;
  const lease = epoch;
  busy.value = true;
  try {
    const data = await LifecycleAPI.policy(
      account.value,
      id,
      controller.signal
    );
    if (!current(lease)) return;
    const record = data.policy;
    if (!record || record.unit_id !== unitId.value)
      throw new TypeError('Invalid lifecycle scope');
    attributes.value.name = record.name;
    attributes.value.service_id = record.service_id
      ? Number(record.service_id)
      : null;
    attributes.value.definition.lifecycle = clone(record.definition);
    feedback.value = 'legacy_imported';
  } catch {
    if (current(lease)) feedback.value = 'load_failed';
  } finally {
    if (current(lease)) busy.value = false;
  }
}
async function saveDraft() {
  if (
    locked.value ||
    !/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$/.test(attributes.value.code)
  ) {
    feedback.value = 'identification_required';
    return;
  }
  const lease = epoch;
  busy.value = true;
  try {
    const row = await Drafts.save(
      account.value,
      unitId.value,
      props.kind,
      attributes.value.code,
      draftPayload(),
      draftVersion.value
    );
    const read = await Drafts.read(
      account.value,
      unitId.value,
      props.kind,
      attributes.value.code
    );
    if (!current(lease)) return;
    if (
      !read ||
      read.lock_version !== row.lock_version ||
      stable(read.payload) !== stable(draftPayload())
    )
      throw new TypeError('Draft readback mismatch');
    draftVersion.value = read.lock_version;
    baseline.value = stable(draftPayload());
    feedback.value = 'draft_saved';
  } catch {
    if (current(lease)) feedback.value = 'draft_failed';
  } finally {
    if (current(lease)) busy.value = false;
  }
}
async function restoreDraft() {
  if (locked.value || !attributes.value.code) return;
  const lease = epoch;
  busy.value = true;
  try {
    const row = await Drafts.read(
      account.value,
      unitId.value,
      props.kind,
      attributes.value.code
    );
    if (!current(lease)) return;
    if (
      !row ||
      row.payload.attributes.kind !== props.kind ||
      row.payload.attributes.code !== attributes.value.code ||
      !Number.isInteger(row.payload.version) ||
      row.payload.version < 0
    )
      throw new TypeError('Invalid private draft');
    if (version.value > row.payload.version) {
      draftVersion.value = row.lock_version;
      feedback.value = 'draft_stale';
      return;
    }
    adopt({ ...row.payload.attributes, version: row.payload.version });
    calendar.value = row.payload.calendar;
    calendarCode.value = row.payload.calendarCode;
    calendarVersion.value = row.payload.calendarVersion;
    draftVersion.value = row.lock_version;
    baseline.value = stable(draftPayload());
    feedback.value = 'draft_restored';
  } catch {
    if (current(lease)) feedback.value = 'draft_failed';
  } finally {
    if (current(lease)) busy.value = false;
  }
}
async function validate() {
  if (locked.value) return;
  const lease = epoch;
  const signature = stable(payload.value);
  busy.value = true;
  feedback.value = '';
  preview.value = null;
  try {
    const facts = {
      ...Object.fromEntries(
        Object.entries(simulationFacts.value).filter(
          ([, value]) => value !== '' && value !== null && value !== undefined
        )
      ),
      ...(simulationPriority.value
        ? { priority_id: Number(simulationPriority.value) }
        : {}),
    };
    if (simulationForm.value.key)
      facts.form_value = {
        [simulationForm.value.key]: simulationForm.value.value,
      };
    const result = await API.preview(
      account.value,
      unitId.value,
      payload.value,
      facts,
      simulationAt.value ? new Date(simulationAt.value).toISOString() : null,
      controller.signal
    );
    if (!current(lease) || signature !== stable(payload.value)) return;
    preview.value = result;
    previewSignature.value = signature;
    feedback.value = 'validated';
  } catch (error) {
    if (current(lease))
      feedback.value =
        { 409: 'conflict', 403: 'forbidden' }[error.response?.status] ||
        'invalid';
  } finally {
    if (current(lease)) busy.value = false;
  }
}
async function readback(row, input) {
  const saved = await API.read(
    account.value,
    unitId.value,
    row.id,
    controller.signal
  );
  if (
    !publicationMatches(saved, input.attributes, input.expected_version) ||
    saved.id !== row.id ||
    saved.digest !== row.digest
  )
    throw new TypeError('Publication readback mismatch');
  publication.value = saved;
  uncertain.value = false;
  baseline.value = stable(draftPayload());
  feedback.value = 'published';
}
async function publish() {
  if (
    busy.value ||
    publication.value ||
    (!pendingCommand.value && (!confirmed.value || !previewCurrent.value))
  )
    return;
  const lease = epoch;
  pendingCommand.value ||= {
    attributes: clone(payload.value),
    expected_version: version.value,
    expected_native_versions: clone(preview.value.native_versions),
    confirmed: true,
    idempotency_key: crypto.randomUUID(),
  };
  busy.value = true;
  try {
    const response = await API.publish(
      account.value,
      unitId.value,
      pendingCommand.value,
      controller.signal
    );
    if (!current(lease)) return;
    await readback(response.publication, pendingCommand.value);
    if (current(lease)) await load();
  } catch (error) {
    if (!current(lease)) return;
    if ([403, 404, 409, 422].includes(error.response?.status)) {
      pendingCommand.value = null;
      preview.value = null;
      confirmed.value = false;
      feedback.value = error.response.status === 409 ? 'conflict' : 'invalid';
    } else {
      uncertain.value = true;
      feedback.value = 'readback_pending';
    }
  } finally {
    if (current(lease)) busy.value = false;
  }
}
async function recover() {
  if (!pendingCommand.value || busy.value) return;
  const lease = epoch;
  busy.value = true;
  try {
    const response = await API.list(
      account.value,
      unitId.value,
      props.kind,
      controller.signal,
      { q: pendingCommand.value.attributes.code }
    );
    if (!current(lease)) return;
    const row = response.items.find(
      item =>
        item.code === pendingCommand.value.attributes.code &&
        item.version === pendingCommand.value.expected_version + 1
    );
    if (!row) {
      feedback.value = 'not_confirmed_retry';
      return;
    }
    await readback(row, pendingCommand.value);
  } catch {
    if (current(lease)) feedback.value = 'readback_pending';
  } finally {
    if (current(lease)) busy.value = false;
  }
}
function next() {
  if (locked.value) return;
  if (
    step.value === 0 &&
    (!attributes.value.name.trim() ||
      !/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$/.test(attributes.value.code))
  ) {
    feedback.value = 'identification_required';
    return;
  }
  feedback.value = '';
  step.value = Math.min(5, step.value + 1);
}
watch(
  payload,
  () => {
    if (!publication.value && !uncertain.value) {
      confirmed.value = false;
      preview.value = null;
    }
  },
  { deep: true }
);
watch(
  [
    unitId,
    () => props.kind,
    () => session.state.context,
    () => session.state.status,
  ],
  () => {
    epoch += 1;
    controller.abort();
    controller = new AbortController();
    open.value = false;
    busy.value = false;
    uncertain.value = false;
    pendingCommand.value = null;
    items.value = [];
    page.value = 1;
    feedback.value = '';
    imported.value = [];
    if (allowed.value && selectedUnit.value) {
      operatorId.value = selectedUnit.value.operator_company.id;
      load();
    }
  },
  { immediate: true }
);
watch(
  () => context.value?.units,
  units => {
    if (
      !unitId.value &&
      props.initialUnitId &&
      units?.some(row => row.id === props.initialUnitId)
    )
      unitId.value = props.initialUnitId;
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  epoch += 1;
  controller.abort();
});
let serviceOptionsEpoch = 0;
watch(serviceId, async value => {
  if (!open.value || !allowed.value || value === options.value.service_id)
    return;
  serviceOptionsEpoch += 1;
  const turn = serviceOptionsEpoch;
  const lease = epoch;
  options.value = { ...options.value, form_fields: [] };
  try {
    const data = await API.options(
      account.value,
      unitId.value,
      props.kind,
      controller.signal,
      value || null
    );
    if (current(lease) && turn === serviceOptionsEpoch) {
      options.value = data;
      if (
        !data.form_fields?.some(field => field.key === simulationForm.value.key)
      )
        simulationForm.value = { key: '', value: null };
    }
  } catch {
    if (current(lease) && turn === serviceOptionsEpoch)
      feedback.value = 'load_failed';
  }
});
watch(
  [simulationFacts, simulationAt, simulationPriority, simulationForm],
  () => {
    if (!publication.value && !uncertain.value) {
      preview.value = null;
      confirmed.value = false;
    }
  },
  { deep: true }
);
</script>

<template>
  <section class="mt-4 grid gap-4">
    <ScopeBar
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      :disabled="busy || open"
    />
    <template v-if="allowed">
      <MetricCards :items="metrics" />
      <header class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 class="text-xl font-semibold">{{ title }}</h2>
          <p class="mt-1 max-w-3xl text-sm text-n-slate-11">
            {{ tr(`${kind}_help`) }}
          </p>
        </div>
        <button
          type="button"
          :class="primaryClass"
          :disabled="busy || !selectedUnit"
          @click="start(null)"
        >
          {{ tr('new_policy') }}
        </button>
      </header>
      <form
        class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-[1fr_200px_auto]"
        @submit.prevent="
          page = 1;
          load();
        "
      >
        <input
          v-model="query"
          :class="fieldClass"
          :aria-label="tr('search')"
          :placeholder="tr('search')"
          maxlength="200"
        />
        <select
          v-model="statusFilter"
          :class="fieldClass"
          :aria-label="tr('state')"
        >
          <option value="all">{{ tr('all_states') }}</option>
          <option value="true">{{ tr('enabled_policies') }}</option>
          <option value="false">{{ tr('disabled_policies') }}</option>
        </select>
        <button
          :class="buttonClass"
          :disabled="busy || !selectedUnit"
        >
          {{ tr('filter') }}
        </button>
      </form>
      <p
        v-if="feedback && !open"
        role="status"
        class="rounded-xl bg-n-amber-2 p-3 text-sm text-n-amber-11"
      >
        {{ tr(feedback) }}
      </p>
      <div class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1">
        <table class="w-full min-w-[650px] text-left text-sm">
          <thead class="bg-n-blue-2">
            <tr>
              <th
                v-for="key in [
                  'name',
                  'state',
                  'precedence',
                  'version',
                  'actions',
                ]"
                :key="key"
                class="p-4"
              >
                {{ tr(key) }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in items"
              :key="row.id"
              class="border-t border-n-weak"
            >
              <td class="p-4">
                <strong>{{ row.name }}</strong>
                <p class="mt-1 text-xs text-n-slate-11">{{ row.code }}</p>
              </td>
              <td class="p-4">
                <span
                  class="rounded-full px-3 py-1 text-xs"
                  :class="
                    row.enabled
                      ? 'bg-n-teal-2 text-n-teal-11'
                      : 'bg-n-amber-2 text-n-amber-11'
                  "
                >
                  {{ tr(row.enabled ? 'enabled' : 'published_disabled') }}
                </span>
              </td>
              <td class="p-4">
                {{
                  row.definition.families.routing?.rules[0]?.precedence ?? '—'
                }}
              </td>
              <td class="p-4">{{ row.version }}</td>
              <td class="p-4">
                <button
                  type="button"
                  :class="buttonClass"
                  :disabled="busy"
                  @click="start(row)"
                >
                  {{ tr('edit') }}
                </button>
              </td>
            </tr>
            <tr v-if="!items.length">
              <td
                colspan="5"
                class="p-8 text-center text-n-slate-11"
              >
                {{ tr(selectedUnit ? 'no_policies' : 'select_unit') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <footer
        v-if="total > 20"
        class="flex items-center justify-between gap-3"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page === 1"
          @click="
            page -= 1;
            load();
          "
        >
          {{ tr('previous') }}
        </button>
        <span class="text-sm">
          {{ tr('page', { n: page, total: Math.ceil(total / 20) }) }}
        </span>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page * 20 >= total"
          @click="
            page += 1;
            load();
          "
        >
          {{ tr('next') }}
        </button>
      </footer>
    </template>
    <details
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
      @toggle="legacyOpen = $event.target.open"
    >
      <summary class="cursor-pointer text-sm font-medium">
        {{ tr('native_configuration') }}
      </summary>
      <p class="my-3 text-xs text-n-slate-11">
        {{ tr('native_configuration_help') }}
      </p>
      <LifecyclePolicyEditor
        v-if="legacyOpen && kind === 'lifecycle'"
        :initial-unit-id="unitId"
      />
      <OperationalRulePanel v-else-if="legacyOpen" />
    </details>
    <AutomationDialog
      :open="open"
      :busy="busy || uncertain"
      :dirty="dirty && !publication"
      :title="title"
      :steps="steps"
      :step="step"
      :max-step="5"
      :validated="previewCurrent || !!publication"
      :placement="kind === 'operational' ? 'right' : 'center'"
      @close="open = false"
      @update:step="step = $event"
    >
      <div class="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_270px]">
        <div class="min-w-0 space-y-4">
          <article
            v-if="feedback"
            role="status"
            class="rounded-xl border p-4 text-sm"
            :class="
              [
                'validated',
                'published',
                'draft_saved',
                'draft_restored',
              ].includes(feedback)
                ? 'border-n-teal-5 bg-n-teal-2 text-n-teal-11'
                : 'border-n-amber-5 bg-n-amber-2 text-n-amber-11'
            "
          >
            {{ tr(feedback) }}
          </article>
          <fieldset
            v-if="step === 0"
            :disabled="locked"
            class="grid gap-4"
          >
            <article
              class="grid gap-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
            >
              <h3 class="font-semibold">{{ tr('identification') }}</h3>
              <label class="grid gap-1 text-sm">
                {{ tr('name') }}
                <input
                  v-model="attributes.name"
                  :class="fieldClass"
                  maxlength="255"
                />
              </label>
              <label class="grid gap-1 text-sm">
                {{ tr('code') }}
                <input
                  v-model="attributes.code"
                  :class="fieldClass"
                  :disabled="locked || version > 0"
                  maxlength="64"
                />
              </label>
              <label class="grid gap-1 text-sm">
                {{ tr('description') }}
                <textarea
                  v-model="attributes.description"
                  :class="fieldClass"
                  maxlength="4000"
                  rows="3"
                />
              </label>
            </article>
            <article
              class="grid gap-4 rounded-xl border border-n-violet-5 bg-n-violet-2 p-4"
            >
              <h3 class="font-semibold">{{ tr('scope') }}</h3>
              <div class="grid gap-3 sm:grid-cols-2">
                <div>
                  <span class="text-xs text-n-slate-11">
                    {{ tr('operator_company') }}
                  </span>
                  <p class="mt-1 font-medium">
                    {{ selectedUnit?.operator_company.name }}
                  </p>
                </div>
                <div>
                  <span class="text-xs text-n-slate-11">{{ tr('unit') }}</span>
                  <p class="mt-1 font-medium">{{ selectedUnit?.name }}</p>
                </div>
              </div>
              <ServiceSelect
                v-model="serviceId"
                :unit-id="unitId"
                :disabled="locked || version > 0"
              />
              <label class="grid gap-1 text-sm">
                {{ tr('policy_type') }}
                <input
                  :value="tr(`${kind}_title`)"
                  readonly
                  :class="fieldClass"
                />
              </label>
              <p class="text-xs">{{ tr('draft_scope_help') }}</p>
            </article>
            <label
              v-if="kind === 'lifecycle' && imported.length && version === 0"
              class="grid gap-1 text-sm"
            >
              {{ tr('import_lifecycle') }}
              <select
                :class="fieldClass"
                @change="importLifecycle($event.target.value)"
              >
                <option value="">{{ tr('choose') }}</option>
                <option
                  v-for="row in imported"
                  :key="row.id"
                  :value="row.id"
                >
                  {{ row.name }}
                </option>
              </select>
            </label>
          </fieldset>
          <template v-else-if="step === 1">
            <template v-if="kind === 'lifecycle'">
              <article
                class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
              >
                <h3 class="font-semibold">{{ steps[1] }}</h3>
                <p class="mt-1 text-xs">{{ tr('lifecycle_graph_help') }}</p>
                <ol class="mt-4 flex list-none flex-wrap gap-2 p-0">
                  <li
                    v-for="status in graphStates"
                    :key="status.id"
                    class="rounded-lg border p-3 text-xs font-medium"
                    :class="statusColors[status.phase]"
                  >
                    {{ status.name }}
                  </li>
                </ol>
              </article>
              <LifecycleVisualEditor
                v-model="lifecycleText"
                :unit-id="unitId"
                :disabled="locked"
                section="lifecycle"
                :statuses="options.statuses || []"
                compact
              />
            </template>
            <RuleConditionGroups
              v-else
              v-model="rule.conditions"
              :unit-id="unitId"
              :options="options"
              :disabled="locked"
            />
          </template>
          <template v-else-if="kind === 'lifecycle'">
            <CompositionSlaTargets
              v-if="step === 2"
              v-model="attributes.definition"
              v-model:calendar="calendar"
              v-model:calendar-code="calendarCode"
              v-model:calendar-version="calendarVersion"
              :unit-id="unitId"
              :disabled="locked"
            />
            <CompositionQueues
              v-else-if="step === 3"
              v-model="attributes.definition.queues"
              :account-id="account"
              :unit-id="unitId"
              :disabled="locked"
            />
            <CompositionNotifications
              v-else-if="step === 4"
              v-model="attributes.definition.notifications"
              :account-id="account"
              :unit-id="unitId"
              :service-id="attributes.service_id"
              :disabled="locked"
            />
          </template>
          <CompositionRoutingSteps
            v-else-if="step < 5"
            v-model="attributes"
            :section="['destination', 'impact', 'advanced'][step - 2]"
            :options="options"
            :account-id="account"
            :unit-id="unitId"
            :disabled="locked"
          />
          <template v-if="step === 5">
            <header class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4">
              <h3 class="font-semibold">{{ tr('review_title') }}</h3>
              <p class="mt-1 text-sm">{{ tr('review_help') }}</p>
            </header>
            <div class="grid gap-3 md:grid-cols-6">
              <article
                v-for="(card, index) in summaryCards"
                :key="card.index"
                class="grid gap-3 rounded-xl border border-n-weak p-4"
                :class="[
                  [
                    'bg-n-blue-2',
                    'bg-n-violet-2',
                    'bg-n-teal-2',
                    'bg-n-amber-2',
                    'bg-n-blue-2',
                  ][index],
                  index < 3 ? 'md:col-span-2' : 'md:col-span-3',
                ]"
              >
                <header class="flex items-center justify-between gap-2">
                  <h4 class="text-sm font-semibold">{{ card.label }}</h4>
                  <button
                    type="button"
                    class="text-xs text-n-blue-11"
                    :disabled="locked"
                    @click="step = card.index"
                  >
                    {{ tr('edit') }}
                  </button>
                </header>
                <p class="text-sm">{{ card.value }}</p>
                <ul
                  class="m-0 grid list-none gap-2 border-t border-n-weak p-0 pt-3 text-xs text-n-slate-11"
                >
                  <li
                    v-for="(line, detailIndex) in summaryDetails[index]"
                    :key="detailIndex"
                    class="break-words"
                  >
                    {{ line }}
                  </li>
                </ul>
              </article>
            </div>
            <article
              class="grid gap-4 rounded-xl border border-n-violet-5 bg-n-violet-2 p-4"
            >
              <h3 class="font-semibold">{{ tr('simulation_title') }}</h3>
              <p class="text-xs">{{ tr('simulation_help') }}</p>
              <div class="grid gap-3 sm:grid-cols-2">
                <LookupSelect
                  v-model="simulationPriority"
                  resource="priorities"
                  :unit-id="unitId"
                  :label="tr('fields.priority_id')"
                  :disabled="locked"
                />
                <label
                  v-for="key in ['impact', 'urgency']"
                  :key="key"
                  class="grid gap-1 text-sm"
                >
                  {{ tr(`fields.${key}`) }}
                  <input
                    v-model="simulationFacts[key]"
                    :class="fieldClass"
                    :disabled="locked"
                  />
                </label>
                <label class="grid gap-1 text-sm">
                  {{ tr('simulation_at') }}
                  <input
                    v-model="simulationAt"
                    type="datetime-local"
                    :class="fieldClass"
                    :disabled="locked"
                  />
                </label>
              </div>
              <button
                type="button"
                :class="buttonClass"
                :disabled="locked"
                @click="validate"
              >
                {{ tr('validate_simulate') }}
              </button>
              <ServiceFormPredicate
                v-if="options.form_fields?.length"
                v-model="simulationForm"
                :fields="options.form_fields"
                :disabled="locked"
              />
              <div
                v-if="previewCurrent"
                class="grid gap-3 text-sm"
              >
                <p class="font-semibold text-n-teal-11">
                  {{ tr('simulation_valid') }}
                </p>
                <p
                  v-if="preview.assignment"
                  class="rounded-lg bg-n-solid-1 p-3"
                >
                  {{
                    tr('eligible_count', {
                      n: preview.assignment.eligible_members,
                    })
                  }}
                  {{
                    preview.assignment.proposed_account_user_id
                      ? tr('proposed_member', {
                          id: preview.assignment.proposed_account_user_id,
                        })
                      : tr('no_candidate_preview')
                  }}
                </p>
                <p
                  v-for="(winner, family) in preview.simulation"
                  :key="family"
                >
                  {{ tr(`families.${family}`) }}:
                  {{
                    winner
                      ? tr('matched', { n: winner.precedence })
                      : tr('no_match')
                  }}
                </p>
                <div
                  v-for="entry in preview.sla_deadlines"
                  :key="entry.key"
                  class="rounded-lg bg-n-solid-1 p-3"
                >
                  <p
                    v-for="(dueAt, clock) in entry.due_at"
                    :key="clock"
                  >
                    {{ tr(`clocks.${clock}`) }}: {{ dueAt }}
                  </p>
                </div>
              </div>
            </article>
            <article
              class="grid gap-3 rounded-xl border border-n-amber-5 bg-n-amber-2 p-4"
            >
              <h3 class="font-semibold">{{ tr('publication_title') }}</h3>
              <p class="text-sm">{{ tr('publication_impact') }}</p>
              <label class="flex items-start gap-2 text-sm">
                <input
                  v-model="attributes.enabled"
                  type="checkbox"
                  :disabled="locked"
                />
                {{ tr('enable_explicit') }}
              </label>
              <p class="text-xs">{{ tr('enable_help') }}</p>
              <label class="flex items-start gap-2 text-sm">
                <input
                  v-model="confirmed"
                  type="checkbox"
                  :disabled="locked || !previewCurrent"
                />
                {{ tr('confirm_publication') }}
              </label>
              <p class="text-xs">
                {{ tr('next_version', { n: version + 1 }) }}
              </p>
            </article>
            <article
              v-if="publication"
              class="rounded-xl border border-n-teal-5 bg-n-teal-2 p-4 text-sm"
            >
              <h3 class="font-semibold">{{ tr('published') }}</h3>
              <p class="mt-2">
                {{
                  tr('readback_version', {
                    n: publication.version,
                    id: publication.id,
                  })
                }}
              </p>
              <p class="mt-2 break-all font-mono text-xs">
                {{ publication.digest }}
              </p>
            </article>
          </template>
        </div>
        <aside class="grid gap-4 xl:sticky xl:top-0">
          <article
            class="grid gap-3 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
          >
            <h3 class="text-sm font-semibold">{{ tr('summary') }}</h3>
            <p class="font-semibold">
              {{ attributes.name || tr('new_policy') }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ selectedUnit?.operator_company.name }} ·
              {{ selectedUnit?.name }}
            </p>
            <dl class="grid gap-3 text-xs">
              <div>
                <dt class="text-n-slate-11">{{ tr('state') }}</dt>
                <dd class="mt-1">
                  {{ publication ? tr('published') : tr('private_draft') }}
                </dd>
              </div>
              <div>
                <dt class="text-n-slate-11">{{ tr('version') }}</dt>
                <dd class="mt-1">{{ version || tr('unpublished') }}</dd>
              </div>
              <div>
                <dt class="text-n-slate-11">{{ tr('validation') }}</dt>
                <dd class="mt-1">
                  {{ tr(previewCurrent ? 'validated' : 'validation_pending') }}
                </dd>
              </div>
            </dl>
          </article>
          <article
            v-if="step === 5"
            class="rounded-xl border border-n-teal-5 bg-n-teal-2 p-4 text-xs"
          >
            <strong>{{ tr('validation') }}</strong>
            <ul class="m-0 mt-3 grid list-none gap-3 p-0">
              <li
                v-for="name in steps.slice(0, 5)"
                :key="name"
                class="flex items-start gap-2"
              >
                <span
                  :class="
                    previewCurrent || publication
                      ? 'i-lucide-circle-check text-n-teal-11'
                      : 'i-lucide-circle-dashed text-n-amber-11'
                  "
                  class="mt-0.5 size-4 shrink-0"
                  aria-hidden="true"
                />
                <span>
                  {{ name }}
                  <small class="mt-1 block">
                    {{
                      tr(
                        previewCurrent || publication
                          ? 'validation_ok'
                          : 'validation_pending'
                      )
                    }}
                  </small>
                </span>
              </li>
            </ul>
          </article>
          <article
            v-else
            class="rounded-xl border border-n-violet-5 bg-n-violet-2 p-4 text-xs"
          >
            <strong>{{ tr('engines_preserved') }}</strong>
            <p class="mt-2">{{ tr('engines_preserved_help') }}</p>
          </article>
          <article
            class="rounded-xl border border-n-teal-5 bg-n-teal-2 p-4 text-xs"
          >
            <strong>{{ tr('history_title') }}</strong>
            <p class="mt-2">{{ tr('history_unchanged') }}</p>
          </article>
        </aside>
      </div>
      <template #footer>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            :class="buttonClass"
            :disabled="locked || !attributes.code"
            @click="saveDraft"
          >
            {{ tr('save_draft') }}
          </button>
          <button
            type="button"
            :class="buttonClass"
            :disabled="locked || !attributes.code"
            @click="restoreDraft"
          >
            {{ tr('restore_draft') }}
          </button>
          <button
            v-if="step > 0"
            type="button"
            :class="buttonClass"
            :disabled="busy || uncertain"
            @click="step -= 1"
          >
            {{ tr('previous') }}
          </button>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            v-if="uncertain"
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="recover"
          >
            {{ tr('recover') }}
          </button>
          <button
            v-if="step < 5"
            type="button"
            :class="primaryClass"
            :disabled="locked"
            @click="next"
          >
            {{ tr('next') }}
          </button>
          <button
            v-else-if="!publication"
            type="button"
            :class="primaryClass"
            :disabled="busy || (!uncertain && (!confirmed || !previewCurrent))"
            @click="publish"
          >
            {{ tr(uncertain ? 'retry_same' : 'publish') }}
          </button>
          <button
            v-else
            type="button"
            :class="primaryClass"
            @click="open = false"
          >
            {{ tr('close') }}
          </button>
        </div>
      </template>
    </AutomationDialog>
  </section>
</template>
