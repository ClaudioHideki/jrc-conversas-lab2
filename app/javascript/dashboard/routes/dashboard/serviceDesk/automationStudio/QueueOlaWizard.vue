<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import LookupSelect from '../components/LookupSelect.vue';
import ClockAutomationFields from '../components/ClockAutomationFields.vue';
import AutomationDialog from './AutomationDialog.vue';
import OlaMonitoring from './OlaMonitoring.vue';
import CalendarFields from './CalendarFields.vue';
import { validCalendar } from './calendarRules';
import Drafts from 'dashboard/api/serviceDeskAutomationDrafts';
import { DISTRIBUTION_MODES, skillCodes } from '../helpers/v2Configuration';
import { configurationAttributes } from '../helpers/configuration';
import { validThresholds, snapshot } from './flowRules';
const props = defineProps({
  modelValue: { type: Object, required: true },
  record: { type: Object, required: true },
  context: { type: Object, required: true },
  unitId: { type: String, required: true },
  saving: Boolean,
  pending: Boolean,
  feedback: { type: String, default: 'idle' },
});
const emit = defineEmits(['update:modelValue', 'save', 'cancel']);
const { t, tm } = useI18n();
const tr = (key, values) =>
  t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.${key}`, values || {});
const steps = computed(() =>
  tm('JRC_SERVICE_DESK.AUTOMATION_STUDIO.ola.steps')
);
const step = ref(0);
const reached = ref(0);
const confirmed = ref(false);
const localMessage = ref('');
const initial = JSON.stringify(props.modelValue);
const dirty = computed(() => JSON.stringify(props.modelValue) !== initial);
const locked = computed(() => props.saving || props.pending);
const olaEnabled = ref(
  Object.keys(props.modelValue.ola_targets || {}).length > 0 ||
    props.modelValue.ola_budget_seconds != null
);
const formClass =
  'w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm disabled:opacity-60';
const buttonClass =
  'rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm disabled:opacity-50';
const primaryClass =
  'rounded-lg bg-n-blue-9 px-4 py-2 text-sm text-white disabled:opacity-50';
const policy = computed(() => props.modelValue.ola_escalation_policy || {});
function update(field, value) {
  if (!locked.value)
    emit('update:modelValue', { ...props.modelValue, [field]: value });
}
const skillsText = computed({
  get: () => (props.modelValue.required_skills || []).join(', '),
  set: value =>
    update(
      'required_skills',
      value
        .split(',')
        .map(item => item.trim())
        .filter(Boolean)
    ),
});

watch(olaEnabled, () => {
  if (locked.value) return;
  emit('update:modelValue', {
    ...props.modelValue,
    ola_budget_seconds: null,
    ola_targets: olaEnabled.value ? props.modelValue.ola_targets || {} : {},
    ola_time_basis: olaEnabled.value
      ? props.modelValue.ola_time_basis || 'calendar'
      : null,
  });
});
watch(
  () => props.modelValue,
  () => {
    confirmed.value = false;
  },
  { deep: true }
);
function setPolicy(value) {
  update('ola_escalation_policy', value);
}
function changeThreshold(index, field, value) {
  const thresholds = (policy.value.thresholds || []).map((row, i) =>
    i === index ? { ...row, [field]: value } : row
  );
  setPolicy({ ...policy.value, thresholds });
}
function setAlert(index, ids, channels) {
  const thresholds = (policy.value.thresholds || []).map((row, i) => {
    if (i !== index) return row;
    const nextPolicy = { ...row };
    if (!ids.length) {
      delete nextPolicy.notification_member_ids;
      delete nextPolicy.notification_channels;
    } else {
      nextPolicy.notification_member_ids = ids;
      nextPolicy.notification_channels = channels;
    }
    return nextPolicy;
  });
  setPolicy({ ...policy.value, thresholds });
}
const alertRecipient = ref('');
function addThreshold() {
  const rows = policy.value.thresholds || [];
  const last = rows.at(-1)?.percent || 0;
  if (rows.length >= 20 || last >= 100) {
    localMessage.value = 'invalid';
    return;
  }
  setPolicy({
    enabled: policy.value.enabled === true,
    ...policy.value,
    thresholds: [
      ...rows,
      {
        percent: Math.min(100, last ? last + 10 : 75),
        queue_id: null,
        team_id: null,
      },
    ],
  });
}
function removeThreshold(index) {
  const rows = (policy.value.thresholds || []).filter((_, i) => i !== index);
  setPolicy(rows.length ? { ...policy.value, thresholds: rows } : {});
}
function validate() {
  try {
    configurationAttributes(
      'queues',
      props.record.id
        ? Object.fromEntries(
            Object.entries(props.modelValue).filter(([key]) => key !== 'code')
          )
        : props.modelValue,
      !props.record.id
    );
    skillCodes(props.modelValue.required_skills || []);
    if (
      olaEnabled.value &&
      (!['calendar', 'business'].includes(props.modelValue.ola_time_basis) ||
        !['first_response', 'update', 'resolution'].every(
          kind =>
            Number.isInteger(props.modelValue.ola_targets?.[kind]) &&
            props.modelValue.ola_targets[kind] > 0
        ))
    )
      return false;
    if (
      olaEnabled.value &&
      props.modelValue.ola_time_basis === 'business' &&
      !validCalendar(props.modelValue.ola_calendar)
    )
      return false;
    if (!validThresholds(policy.value)) return false;
    if (policy.value.enabled && !olaEnabled.value) return false;
    return true;
  } catch {
    return false;
  }
}
function next() {
  localMessage.value = '';
  if (!props.modelValue.name?.trim() || !props.modelValue.code?.trim()) {
    localMessage.value = 'invalid';
    return;
  }
  if (step.value >= 2 && !validate()) {
    localMessage.value = 'invalid';
    return;
  }
  step.value = Math.min(5, step.value + 1);
  reached.value = Math.max(reached.value, step.value);
}
function save() {
  if (!locked.value && confirmed.value && validate()) emit('save');
  else localMessage.value = 'invalid';
}
const draftVersion = ref(-1);
const versions = ref([]);
const draftCode = () =>
  String(props.record.id || props.modelValue.code || 'new');
async function saveLocal() {
  try {
    const row = await Drafts.save(
      props.context.account_id,
      props.unitId,
      'queue',
      draftCode(),
      {
        form: props.modelValue,
        olaEnabled: olaEnabled.value,
        revision: props.record.revision || null,
      },
      draftVersion.value
    );
    draftVersion.value = row.lock_version;
    localMessage.value = 'private_draft_saved';
  } catch {
    localMessage.value = 'draft_error';
  }
}
async function restoreLocal() {
  try {
    const row = await Drafts.read(
      props.context.account_id,
      props.unitId,
      'queue',
      draftCode()
    );
    const draft = row.payload;
    if (draft.revision !== (props.record.revision || null))
      throw new Error('Publication changed');
    if (props.record.id && draft.form.code !== props.record.code)
      throw new Error('Draft identity mismatch');
    emit('update:modelValue', snapshot(draft.form));
    olaEnabled.value = draft.olaEnabled === true;
    draftVersion.value = row.lock_version;
    confirmed.value = false;
    localMessage.value = 'draft_restored';
  } catch {
    localMessage.value = 'draft_error';
  }
}
async function readVersions() {
  if (!props.record.id) return;
  try {
    versions.value = (
      await Drafts.versions(
        props.context.account_id,
        props.unitId,
        props.record.id
      )
    ).versions;
  } catch {
    localMessage.value = 'unavailable';
  }
}
readVersions();
</script>

<template>
  <AutomationDialog
    open
    :title="tr('ola.title')"
    :steps="steps"
    :step="step"
    :max-step="reached"
    :busy="locked"
    :dirty="dirty"
    @update:step="step = $event"
    @close="emit('cancel')"
  >
    <div class="grid min-w-0 gap-5 lg:grid-cols-[minmax(0,1fr)_17rem]">
      <section class="min-w-0 space-y-4">
        <div
          v-if="step === 0"
          class="grid gap-4 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
        >
          <h3 class="font-semibold">{{ steps[0] }}</h3>
          <label class="grid gap-1 text-sm">
            {{ tr('name') }}
            <input
              :value="modelValue.name"
              :class="formClass"
              maxlength="255"
              :disabled="locked"
              @input="update('name', $event.target.value)"
            />
          </label>
          <label class="grid gap-1 text-sm">
            {{ tr('code') }}
            <input
              :value="modelValue.code"
              :class="formClass"
              maxlength="80"
              :disabled="!!record.id || locked"
              @input="update('code', $event.target.value)"
            />
          </label>
          <LookupSelect
            :model-value="modelValue.team_id || ''"
            resource="teams"
            :unit-id="unitId"
            :disabled="locked"
            :label="tr('ola.team')"
            @update:model-value="update('team_id', $event || null)"
          />
          <label class="flex gap-2 text-sm">
            <input
              type="checkbox"
              :checked="modelValue.active"
              :disabled="locked"
              @change="update('active', $event.target.checked)"
            />
            {{ tr('active') }}
          </label>
          <p class="text-xs text-n-slate-11">{{ tr('ola.team_stable') }}</p>
        </div>
        <div
          v-else-if="step === 1"
          class="grid gap-4"
        >
          <h3 class="font-semibold">{{ steps[1] }}</h3>
          <div class="grid gap-3 md:grid-cols-2">
            <label
              v-for="mode in DISTRIBUTION_MODES"
              :key="mode"
              class="flex items-center gap-3 rounded-xl border p-4 text-sm"
              :class="
                modelValue.distribution_mode === mode
                  ? 'border-n-blue-7 bg-n-blue-2'
                  : 'border-n-weak bg-n-solid-1'
              "
            >
              <input
                type="radio"
                name="ola-distribution"
                :checked="modelValue.distribution_mode === mode"
                :disabled="locked"
                @change="update('distribution_mode', mode)"
              />
              {{ tr(`ola.${mode}`) }}
            </label>
          </div>
          <label class="grid gap-1 text-sm">
            {{ tr('ola.skills') }}
            <input
              v-model="skillsText"
              :class="formClass"
              :disabled="locked"
            />
          </label>
          <p class="rounded-xl border border-n-teal-5 bg-n-teal-2 p-4 text-sm">
            {{ tr('ola.distribution_help') }}
          </p>
          <a
            class="rounded-lg border px-3 py-2 text-sm text-n-blue-11 underline"
            :href="`/app/accounts/${context.account_id}/service-desk/assignees?unit_id=${unitId}`"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{ tr('ola.configure_capacity') }}
          </a>
        </div>
        <div
          v-else-if="step === 2"
          class="grid gap-4 rounded-xl border border-n-violet-5 bg-n-violet-2 p-4"
        >
          <h3 class="font-semibold">{{ steps[2] }}</h3>
          <label class="flex gap-2 text-sm">
            <input
              v-model="olaEnabled"
              type="checkbox"
              :disabled="locked"
            />
            {{ tr('ola.enabled') }}
          </label>
          <div
            v-if="olaEnabled"
            class="grid gap-4"
          >
            <label
              v-for="kind in ['first_response', 'update', 'resolution']"
              :key="kind"
              class="grid gap-1 text-sm"
            >
              {{ tr(`ola.metric_${kind}`) }}
              <input
                type="number"
                min="1"
                max="525600"
                :value="
                  modelValue.ola_targets?.[kind]
                    ? modelValue.ola_targets[kind] / 60
                    : ''
                "
                :class="formClass"
                :disabled="locked"
                @input="
                  update('ola_targets', {
                    ...(modelValue.ola_targets || {}),
                    [kind]: Number($event.target.value) * 60,
                  })
                "
              />
            </label>
            <label class="grid gap-1 text-sm">
              {{ tr('ola.basis') }}
              <select
                :value="modelValue.ola_time_basis"
                :class="formClass"
                :disabled="locked"
                @change="update('ola_time_basis', $event.target.value)"
              >
                <option value="calendar">{{ tr('ola.calendar') }}</option>
                <option value="business">{{ tr('ola.business') }}</option>
              </select>
            </label>
            <CalendarFields
              v-if="modelValue.ola_time_basis === 'business'"
              :model-value="modelValue.ola_calendar || {}"
              :disabled="locked"
              @update:model-value="update('ola_calendar', $event)"
            />
            <label class="flex gap-2 text-sm">
              <input
                type="checkbox"
                :checked="modelValue.ola_pause_waiting"
                :disabled="locked"
                @change="update('ola_pause_waiting', $event.target.checked)"
              />
              {{ tr('ola.pause') }}
            </label>
          </div>
          <p class="text-xs text-n-slate-11">{{ tr('ola.budget_hint') }}</p>
          <p
            v-if="modelValue.ola_time_basis === 'business'"
            class="rounded-lg bg-n-amber-2 p-3 text-xs"
          >
            {{ tr('ola.business_hint') }}
          </p>
        </div>
        <div
          v-else-if="step === 3"
          class="grid gap-4"
        >
          <h3 class="font-semibold">{{ steps[3] }}</h3>
          <p class="text-sm text-n-slate-11">{{ tr('ola.threshold_help') }}</p>
          <label class="flex gap-2 text-sm">
            <input
              type="checkbox"
              :checked="policy.enabled"
              :disabled="locked || !policy.thresholds?.length || !olaEnabled"
              @change="
                setPolicy({
                  ...policy,
                  enabled: $event.target.checked,
                  automatic: false,
                })
              "
            />
            {{ tr('ola.escalation_enabled') }}
          </label>
          <article
            v-for="(row, index) in policy.thresholds || []"
            :key="index"
            class="grid gap-3 rounded-xl border border-n-weak p-4"
            :class="index % 2 ? 'bg-n-amber-2' : 'bg-n-blue-2'"
          >
            <label class="grid gap-1 text-sm">
              {{ tr('ola.threshold_percent') }}
              <input
                :value="row.percent"
                :disabled="locked"
                type="number"
                min="1"
                max="100"
                :class="formClass"
                @input="
                  changeThreshold(index, 'percent', Number($event.target.value))
                "
              />
            </label>
            <LookupSelect
              :model-value="row.queue_id || ''"
              resource="queues"
              :unit-id="unitId"
              :disabled="locked"
              :label="tr('ola.target_queue')"
              @update:model-value="
                changeThreshold(index, 'queue_id', $event || null)
              "
            />
            <LookupSelect
              :model-value="row.team_id || ''"
              resource="teams"
              :unit-id="unitId"
              :disabled="locked || !row.queue_id"
              :label="tr('ola.target_team')"
              @update:model-value="
                changeThreshold(index, 'team_id', $event || null)
              "
            />
            <div
              class="grid gap-2 rounded-xl border border-n-violet-5 bg-n-violet-2 p-3"
            >
              <LookupSelect
                v-model="alertRecipient"
                resource="assignees"
                :unit-id="unitId"
                :disabled="locked"
                :label="tr('monitoring.recipient')"
              />
              <button
                :class="buttonClass"
                :disabled="
                  locked ||
                  !alertRecipient ||
                  (row.notification_member_ids || []).includes(alertRecipient)
                "
                @click="
                  setAlert(
                    index,
                    [...(row.notification_member_ids || []), alertRecipient],
                    row.notification_channels || []
                  )
                "
              >
                {{ tr('monitoring.add_recipient') }}
              </button>
              <button
                v-for="id in row.notification_member_ids || []"
                :key="id"
                :class="buttonClass"
                :disabled="locked"
                @click="
                  setAlert(
                    index,
                    row.notification_member_ids.filter(value => value !== id),
                    row.notification_channels || []
                  )
                "
              >
                #{{ id }} · {{ tr('ola.remove') }}
              </button>
              <label
                v-for="channel in ['in_app', 'email']"
                :key="channel"
                class="flex gap-2 text-sm"
              >
                <input
                  type="checkbox"
                  :checked="(row.notification_channels || []).includes(channel)"
                  :disabled="locked || !row.notification_member_ids?.length"
                  @change="
                    setAlert(
                      index,
                      row.notification_member_ids,
                      $event.target.checked
                        ? [...(row.notification_channels || []), channel]
                        : (row.notification_channels || []).filter(
                            value => value !== channel
                          )
                    )
                  "
                />
                {{ tr(`monitoring.${channel}`) }}
              </label>
              <p class="text-xs">{{ tr('monitoring.recipient_help') }}</p>
            </div>
            <button
              :class="buttonClass"
              :disabled="locked"
              @click="removeThreshold(index)"
            >
              {{ tr('ola.remove') }}
            </button>
          </article>
          <button
            :class="buttonClass"
            :disabled="locked || !olaEnabled"
            @click="addThreshold"
          >
            {{ tr('ola.add_threshold') }}
          </button>
          <ClockAutomationFields
            :model-value="policy"
            :unit-id="unitId"
            :disabled="locked || !olaEnabled"
            @update:model-value="setPolicy"
          />
        </div>
        <div
          v-else-if="step === 4"
          class="grid gap-4"
        >
          <h3 class="font-semibold">{{ steps[4] }}</h3>
          <OlaMonitoring
            v-if="record.id"
            :account-id="context.account_id"
            :unit-id="unitId"
            :queue-id="record.id"
          />
          <p
            v-else
            class="rounded-xl bg-n-blue-2 p-4 text-sm"
          >
            {{ tr('ola.save_first') }}
          </p>
        </div>
        <div
          v-else
          class="grid gap-4"
        >
          <h3 class="font-semibold">{{ steps[5] }}</h3>
          <p class="rounded-xl bg-n-teal-2 p-4 text-sm">
            {{ tr('ola.review_hint') }}
          </p>
          <div class="grid gap-3 sm:grid-cols-2">
            <article
              v-for="(label, index) in steps.slice(0, 4)"
              :key="label"
              class="rounded-xl border border-n-weak p-4"
              :class="index % 2 ? 'bg-n-violet-2' : 'bg-n-blue-2'"
            >
              <div class="flex items-center justify-between gap-2">
                <h4 class="text-sm font-semibold">{{ label }}</h4>
                <button
                  class="text-xs text-n-blue-11"
                  :disabled="locked"
                  @click="step = index"
                >
                  {{ tr('edit') }}
                </button>
              </div>
              <p
                v-if="index === 0"
                class="mt-3 text-sm"
              >
                {{ modelValue.name }} / {{ modelValue.code }}
              </p>
              <p
                v-else-if="index === 1"
                class="mt-3 text-sm"
              >
                {{ tr(`ola.${modelValue.distribution_mode}`) }}
              </p>
              <div
                v-else-if="index === 2"
                class="mt-3 space-y-2 text-sm"
              >
                <p
                  v-for="kind in ['first_response', 'update', 'resolution']"
                  :key="kind"
                >
                  {{ tr(`ola.metric_${kind}`) }}:
                  {{
                    olaEnabled
                      ? `${(modelValue.ola_targets?.[kind] || 0) / 60} min`
                      : tr('inactive')
                  }}
                </p>
              </div>
              <p
                v-else
                class="mt-3 text-sm"
              >
                {{ policy.enabled ? tr('active') : tr('inactive') }} /
                {{ policy.thresholds?.length || 0 }}
              </p>
            </article>
          </div>
          <label class="flex gap-2 rounded-xl border border-n-weak p-4 text-sm">
            <input
              v-model="confirmed"
              type="checkbox"
              :disabled="locked"
            />
            {{ tr('confirm') }}
          </label>
        </div>
        <p
          v-if="localMessage"
          role="status"
          class="rounded-lg bg-n-amber-2 p-3 text-sm"
        >
          {{ tr(localMessage) }}
        </p>
        <p
          v-if="feedback !== 'idle'"
          role="status"
          class="rounded-lg bg-n-blue-2 p-3 text-sm"
        >
          {{ t(`JRC_SERVICE_DESK.ADMIN.feedback.${feedback}`) }}
        </p>
      </section>
      <aside class="min-w-0 space-y-4">
        <article class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4">
          <h3 class="font-semibold">{{ tr('scope') }}</h3>
          <p class="mt-3 text-sm">
            {{ context.units.find(row => row.id === unitId)?.name }}
          </p>
          <p class="mt-2 text-sm">{{ modelValue.name || tr('new') }}</p>
        </article>
        <article
          class="rounded-xl border border-n-violet-5 bg-n-violet-2 p-4 text-sm"
        >
          <strong>{{ tr('ola.subtitle') }}</strong>
          <p class="mt-3">{{ tr('ola.distribution_help') }}</p>
        </article>
        <article class="rounded-xl border border-n-weak p-4 text-xs">
          <strong>{{ tr('ola.revision') }}</strong>
          <p class="mt-2 break-all">
            {{ record.revision || tr('ola.new_revision') }}
          </p>
          <div
            v-for="item in versions"
            :key="item.id"
            class="mt-3 border-t border-n-weak pt-2"
          >
            <strong>
              {{ tr('version_label', { version: item.version }) }}
            </strong>
            <p>{{ item.published_at }}</p>
            <p class="break-all">{{ item.digest }}</p>
          </div>
        </article>
      </aside>
    </div>
    <template #footer>
      <div class="flex flex-wrap gap-2">
        <button
          :class="buttonClass"
          :disabled="locked"
          @click="saveLocal"
        >
          {{ tr('save_private_draft') }}
        </button>
        <button
          v-if="step === 0"
          :class="buttonClass"
          :disabled="locked"
          @click="restoreLocal"
        >
          {{ tr('restore_draft') }}
        </button>
      </div>
      <div class="flex gap-2">
        <button
          :class="buttonClass"
          :disabled="locked || !step"
          @click="step -= 1"
        >
          {{ tr('back') }}
        </button>
        <button
          v-if="step < 5"
          :class="primaryClass"
          :disabled="locked"
          @click="next"
        >
          {{ tr('next') }}
        </button>
        <button
          v-else
          :class="primaryClass"
          :disabled="saving || (!pending && (!confirmed || !validate()))"
          @click="pending ? emit('save') : save()"
        >
          {{ pending ? t('JRC_SERVICE_DESK.ADMIN.retry_same') : tr('publish') }}
        </button>
      </div>
    </template>
  </AutomationDialog>
</template>
