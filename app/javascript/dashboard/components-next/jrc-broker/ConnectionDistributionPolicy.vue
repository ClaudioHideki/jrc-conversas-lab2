<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  inboxId: { type: Number, required: true },
  connected: { type: Boolean, default: null },
  presentation: {
    type: String,
    default: 'all',
    validator: value =>
      ['all', 'summary', 'policy', 'rules', 'history'].includes(value),
  },
});
const emit = defineEmits(['saved', 'edit']);
const { t, locale } = useI18n();
const enabled = ref(false);
const hasPolicy = ref(false);
const savedPolicy = ref(null);
const mode = ref('round_robin');
const maxOpen = ref(10);
const respectAvailability = ref(true);
const capacityEnabled = ref(true);
const waitingEnabled = ref(true);
const schedule = ref('always');
const fallback = ref('waiting');
const fallbackTeamId = ref(null);
const calendar = ref(null);
const teamIds = ref([]);
const teams = ref([]);
const agents = ref([]);
const visibility = ref('shared');
const supervisorIds = ref([]);
const agentLimits = ref({});
const exclusive = computed(() => visibility.value === 'assigned_only');
watch(exclusive, value => {
  if (!value) return;
  respectAvailability.value = true;
  capacityEnabled.value = true;
  waitingEnabled.value = true;
  fallback.value = 'waiting';
  if (mode.value === 'direct') mode.value = 'round_robin';
});
const setAgentLimit = (id, value) => {
  if (value === '') delete agentLimits.value[id];
  else agentLimits.value[id] = Number(value);
};
const effectiveFrom = ref(null);
const loaded = ref(false);
const busy = ref(false);
const feedback = ref('');
const history = ref([]);
const historyVisible = ref(false);
const historyBusy = ref(false);
const historyError = ref(false);
const historyCursor = ref(null);
let controller;
let generation = 0;
let api;

const valid = computed(
  () =>
    ['round_robin', 'priority', 'direct'].includes(mode.value) &&
    Number.isInteger(maxOpen.value) &&
    maxOpen.value >= 1 &&
    maxOpen.value <= 100 &&
    (!enabled.value || teamIds.value.length > 0) &&
    (mode.value !== 'direct' || teamIds.value.length === 1) &&
    Object.values(agentLimits.value).every(
      limit => Number.isInteger(limit) && limit >= 1 && limit <= 100
    ) &&
    teamIds.value.every(id => teams.value.some(team => team.id === id)) &&
    (schedule.value !== 'inbox' || calendar.value?.enabled === true) &&
    (fallback.value !== 'waiting' || waitingEnabled.value) &&
    (fallback.value !== 'default_team' ||
      teams.value.some(team => team.id === fallbackTeamId.value))
);
const teamName = id =>
  teams.value.find(team => team.id === id)?.name ||
  t('JRC_BROKER.DISTRIBUTION.TEAM_UNAVAILABLE');
const validTime = value =>
  typeof value === 'string' && Number.isFinite(Date.parse(value));
const formatTime = value =>
  new Date(value).toLocaleString(locale.value.replace('_', '-'));
const modeLabel = value =>
  t(
    `JRC_BROKER.DISTRIBUTION.MODES.${
      { round_robin: 'ROUND_ROBIN', priority: 'PRIORITY', direct: 'DIRECT' }[
        value
      ] || 'UNKNOWN'
    }`
  );
