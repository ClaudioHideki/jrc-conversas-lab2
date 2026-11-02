<script setup>
import LookupSelect from '../components/LookupSelect.vue';
import ServiceSelect from '../components/ServiceDefinitionSelect.vue';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import ServiceFormPredicate from './ServiceFormPredicate.vue';
import { predicateResources, predicateFields } from './compositionForm';
import { useCompositionCopy, fieldClass, buttonClass } from './compositionCopy';
defineProps({
  unitId: { type: String, required: true },
  disabled: Boolean,
  options: { type: Object, default: () => ({ labels: [], inboxes: [] }) },
});
const model = defineModel({ type: Object, required: true });
const tr = useCompositionCopy();
function addGroup() {
  model.value.groups.push({ operator: 'all', items: [] });
}
function addItem(group) {
  group.items.push({ field: 'priority_id', operator: 'eq', value: null });
}
function changeField(item, value) {
  item.field = value;
  item.value = value === 'form_value' ? { key: '', value: null } : null;
}
function valueFor(item, value) {
  if (item.field.endsWith('_id')) item.value = value ? Number(value) : null;
  else item.value = value;
}
</script>

<template>
  <fieldset
    :disabled="disabled"
    class="grid gap-4"
  >
    <article class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-4 text-sm">
      <h3 class="font-semibold">{{ tr('conditions_title') }}</h3>
      <p class="mt-1 text-xs">{{ tr('conditions_help') }}</p>
    </article>
    <label class="grid gap-1 text-sm">
      {{ tr('between_groups') }}
      <select
        v-model="model.operator"
        :class="fieldClass"
      >
        <option value="all">{{ tr('all') }}</option>
        <option value="any">{{ tr('any') }}</option>
      </select>
    </label>
    <article
      v-for="(group, index) in model.groups"
      :key="index"
      class="grid gap-3 rounded-xl border border-n-violet-5 bg-n-violet-2 p-4"
    >
      <header class="flex flex-wrap items-center justify-between gap-3">
        <h4 class="text-sm font-semibold">
          {{ tr('group', { n: index + 1 }) }}
        </h4>
        <select
          v-model="group.operator"
          :aria-label="tr('within_group')"
          :class="fieldClass"
        >
          <option value="all">{{ tr('all') }}</option>
          <option value="any">{{ tr('any') }}</option>
        </select>
        <button
          type="button"
          :class="buttonClass"
          :disabled="model.groups.length === 1"
          @click="model.groups.splice(index, 1)"
        >
          {{ tr('remove') }}
        </button>
      </header>
      <div
        v-for="(item, itemIndex) in group.items"
        :key="itemIndex"
        class="grid items-end gap-2 rounded-lg bg-n-solid-1 p-3 lg:grid-cols-[1fr_100px_1fr_auto]"
      >
        <label class="grid gap-1 text-xs">
          {{ tr('field') }}
          <select
            :value="item.field"
            :class="fieldClass"
            @change="changeField(item, $event.target.value)"
          >
            <option
              v-for="key in predicateFields"
              :key="key"
              :value="key"
            >
              {{ tr(`fields.${key}`) }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-xs">
          {{ tr('operator') }}
          <select
            v-model="item.operator"
            :class="fieldClass"
          >
            <option value="eq">{{ tr('equals') }}</option>
            <option value="neq">{{ tr('different') }}</option>
          </select>
        </label>
        <ServiceFormPredicate
          v-if="item.field === 'form_value'"
          v-model="item.value"
          :fields="options.form_fields || []"
          :disabled="disabled"
        />
        <ServiceSelect
          v-else-if="item.field === 'service_id'"
          :model-value="String(item.value || '')"
          :unit-id="unitId"
          :disabled="disabled"
          @update:model-value="valueFor(item, $event)"
        />
        <CompanyPicker
          v-else-if="item.field === 'company_id'"
          :model-value="item.value"
          :disabled="disabled"
          @update:model-value="valueFor(item, $event)"
        />
        <label
          v-else-if="
            ['inbox_id', 'label_id', 'channel_type'].includes(item.field)
          "
          class="grid gap-1 text-xs"
        >
          {{ tr('value') }}
          <select
            :value="item.value"
            :class="fieldClass"
            @change="valueFor(item, $event.target.value)"
          >
            <option value="">{{ tr('choose') }}</option>
            <option
              v-for="choice in item.field === 'label_id'
                ? options.labels
                : options.inboxes"
              :key="choice.id"
              :value="
                item.field === 'channel_type' ? choice.channel_type : choice.id
              "
            >
              {{ choice.name
              }}{{
                item.field === 'channel_type' ? ` · ${choice.channel_type}` : ''
              }}
            </option>
          </select>
        </label>
        <LookupSelect
          v-else-if="predicateResources[item.field]"
          :model-value="String(item.value || '')"
          :label="tr('value')"
          :unit-id="unitId"
          :resource="predicateResources[item.field]"
          :disabled="disabled"
          @update:model-value="valueFor(item, $event)"
        />
        <label
          v-else
          class="grid gap-1 text-xs"
        >
          {{ tr('value') }}
          <input
            :value="item.value"
            :class="fieldClass"
            @input="valueFor(item, $event.target.value)"
          />
        </label>
        <button
          type="button"
          :class="buttonClass"
          @click="group.items.splice(itemIndex, 1)"
        >
          {{ tr('remove') }}
        </button>
      </div>
      <p
        v-if="!group.items.length"
        class="text-xs text-n-amber-11"
      >
        {{ tr('empty_group') }}
      </p>
      <button
        type="button"
        :class="buttonClass"
        :disabled="group.items.length >= 20"
        @click="addItem(group)"
      >
        {{ tr('add_condition') }}
      </button>
    </article>
    <button
      type="button"
      :class="buttonClass"
      :disabled="model.groups.length >= 20"
      @click="addGroup"
    >
      {{ tr('add_group') }}
    </button>
    <p class="rounded-xl bg-n-amber-2 p-3 text-xs text-n-amber-11">
      {{ tr('tags_condition_help') }}
    </p>
  </fieldset>
</template>
