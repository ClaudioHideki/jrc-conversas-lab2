<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { FIELDS, STATES, buttonClass, inputClass } from './definitions';
import SlaSummary from './SlaSummary.vue';
import WorkContextPanel from './WorkContextPanel.vue';
const props = defineProps({
  kind: { type: String, required: true },
  record: { type: Object, default: () => ({}) },
  customers: { type: Array, default: () => [] },
  metadata: { type: Object, default: () => ({}) },
  busy: Boolean,
  readOnly: Boolean,
});
const emit = defineEmits(['save', 'close']);
const { t } = useI18n();
const form = reactive({
  assignment_id: props.record.assignment_id || '',
  request_id: crypto.randomUUID(),
  ...props.record,
  notes: props.record.metadata?.notes || '',
  expansion_kind:
    props.record.metadata?.expansion_kind ||
    props.record.metadata?.kind ||
    'upsell',
  renewed_contract_id: props.record.metadata?.renewed_contract_id || '',
});
const workContext = ref(null);
const loadContext = data => {
  workContext.value = data;
  if (props.kind === 'qbrs' && !form.agenda && data)
    form.agenda = data.agenda_template;
  if (data) {
    form.period_from = data.period.from;
    form.period_to = data.period.to;
  }
};
const references = key =>
  ({
    owner_id: props.metadata.owners,
    user_id: props.metadata.owners,
    product_id: props.metadata.products,
    source_product_id: props.metadata.products,
    contract_id: workContext.value?.contracts?.map(row => [row.id, row.number]),
    source_contract_id: workContext.value?.contracts?.map(row => [
      row.id,
      row.number,
    ]),
    contact_id: workContext.value?.contacts,
    activity_id: workContext.value?.activities,
    task_id: workContext.value?.tasks,
    ticket_id: workContext.value?.linked_tickets,
    qbr_id: workContext.value?.qbrs,
  })[key];
const fields = computed(() => FIELDS[props.kind] || []);
const collections = computed(
  () =>
    ({ plans: ['goals', 'milestones'], qbrs: ['participants', 'decisions'] })[
      props.kind
    ] || []
);
collections.value.forEach(key => {
  const values =
    key === 'milestones'
      ? props.record.metadata?.milestones
      : props.record[key];
  form[key] = JSON.parse(JSON.stringify(values || [])).map((item, index) => ({
    ...(key === 'decisions'
      ? { decision_key: item.decision_key || String(index) }
      : {}),
    ...(key === 'goals' ? { title: item.metric || '' } : {}),
    ...(['goals', 'milestones'].includes(key)
      ? {
          owner_id: '',
          evidence: '',
          notes: '',
          activity_id: '',
          task_id: '',
          ticket_id: '',
          qbr_id: '',
        }
      : {}),
    ...(key === 'participants'
      ? { user_id: '', participant_type: 'external' }
      : {}),
    ...item,
  }));
});
if (props.kind === 'risks')
  form.plan = {
    cause: '',
    strategy: '',
    actions: '',
    concessions: '',
    approval_status: 'pending',
    ...props.record.plan,
  };
const options = key => {
  if (key === 'status')
    return props.kind === 'expansion'
      ? STATES.expansion.filter(
          value =>
            !['approved', 'converted'].includes(value) ||
            value === props.record.status
        )
      : STATES[props.kind];
  if (key === 'severity') return ['low', 'medium', 'high', 'critical'];
  if (key === 'kind' && props.kind === 'surveys') return ['nps', 'ces'];
  if (key === 'expansion_kind')
    return ['upsell', 'cross_sell', 'usage', 'new_product', 'new_unit'];
  return null;
};
const fieldType = key => {
  if (
    key.endsWith('_cents') ||
    ['priority', 'project_id', 'product_id'].includes(key)
  )
    return 'number';
  if (key.endsWith('_on')) return 'date';
  if (key.endsWith('_at')) return 'datetime-local';
  if (key.endsWith('_url')) return 'url';
  return 'text';
};
['due_at', 'scheduled_at'].forEach(key => {
  if (form[key]) {
    const d = new Date(form[key]);
    form[key] = new Date(d.getTime() - d.getTimezoneOffset() * 60000)
      .toISOString()
      .slice(0, 16);
  }
});
collections.value.forEach(key =>
  form[key].forEach(item => {
    if (!item.due_at) return;
    const date = new Date(item.due_at);
    item.due_at = new Date(date.getTime() - date.getTimezoneOffset() * 60000)
      .toISOString()
      .slice(0, 16);
  })
);
const add = key => {
  let item = { title: '', due_at: '', owner_id: '', evidence: '' };
  if (key === 'goals')
    item = {
      title: '',
      metric: '',
      baseline: 0,
      target: 0,
      current: 0,
      due_at: '',
      status: 'active',
      owner_id: '',
      evidence: '',
      notes: '',
      activity_id: '',
      task_id: '',
      ticket_id: '',
      qbr_id: '',
      product_id: '',
    };
  if (key === 'milestones')
    item = {
      ...item,
      status: 'active',
      notes: '',
      activity_id: '',
      task_id: '',
      ticket_id: '',
      qbr_id: '',
    };
  if (key === 'decisions') item.decision_key = crypto.randomUUID();
  if (key === 'participants')
    item = { name: '', email: '', user_id: '', participant_type: 'external' };
  form[key].push(item);
};
const submit = () => {
  if (props.readOnly || props.busy) return;
  const payload = { ...form };
  ['due_at', 'scheduled_at'].forEach(key => {
    if (payload[key]) payload[key] = new Date(payload[key]).toISOString();
  });
  [
    'priority',
    'potential_cents',
    'proposed_mrr_cents',
    'owner_id',
    'project_id',
    'product_id',
    'source_contract_id',
    'source_product_id',
    'contract_id',
    'contact_id',
    'renewed_contract_id',
  ].forEach(key => {
    if (payload[key] !== undefined)
      payload[key] = payload[key] === '' ? null : Number(payload[key]);
  });
  collections.value
    .filter(key => key !== 'participants')
    .forEach(key => {
      payload[key] = (payload[key] || []).map(item => ({
        ...item,
        due_at: item.due_at ? new Date(item.due_at).toISOString() : null,
      }));
    });
  emit('save', payload);
};
</script>

