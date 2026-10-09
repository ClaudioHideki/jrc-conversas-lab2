<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import LifecycleAPI from 'dashboard/api/serviceDeskLifecycle';
import Panel from './ServiceDeskPanel.vue';
import State from './ServiceDeskState.vue';
import SlaSnapshotEditor from './SlaSnapshotEditor.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import {
  createLifecycleSession,
  createLifecycleState,
} from '../helpers/lifecycle.js';
import { newRequestKey } from '../helpers/drafts.js';
const props = defineProps({ ticket: { type: Object, required: true } });
const emit = defineEmits(['updated', 'snapshotRecorded']);
const { t } = useI18n();
const session = useServiceDesk();
const state = reactive(createLifecycleState());
const lifecycle = createLifecycleSession(
  LifecycleAPI,
  () => (session.state.status === 'ready' ? session.state.context : null),
  state
);
const selected = ref('');
const reason = ref('');
const note = ref('');
const solution = ref('');
const evidence = ref('');
const pendingCommand = ref(null);
const fields = reactive({});
const page = ref(1);
let requestKey = null;
const rule = computed(() =>
  state.data?.options.find(row => row.key === selected.value)
);
const maySeeNotes = computed(
  () => props.ticket.permissions.view_notes === true
);
const busy = computed(() => state.writeStatus === 'saving');
const load = () => lifecycle.load(props.ticket, page.value);
const resetDraft = () => {
  pendingCommand.value = null;
  selected.value = '';
  reason.value = '';
  note.value = '';
  solution.value = '';
  evidence.value = '';
  requestKey = null;
  Object.keys(fields).forEach(key => delete fields[key]);
};
watch(
  [
    () => props.ticket.id,
    () => session.state.context,
    () => session.state.status,
  ],
  () => {
    lifecycle.clear();
    resetDraft();
    page.value = 1;
    if (session.state.status === 'ready') load();
  },
  { immediate: true, flush: 'sync' }
);
watch(page, load);
watch(
  () => props.ticket.lock_version,
  () => {
    if (!busy.value && session.state.status === 'ready') load();
  }
);
watch(selected, () => {
  reason.value = '';
  if (!pendingCommand.value) requestKey = null;
  Object.keys(fields).forEach(key => delete fields[key]);
});
const submit = async () => {
  if (!rule.value || busy.value || !state.data?.policy) return;
  try {
    requestKey ||= newRequestKey();
    const custom = Object.fromEntries(
      Object.entries(fields)
        .filter(([, value]) => value !== '')
        .map(([key, value]) => [
          key,
          rule.value.requirements.fields[key].type === 'integer'
            ? Number(value)
            : value,
        ])
    );
    const command = {
      rule_key: rule.value.key,
      expected_lock_version: state.data.lock_version,
      expected_policy_version_id: state.data.policy.id,
      note: note.value,
      solution: solution.value,
      fields: custom,
      evidence_note_ids: evidence.value.trim()
        ? evidence.value.split(',').map(value => value.trim())
        : [],
      ...(rule.value.action === 'pause' ? { reason_code: reason.value } : {}),
    };
    pendingCommand.value = command;
    const result = await lifecycle.apply(props.ticket, command, requestKey);
    if (
      ['invalid_input', 'dependency', 'conflict', 'denied'].includes(
        state.writeStatus
      )
    )
      pendingCommand.value = null;
    if (result) {
      resetDraft();
      if (session.operations) session.operations.state.revision += 1;
      emit('updated', result);
    }
  } catch {
    state.writeStatus = 'invalid_input';
  }
};
const recover = async () => {
  if (!pendingCommand.value || busy.value) return;
  const result = await lifecycle.apply(
    props.ticket,
    pendingCommand.value,
    requestKey
  );
  if (result) {
    resetDraft();
    if (session.operations) session.operations.state.revision += 1;
    emit('updated', result);
  }
  if (
    ['invalid_input', 'dependency', 'conflict', 'denied'].includes(
      state.writeStatus
    )
  )
    pendingCommand.value = null;
};
onBeforeUnmount(() => lifecycle.clear());
</script>

