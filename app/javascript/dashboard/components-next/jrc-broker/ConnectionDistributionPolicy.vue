<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  inboxId: { type: Number, required: true },
});
const { t } = useI18n();
const enabled = ref(false);
const hasPolicy = ref(false);
const mode = ref('round_robin');
const maxOpen = ref(10);
const teamIds = ref([]);
const teams = ref([]);
const effectiveFrom = ref(null);
const loaded = ref(false);
const busy = ref(false);
const feedback = ref('');
const history = ref([]);
const historyVisible = ref(false);
const historyBusy = ref(false);
const historyError = ref(false);
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
    teamIds.value.every(id => teams.value.some(team => team.id === id))
);
const teamName = id =>
  teams.value.find(team => team.id === id)?.name ||
  t('JRC_BROKER.DISTRIBUTION.TEAM_UNAVAILABLE');
const validTime = value =>
  typeof value === 'string' && Number.isFinite(Date.parse(value));
const formatTime = value => new Date(value).toLocaleString();
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
  return t('JRC_BROKER.DISTRIBUTION.POLICY_SUMMARY', {
    state: t(
      `JRC_BROKER.DISTRIBUTION.${policy.enabled ? 'ACTIVE' : 'INACTIVE'}`
    ),
    mode: modeLabel(policy.mode),
    teams:
      (policy.team_ids || []).map(teamName).join(', ') ||
      t('JRC_BROKER.DISTRIBUTION.NO_SELECTION'),
    capacity: policy.max_open,
  });
};
const apply = policy => {
  hasPolicy.value = policy !== null && policy !== undefined;
  enabled.value = policy?.enabled === true;
  mode.value = policy?.mode || 'round_robin';
  maxOpen.value = policy?.max_open ?? 10;
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
  history.value = [];
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
      },
      controller.signal
    );
    if (current !== generation) return;
    apply(result.policy);
    feedback.value = 'SAVED';
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
const loadHistory = async () => {
  if (!loaded.value || busy.value || historyBusy.value) return;
  const current = generation;
  historyVisible.value = true;
  historyBusy.value = true;
  historyError.value = false;
  history.value = [];
  try {
    const result = await api.distributionHistory(
      props.inboxId,
      controller.signal
    );
    if (current !== generation) return;
    history.value = result.data;
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
      {{ t('JRC_BROKER.DISTRIBUTION.HELP') }}
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
    <Button
      variant="outline"
      :disabled="busy"
      :label="t('JRC_BROKER.DISTRIBUTION.RELOAD')"
      @click="load"
    />
    <form @submit.prevent="save">
      <fieldset :disabled="busy || !loaded" class="flex flex-col gap-4">
        <label class="flex items-center gap-2 text-sm">
          <input
            v-model="enabled"
            data-testid="distribution-enabled"
            type="checkbox"
          />
          {{ t('JRC_BROKER.DISTRIBUTION.ENABLED') }}
        </label>
        <label class="flex flex-col gap-2 text-sm">
          {{ t('JRC_BROKER.DISTRIBUTION.MODE') }}
          <select v-model="mode">
            <option value="round_robin">{{ modeLabel('round_robin') }}</option>
            <option value="priority">{{ modeLabel('priority') }}</option>
            <option value="direct">{{ modeLabel('direct') }}</option>
          </select>
        </label>
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
        <ol v-if="teamIds.length" class="flex flex-col gap-2 list-decimal pl-5">
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
                  t('JRC_BROKER.DISTRIBUTION.MOVE_UP', { name: teamName(id) })
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
                  t('JRC_BROKER.DISTRIBUTION.MOVE_DOWN', { name: teamName(id) })
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
        <p v-if="!valid" class="text-sm">
          {{ t('JRC_BROKER.DISTRIBUTION.VALIDATION') }}
        </p>
        <Button
          type="submit"
          :disabled="!valid"
          :label="t('JRC_BROKER.DISTRIBUTION.SAVE')"
        />
      </fieldset>
    </form>
    <p v-if="effectiveFrom" class="text-sm text-n-slate-11">
      {{ t('JRC_BROKER.DISTRIBUTION.EFFECTIVE_FROM') }}
      <time :datetime="effectiveFrom">{{ formatTime(effectiveFrom) }}</time>
    </p>
    <Button
      data-testid="load-distribution-history"
      variant="outline"
      :disabled="!loaded || busy || historyBusy"
      :label="t('JRC_BROKER.DISTRIBUTION.HISTORY')"
      @click="loadHistory"
    />
    <div
      v-if="historyVisible"
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
          <p>{{ t('JRC_BROKER.DISTRIBUTION.ACTOR', { id: entry.user_id }) }}</p>
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
    </div>
  </section>
</template>