<template>
  <form
    class="rounded-xl border border-n-weak bg-n-solid-2 p-5"
    @submit.prevent="submit"
  >
    <div class="mb-4 flex items-center justify-between">
      <h3 class="font-semibold">
        {{ t(record.id ? 'RELATIONSHIP.EDIT' : 'RELATIONSHIP.NEW') }}
      </h3>
      <button
        type="button"
        :class="buttonClass"
        @click="emit('close')"
      >
        {{ t('RELATIONSHIP.CLOSE') }}
      </button>
    </div>
    <fieldset :disabled="readOnly">
      <label class="mb-4 block text-sm"
        >{{ t('RELATIONSHIP.FIELDS.customer')
        }}<select
          v-model="form.assignment_id"
          :class="inputClass"
          :disabled="!!record.id"
          required
        >
          <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
          <option
            v-for="customer in customers"
            :key="customer.id"
            :value="customer.id"
          >
            {{ customer.name }}
          </option>
        </select></label
      >
      <SlaSummary
        v-if="kind === 'actions'"
        :sla="record.sla"
        :metadata="metadata"
      />
      <WorkContextPanel
        v-if="['qbrs', 'plans', 'expansion'].includes(kind)"
        :assignment-id="form.assignment_id"
        :initial-period="record.metadata || {}"
        @loaded="loadContext"
      />
      <div class="grid gap-4 md:grid-cols-2">
        <label
          v-if="kind === 'renewals' && form.status === 'won'"
          class="text-sm"
        >
          {{ t('RELATIONSHIP.RENEWAL_NATIVE_PROOF') }}
          <select
            v-model="form.renewed_contract_id"
            required
            :class="inputClass"
            data-testid="renewal-successor"
          >
            <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
            <option
              v-for="contract in record.commercial_context
                ?.successor_contracts || []"
              :key="contract.id"
              :value="contract.id"
            >
              {{ contract.number }}
            </option>
          </select>
        </label>
        <label
          v-for="key in fields"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.FIELDS.${key}`) }}
          <select
            v-if="key === 'owner_id'"
            v-model="form[key]"
            :class="inputClass"
            :disabled="!metadata.can_team"
          >
            <option value="">{{ t('RELATIONSHIP.UNASSIGNED') }}</option>
            <option
              v-for="owner in metadata.owners || []"
              :key="owner[0]"
              :value="owner[0]"
            >
              {{ owner[1] }}
            </option>
          </select>
          <select
            v-else-if="
              [
                'project_id',
                'product_id',
                'source_product_id',
                'contract_id',
                'source_contract_id',
                'contact_id',
              ].includes(key)
            "
            v-model="form[key]"
            :class="inputClass"
          >
            <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
            <option
              v-for="item in (key === 'project_id'
                ? metadata.projects
                : references(key)) || []"
              :key="item[0]"
              :value="item[0]"
            >
              {{ item[1] }}
            </option>
          </select>
          <select
            v-else-if="options(key)"
            v-model="form[key]"
            :class="inputClass"
            required
          >
            <option
              v-for="value in options(key)"
              :key="value"
              :value="value"
            >
              {{ t(`RELATIONSHIP.STATES.${value}`) }}
            </option>
          </select>
          <template v-else-if="key === 'reason' && kind === 'risks'">
            <input
              v-model="form.reason"
              list="relationship-risk-reasons"
              :class="inputClass"
              maxlength="120"
              required
            />
            <datalist id="relationship-risk-reasons">
              <option
                v-for="reason in metadata.risk_reasons || []"
                :key="reason"
                :value="reason"
              />
            </datalist>
          </template>
          <textarea
            v-else-if="
              [
                'reason',
                'result',
                'outcome',
                'agenda',
                'summary',
                'evidence',
              ].includes(key)
            "
            v-model="form[key]"
            :class="inputClass"
            rows="3"
            :required="
              ['reason'].includes(key) ||
              (key === 'result' && form.status === 'completed') ||
              (key === 'summary' && form.status === 'completed') ||
              (key === 'outcome' &&
                ['retained', 'churn', 'no_action'].includes(form.status))
            "
          />
          <input
            v-else
            v-model="form[key]"
            :class="inputClass"
            :type="fieldType(key)"
            :min="fieldType(key) === 'number' ? 0 : undefined"
            :required="['title', 'scheduled_at'].includes(key)"
          />
        </label>
      </div>
      <label
        v-if="kind === 'plans'"
        class="mt-3 block text-sm"
        >{{ t('RELATIONSHIP.FIELDS.notes')
        }}<textarea
          v-model="form.notes"
          :class="inputClass"
        />
      </label>
      <div
        v-if="kind === 'risks'"
        class="mt-4 grid gap-3 md:grid-cols-2"
      >
        <label
          v-for="key in [
            'cause',
            'hypothesis',
            'strategy',
            'actions',
            'concessions',
          ]"
          :key="key"
          class="text-sm"
          >{{ t(`RELATIONSHIP.FIELDS.${key}`)
          }}<textarea
            v-model="form.plan[key]"
            :class="inputClass"
            :disabled="key === 'concessions' && !metadata.can_team"
          />
        </label>
      </div>
      <section
        v-for="collection in collections"
        :key="collection"
        class="mt-4"
      >
        <h4 class="mb-2 font-semibold">
          {{ t(`RELATIONSHIP.FIELDS.${collection}`) }}
        </h4>
        <div
          v-for="(item, index) in form[collection]"
          :key="index"
          class="mb-2 flex flex-wrap items-end gap-2"
        >
          <label
            v-for="key in Object.keys(item).filter(
              field => field !== 'decision_key'
            )"
            :key="key"
            class="min-w-28 flex-1 text-xs"
            >{{ t(`RELATIONSHIP.FIELDS.${key}`)
            }}<select
              v-if="key === 'participant_type'"
              v-model="item[key]"
              :class="inputClass"
            >
              <option
                v-for="type in ['internal', 'external']"
                :key="type"
                :value="type"
              >
                {{ t(`RELATIONSHIP.PARTICIPANTS.${type}`) }}
              </option></select
            ><select
              v-else-if="references(key)"
              v-model="item[key]"
              :class="inputClass"
            >
              <option value="">{{ t('RELATIONSHIP.SELECT') }}</option>
              <option
                v-for="reference in references(key)"
                :key="reference[0]"
                :value="reference[0]"
              >
                {{ reference[1] }}
              </option></select
            ><input
              v-else
              v-model="item[key]"
              :class="inputClass"
              :type="
                ['baseline', 'target', 'current'].includes(key)
                  ? 'number'
                  : key === 'due_at'
                    ? 'datetime-local'
                    : 'text'
              "
              :required="['metric', 'title', 'name'].includes(key)"
          /></label>
          <button
            type="button"
            :class="buttonClass"
            @click="form[collection].splice(index, 1)"
          >
            {{ t('RELATIONSHIP.REMOVE_ITEM') }}
          </button>
        </div>
        <button
          type="button"
          :class="buttonClass"
          :disabled="form[collection].length >= 50"
          @click="add(collection)"
        >
          {{ t('RELATIONSHIP.ADD_ITEM') }}
        </button>
      </section>
      <p
        v-if="['qbrs', 'plans'].includes(kind)"
        class="mt-3 text-xs text-n-slate-11"
      >
        {{ t('RELATIONSHIP.NATIVE_TASKS') }}
      </p>
      <label
        v-if="kind === 'risks' && form.plan.concessions"
        class="mt-3 block text-sm"
      >
        {{ t('RELATIONSHIP.CONCESSION_APPROVAL') }}
        <select
          v-model="form.plan.approval_status"
          :class="inputClass"
          :disabled="!metadata.can_team"
        >
          <option
            v-for="status in ['pending', 'approved', 'rejected']"
            :key="status"
            :value="status"
          >
            {{ t(`RELATIONSHIP.STATES.${status}`) }}
          </option>
        </select>
      </label>
    </fieldset>
    <button
      v-if="!readOnly"
      type="submit"
      :class="buttonClass"
      class="mt-5"
      :disabled="busy"
    >
      {{ t('RELATIONSHIP.SAVE') }}
    </button>
  </form>
</template>