const policySummary = policy => {
  if (!policy || Object.keys(policy).length === 0)
    return t('JRC_BROKER.DISTRIBUTION.NO_POLICY');
  const state = t(
    `JRC_BROKER.DISTRIBUTION.${policy.enabled ? 'ACTIVE' : 'INACTIVE'}`
  );
  if (policy.scope === 'GLOBAL') {
    return t('JRC_BROKER.DISTRIBUTION.GLOBAL_POLICY_SUMMARY', {
      state,
      selection: policy.included
        ? t('JRC_BROKER.DISTRIBUTION.GLOBAL_INCLUDED')
        : t('JRC_BROKER.DISTRIBUTION.GLOBAL_EXCLUDED'),
      capacity: policy.max_open,
    });
  }
  if (policy.scope === 'GLOBAL_ACCOUNT') {
    const inboxes = Array.isArray(policy.inbox_ids)
      ? policy.inbox_ids
          .map(id =>
            Number.isSafeInteger(id) && id > 0
              ? id
              : t('JRC_BROKER.DISTRIBUTION.INBOX_UNAVAILABLE')
          )
          .join(', ') || t('JRC_BROKER.DISTRIBUTION.NO_INBOX_SELECTION')
      : t('JRC_BROKER.DISTRIBUTION.INBOX_UNAVAILABLE');
    return t('JRC_BROKER.DISTRIBUTION.GLOBAL_ACCOUNT_POLICY_SUMMARY', {
      state,
      inboxes,
      capacity: policy.max_open,
    });
  }
  const distribution = t('JRC_BROKER.DISTRIBUTION.POLICY_SUMMARY', {
    state,
    mode: modeLabel(policy.mode),
    teams:
      (policy.team_ids || []).map(teamName).join(', ') ||
      t('JRC_BROKER.DISTRIBUTION.NO_SELECTION'),
    capacity:
      policy.capacity_enabled === false
        ? t('JRC_BROKER.DISTRIBUTION.NO_CAPACITY_LIMIT')
        : policy.max_open,
  });
  const fallbackLabel = {
    waiting: t('JRC_BROKER.DISTRIBUTION.WAITING'),
    default_team: t('JRC_BROKER.DISTRIBUTION.DEFAULT_TEAM'),
    unassigned: t('JRC_BROKER.DISTRIBUTION.UNASSIGNED'),
  }[policy.fallback || 'waiting'];
  const rules = [
    policy.schedule === 'inbox'
      ? t('JRC_BROKER.DISTRIBUTION.INBOX_CALENDAR')
      : t('JRC_BROKER.DISTRIBUTION.ALWAYS'),
    policy.respect_availability === false
      ? t('JRC_BROKER.DISTRIBUTION.IGNORE_AVAILABILITY')
      : t('JRC_BROKER.DISTRIBUTION.AVAILABILITY'),
    fallbackLabel,
    policy.fallback_team_id ? teamName(policy.fallback_team_id) : '',
  ]
    .filter(Boolean)
    .join('; ');
  return `${distribution}; ${rules}`;
};
const apply = policy => {
  savedPolicy.value = policy;
  hasPolicy.value = policy !== null && policy !== undefined;
  visibility.value = policy?.visibility || 'shared';
  supervisorIds.value = [...(policy?.supervisor_ids || [])];
  agentLimits.value = { ...(policy?.agent_limits || {}) };
  enabled.value = policy?.enabled === true;
  mode.value = policy?.mode || 'round_robin';
  maxOpen.value = policy?.max_open ?? 10;
  respectAvailability.value = policy?.respect_availability !== false;
  capacityEnabled.value = policy?.capacity_enabled !== false;
  waitingEnabled.value = policy?.waiting_enabled !== false;
  schedule.value = policy?.schedule || 'always';
  fallback.value = policy?.fallback || 'waiting';
  fallbackTeamId.value = policy?.fallback_team_id ?? null;
  teamIds.value = [...(policy?.team_ids || [])];
  effectiveFrom.value = validTime(policy?.effective_from)
    ? policy.effective_from
    : null;
};
const clear = () => {
  generation += 1;
  controller?.abort();
  loaded.value = false;
  busy.value = false;
  feedback.value = '';
  teams.value = [];
  agents.value = [];
  calendar.value = null;
  history.value = [];
  historyCursor.value = null;
  historyVisible.value = false;
  historyBusy.value = false;
  historyError.value = false;
  apply(null);
};
const fail = (error, message) => {
  if ([401, 403, 404].includes(error?.response?.status)) {
    clear();
    feedback.value = 'DENIED';
  } else {
    feedback.value = message;
  }
};
const load = async () => {
  clear();
  const current = generation;
  controller = new AbortController();
  api = createJrcBrokerApi(props.accountId);
  busy.value = true;
  try {
    const result = await api.connectionDistribution(
      props.inboxId,
      controller.signal
    );
    if (current !== generation) return;
    teams.value = result.teams;
    agents.value = result.agents || [];
    calendar.value = result.calendar;
    apply(result.policy);
    loaded.value = true;
  } catch (error) {
    if (current === generation) fail(error, 'LOAD_ERROR');
  } finally {
    if (current === generation) busy.value = false;
  }
};
const save = async () => {
  if (!loaded.value || busy.value || !valid.value) return;
  const current = generation;
  busy.value = true;
  feedback.value = '';
  try {
    const result = await api.saveConnectionDistribution(
      props.inboxId,
      {
        enabled: enabled.value,
        mode: mode.value,
        team_ids: [...teamIds.value],
        max_open: maxOpen.value,
        visibility: visibility.value,
        supervisor_ids: [...supervisorIds.value],
        agent_limits: { ...agentLimits.value },
        respect_availability: respectAvailability.value,
        capacity_enabled: capacityEnabled.value,
        waiting_enabled: waitingEnabled.value,
        schedule: schedule.value,
        fallback: fallback.value,
        fallback_team_id:
          fallback.value === 'default_team' ? fallbackTeamId.value : null,
      },
      controller.signal
    );
    if (current !== generation) return;
    apply(result.policy);
    feedback.value = 'SAVED';
    emit('saved', { accountId: props.accountId, inboxId: props.inboxId });
    history.value = [];
    historyVisible.value = false;
  } catch (error) {
    if (current === generation) fail(error, 'SAVE_ERROR');
  } finally {
    if (current === generation) busy.value = false;
  }
};
const toggleTeam = (id, selected) => {
  teamIds.value = selected
    ? [...teamIds.value, id]
    : teamIds.value.filter(value => value !== id);
};
const moveTeam = (index, offset) => {
  const target = index + offset;
  if (target < 0 || target >= teamIds.value.length) return;
  const ordered = [...teamIds.value];
  [ordered[index], ordered[target]] = [ordered[target], ordered[index]];
  teamIds.value = ordered;
};
const loadHistory = async (more = false) => {
  if (!loaded.value || busy.value || historyBusy.value) return;
  const current = generation;
  historyVisible.value = true;
  historyBusy.value = true;
  historyError.value = false;
  if (!more) history.value = [];
  try {
    const result = more
      ? await api.distributionHistory(
          props.inboxId,
          controller.signal,
          historyCursor.value
        )
      : await api.distributionHistory(props.inboxId, controller.signal);
    if (current !== generation) return;
    history.value = [...history.value, ...result.data];
    historyCursor.value = result.next_cursor;
  } catch (error) {
    if (current !== generation) return;
    if ([401, 403, 404].includes(error?.response?.status))
      fail(error, 'DENIED');
    else historyError.value = true;
  } finally {
    if (current === generation) historyBusy.value = false;
  }
};
watch(() => [props.accountId, props.inboxId], load, {
  immediate: true,
  flush: 'sync',
});
onBeforeUnmount(clear);
</script>

