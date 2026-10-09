<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/serviceDeskOperationalRules';
import ScopeBar from './ScopeBar.vue';
import Panel from './ServiceDeskPanel.vue';
import OperationalRuleRow from './OperationalRuleRow.vue';
import { useOperationalScope } from '../composables/useOperationalScope';
import {
  ruleKinds,
  kindLabels,
  approvalTargets,
  groupingFields,
  emptyRule,
  loadRules,
  rulesDefinition,
  deadlineDefinition,
  recurrenceDefinition,
  assertEnvelope,
} from '../helpers/operationalRules.mjs';
const { t } = useI18n();
const unitId = ref('');
const operatorId = ref('');
const kind = ref('routing');
const scope = useOperationalScope(
  unitId,
  context => context?.capabilities?.operational_rules?.[kind.value] === true
);
const kinds = computed(() =>
  ruleKinds.filter(
    value =>
      scope.session.state.context?.capabilities?.operational_rules?.[value] ===
      true
  )
);
const rows = ref([]);
const versions = ref([]);
const enabled = ref(false);
const confirmed = ref(false);
const busy = ref(false);
const feedback = ref('');
const latest = computed(() => versions.value[0]);
const deadline = reactive({
  executor_account_user_id: '',
  after_due_seconds: '',
  new_due_seconds: '',
  target_kind: '',
  target_value: '',
  reason: '',
});
const recurrence = reactive({
  window_days: '',
  minimum_occurrences: '',
  group_by: [],
});
const reset = () => {
  rows.value = [];
  versions.value = [];
  enabled.value = false;
  confirmed.value = false;
  feedback.value = '';
  Object.keys(deadline).forEach(key => {
    deadline[key] = '';
  });
  Object.assign(recurrence, {
    window_days: '',
    minimum_occurrences: '',
    group_by: [],
  });
};
const adopt = record => {
  if (!record) return;
  enabled.value = record.enabled === true;
  if (record.definition.rules) rows.value = loadRules(record.definition);
  if (kind.value === 'recurrence')
    Object.assign(recurrence, {
      ...record.definition,
      group_by: [...record.definition.group_by],
    });
  if (kind.value === 'approval_deadline') {
    const [targetKind, targetValue] = Object.entries(
      record.definition.target
    )[0];
    Object.assign(deadline, record.definition, {
      target_kind: targetKind,
      target_value: String(targetValue),
    });
    delete deadline.target;
  }
};
const load = async () => {
  reset();
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  const family = kind.value;
  try {
    const payload = assertEnvelope(
      await API.list(
        lease.context.account_id,
        lease.unit,
        family,
        lease.signal
      ),
      lease.context,
      lease.unit
    );
    if (!scope.live(lease) || family !== kind.value) return;
    if (payload.kind !== family || !Array.isArray(payload.versions))
      throw new Error('Invalid rule response');
    versions.value = payload.versions;
    adopt(latest.value);
  } catch {
    if (scope.live(lease)) feedback.value = 'unavailable';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
watch(
  [scope.identity, unitId, kind],
  () => {
    busy.value = false;
    load();
  },
  { immediate: true }
);
watch(
  kinds,
  values => {
    if (!values.includes(kind.value)) kind.value = values[0] || '';
  },
  { immediate: true }
);
watch(
  [rows, deadline, recurrence, enabled],
  () => {
    confirmed.value = false;
  },
  { deep: true, flush: 'sync' }
);
const publish = async () => {
  if (busy.value || !confirmed.value) return;
  let definition;
  try {
    if (kind.value === 'approval_deadline') {
      definition = deadlineDefinition(deadline);
    } else if (kind.value === 'recurrence') {
      definition = recurrenceDefinition(recurrence);
    } else {
      definition = rulesDefinition(kind.value, rows.value);
    }
  } catch {
    feedback.value = 'invalid';
    return;
  }
  const lease = scope.begin();
  if (!lease) return;
  const family = kind.value;
  const expectedVersion = latest.value?.version || 0;
  busy.value = true;
  feedback.value = '';
  try {
    const ack = assertEnvelope(
      await API.publish(
        lease.context.account_id,
        lease.unit,
        family,
        {
          definition,
          enabled: enabled.value,
          expected_version: expectedVersion,
        },
        lease.signal
      ),
      lease.context,
      lease.unit
    );
    if (!scope.live(lease)) return;
    const readback = assertEnvelope(
      await API.list(
        lease.context.account_id,
        lease.unit,
        family,
        lease.signal
      ),
      lease.context,
      lease.unit
    );
    if (!scope.live(lease)) return;
    const actual = readback.versions.find(
      row =>
        row.id === ack.version.id &&
        row.version === expectedVersion + 1 &&
        row.digest === ack.version.digest
    );
    if (!actual) throw new Error('Unconfirmed write');
    versions.value = readback.versions;
    adopt(actual);
    confirmed.value = false;
    feedback.value = 'saved';
  } catch {
    if (scope.live(lease)) feedback.value = 'invalid';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
</script>

<template>
  <Panel v-if="kinds.length" :title="t('JRC_SERVICE_DESK.COMPLETION.title')">
    <ScopeBar
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      :disabled="busy"
    />
    <p class="my-3 text-sm">{{ t('JRC_SERVICE_DESK.COMPLETION.help') }}</p>
    <p class="my-3 text-xs">
      {{ t('JRC_SERVICE_DESK.COMPLETION.units_note') }}
    </p>
    <select
      v-model="kind"
      :disabled="busy"
      :aria-label="t('JRC_SERVICE_DESK.COMPLETION.title')"
      class="my-3 rounded border border-n-weak bg-n-solid-1 p-2"
    >
      <option v-for="value in kinds" :key="value" :value="value">
        {{ t(kindLabels[value]) }}
      </option>
    </select>
    <p v-if="!unitId" class="text-sm">
      {{ t('JRC_SERVICE_DESK.COMPLETION.unit_required') }}
    </p>
    <form v-else class="grid gap-4" @submit.prevent="publish">
      <template
        v-if="['routing', 'priority_matrix', 'sla_selection'].includes(kind)"
      >
        <OperationalRuleRow
          v-for="(_, index) in rows"
          :key="index"
          v-model="rows[index]"
          :kind="kind"
          :disabled="busy"
          @remove="rows.splice(index, 1)"
        />
        <Button
          variant="outline"
          :disabled="busy || rows.length >= 100"
          :label="t('JRC_SERVICE_DESK.COMPLETION.add_rule')"
          @click="rows.push(emptyRule())"
        />
      </template>
      <fieldset
        v-else-if="kind === 'approval_deadline'"
        :disabled="busy"
        class="grid gap-3 md:grid-cols-2"
      >
        <p class="text-sm md:col-span-2">
          {{ t('JRC_SERVICE_DESK.COMPLETION.deadline_help') }}
        </p>
        <label
          v-for="field in [
            'executor_account_user_id',
            'after_due_seconds',
            'new_due_seconds',
          ]"
          :key="field"
          class="grid gap-1 text-sm"
          ><span>{{ t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`) }}</span
          ><input
            v-model="deadline[field]"
            inputmode="numeric"
            class="rounded border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label class="grid gap-1 text-sm"
          ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.target_kind') }}</span
          ><select
            v-model="deadline.target_kind"
            class="rounded border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">
              {{ t('JRC_SERVICE_DESK.COMPLETION.select') }}
            </option>
            <option
              v-for="target in approvalTargets"
              :key="target"
              :value="target"
            >
              {{ t(`JRC_SERVICE_DESK.COMPLETION.targets.${target}`) }}
            </option>
          </select></label
        >
        <label class="grid gap-1 text-sm"
          ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.target_value') }}</span
          ><input
            v-model="deadline.target_value"
            class="rounded border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label class="grid gap-1 text-sm"
          ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.reason') }}</span
          ><textarea
            v-model="deadline.reason"
            maxlength="1000"
            class="rounded border border-n-weak bg-n-solid-1 p-2"
          />
        </label>
      </fieldset>
      <fieldset
        v-else-if="kind === 'recurrence'"
        :disabled="busy"
        class="grid gap-3"
      >
        <p class="text-sm">
          {{ t('JRC_SERVICE_DESK.COMPLETION.recurrence_help') }}
        </p>
        <label
          v-for="field in ['window_days', 'minimum_occurrences']"
          :key="field"
          class="grid gap-1 text-sm"
          ><span>{{ t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`) }}</span
          ><input
            v-model="recurrence[field]"
            inputmode="numeric"
            class="rounded border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label
          v-for="field in groupingFields"
          :key="field"
          class="flex gap-2 text-sm"
          ><input
            v-model="recurrence.group_by"
            type="checkbox"
            :value="field"
          /><span>{{
            t(`JRC_SERVICE_DESK.COMPLETION.fields.${field}`)
          }}</span></label
        >
      </fieldset>
      <label class="flex items-center gap-2 text-sm"
        ><input v-model="enabled" type="checkbox" :disabled="busy" />{{
          t('JRC_SERVICE_DESK.COMPLETION.enabled')
        }}</label
      >
      <label class="flex items-center gap-2 text-sm"
        ><input v-model="confirmed" type="checkbox" :disabled="busy" />{{
          t('JRC_SERVICE_DESK.COMPLETION.confirmed')
        }}</label
      >
      <div class="flex flex-wrap gap-2">
        <Button
          type="submit"
          :disabled="busy || !confirmed || !scope.allowed.value"
          :label="t('JRC_SERVICE_DESK.COMPLETION.publish')"
        /><Button
          variant="outline"
          :disabled="busy"
          :label="t('JRC_SERVICE_DESK.COMPLETION.load')"
          @click="load"
        />
      </div>
      <p v-if="feedback" role="status" class="text-sm">
        {{ t(`JRC_SERVICE_DESK.COMPLETION.${feedback}`) }}
      </p>
    </form>
    <details v-if="versions.length" class="mt-4">
      <summary>{{ t('JRC_SERVICE_DESK.COMPLETION.history') }}</summary>
      <ol class="grid gap-1 text-xs">
        <li v-for="version in versions" :key="version.id">
          {{ t('JRC_SERVICE_DESK.COMPLETION.version') }} {{ version.version }}:
          {{ version.created_at }} / {{ version.digest }}
        </li>
      </ol>
    </details>
  </Panel>
</template>
