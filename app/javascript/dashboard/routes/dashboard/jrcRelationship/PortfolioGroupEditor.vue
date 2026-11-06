<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { buttonClass, inputClass } from './definitions';
const props = defineProps({
  record: { type: Object, default: null },
  metadata: { type: Object, required: true },
  busy: Boolean,
  error: { type: String, default: '' },
  conflict: Boolean,
});
const emit = defineEmits(['close', 'save', 'reload']);
const { t } = useI18n();
const store = useStore();
const dialog = ref(null);
const tabs = ['general', 'goals', 'permissions', 'review'];
const tab = ref('general');
const reason = ref('');
const record = props.record;
const expectedVersion = record?.version;
const initialUnit =
  record?.business_unit_id ||
  (!record && props.metadata.units?.length === 1
    ? props.metadata.units[0][0]
    : '');
const title = computed(() =>
  record
    ? t('RELATIONSHIP.NAMED_PORTFOLIOS.EDIT')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.NEW')
);
const tabOptions = computed(() => [
  { value: 'general', label: t('RELATIONSHIP.NAMED_PORTFOLIOS.TABS.general') },
  { value: 'goals', label: t('RELATIONSHIP.NAMED_PORTFOLIOS.TABS.goals') },
  {
    value: 'permissions',
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.TABS.permissions'),
  },
  { value: 'review', label: t('RELATIONSHIP.NAMED_PORTFOLIOS.TABS.review') },
]);
const statusOptions = computed(() => [
  { value: 'active', label: t('RELATIONSHIP.NAMED_PORTFOLIOS.STATES.active') },
  {
    value: 'archived',
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.STATES.archived'),
  },
]);
const visibilityOptions = computed(() => [
  {
    value: 'private',
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.VISIBILITY_OPTIONS.private'),
  },
  {
    value: 'team',
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.VISIBILITY_OPTIONS.team'),
  },
  {
    value: 'account',
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.VISIBILITY_OPTIONS.account'),
  },
]);
const measureOptions = computed(() => [
  {
    value: 'baseline',
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.MEASURES.baseline'),
  },
  {
    value: 'target',
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.MEASURES.target'),
  },
  {
    value: 'current',
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.MEASURES.current'),
  },
]);
const submitLabel = computed(() => {
  if (props.busy) return t('RELATIONSHIP.NAMED_PORTFOLIOS.SAVING');
  return tab.value === 'review'
    ? t('RELATIONSHIP.NAMED_PORTFOLIOS.SAVE')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.NEXT');
});
const withCurrent = (options, id, label) => {
  const rows = options || [];
  return id && !rows.some(row => String(row[0]) === String(id))
    ? [[id, label || t('RELATIONSHIP.UNAVAILABLE')], ...rows]
    : rows;
};
const owners = computed(() =>
  withCurrent(props.metadata.owners, record?.owner_id, record?.owner_name)
);
const teams = computed(() =>
  withCurrent(props.metadata.teams, record?.team_id, record?.team_name)
);
const units = computed(() =>
  withCurrent(
    props.metadata.units,
    record?.business_unit_id,
    record?.business_unit_name
  )
);
const segments = computed(() =>
  withCurrent(props.metadata.segments, record?.segment_id, record?.segment_name)
);
const form = reactive({
  name: record?.name || '',
  objective: record?.objective || '',
  owner_id: String(record?.owner_id || store.getters.getCurrentUserID || ''),
  team_id: String(record?.team_id || ''),
  business_unit_id: String(initialUnit),
  segment_id: String(record?.segment_id || ''),
  visibility: record?.visibility || 'private',
  status: record?.status || 'active',
  goals: (record?.goals || []).map(goal => ({
    metric: goal.metric,
    baseline: goal.baseline ?? '',
    target: goal.target ?? '',
    current: goal.current ?? '',
    unit: goal.unit || '',
  })),
});
const configurable = computed(() => props.metadata.can_configure);
const goalIndex = ref(0);
const goalDraft = computed(() => form.goals[goalIndex.value]);
const addGoal = () => {
  form.goals.push({
    metric: '',
    baseline: '',
    target: '',
    current: '',
    unit: '',
  });
  goalIndex.value = form.goals.length - 1;
};
const removeGoal = () => {
  form.goals.splice(goalIndex.value, 1);
  goalIndex.value = Math.max(
    0,
    Math.min(goalIndex.value, form.goals.length - 1)
  );
};
const reviewDetails = computed(() => [
  {
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.STATUS'),
    value: statusOptions.value.find(row => row.value === form.status)?.label,
  },
  {
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.UNIT'),
    value:
      units.value.find(row => String(row[0]) === form.business_unit_id)?.[1] ||
      t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_UNIT'),
  },
  {
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.SEGMENT'),
    value:
      segments.value.find(row => String(row[0]) === form.segment_id)?.[1] ||
      t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_SEGMENT'),
  },
  {
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.TEAM'),
    value:
      teams.value.find(row => String(row[0]) === form.team_id)?.[1] ||
      t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_TEAM'),
  },
  {
    label: t('RELATIONSHIP.NAMED_PORTFOLIOS.VISIBILITY'),
    value: visibilityOptions.value.find(row => row.value === form.visibility)
      ?.label,
  },
]);
const valid = computed(
  () =>
    Boolean(form.name.trim() && form.owner_id) &&
    form.name.length <= 120 &&
    form.objective.length <= 4000 &&
    (form.visibility !== 'team' || Boolean(form.team_id)) &&
    form.goals.length <= 50 &&
    form.goals.every(
      goal =>
        goal.metric.trim() &&
        goal.metric.length <= 200 &&
        goal.unit.length <= 40 &&
        ['baseline', 'target', 'current'].every(
          key => goal[key] === '' || Number.isFinite(Number(goal[key]))
        )
    )
);
const fields = () => ({
  ...form,
  name: form.name.trim(),
  owner_id: Number(form.owner_id),
  team_id: form.team_id ? Number(form.team_id) : null,
  business_unit_id: form.business_unit_id
    ? Number(form.business_unit_id)
    : null,
  segment_id: form.segment_id ? Number(form.segment_id) : null,
  goals: form.goals.map(goal => {
    const value = { metric: goal.metric.trim(), unit: goal.unit };
    ['baseline', 'target', 'current'].forEach(key => {
      if (goal[key] !== '') value[key] = Number(goal[key]);
    });
    return value;
  }),
});
const submit = () => {
  if (props.busy || props.conflict || !valid.value) return;
  const position = tabs.indexOf(tab.value);
  if (position < tabs.length - 1) {
    tab.value = tabs[position + 1];
    return;
  }
  if (props.record && !reason.value.trim()) return;
  emit('save', {
    portfolio_group: fields(),
    expected_version: expectedVersion,
    reason: reason.value.trim(),
  });
};
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    width="2xl"
    :title="title"
    :use-form="false"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :show-close-button="!busy"
    :dismissible="!busy"
    :close-on-click-outside="false"
    overflow-y-auto
    @close="emit('close')"
  >
    <form
      class="min-w-0 space-y-4"
      @submit.prevent="submit"
    >
      <nav
        class="flex flex-wrap gap-2"
        :aria-label="t('RELATIONSHIP.NAMED_PORTFOLIOS.EDIT')"
      >
        <button
          v-for="option in tabOptions"
          :key="option.value"
          type="button"
          :disabled="busy || (option.value === 'review' && !valid)"
          :aria-current="tab === option.value ? 'step' : undefined"
          :class="[
            buttonClass,
            tab === option.value &&
              'border-n-violet-7 bg-n-violet-2 text-n-violet-11',
          ]"
          @click="tab = option.value"
        >
          {{ option.label }}
        </button>
      </nav>
      <p
        v-if="error"
        role="alert"
        class="break-words text-sm text-n-ruby-11"
      >
        {{ error }}
      </p>
      <button
        v-if="conflict"
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="emit('reload')"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.RELOAD_DRAFT') }}
      </button>
      <fieldset
        v-if="tab === 'general'"
        :disabled="busy"
        class="grid min-w-0 gap-3 sm:grid-cols-2"
      >
        <label class="min-w-0">
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NAME') }}</span>
          <input
            v-model="form.name"
            :class="inputClass"
            maxlength="120"
            required
            data-testid="portfolio-group-name"
          />
        </label>
        <label>
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.STATUS') }}</span>
          <select
            v-model="form.status"
            :class="inputClass"
          >
            <option
              v-for="status in statusOptions"
              :key="status.value"
              :value="status.value"
            >
              {{ status.label }}
            </option>
          </select>
        </label>
        <label class="min-w-0 sm:col-span-2">
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.OBJECTIVE') }}</span>
          <textarea
            v-model="form.objective"
            :class="inputClass"
            rows="3"
            maxlength="4000"
          />
        </label>
        <label>
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.UNIT') }}</span>
          <select
            v-model="form.business_unit_id"
            :class="inputClass"
            :disabled="!configurable && Boolean(record)"
          >
            <option value="">
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_UNIT') }}
            </option>
            <option
              v-for="unit in units"
              :key="unit[0]"
              :value="String(unit[0])"
            >
              {{ unit[1] }}
            </option>
          </select>
        </label>
        <label>
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.SEGMENT') }}</span>
          <select
            v-model="form.segment_id"
            :class="inputClass"
          >
            <option value="">
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_SEGMENT') }}
            </option>
            <option
              v-for="segment in segments"
              :key="segment[0]"
              :value="String(segment[0])"
            >
              {{ segment[1] }}
            </option>
          </select>
        </label>
      </fieldset>
      <section
        v-else-if="tab === 'goals'"
        class="min-w-0 space-y-3"
      >
        <p class="text-sm text-n-slate-11">
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.GOALS_HELP') }}
        </p>
        <label
          v-if="form.goals.length"
          class="block min-w-0"
        >
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.SELECT_GOAL') }}</span>
          <select
            v-model.number="goalIndex"
            :class="inputClass"
            :disabled="busy"
          >
            <option
              v-for="(item, index) in form.goals"
              :key="index"
              :value="index"
            >
              {{
                item.metric ||
                t('RELATIONSHIP.NAMED_PORTFOLIOS.GOAL_NUMBER', {
                  number: index + 1,
                })
              }}
            </option>
          </select>
        </label>
        <fieldset
          v-if="goalDraft"
          :key="goalIndex"
          :disabled="busy"
          class="grid min-w-0 gap-2 rounded-lg border border-n-weak p-3 sm:grid-cols-2"
        >
          <label class="min-w-0 sm:col-span-2">
            <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.METRIC') }}</span>
            <input
              v-model="goalDraft.metric"
              :class="inputClass"
              maxlength="200"
              required
            />
          </label>
          <label
            v-for="field in measureOptions"
            :key="field.value"
          >
            {{ field.label }}
            <input
              v-model="goalDraft[field.value]"
              type="number"
              step="any"
              :class="inputClass"
            />
          </label>
          <label>
            <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.GOAL_UNIT') }}</span>
            <input
              v-model="goalDraft.unit"
              :class="inputClass"
              maxlength="40"
            />
          </label>
          <button
            type="button"
            :class="buttonClass"
            @click="removeGoal"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.REMOVE_GOAL') }}
          </button>
        </fieldset>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || form.goals.length >= 50"
          @click="addGoal"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.ADD_GOAL') }}
        </button>
      </section>
      <fieldset
        v-else-if="tab === 'permissions'"
        :disabled="busy"
        class="grid min-w-0 gap-3 sm:grid-cols-2"
      >
        <p class="text-sm text-n-slate-11 sm:col-span-2">
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.COORDINATION_HELP') }}
        </p>
        <label>
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.COORDINATOR') }}</span>
          <select
            v-model="form.owner_id"
            :class="inputClass"
            required
          >
            <option
              v-for="owner in owners"
              :key="owner[0]"
              :value="String(owner[0])"
            >
              {{ owner[1] }}
            </option>
          </select>
        </label>
        <label>
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.TEAM') }}</span>
          <select
            v-model="form.team_id"
            :class="inputClass"
            :disabled="!configurable"
            :required="form.visibility === 'team'"
          >
            <option value="">
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NO_TEAM') }}
            </option>
            <option
              v-for="team in teams"
              :key="team[0]"
              :value="String(team[0])"
            >
              {{ team[1] }}
            </option>
          </select>
        </label>
        <label>
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.VISIBILITY') }}</span>
          <select
            v-model="form.visibility"
            :class="inputClass"
            :disabled="!configurable"
          >
            <option
              v-for="visibility in visibilityOptions"
              :key="visibility.value"
              :value="visibility.value"
            >
              {{ visibility.label }}
            </option>
          </select>
        </label>
      </fieldset>
      <section
        v-else
        class="min-w-0 space-y-3"
      >
        <h3 class="font-semibold">
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.REVIEW') }}
        </h3>
        <dl class="grid min-w-0 gap-3 sm:grid-cols-2">
          <div>
            <dt class="text-sm text-n-slate-11">
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NAME') }}
            </dt>
            <dd class="break-words font-semibold">{{ form.name }}</dd>
          </div>
          <div>
            <dt class="text-sm text-n-slate-11">
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.COORDINATOR') }}
            </dt>
            <dd>
              {{
                owners.find(row => String(row[0]) === form.owner_id)?.[1] ||
                t('RELATIONSHIP.UNAVAILABLE')
              }}
            </dd>
          </div>
          <div class="sm:col-span-2">
            <dt class="text-sm text-n-slate-11">
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.OBJECTIVE') }}
            </dt>
            <dd class="whitespace-pre-wrap break-words">
              {{ form.objective || '—' }}
            </dd>
          </div>
          <div
            v-for="item in reviewDetails"
            :key="item.label"
          >
            <dt class="text-sm text-n-slate-11">{{ item.label }}</dt>
            <dd class="break-words">{{ item.value }}</dd>
          </div>
        </dl>
        <ul class="max-h-64 space-y-2 overflow-y-auto">
          <li
            v-for="(goal, index) in form.goals"
            :key="index"
            class="break-words rounded-lg border border-n-weak p-2"
          >
            {{
              t('RELATIONSHIP.NAMED_PORTFOLIOS.GOAL_SUMMARY', {
                metric: goal.metric,
                current:
                  goal.current === ''
                    ? t('RELATIONSHIP.UNAVAILABLE')
                    : goal.current,
                target:
                  goal.target === ''
                    ? t('RELATIONSHIP.UNAVAILABLE')
                    : goal.target,
                unit: goal.unit,
              })
            }}
          </li>
        </ul>
        <label
          v-if="record"
          class="block"
        >
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.REASON') }}</span>
          <textarea
            v-model="reason"
            :class="inputClass"
            maxlength="4000"
            required
            :disabled="busy"
          />
        </label>
      </section>
      <p
        v-if="!valid"
        role="status"
        class="text-sm text-n-amber-11"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.COMPLETE_FIELDS') }}
      </p>
      <footer
        class="flex flex-wrap justify-end gap-2 border-t border-n-weak pt-4"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="emit('close')"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CANCEL') }}
        </button>
        <button
          v-if="tab !== 'general'"
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="tab = tabs[tabs.indexOf(tab) - 1]"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.BACK') }}
        </button>
        <button
          type="submit"
          :disabled="
            busy ||
            conflict ||
            !valid ||
            (tab === 'review' && record && !reason.trim())
          "
          class="rounded-lg bg-n-violet-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
          data-testid="portfolio-group-submit"
        >
          {{ submitLabel }}
        </button>
      </footer>
    </form>
  </Dialog>
</template>