<template>
  <section
    data-testid="connection-distribution-policy"
    class="mt-5 rounded-xl border border-n-weak p-5 flex flex-col gap-4"
  >
    <h3 class="text-lg font-semibold text-n-slate-12">
      {{ t('JRC_BROKER.DISTRIBUTION.TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-11">
      {{
        presentation === 'history'
          ? t('JRC_BROKER.DISTRIBUTION.HISTORY_HELP')
          : t('JRC_BROKER.DISTRIBUTION.HELP')
      }}
    </p>
    <p
      v-if="connected === false"
      data-testid="distribution-awaiting-connection"
      class="text-sm text-n-amber-11"
    >
      {{ t('JRC_BROKER.DISTRIBUTION.AWAITING_CONNECTION') }}
    </p>
    <p
      v-if="loaded && !hasPolicy"
      data-testid="distribution-global-fallback"
      class="text-sm text-n-slate-11"
    >
      {{ t('JRC_BROKER.DISTRIBUTION.GLOBAL_FALLBACK') }}
    </p>
    <p v-if="feedback" :role="feedback === 'SAVED' ? 'status' : 'alert'">
      {{ t(`JRC_BROKER.DISTRIBUTION.${feedback}`) }}
    </p>
    <p
      v-if="loaded && hasPolicy && presentation === 'summary'"
      data-testid="distribution-saved-summary"
      class="sr-only"
    >
      {{ policySummary(savedPolicy) }}
    </p>
    <div
      v-if="presentation === 'summary' && loaded"
      class="grid gap-5 lg:grid-cols-2"
    >
      <section
        data-testid="distribution-queue-card"
        class="flex flex-col gap-4 rounded-xl border border-n-weak p-5"
      >
        <h4 class="flex items-center gap-2 text-sm font-semibold">
          <span
            aria-hidden="true"
            class="i-lucide-git-branch size-4 text-n-brand"
          />{{ t('JRC_BROKER.DISTRIBUTION.QUEUES') }}
        </h4>
        <div class="flex flex-wrap gap-2">
          <span
            v-for="id in savedPolicy?.team_ids || []"
            :key="id"
            class="rounded-md bg-n-alpha-2 px-3 py-1 text-sm text-n-blue-11"
            >{{ teamName(id) }}</span
          >
          <p
            v-if="!savedPolicy?.team_ids?.length"
            class="text-sm text-n-slate-11"
          >
            {{ t('JRC_BROKER.DISTRIBUTION.NO_SELECTION') }}
          </p>
        </div>
        <p v-if="savedPolicy?.mode" class="text-sm text-n-slate-11">
          {{ modeLabel(savedPolicy.mode) }}
        </p>
        <Button
          data-testid="edit-connection-distribution"
          class="mt-auto self-start"
          variant="outline"
          icon="i-lucide-pencil"
          :label="t('JRC_BROKER.WORKSPACE.CONFIGURE_DISTRIBUTION')"
          @click="emit('edit', 'distribution')"
        />
      </section>
      <section class="flex flex-col gap-4 rounded-xl border border-n-weak p-5">
        <h4 class="flex items-center gap-2 text-sm font-semibold">
          <span
            aria-hidden="true"
            class="i-lucide-clock-3 size-4 text-n-brand"
          />{{ t('JRC_BROKER.DISTRIBUTION.RULES') }}
        </h4>
        <template v-if="hasPolicy">
          <span
            class="self-start rounded-full bg-n-alpha-2 px-3 py-1 text-xs"
            :class="savedPolicy.enabled ? 'text-n-teal-11' : 'text-n-slate-11'"
            >{{
              t(
                `JRC_BROKER.DISTRIBUTION.${savedPolicy.enabled ? 'ACTIVE' : 'INACTIVE'}`
              )
            }}</span
          >
          <ul class="space-y-2 text-sm text-n-slate-11">
            <li>
              {{
                t(
                  savedPolicy.respect_availability === false
                    ? 'JRC_BROKER.DISTRIBUTION.IGNORE_AVAILABILITY'
                    : 'JRC_BROKER.DISTRIBUTION.AVAILABILITY'
                )
              }}
            </li>
            <li>
              {{
                savedPolicy.capacity_enabled === false
                  ? t('JRC_BROKER.DISTRIBUTION.NO_CAPACITY_LIMIT')
                  : t('JRC_BROKER.DISTRIBUTION.CAPACITY')
              }}<span v-if="savedPolicy.capacity_enabled !== false"
                >: {{ savedPolicy.max_open }}</span
              >
            </li>
            <li>
              {{
                t(
                  savedPolicy.schedule === 'inbox'
                    ? 'JRC_BROKER.DISTRIBUTION.INBOX_CALENDAR'
                    : 'JRC_BROKER.DISTRIBUTION.ALWAYS'
                )
              }}
            </li>
            <li>
              {{ t('JRC_BROKER.DISTRIBUTION.FALLBACK') }}:
              {{
                t(
                  savedPolicy.fallback === 'unassigned'
                    ? 'JRC_BROKER.DISTRIBUTION.UNASSIGNED'
                    : savedPolicy.fallback === 'default_team'
                      ? 'JRC_BROKER.DISTRIBUTION.DEFAULT_TEAM'
                      : 'JRC_BROKER.DISTRIBUTION.WAITING'
                )
              }}
              <span v-if="savedPolicy.fallback === 'default_team'">
                — {{ teamName(savedPolicy.fallback_team_id) }}</span
              >
            </li>
          </ul>
        </template>
        <p v-else class="text-sm text-n-slate-11">
          {{ t('JRC_BROKER.DISTRIBUTION.NO_POLICY') }}
        </p>
        <Button
          data-testid="edit-connection-rules"
          class="mt-auto self-start"
          variant="outline"
          icon="i-lucide-pencil"
          :label="t('JRC_BROKER.DISTRIBUTION.RULES')"
          @click="emit('edit', 'rules')"
        />
      </section>
    </div>
    <Button
      variant="outline"
      :disabled="busy"
      :label="t('JRC_BROKER.DISTRIBUTION.RELOAD')"
      @click="load"
    />
    <p
      v-if="presentation === 'rules' && loaded"
      class="text-sm text-n-slate-11"
    >
      {{ policySummary(savedPolicy) }}
    </p>
    <form
      v-if="
        presentation === 'all' ||
        presentation === 'policy' ||
        presentation === 'rules'
      "
      @submit.prevent="save"
    >
      <fieldset :disabled="busy || !loaded" class="min-w-0">
        <div
          class="grid grid-cols-1 items-start gap-6"
          :class="presentation === 'rules' ? 'grid-cols-1' : 'lg:grid-cols-2'"
        >
          <div v-show="presentation !== 'rules'" class="flex flex-col gap-4">
            <label class="flex flex-col gap-2 text-sm">
              {{ t('JRC_BROKER.DISTRIBUTION.VISIBILITY') }}
              <select
                v-model="visibility"
                data-testid="distribution-visibility"
              >
                <option value="shared">
                  {{ t('JRC_BROKER.DISTRIBUTION.SHARED') }}
                </option>
                <option value="assigned_only">
                  {{ t('JRC_BROKER.DISTRIBUTION.ASSIGNED_ONLY') }}
                </option>
              </select>
            </label>
            <fieldset v-if="exclusive" class="flex flex-col gap-2">
              <legend>{{ t('JRC_BROKER.DISTRIBUTION.SUPERVISORS') }}</legend>
              <p class="text-sm text-n-slate-11">
                {{ t('JRC_BROKER.DISTRIBUTION.EXCLUSIVE_HELP') }}
              </p>
              <label
                v-for="agent in agents.filter(
                  item => item.can_supervise !== false
                )"
                :key="agent.id"
                class="flex items-center gap-2 text-sm"
              >
                <input
                  v-model="supervisorIds"
                  type="checkbox"
                  :value="agent.id"
                  :data-supervisor-id="agent.id"
                />
                {{ agent.name }}
              </label>
            </fieldset>
            <fieldset v-if="exclusive" class="flex flex-col gap-2">
              <legend>
                {{ t('JRC_BROKER.DISTRIBUTION.INDIVIDUAL_LIMITS') }}
              </legend>
              <label
                v-for="agent in agents"
                :key="agent.id"
                class="flex items-center justify-between gap-2 text-sm"
              >
                <span
                  >{{ agent.name }}
                  <span v-if="agent.active !== undefined"
                    >({{ agent.active }} /
                    {{ agentLimits[agent.id] || maxOpen }})</span
                  ></span
                >
                <input
                  type="number"
                  min="1"
                  max="100"
                  step="1"
                  :value="agentLimits[agent.id] ?? ''"
                  :placeholder="String(maxOpen)"
                  :data-agent-limit-id="agent.id"
                  :aria-label="
                    t('JRC_BROKER.DISTRIBUTION.AGENT_LIMIT', {
                      name: agent.name,
                    })
                  "
                  @input="setAgentLimit(agent.id, $event.target.value)"
                />
              </label>
            </fieldset>
            <label class="flex items-center gap-2 text-sm">
              <input
                v-model="enabled"
                data-testid="distribution-enabled"
                type="checkbox"
              />
              {{ t('JRC_BROKER.DISTRIBUTION.ENABLED') }}
            </label>
            <fieldset class="flex flex-col gap-3">
              <legend class="mb-3 text-sm font-medium">
                {{ t('JRC_BROKER.DISTRIBUTION.MODE') }}
              </legend>
              <label
                v-for="option in ['round_robin', 'priority', 'direct']"
                :key="option"
                class="flex cursor-pointer items-center gap-3 rounded-xl border p-4 text-sm"
                :class="
                  mode === option
                    ? 'border-n-brand bg-n-alpha-1'
                    : 'border-n-weak'
                "
              >
                <input
                  v-model="mode"
                  type="radio"
                  name="connection-distribution-mode"
                  :value="option"
                  :disabled="exclusive && option === 'direct'"
                />{{ modeLabel(option) }}
              </label>
            </fieldset>
            <p v-if="mode === 'direct'" class="text-sm text-n-slate-11">
              {{ t('JRC_BROKER.DISTRIBUTION.DIRECT_HELP') }}
            </p>
            <p v-if="mode === 'priority'" class="text-sm text-n-slate-11">
              {{ t('JRC_BROKER.DISTRIBUTION.PRIORITY_HELP') }}
            </p>
            <div class="flex flex-col gap-2">
              <p class="text-sm font-medium">
                {{ t('JRC_BROKER.DISTRIBUTION.QUEUES') }}
              </p>
              <label
                v-for="team in teams"
                :key="team.id"
                class="flex items-center gap-2 text-sm"
              >
                <input
                  type="checkbox"
                  :data-team-id="team.id"
                  :checked="teamIds.includes(team.id)"
                  @change="toggleTeam(team.id, $event.target.checked)"
                />
                {{ team.name }}
              </label>
              <p v-if="!teams.length" class="text-sm">
                {{ t('JRC_BROKER.DISTRIBUTION.NO_TEAMS') }}
              </p>
            </div>
            <ol
              v-if="teamIds.length"
              class="flex flex-col gap-2 list-decimal pl-5"
            >
              <li
                v-for="(id, index) in teamIds"
                :key="id"
                :data-selected-team="id"
                class="text-sm"
              >
                <span>{{ teamName(id) }}</span>
                <div class="mt-2 flex flex-wrap gap-2">
                  <Button
                    v-if="mode === 'priority'"
                    type="button"
                    variant="outline"
                    icon="i-lucide-arrow-up"
                    :disabled="index === 0"
                    :aria-label="
                      t('JRC_BROKER.DISTRIBUTION.MOVE_UP', {
                        name: teamName(id),
                      })
                    "
                    @click="moveTeam(index, -1)"
                  />
                  <Button
                    v-if="mode === 'priority'"
                    type="button"
                    variant="outline"
                    icon="i-lucide-arrow-down"
                    :disabled="index === teamIds.length - 1"
                    :aria-label="
                      t('JRC_BROKER.DISTRIBUTION.MOVE_DOWN', {
                        name: teamName(id),
                      })
                    "
                    @click="moveTeam(index, 1)"
                  />
                  <Button
                    type="button"
                    variant="outline"
                    :label="t('JRC_BROKER.DISTRIBUTION.REMOVE')"
                    :aria-label="
                      t('JRC_BROKER.DISTRIBUTION.REMOVE_TEAM', {
                        name: teamName(id),
                      })
                    "
                    @click="toggleTeam(id, false)"
                  />
                </div>
              </li>
            </ol>
            <label class="flex flex-col gap-2 text-sm">
              {{ t('JRC_BROKER.DISTRIBUTION.CAPACITY') }}
              <input
                v-model.number="maxOpen"
                type="number"
                min="1"
                max="100"
                step="1"
                required
              />
            </label>
          </div>
          <section
            data-testid="distribution-rules-fields"
            :aria-label="t('JRC_BROKER.DISTRIBUTION.RULES')"
            class="flex min-w-0 flex-col gap-4 rounded-xl border border-n-weak bg-n-alpha-1 p-5"
          >
            <h4 class="text-sm font-semibold">
              {{ t('JRC_BROKER.DISTRIBUTION.RULES') }}
            </h4>
            <label class="flex items-center gap-2 text-sm">
              <input
                v-model="respectAvailability"
                data-testid="distribution-availability"
                :disabled="exclusive"
                type="checkbox"
              />
              {{ t('JRC_BROKER.DISTRIBUTION.AVAILABILITY') }}
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input
                v-model="capacityEnabled"
                data-testid="distribution-capacity-enabled"
                :disabled="exclusive"
                type="checkbox"
              />
              {{ t('JRC_BROKER.DISTRIBUTION.CAPACITY_ENABLED') }}
            </label>
            <label class="flex items-center gap-2 text-sm">
              <input
                v-model="waitingEnabled"
                data-testid="distribution-waiting"
                :disabled="exclusive"
                type="checkbox"
              />
              {{ t('JRC_BROKER.DISTRIBUTION.WAITING') }}
            </label>
            <label class="flex flex-col gap-2 text-sm">
              {{ t('JRC_BROKER.DISTRIBUTION.SCHEDULE') }}
              <select v-model="schedule" data-testid="distribution-schedule">
                <option value="always">
                  {{ t('JRC_BROKER.DISTRIBUTION.ALWAYS') }}
                </option>
                <option value="inbox" :disabled="!calendar?.enabled">
                  {{ t('JRC_BROKER.DISTRIBUTION.INBOX_CALENDAR') }}
                </option>
              </select>
            </label>
            <p v-if="calendar?.timezone" class="text-sm">
              {{ t('JRC_BROKER.DISTRIBUTION.TIMEZONE') }}
              {{ calendar.timezone }}
            </p>
            <a
              :href="`/app/accounts/${accountId}/settings/inboxes/${inboxId}/business-hours`"
              class="text-sm text-n-blue-11 underline"
            >
              {{ t('JRC_BROKER.DISTRIBUTION.EDIT_CALENDAR') }}
            </a>
            <label class="flex flex-col gap-2 text-sm">
              {{ t('JRC_BROKER.DISTRIBUTION.FALLBACK') }}
              <select
                v-model="fallback"
                data-testid="distribution-fallback"
                :disabled="exclusive"
              >
                <option value="waiting" :disabled="!waitingEnabled">
                  {{ t('JRC_BROKER.DISTRIBUTION.WAITING') }}
                </option>
                <option value="default_team">
                  {{ t('JRC_BROKER.DISTRIBUTION.DEFAULT_TEAM') }}
                </option>
                <option value="unassigned">
                  {{ t('JRC_BROKER.DISTRIBUTION.UNASSIGNED') }}
                </option>
              </select>
            </label>
            <label
              v-if="fallback === 'default_team'"
              class="flex flex-col gap-2 text-sm"
            >
              {{ t('JRC_BROKER.DISTRIBUTION.DEFAULT_TEAM') }}
              <select
                v-model="fallbackTeamId"
                data-testid="distribution-fallback-team"
              >
                <option :value="null">
                  {{ t('JRC_BROKER.DISTRIBUTION.NO_SELECTION') }}
                </option>
                <option v-for="team in teams" :key="team.id" :value="team.id">
                  {{ team.name }}
                </option>
              </select>
            </label>
          </section>
          <p v-if="!valid" class="text-sm lg:col-span-2">
            {{ t('JRC_BROKER.DISTRIBUTION.VALIDATION') }}
          </p>
          <Button
            data-testid="distribution-policy-save"
            type="submit"
            class="justify-self-start"
            :class="presentation === 'rules' ? '' : 'lg:col-span-2'"
            :disabled="!valid"
            :label="t('JRC_BROKER.DISTRIBUTION.SAVE')"
          />
        </div>
      </fieldset>
    </form>
    <p v-if="effectiveFrom" class="text-sm text-n-slate-11">
      {{ t('JRC_BROKER.DISTRIBUTION.EFFECTIVE_FROM') }}
      <time :datetime="effectiveFrom">{{ formatTime(effectiveFrom) }}</time>
    </p>
    <Button
      v-if="presentation === 'all' || presentation === 'history'"
      data-testid="load-distribution-history"
      variant="outline"
      :disabled="!loaded || busy || historyBusy"
      :label="t('JRC_BROKER.DISTRIBUTION.HISTORY')"
      @click="loadHistory()"
    />
    <div
      v-if="
        historyVisible && (presentation === 'all' || presentation === 'history')
      "
      data-testid="distribution-history"
      class="flex flex-col gap-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_BROKER.DISTRIBUTION.HISTORY_HELP') }}
      </p>
      <p v-if="historyBusy" role="status">
        {{ t('JRC_BROKER.DISTRIBUTION.HISTORY_LOADING') }}
      </p>
      <p v-else-if="historyError" role="alert">
        {{ t('JRC_BROKER.DISTRIBUTION.HISTORY_ERROR') }}
      </p>
      <p v-else-if="!history.length" data-testid="empty-distribution-history">
        {{ t('JRC_BROKER.DISTRIBUTION.HISTORY_EMPTY') }}
      </p>
      <ol v-else class="flex flex-col gap-3">
        <li
          v-for="entry in history"
          :key="entry.id"
          class="rounded-lg border border-n-weak p-3 text-sm"
        >
          <p>
            {{
              entry.user_id === null || entry.user_id === undefined
                ? t('JRC_BROKER.DISTRIBUTION.ACTOR_SYSTEM')
                : t('JRC_BROKER.DISTRIBUTION.ACTOR', { id: entry.user_id })
            }}
          </p>
          <time v-if="validTime(entry.created_at)" :datetime="entry.created_at">
            {{ formatTime(entry.created_at) }}
          </time>
          <dl class="mt-2 flex flex-col gap-2">
            <div>
              <dt class="font-medium">
                {{ t('JRC_BROKER.DISTRIBUTION.PREVIOUS') }}
              </dt>
              <dd>{{ policySummary(entry.previous_policy) }}</dd>
            </div>
            <div>
              <dt class="font-medium">
                {{ t('JRC_BROKER.DISTRIBUTION.NEXT') }}
              </dt>
              <dd>{{ policySummary(entry.next_policy) }}</dd>
            </div>
          </dl>
        </li>
      </ol>
      <Button
        v-if="historyCursor"
        data-testid="distribution-history-more"
        variant="outline"
        :disabled="historyBusy"
        :label="t('JRC_BROKER.HISTORY.MORE')"
        @click="loadHistory(true)"
      />
    </div>
  </section>
</template>
