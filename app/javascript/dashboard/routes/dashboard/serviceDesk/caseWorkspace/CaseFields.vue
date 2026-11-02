<script setup>
import { useI18n } from 'vue-i18n';
import Lookup from '../components/LookupSelect.vue';
import ServiceSelect from '../components/ServiceDefinitionSelect.vue';
const props = defineProps({
  modelValue: { type: Object, required: true },
  unitId: { type: String, required: true },
  kind: { type: String, required: true },
  disabled: Boolean,
  section: { type: String, default: 'main' },
  ownerName: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const tr = key => t(`JRC_SERVICE_DESK.CASES.${key}`);
const change = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
const detail = (key, value) =>
  change('details', { ...props.modelValue.details, [key]: value });
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="min-w-0 space-y-4 disabled:opacity-60"
  >
    <template v-if="section === 'main'">
      <label class="grid gap-2 text-sm">
        {{ tr('title') }}
        <input
          :value="modelValue.title"
          maxlength="255"
          required
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="change('title', $event.target.value)"
        />
      </label>
      <label class="grid gap-2 text-sm">
        {{ tr('description') }}
        <textarea
          :value="modelValue.description"
          rows="4"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="change('description', $event.target.value)"
        />
      </label>
      <div class="grid gap-4 sm:grid-cols-2">
        <label class="grid gap-2 text-sm">
          {{ tr(kind === 'problem' ? 'severity' : 'priority') }}
          <select
            :value="modelValue.severity"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
            @change="change('severity', $event.target.value)"
          >
            <option
              v-for="v in ['low', 'normal', 'high', 'critical']"
              :key="v"
              :value="v"
            >
              {{ tr(`severity_values.${v}`) }}
            </option>
          </select>
        </label>
        <Lookup
          :model-value="modelValue.owner_account_user_id"
          :current-name="ownerName"
          :label="tr('owner')"
          resource="assignees"
          :unit-id="unitId"
          :disabled="disabled"
          @update:model-value="change('owner_account_user_id', $event)"
        />
        <ServiceSelect
          :model-value="modelValue.service_id"
          :unit-id="unitId"
          :disabled="disabled"
          @update:model-value="change('service_id', $event)"
        />
        <Lookup
          :model-value="modelValue.category_id"
          :label="tr('category')"
          resource="categories"
          :unit-id="unitId"
          :disabled="disabled"
          @update:model-value="change('category_id', $event)"
        />
      </div>
    </template>
    <template v-if="section === 'impact'">
      <div class="rounded-xl bg-n-amber-2 p-4 text-sm text-n-amber-11">
        {{ tr('impact_help') }}
      </div>
      <label class="grid gap-2 text-sm">
        {{ tr('impact_level') }}
        <select
          :value="modelValue.details.impact_level"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @change="detail('impact_level', $event.target.value)"
        >
          <option value="">{{ tr('not_defined') }}</option>
          <option
            v-for="v in ['low', 'moderate', 'high', 'widespread']"
            :key="v"
            :value="v"
          >
            {{ tr(`impact_values.${v}`) }}
          </option>
        </select>
      </label>
      <label class="grid gap-2 text-sm">
        {{ tr('impact') }}
        <textarea
          :value="modelValue.impact"
          rows="5"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="change('impact', $event.target.value)"
        />
      </label>
      <label class="grid gap-2 text-sm">
        {{ tr('workaround') }}
        <textarea
          :value="modelValue.workaround"
          rows="4"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="change('workaround', $event.target.value)"
        />
      </label>
    </template>
    <template v-if="section === 'cause'">
      <div class="rounded-xl bg-n-violet-2 p-4 text-sm text-n-violet-11">
        {{ tr('cause_help') }}
      </div>
      <label class="grid gap-2 text-sm">
        {{ tr('hypothesis') }}
        <textarea
          :value="modelValue.details.hypothesis"
          rows="3"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="detail('hypothesis', $event.target.value)"
        />
      </label>
      <label class="grid gap-2 text-sm">
        {{ tr('cause') }}
        <textarea
          :value="modelValue.cause"
          rows="3"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="change('cause', $event.target.value)"
        />
      </label>
      <label class="grid gap-2 text-sm">
        {{ tr('evidence_summary') }}
        <textarea
          :value="modelValue.details.evidence_summary"
          rows="3"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="detail('evidence_summary', $event.target.value)"
        />
      </label>
      <label class="grid gap-2 text-sm">
        {{ tr('workaround') }}
        <textarea
          :value="modelValue.workaround"
          rows="3"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="change('workaround', $event.target.value)"
        />
      </label>
    </template>
    <template v-if="section === 'solution'">
      <div class="rounded-xl bg-n-teal-2 p-4 text-sm text-n-teal-11">
        {{ tr('solution_help') }}
      </div>
      <label class="grid gap-2 text-sm">
        {{ tr('resolution') }}
        <textarea
          :value="modelValue.resolution"
          rows="4"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="change('resolution', $event.target.value)"
        />
      </label>
      <label class="grid gap-2 text-sm">
        {{ tr('action_plan') }}
        <textarea
          :value="modelValue.details.action_plan"
          rows="5"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="detail('action_plan', $event.target.value)"
        />
      </label>
      <p class="text-xs text-n-slate-11">{{ tr('plan_help') }}</p>
      <label class="grid gap-2 text-sm">
        {{ tr('expected_result') }}
        <textarea
          :value="modelValue.details.expected_result"
          rows="3"
          maxlength="20000"
          class="rounded-lg border border-n-weak bg-n-solid-1 p-3"
          @input="detail('expected_result', $event.target.value)"
        />
      </label>
    </template>
  </fieldset>
</template>
