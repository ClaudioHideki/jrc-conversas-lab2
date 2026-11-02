<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import LookupSelect from '../components/LookupSelect.vue';
import CalendarFields from './CalendarFields.vue';
const props = defineProps({
  modelValue: { type: Object, required: true },
  unitId: { type: String, required: true },
  section: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const tr = key =>
  t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.notification_controls.${key}`);
const field = 'w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm';
const button =
  'rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm disabled:opacity-50';
const contacts = ref({});
const members = ref({});
const resources = {
  ticket_type_id: 'ticket_types',
  service_id: 'services',
  priority_id: 'priorities',
  queue_id: 'queues',
  status_id: 'statuses',
  category_id: 'categories',
  origin_channel: null,
};
function update(key, value) {
  emit('update:modelValue', { ...props.modelValue, [key]: value });
}
function condition(index, key, value) {
  update('conditions', {
    ...props.modelValue.conditions,
    items: props.modelValue.conditions.items.map((row, i) =>
      i === index ? { ...row, [key]: value } : row
    ),
  });
}
function addCondition() {
  update('conditions', {
    ...props.modelValue.conditions,
    items: [
      ...props.modelValue.conditions.items,
      { field: 'priority_id', operator: 'eq', value: '' },
    ],
  });
}
function removeCondition(index) {
  update('conditions', {
    ...props.modelValue.conditions,
    items: props.modelValue.conditions.items.filter((_, i) => i !== index),
  });
}
function selectRecipient(key, id, row) {
  if (!id) return;
  const names = key === 'additional_contact_ids' ? contacts : members;
  if (row) names.value[id] = row.name;
  update(key, [...new Set([...props.modelValue[key], String(id)])]);
}
function toggleChannel(channel, checked) {
  const order = checked
    ? [...new Set([...props.modelValue.channel_order, channel])]
    : props.modelValue.channel_order.filter(key => key !== channel);
  if (order.length) update('channel_order', order);
}
</script>

<template>
  <section class="grid min-w-0 gap-4">
    <template v-if="section === 'conditions'">
      <label class="grid gap-1 text-sm">
        {{ tr('match') }}
        <select
          :class="field"
          :value="modelValue.conditions.operator"
          :disabled="disabled"
          @change="
            update('conditions', {
              ...modelValue.conditions,
              operator: $event.target.value,
            })
          "
        >
          <option value="all">{{ tr('all_conditions') }}</option>
          <option value="any">{{ tr('any_condition') }}</option>
        </select>
      </label>
      <article
        v-for="(row, index) in modelValue.conditions.items"
        :key="index"
        class="grid gap-3 rounded-xl border border-n-violet-5 bg-n-violet-2 p-3"
      >
        <select
          :class="field"
          :value="row.field"
          :disabled="disabled"
          :aria-label="tr('condition_field')"
          @change="
            condition(index, 'field', $event.target.value);
            condition(index, 'value', '');
          "
        >
          <option
            v-for="(resource, key) in resources"
            :key="key"
            :value="key"
          >
            {{ tr(key) }}
          </option>
        </select>
        <select
          :class="field"
          :value="row.operator"
          :disabled="disabled"
          :aria-label="tr('comparison')"
          @change="condition(index, 'operator', $event.target.value)"
        >
          <option value="eq">{{ tr('equals') }}</option>
          <option value="neq">{{ tr('differs') }}</option>
        </select>
        <input
          v-if="row.field === 'origin_channel'"
          :value="row.value"
          :class="field"
          maxlength="80"
          :aria-label="tr('origin_channel')"
          :placeholder="tr('origin_example')"
          :disabled="disabled"
          @input="condition(index, 'value', $event.target.value)"
        />
        <LookupSelect
          v-else
          :model-value="String(row.value)"
          :resource="resources[row.field]"
          :unit-id="unitId"
          :disabled="disabled"
          :label="tr('condition_value')"
          @update:model-value="condition(index, 'value', $event)"
        />
        <button
          :class="button"
          :disabled="disabled"
          @click="removeCondition(index)"
        >
          {{ tr('remove') }}
        </button>
      </article>
      <button
        :class="button"
        :disabled="disabled || modelValue.conditions.items.length >= 20"
        @click="addCondition"
      >
        {{ tr('add_condition') }}
      </button>
      <p class="text-xs text-n-slate-11">{{ tr('event_snapshot') }}</p>
    </template>
    <template v-else-if="section === 'channels'">
      <fieldset class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4">
        <legend class="text-sm font-semibold">{{ tr('channels') }}</legend>
        <label
          v-for="key in ['whatsapp', 'email']"
          :key="key"
          class="m-2 inline-flex items-center gap-2 text-sm"
        >
          <input
            type="checkbox"
            :checked="modelValue.channel_order.includes(key)"
            :disabled="disabled"
            @change="toggleChannel(key, $event.target.checked)"
          />
          {{ tr(key) }}
        </label>
        <label class="mt-3 grid gap-1 text-sm">
          {{ tr('strategy') }}
          <select
            :class="field"
            :value="modelValue.multichannel_mode"
            :disabled="disabled"
            @change="update('multichannel_mode', $event.target.value)"
          >
            <option value="first_available">{{ tr('first_available') }}</option>
            <option value="all_explicit">{{ tr('all_explicit') }}</option>
          </select>
        </label>
        <button
          v-if="modelValue.channel_order.length > 1"
          :class="button"
          :disabled="disabled"
          @click="
            update('channel_order', [...modelValue.channel_order].reverse())
          "
        >
          {{ tr('reverse_order') }}:
          {{ modelValue.channel_order.map(key => tr(key)).join(' → ') }}
        </button>
        <p class="mt-3 text-xs">{{ tr('strategy_help') }}</p>
      </fieldset>
    </template>
    <template v-else>
      <article
        class="grid gap-3 rounded-xl border border-n-teal-5 bg-n-teal-2 p-4"
      >
        <h3 class="font-semibold">{{ tr('recipients') }}</h3>
        <p class="text-xs">{{ tr('recipient_help') }}</p>
        <label class="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            :checked="modelValue.copy_assignee === true"
            :disabled="disabled"
            @change="update('copy_assignee', $event.target.checked)"
          />
          {{ tr('copy_assignee') }}
        </label>
        <LookupSelect
          model-value=""
          resource="requesters"
          :unit-id="unitId"
          :disabled="disabled || modelValue.additional_contact_ids.length >= 20"
          :label="tr('additional_contact')"
          @selected="
            selectRecipient('additional_contact_ids', $event?.id, $event)
          "
        />
        <div
          v-for="id in modelValue.additional_contact_ids"
          :key="id"
          class="flex items-center justify-between gap-2 text-sm"
        >
          <span>{{ contacts[id] || `#${id}` }}</span>
          <button
            :class="button"
            :disabled="disabled"
            @click="
              update(
                'additional_contact_ids',
                modelValue.additional_contact_ids.filter(
                  value => String(value) !== String(id)
                )
              )
            "
          >
            {{ tr('remove') }}
          </button>
        </div>
        <LookupSelect
          model-value=""
          resource="assignees"
          :unit-id="unitId"
          :disabled="
            disabled || modelValue.internal_copy_member_ids.length >= 20
          "
          :label="tr('internal_copy')"
          @selected="
            selectRecipient('internal_copy_member_ids', $event?.id, $event)
          "
        />
        <div
          v-for="id in modelValue.internal_copy_member_ids"
          :key="id"
          class="flex items-center justify-between gap-2 text-sm"
        >
          <span>{{ members[id] || `#${id}` }}</span>
          <button
            :class="button"
            :disabled="disabled"
            @click="
              update(
                'internal_copy_member_ids',
                modelValue.internal_copy_member_ids.filter(
                  value => String(value) !== String(id)
                )
              )
            "
          >
            {{ tr('remove') }}
          </button>
        </div>
      </article>
      <article
        class="grid gap-3 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4"
      >
        <label class="flex gap-2 text-sm">
          <input
            type="checkbox"
            :checked="modelValue.window.enabled"
            :disabled="disabled"
            @change="
              update('window', {
                ...modelValue.window,
                enabled: $event.target.checked,
              })
            "
          />
          {{ tr('send_window') }}
        </label>
        <CalendarFields
          v-if="modelValue.window.enabled"
          :model-value="modelValue.window"
          :disabled="disabled"
          @update:model-value="update('window', { ...$event, enabled: true })"
        />
        <label class="grid gap-1 text-sm">
          {{ tr('outside_window') }}
          <select
            :class="field"
            :value="modelValue.outside_window"
            :disabled="disabled"
            @change="update('outside_window', $event.target.value)"
          >
            <option value="defer">{{ tr('defer') }}</option>
            <option value="skip">{{ tr('skip') }}</option>
          </select>
        </label>
      </article>
      <article
        class="grid gap-3 rounded-xl border border-n-amber-5 bg-n-amber-2 p-4"
      >
        <label class="grid gap-1 text-sm">
          {{ tr('attempts') }}
          <input
            type="number"
            min="1"
            max="3"
            :value="modelValue.max_attempts"
            :class="field"
            :disabled="disabled"
            @input="update('max_attempts', Number($event.target.value))"
          />
        </label>
        <label class="grid gap-1 text-sm">
          {{ tr('backoff') }}
          <input
            type="number"
            min="1"
            max="1440"
            :value="modelValue.backoff_minutes"
            :class="field"
            :disabled="disabled"
            @input="update('backoff_minutes', Number($event.target.value))"
          />
        </label>
        <p class="text-xs">{{ tr('retry_help') }}</p>
      </article>
    </template>
  </section>
</template>