<template>
  <Panel :title="t('JRC_SERVICE_DESK.LIFECYCLE.title')">
    <div class="grid gap-3">
      <State
        v-if="state.status !== 'ready'"
        :status="state.status"
        retry
        compact
        @retry="load"
      />
      <template v-else>
        <p v-if="state.data.policy" class="text-xs text-n-slate-11">
          {{
            t('JRC_SERVICE_DESK.LIFECYCLE.version', {
              version: state.data.policy.version,
            })
          }}
        </p>
        <p v-if="state.data.unavailable_reason" class="text-sm text-n-slate-11">
          {{ t(`JRC_SERVICE_DESK.LIFECYCLE.${state.data.unavailable_reason}`) }}
        </p>
        <p v-if="state.data.pause" class="text-xs">
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.paused_at') }}:
          {{ state.data.pause.started_at }} / {{ state.data.pause.reason_code }}
        </p>
        <div v-if="state.data.reopening" class="text-xs">
          <p>
            {{ t('JRC_SERVICE_DESK.LIFECYCLE.reopening') }}:
            {{
              t(`JRC_SERVICE_DESK.LIFECYCLE.${state.data.reopening.sla_cycle}`)
            }}
          </p>
          <p v-if="state.data.reopening.expires_at">
            {{ t('JRC_SERVICE_DESK.LIFECYCLE.window_end') }}:
            {{ state.data.reopening.expires_at }}
          </p>
          <p>
            {{
              t(
                `JRC_SERVICE_DESK.LIFECYCLE.expired_${state.data.reopening.expired_behavior}`
              )
            }}
          </p>
        </div>
        <form
          v-if="state.data.options.length"
          class="grid gap-3"
          @submit.prevent="submit"
        >
          <Select
            v-model="selected"
            :disabled="busy || !!pendingCommand"
            :placeholder="t('JRC_SERVICE_DESK.LIFECYCLE.choose_action')"
            :options="
              state.data.options.map(row => ({
                value: row.key,
                label: `${t(`JRC_SERVICE_DESK.LIFECYCLE.actions.${row.action}`)}: ${row.to_status_name}`,
              }))
            "
          />
          <template v-if="rule">
            <Select
              v-if="rule.action === 'pause'"
              v-model="reason"
              :disabled="busy || !!pendingCommand"
              :placeholder="t('JRC_SERVICE_DESK.LIFECYCLE.reason')"
              :options="
                rule.reasons.map(row => ({ value: row.code, label: row.name }))
              "
            />
            <TextArea
              v-if="maySeeNotes"
              v-model="note"
              :disabled="busy || !!pendingCommand"
              :max-length="20000"
              :label="
                t('JRC_SERVICE_DESK.LIFECYCLE.note') +
                (rule.requirements.note ? ' *' : '')
              "
            />
            <TextArea
              v-if="maySeeNotes"
              v-model="solution"
              :disabled="busy || !!pendingCommand"
              :max-length="20000"
              :label="
                t('JRC_SERVICE_DESK.LIFECYCLE.solution') +
                (rule.requirements.solution ? ' *' : '')
              "
            />
            <Input
              v-if="maySeeNotes"
              v-model="evidence"
              :disabled="busy || !!pendingCommand"
              :label="
                t('JRC_SERVICE_DESK.LIFECYCLE.evidence') +
                (rule.requirements.evidence ? ' *' : '')
              "
            />
            <p v-if="rule.requirements.classification" class="text-xs">
              {{ t('JRC_SERVICE_DESK.LIFECYCLE.classification') }}
            </p>
            <template
              v-for="(spec, field) in maySeeNotes
                ? rule.requirements.fields
                : {}"
              :key="field"
            >
              <span
                v-if="Object.hasOwn(spec, 'equals')"
                class="text-xs"
                data-testid="lifecycle-expected-value"
                >{{ t('JRC_SERVICE_DESK.LIFECYCLE.expected_value') }}:
                {{ spec.equals }}</span
              >
              <label
                v-if="spec.type === 'boolean'"
                class="text-sm"
                data-testid="lifecycle-boolean-field"
                ><input
                  v-model="fields[field]"
                  type="checkbox"
                  :disabled="busy || !!pendingCommand"
                />
                {{ spec.label }}{{ spec.required ? ' *' : '' }}</label
              >
              <Input
                v-else
                v-model="fields[field]"
                :disabled="busy || !!pendingCommand"
                :type="spec.type === 'integer' ? 'number' : 'text'"
                :label="spec.label + (spec.required ? ' *' : '')"
              />
            </template>
            <Button
              type="submit"
              :disabled="
                busy || !!pendingCommand || (rule.action === 'pause' && !reason)
              "
              :label="t('JRC_SERVICE_DESK.LIFECYCLE.apply')"
            />
          </template>
        </form>
        <p
          v-else-if="!state.data.unavailable_reason"
          class="text-xs text-n-slate-11"
        >
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.no_actions') }}
        </p>
        <div v-if="state.data.cycle" class="grid gap-2 text-xs">
          <p>
            {{
              t('JRC_SERVICE_DESK.LIFECYCLE.cycle', {
                number: state.data.cycle.number,
              })
            }}
            / {{ state.data.cycle.timezone }}
          </p>
          <p v-for="clock in state.data.cycle.clocks" :key="clock.id">
            {{ t(`JRC_SERVICE_DESK.LIFECYCLE.clocks.${clock.kind}`) }}:
            {{ t(`JRC_SERVICE_DESK.LIFECYCLE.states.${clock.state}`) }} /
            {{ clock.due_at }}
          </p>
          <p>{{ t('JRC_SERVICE_DESK.LIFECYCLE.clock_notice') }}</p>
        </div>
        <h4 class="text-sm font-medium">
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.history') }}
        </h4>
        <article
          v-for="item in state.data.history"
          :key="item.id"
          class="border-t border-n-weak pt-2 text-xs break-words"
        >
          <p>
            {{ t(`JRC_SERVICE_DESK.LIFECYCLE.actions.${item.action}`) }} /
            {{ item.author.name }} / {{ item.occurred_at }}
          </p>
          <p>
            {{
              t('JRC_SERVICE_DESK.LIFECYCLE.version', {
                version: item.policy_version,
              })
            }}
          </p>
          <p v-if="item.note" class="whitespace-pre-wrap">{{ item.note }}</p>
          <p v-if="item.solution" class="whitespace-pre-wrap">
            {{ item.solution }}
          </p>
          <p v-if="item.reason_code">{{ item.reason_code }}</p>
          <p v-if="item.evidence_note_ids.length">
            {{ t('JRC_SERVICE_DESK.LIFECYCLE.evidence') }}:
            {{ item.evidence_note_ids.join(', ') }}
          </p>
          <p v-for="(value, field) in item.fields" :key="field">
            {{ field }}: {{ value }}
          </p>
          <p v-if="item.cycle_rule">
            {{ t(`JRC_SERVICE_DESK.LIFECYCLE.${item.cycle_rule}`) }}
          </p>
        </article>
        <Pagination
          v-if="state.data.meta.total > 20"
          :current-page="page"
          :items-per-page="20"
          :total-items="state.data.meta.total"
          @update:current-page="page = $event"
        />
      </template>
      <p v-if="state.writeStatus !== 'idle'" role="status" class="text-sm">
        {{ t(`JRC_SERVICE_DESK.LIFECYCLE.feedback.${state.writeStatus}`) }}
      </p>
      <Button
        v-if="
          pendingCommand &&
          ['error', 'readback_pending'].includes(state.writeStatus)
        "
        size="sm"
        variant="outline"
        :disabled="busy"
        :label="t('JRC_SERVICE_DESK.LIFECYCLE.recover')"
        @click="recover"
      />
      <Button
        size="xs"
        variant="outline"
        :disabled="busy"
        :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
        @click="load"
      />
      <SlaSnapshotEditor
        v-if="ticket.permissions.record_sla_snapshot"
        :ticket="ticket"
        @snapshot-recorded="emit('snapshotRecorded', $event)"
      />
    </div>
  </Panel>
</template>
