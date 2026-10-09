<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LookupSelect from './LookupSelect.vue';
import StatusSetEditor from './StatusSetEditor.vue';
import {
  ACTIONS,
  readLifecycleDraft,
  blankLifecycleDraft,
  blankTransition,
  patchLifecycleDraft,
  explicitInteger,
  clockKinds,
  lifecycleDraftIssues,
  simulateLifecycleDraft,
} from '../helpers/lifecycleDesigner.js';
const props = defineProps({
  modelValue: { type: String, default: '' },
  unitId: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const d = computed(() => readLifecycleDraft(props.modelValue));
const clocks = computed(() => (d.value ? clockKinds(d.value) : []));
const issues = computed(() => lifecycleDraftIssues(props.modelValue));
const localError = ref(false);
const checked = ref(false);
const simulatorState = ref('');
const simulation = computed(() => {
  try {
    return simulateLifecycleDraft(props.modelValue, simulatorState.value);
  } catch {
    return [];
  }
});
watch(
  () => props.unitId,
  () => {
    localError.value = false;
    checked.value = false;
    simulatorState.value = '';
  }
);
const root = 'JRC_SERVICE_DESK.EXPERIENCE.designer';
function update(path, value) {
  if (props.disabled) return;
  try {
    emit(
      'update:modelValue',
      patchLifecycleDraft(props.modelValue, path, value)
    );
    localError.value = false;
  } catch {
    localError.value = true;
  }
}
function number(path, value) {
  try {
    update(path, explicitInteger(value));
  } catch {
    localError.value = true;
  }
}
function add(kind) {
  if (!d.value || props.disabled) return;
  const rows = d.value[kind];
  if (rows.length >= 100) return;
  const row =
    kind === 'transitions'
      ? blankTransition(d.value)
      : { code: '', name: '', status_ids: [], clocks: [] };
  update([kind], [...rows, row]);
}
function remove(kind, index) {
  if (d.value)
    update(
      [kind],
      d.value[kind].filter((_, i) => i !== index)
    );
}
function toggle(path, list, value, enabled) {
  update(
    path,
    enabled
      ? [...new Set([...list, value])]
      : list.filter(item => item !== value)
  );
}
function start() {
  if (!props.disabled && !props.modelValue.trim())
    emit('update:modelValue', blankLifecycleDraft());
}
</script>

<template>
  <div class="grid gap-4" data-testid="lifecycle-visual-editor">
    <p class="text-sm text-n-slate-11">{{ t(`${root}.notice`) }}</p>
    <Button
      v-if="!modelValue.trim()"
      type="button"
      variant="outline"
      :disabled="disabled"
      :label="t(`${root}.start`)"
      @click="start"
    />
    <p v-else-if="!d" role="alert" class="text-sm text-n-ruby-11">
      {{ t(`${root}.advanced_required`) }}
    </p>
    <template v-if="d">
      <fieldset
        class="rounded-xl border border-n-weak p-4 grid gap-3"
        :disabled="disabled"
      >
        <legend class="font-semibold text-sm">
          {{ t(`${root}.sla_mode`) }}
        </legend>
        <select
          class="rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
          :value="d.sla.mode"
          :aria-label="t(`${root}.sla_mode`)"
          @change="update(['sla', 'mode'], $event.target.value)"
        >
          <option value="">{{ t('JRC_SERVICE_DESK.COMMON.select') }}</option>
          <option
            v-for="value in ['calendar_snapshot', 'not_applicable']"
            :key="value"
            :value="value"
          >
            {{ t(`${root}.values.${value}`) }}
          </option>
        </select>
      </fieldset>
      <section class="grid gap-3">
        <div class="flex flex-wrap justify-between gap-2">
          <h4 class="font-semibold">{{ t(`${root}.transitions`) }}</h4>
          <Button
            type="button"
            size="xs"
            variant="outline"
            :disabled="disabled || d.transitions.length >= 100"
            :label="t(`${root}.add_transition`)"
            @click="add('transitions')"
          />
        </div>
        <article
          v-for="(row, index) in d.transitions"
          :key="index"
          class="grid gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-4"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h5 class="text-sm font-semibold">
              {{ t(`${root}.step`, { number: index + 1 }) }}
            </h5>
            <Button
              type="button"
              size="xs"
              variant="ghost"
              :disabled="disabled"
              :label="t('JRC_SERVICE_DESK.EXPERIENCE.remove')"
              @click="remove('transitions', index)"
            />
          </div>
          <div class="grid gap-3 md:grid-cols-2">
            <label class="grid gap-1 text-sm"
              >{{ t(`${root}.key`)
              }}<input
                class="rounded border border-n-weak bg-n-solid-1 p-2"
                :disabled="disabled"
                :value="row.key"
                maxlength="80"
                @input="
                  update(['transitions', index, 'key'], $event.target.value)
                "
            /></label>
            <label class="grid gap-1 text-sm"
              >{{ t(`${root}.action`)
              }}<select
                class="rounded border border-n-weak bg-n-solid-1 p-2"
                :disabled="disabled"
                :value="row.action"
                @change="
                  update(['transitions', index, 'action'], $event.target.value)
                "
              >
                <option value="">
                  {{ t('JRC_SERVICE_DESK.COMMON.select') }}
                </option>
                <option v-for="action in ACTIONS" :key="action" :value="action">
                  {{ t(`${root}.actions.${action}`) }}
                </option>
              </select></label
            >
            <StatusSetEditor
              :model-value="row.from_status_ids || []"
              :unit-id="unitId"
              :disabled="disabled"
              :label="t(`${root}.from`)"
              @update:model-value="
                update(['transitions', index, 'from_status_ids'], $event)
              "
            />
            <LookupSelect
              :model-value="String(row.to_status_id || '')"
              resource="statuses"
              :unit-id="unitId"
              :disabled="disabled"
              :label="t(`${root}.to`)"
              @update:model-value="
                number(['transitions', index, 'to_status_id'], $event)
              "
            />
          </div>
          <fieldset
            v-if="row.requirements"
            :disabled="disabled"
            class="flex flex-wrap gap-3"
          >
            <legend class="text-xs text-n-slate-11 mb-2">
              {{ t(`${root}.requirements`) }}
            </legend>
            <label
              v-for="field in [
                'note',
                'solution',
                'evidence',
                'classification',
              ]"
              :key="field"
              class="text-sm flex items-center gap-2"
              ><input
                type="checkbox"
                :checked="row.requirements[field]"
                @change="
                  update(
                    ['transitions', index, 'requirements', field],
                    $event.target.checked
                  )
                "
              />{{ t(`${root}.require.${field}`) }}</label
            >
          </fieldset>
          <p
            v-if="Object.keys(row.requirements?.fields || {}).length"
            class="text-xs text-n-slate-11"
          >
            {{
              t(`${root}.custom_fields_preserved`, {
                count: Object.keys(row.requirements.fields).length,
              })
            }}
          </p>
          <div v-if="row.clocks" class="grid gap-3 sm:grid-cols-3">
            <label
              v-for="clock in clocks"
              :key="clock"
              class="grid gap-1 text-sm"
              >{{ t(`JRC_SERVICE_DESK.COMPLETION.clocks.${clock}`)
              }}<select
                class="rounded border border-n-weak bg-n-solid-1 p-2"
                :disabled="disabled"
                :value="row.clocks[clock]"
                @change="
                  update(
                    ['transitions', index, 'clocks', clock],
                    $event.target.value
                  )
                "
              >
                <option
                  v-for="effect in ['keep', 'stop', 'complete'].filter(
                    value => clock !== 'first_response' || value !== 'complete'
                  )"
                  :key="effect"
                  :value="effect"
                >
                  {{ t(`${root}.effects.${effect}`) }}
                </option>
              </select></label
            >
          </div>
          <label class="text-sm"
            ><input
              type="checkbox"
              :disabled="disabled"
              :checked="row.end_pause"
              @change="
                update(
                  ['transitions', index, 'end_pause'],
                  $event.target.checked
                )
              "
            />
            {{ t(`${root}.end_pause`) }}</label
          >
        </article>
      </section>
      <section class="grid gap-3">
        <div class="flex flex-wrap justify-between gap-2">
          <h4 class="font-semibold">{{ t(`${root}.pauses`) }}</h4>
          <Button
            type="button"
            size="xs"
            variant="outline"
            :disabled="disabled || d.pause_reasons.length >= 100"
            :label="t(`${root}.add_pause`)"
            @click="add('pause_reasons')"
          />
        </div>
        <article
          v-for="(row, index) in d.pause_reasons"
          :key="index"
          class="grid gap-3 rounded-xl border border-n-weak p-4"
        >
          <div class="grid gap-3 sm:grid-cols-2">
            <label
              v-for="field in ['code', 'name']"
              :key="field"
              class="grid gap-1 text-sm"
              >{{ t(`JRC_SERVICE_DESK.FIELDS.${field}`)
              }}<input
                class="rounded border border-n-weak bg-n-solid-1 p-2"
                :value="row[field]"
                :disabled="disabled"
                :maxlength="field === 'code' ? 80 : 255"
                @input="
                  update(['pause_reasons', index, field], $event.target.value)
                "
            /></label>
          </div>
          <StatusSetEditor
            :model-value="row.status_ids || []"
            :unit-id="unitId"
            :disabled="disabled"
            :label="t(`${root}.from`)"
            @update:model-value="
              update(['pause_reasons', index, 'status_ids'], $event)
            "
          />
          <fieldset class="flex flex-wrap gap-3" :disabled="disabled">
            <legend class="text-xs text-n-slate-11 mb-2">
              {{ t(`${root}.paused_clocks`) }}
            </legend>
            <label
              v-for="clock in clocks"
              :key="clock"
              class="inline-flex items-center gap-2 text-sm"
              ><input
                type="checkbox"
                :checked="row.clocks?.includes(clock)"
                @change="
                  toggle(
                    ['pause_reasons', index, 'clocks'],
                    row.clocks || [],
                    clock,
                    $event.target.checked
                  )
                "
              />
              {{ t(`JRC_SERVICE_DESK.COMPLETION.clocks.${clock}`) }}</label
            >
          </fieldset>
          <Button
            type="button"
            size="xs"
            variant="ghost"
            :disabled="disabled"
            :label="t('JRC_SERVICE_DESK.EXPERIENCE.remove')"
            @click="remove('pause_reasons', index)"
          />
        </article>
      </section>
      <fieldset
        class="grid gap-3 rounded-xl border border-n-weak p-4"
        :disabled="disabled"
      >
        <legend class="font-semibold text-sm">
          {{ t(`${root}.reopening`) }}
        </legend>
        <label class="text-sm"
          ><input
            type="checkbox"
            :checked="d.reopen.allowed"
            @change="update(['reopen', 'allowed'], $event.target.checked)"
          />
          {{ t(`${root}.allow_reopen`) }}</label
        >
        <div v-if="d.reopen.allowed" class="grid gap-3 sm:grid-cols-2">
          <label class="grid gap-1 text-sm"
            >{{ t(`${root}.window_seconds`)
            }}<input
              class="rounded border border-n-weak bg-n-solid-1 p-2"
              type="number"
              min="1"
              step="1"
              :value="d.reopen.window_seconds"
              @input="
                number(['reopen', 'window_seconds'], $event.target.value)
              "
          /></label>
          <label
            v-for="(values, field) in {
              anchor_action: ['resolve', 'close', 'cancel'],
              expired: ['deny', 'require_new_ticket'],
              sla_cycle: ['continue_cycle', 'new_cycle'],
              inactive_time: ['count', 'exclude'],
              new_cycle_snapshot: ['same_snapshot', 'latest_snapshot'],
            }"
            :key="field"
            class="grid gap-1 text-sm"
            >{{ t(`${root}.reopen_fields.${field}`)
            }}<select
              class="rounded border border-n-weak bg-n-solid-1 p-2"
              :value="d.reopen[field] || ''"
              @change="update(['reopen', field], $event.target.value)"
            >
              <option value="">
                {{ t('JRC_SERVICE_DESK.COMMON.select') }}
              </option>
              <option v-for="value in values" :key="value" :value="value">
                {{ t(`${root}.values.${value}`) }}
              </option>
            </select></label
          >
          <fieldset class="flex flex-wrap gap-2 sm:col-span-2">
            <legend class="text-xs text-n-slate-11 mb-2">
              {{ t(`${root}.resumed_clocks`) }}
            </legend>
            <label
              v-for="clock in clocks"
              :key="clock"
              class="inline-flex items-center gap-2 text-sm"
              ><input
                type="checkbox"
                :checked="d.reopen.resume_clocks?.includes(clock)"
                @change="
                  toggle(
                    ['reopen', 'resume_clocks'],
                    d.reopen.resume_clocks || [],
                    clock,
                    $event.target.checked
                  )
                "
              />
              {{ t(`JRC_SERVICE_DESK.COMPLETION.clocks.${clock}`) }}</label
            >
          </fieldset>
        </div>
      </fieldset>
      <section class="grid gap-3 rounded-xl border border-n-weak p-4">
        <h4 class="font-semibold text-sm">{{ t(`${root}.simulation`) }}</h4>
        <p class="text-xs text-n-slate-11">
          {{ t(`${root}.simulation_notice`) }}
        </p>
        <LookupSelect
          v-model="simulatorState"
          resource="statuses"
          :unit-id="unitId"
          :disabled="disabled"
          :label="t(`${root}.from`)"
        />
        <Button
          type="button"
          size="sm"
          variant="outline"
          :label="t(`${root}.validate`)"
          :disabled="disabled"
          @click="checked = true"
        />
        <ul
          v-if="checked && issues.length"
          role="alert"
          class="text-sm text-n-ruby-11 list-disc ps-5"
        >
          <li v-for="issue in issues" :key="issue">
            {{ t(`${root}.issues.${issue}`) }}
          </li>
        </ul>
        <p v-else-if="checked" role="status" class="text-sm">
          {{ t(`${root}.locally_valid`) }}
        </p>
        <ul v-if="simulatorState" class="grid gap-2">
          <li v-for="row in simulation" :key="row.key" class="text-sm">
            {{ row.key }}: {{ t(`${root}.actions.${row.action}`) }}
            <Icon icon="i-lucide-arrow-right" class="inline-block size-3" />
            {{
              t('JRC_SERVICE_DESK.EXPERIENCE.reference', {
                id: row.to_status_id,
              })
            }}
          </li>
        </ul>
        <p
          v-if="simulatorState && !simulation.length"
          class="text-xs text-n-slate-11"
        >
          {{ t(`${root}.no_simulation`) }}
        </p>
      </section>
    </template>
    <p v-if="localError" role="alert" class="text-sm text-n-ruby-11">
      {{ t(`${root}.advanced_required`) }}
    </p>
  </div>
</template>
