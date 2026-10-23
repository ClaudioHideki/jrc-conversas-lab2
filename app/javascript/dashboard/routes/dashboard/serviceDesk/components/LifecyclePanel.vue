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
import { tones } from '../helpers/visualTheme';
import { formatTimestamp } from '../helpers/presentation';
import {
  closureOptions,
  preferredClosure,
  closureFieldsValid,
} from '../helpers/closurePresentation';
const props = defineProps({
  ticket: { type: Object, required: true },
  mode: { type: String, default: 'all' },
});
const emit = defineEmits(['updated', 'snapshotRecorded', 'busyChange']);
const { t, locale } = useI18n();
const session = useServiceDesk();
const state = reactive(createLifecycleState());
const lifecycle = createLifecycleSession(
  LifecycleAPI,
  () => (session.state.status === 'ready' ? session.state.context : null),
  state
);
const actionLabels = computed(() => ({
  pause: t('JRC_SERVICE_DESK.LIFECYCLE.actions.pause'),
  resume: t('JRC_SERVICE_DESK.LIFECYCLE.actions.resume'),
  resolve: t('JRC_SERVICE_DESK.LIFECYCLE.actions.resolve'),
  close: t('JRC_SERVICE_DESK.LIFECYCLE.actions.close'),
  cancel: t('JRC_SERVICE_DESK.LIFECYCLE.actions.cancel'),
  reopen: t('JRC_SERVICE_DESK.LIFECYCLE.actions.reopen'),
  work_status: t('JRC_SERVICE_DESK.LIFECYCLE.actions.work_status'),
}));
const selected = ref('');
const reason = ref('');
const note = ref('');
const solution = ref('');
const outcome = ref('');
const validation = ref('');
const isClosure = computed(() => props.mode === 'closure');
const isSolution = computed(() => ['solution', 'closure'].includes(props.mode));
const confirmed = ref(false);
const actionOptions = computed(() =>
  (isClosure.value
    ? closureOptions(state.data)
    : state.data?.options || []
  ).filter(
    option =>
      props.mode !== 'sla' &&
      (props.mode !== 'solution' ||
        ['resolve', 'close', 'reopen', 'work_status'].includes(option.action))
  )
);
const solutionHistory = computed(() =>
  (state.data?.history || []).filter(
    item =>
      props.mode === 'all' ||
      (props.mode === 'solution' &&
        (item.solution || ['resolve', 'close', 'reopen'].includes(item.action)))
  )
);
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
// Keep the modal mounted while the outcome is uncertain, so recovery reuses
// the same request key instead of creating a second closing command.
watch(
  [busy, pendingCommand],
  ([saving, pending]) => emit('busyChange', saving || !!pending),
  { immediate: true }
);
const closureValid = computed(() =>
  closureFieldsValid(
    rule.value,
    {
      note: note.value,
      solution: solution.value,
      evidence: evidence.value,
      fields,
    },
    maySeeNotes.value
  )
);
watch([actionOptions, isClosure], () => {
  if (!isClosure.value || busy.value || pendingCommand.value) return;
  if (!actionOptions.value.some(row => row.key === selected.value))
    selected.value = preferredClosure(actionOptions.value);
});
const actionTone = action =>
  ({
    resolve: 'teal',
    close: 'teal',
    pause: 'amber',
    cancel: 'ruby',
    reopen: 'blue',
  })[action] || 'blue';
const load = () => lifecycle.load(props.ticket, page.value);
const resetDraft = () => {
  pendingCommand.value = null;
  selected.value = '';
  confirmed.value = false;
  reason.value = '';
  note.value = '';
  solution.value = '';
  outcome.value = '';
  validation.value = '';
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
  confirmed.value = false;
  reason.value = '';
  if (!pendingCommand.value) requestKey = null;
  Object.keys(fields).forEach(key => delete fields[key]);
});
const submit = async () => {
  if (!rule.value || busy.value || pendingCommand.value || !state.data?.policy)
    return;
  if (isClosure.value && (!confirmed.value || !closureValid.value)) return;
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
      solution: isSolution.value
        ? [
            solution.value,
            ...(outcome.value.trim()
              ? [
                  `${t('JRC_SERVICE_DESK.REDESIGN_DETAIL.outcome')}: ${outcome.value.trim()}`,
                ]
              : []),
            ...(validation.value
              ? [
                  `${t('JRC_SERVICE_DESK.REDESIGN_DETAIL.customer_validation')}: ${t(`JRC_SERVICE_DESK.REDESIGN_DETAIL.validation.${validation.value}`)}`,
                ]
              : []),
          ]
            .filter(Boolean)
            .join('\n\n')
        : solution.value,
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
onBeforeUnmount(() => {
  lifecycle.clear();
  emit('busyChange', false);
});
</script>

<template>
  <Panel
    :title="
      t(
        isSolution
          ? 'JRC_SERVICE_DESK.TICKET.tabs.solution'
          : mode === 'sla'
            ? 'JRC_SERVICE_DESK.REDESIGN_DETAIL.sla_title'
            : 'JRC_SERVICE_DESK.REDESIGN_DETAIL.actions.status'
      )
    "
  >
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
        <div
          v-if="isClosure"
          class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4 text-sm"
          role="status"
        >
          <p>{{ t('JRC_SERVICE_DESK.REFINEMENT.closure.help') }}</p>
          <p v-if="rule?.action === 'resolve'" class="mt-2 font-medium">
            {{ t('JRC_SERVICE_DESK.REFINEMENT.closure.resolve_first') }}
          </p>
          <p v-if="!actionOptions.length" class="mt-2">
            {{ t('JRC_SERVICE_DESK.REFINEMENT.closure.unavailable') }}
          </p>
        </div>
        <form
          v-if="actionOptions.length"
          class="grid gap-3"
          @submit.prevent="submit"
        >
          <div
            v-if="mode === 'all'"
            class="flex flex-wrap gap-2"
            data-testid="lifecycle-shortcuts"
          >
            <Button
              v-for="option in actionOptions"
              :key="option.key"
              type="button"
              variant="outline"
              :color="actionTone(option.action)"
              :class="tones[actionTone(option.action)].soft"
              :disabled="busy || !!pendingCommand"
              :aria-pressed="selected === option.key"
              :label="`${actionLabels[option.action]}: ${option.to_status_name}`"
              @click="selected = option.key"
            />
          </div>
          <Select
            v-model="selected"
            :disabled="busy || !!pendingCommand"
            :placeholder="t('JRC_SERVICE_DESK.LIFECYCLE.choose_action')"
            :options="
              actionOptions.map(row => ({
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
              v-if="maySeeNotes && (!isClosure || rule.requirements.note)"
              v-model="note"
              :disabled="busy || !!pendingCommand"
              :max-length="20000"
              :label="
                t(
                  isSolution
                    ? 'JRC_SERVICE_DESK.REDESIGN_DETAIL.diagnosis'
                    : 'JRC_SERVICE_DESK.LIFECYCLE.note'
                ) + (rule.requirements.note ? ' *' : '')
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
            <details
              v-if="isSolution && maySeeNotes"
              :open="!isClosure"
              class="rounded-xl border border-n-weak p-3"
            >
              <summary class="mb-3 cursor-pointer text-sm font-medium">
                {{ t('JRC_SERVICE_DESK.REFINEMENT.closure.additional') }}
              </summary>
              <TextArea
                v-if="isClosure && !rule.requirements.note"
                v-model="note"
                :disabled="busy || !!pendingCommand"
                :max-length="20000"
                :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.diagnosis')"
              />
              <div class="grid gap-3">
                <TextArea
                  v-model="outcome"
                  :disabled="busy || !!pendingCommand"
                  :max-length="4000"
                  :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.outcome')"
                />
                <label class="grid gap-1 text-sm"
                  >{{
                    t('JRC_SERVICE_DESK.REDESIGN_DETAIL.customer_validation')
                  }}
                  <select
                    v-model="validation"
                    :disabled="busy || !!pendingCommand"
                    class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
                  >
                    <option value="">
                      {{ t('JRC_SERVICE_DESK.COMMON.not_informed') }}
                    </option>
                    <option
                      v-for="value in [
                        'awaiting',
                        'confirmed',
                        'not_confirmed',
                      ]"
                      :key="value"
                      :value="value"
                    >
                      {{
                        t(
                          `JRC_SERVICE_DESK.REDESIGN_DETAIL.validation.${value}`
                        )
                      }}
                    </option>
                  </select>
                </label>
                <Input
                  v-if="isClosure && !rule.requirements.evidence"
                  v-model="evidence"
                  :disabled="busy || !!pendingCommand"
                  :label="t('JRC_SERVICE_DESK.LIFECYCLE.evidence')"
                />
              </div>
            </details>
            <Input
              v-if="maySeeNotes && (!isClosure || rule.requirements.evidence)"
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
              >
                {{
                  `${t('JRC_SERVICE_DESK.LIFECYCLE.expected_value')}: ${spec.equals}`
                }}
              </span>
              <label
                v-if="spec.type === 'boolean'"
                class="text-sm"
                data-testid="lifecycle-boolean-field"
              >
                <input
                  v-model="fields[field]"
                  type="checkbox"
                  :disabled="busy || !!pendingCommand"
                />
                <span>{{ spec.label }}{{ spec.required ? ' *' : '' }}</span>
              </label>
              <Input
                v-else
                v-model="fields[field]"
                :disabled="busy || !!pendingCommand"
                :type="spec.type === 'integer' ? 'number' : 'text'"
                :label="spec.label + (spec.required ? ' *' : '')"
              />
            </template>
            <label
              v-if="isClosure"
              class="flex items-start gap-2 rounded-lg border border-n-weak p-3 text-sm"
            >
              <input
                v-model="confirmed"
                type="checkbox"
                :disabled="busy || !!pendingCommand"
                class="mt-1"
              />
              <span>{{
                t('JRC_SERVICE_DESK.REFINEMENT.closure.confirm', {
                  status: rule.to_status_name,
                })
              }}</span>
            </label>
            <Button
              type="submit"
              :disabled="
                busy ||
                !!pendingCommand ||
                (isClosure && (!confirmed || !closureValid)) ||
                (rule.action === 'pause' && !reason) ||
                (rule.requirements.solution && !solution.trim()) ||
                (rule.requirements.note && !note.trim()) ||
                (rule.requirements.evidence && !evidence.trim())
              "
              :color="
                ['resolve', 'close'].includes(rule.action)
                  ? 'teal'
                  : rule.action === 'cancel'
                    ? 'ruby'
                    : 'blue'
              "
              :label="
                isClosure
                  ? t(`JRC_SERVICE_DESK.REFINEMENT.closure.${rule.action}`)
                  : actionLabels[rule.action]
              "
            />
          </template>
        </form>
        <p
          v-else-if="mode !== 'sla' && !state.data.unavailable_reason"
          class="text-xs text-n-slate-11"
        >
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.no_actions') }}
        </p>
        <div
          v-if="['sla', 'all'].includes(mode) && state.data.cycle"
          class="grid gap-3 text-sm"
        >
          <p>
            {{
              t('JRC_SERVICE_DESK.LIFECYCLE.cycle', {
                number: state.data.cycle.number,
              })
            }}
            / {{ state.data.cycle.timezone }}
          </p>
          <div
            v-for="clock in state.data.cycle.clocks"
            :key="clock.id"
            class="grid gap-1 rounded-lg border border-n-weak bg-n-solid-2 p-4"
          >
            <p class="font-semibold">
              {{ t(`JRC_SERVICE_DESK.LIFECYCLE.clocks.${clock.kind}`) }}
            </p>
            <p>{{ t(`JRC_SERVICE_DESK.LIFECYCLE.states.${clock.state}`) }}</p>
            <p class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.FIELDS.due_at') }}:
              {{ formatTimestamp(clock.due_at, locale) }}
            </p>
          </div>
          <p>{{ t('JRC_SERVICE_DESK.LIFECYCLE.clock_notice') }}</p>
        </div>
        <p
          v-if="mode === 'sla' && !state.data.cycle"
          class="rounded-lg bg-n-amber-2 p-4 text-sm"
        >
          {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.sla_unconfigured') }}
        </p>
        <h4 v-if="solutionHistory.length" class="text-sm font-medium">
          {{ t('JRC_SERVICE_DESK.LIFECYCLE.history') }}
        </h4>
        <article
          v-for="item in solutionHistory"
          :key="item.id"
          class="border-t border-n-weak pt-2 text-xs break-words"
        >
          <p>
            {{ t(`JRC_SERVICE_DESK.LIFECYCLE.actions.${item.action}`) }} /
            {{ item.author.name }} /
            {{ formatTimestamp(item.occurred_at, locale) }}
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
          v-if="
            ['solution', 'all'].includes(mode) && state.data.meta.total > 20
          "
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
        v-if="
          ['sla', 'all'].includes(mode) &&
          ticket.permissions.record_sla_snapshot
        "
        :ticket="ticket"
        @snapshot-recorded="emit('snapshotRecorded', $event)"
      />
    </div>
  </Panel>
</template>
