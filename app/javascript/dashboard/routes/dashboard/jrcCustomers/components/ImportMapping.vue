<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ImportPager from './ImportPager.vue';
import { inputClass, primaryClass } from '../copy';
const props = defineProps({
  source: { type: Object, required: true },
  mapping: { type: Object, required: true },
  options: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['mapping', 'options', 'preview']);
const { t, tm } = useI18n();
const copy = computed(() => tm('CRM.CUSTOMER_IMPORTS'));
const page = ref(1);
const headers = computed(() =>
  props.source.headers.slice((page.value - 1) * 8, page.value * 8)
);
const fieldLabel = field => copy.value.FIELDS[field.replace('.', '_')] || field;
const setOption = (key, value) =>
  emit('options', { ...props.options, [key]: value });
const confirm = (key, value) =>
  setOption('confirmations', { ...props.options.confirmations, [key]: value });
</script>

<template>
  <form
    class="space-y-5"
    @submit.prevent="emit('preview')"
  >
    <p class="text-sm text-n-slate-11">
      {{ t('CRM.CUSTOMER_IMPORTS.MAPPING_HELP', { count: source.row_count }) }}
    </p>
    <div class="grid gap-3 sm:grid-cols-2">
      <label
        v-for="header in headers"
        :key="header"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
      >
        <span class="break-words font-semibold">{{ header }}</span>
        <select
          :value="mapping[header] || ''"
          :class="inputClass"
          :disabled="disabled"
          @change="
            emit('mapping', {
              ...mapping,
              [header]: $event.target.value || null,
            })
          "
        >
          <option value="">
            {{ t('CRM.CUSTOMER_IMPORTS.IGNORE_COLUMN') }}
          </option>
          <option
            v-for="field in source.fields"
            :key="field"
            :value="field"
            :disabled="
              field !== mapping[header] &&
              Object.values(mapping).includes(field)
            "
          >
            {{ fieldLabel(field) }}
          </option>
        </select>
      </label>
    </div>
    <ImportPager
      :page="page"
      :size="8"
      :total="source.headers.length"
      :disabled="disabled"
      @page="page = $event"
    />
    <label class="block text-sm font-semibold">
      {{ t('CRM.CUSTOMER_IMPORTS.EXISTING') }}
      <select
        :value="options.existing"
        :class="inputClass"
        :disabled="disabled"
        @change="setOption('existing', $event.target.value)"
      >
        <option value="skip">
          {{ t('CRM.CUSTOMER_IMPORTS.SKIP_EXISTING') }}
        </option>
        <option value="update">
          {{ t('CRM.CUSTOMER_IMPORTS.UPDATE_EXISTING') }}
        </option>
      </select>
    </label>
    <div
      class="space-y-3 rounded-lg border border-n-amber-7 bg-n-amber-3 p-4 text-sm text-n-amber-12"
    >
      <p>{{ t('CRM.CUSTOMER_IMPORTS.NO_DELETE') }}</p>
      <label class="flex items-start gap-2">
        <input
          type="checkbox"
          :checked="options.confirmations.reassignment"
          :disabled="disabled"
          @change="confirm('reassignment', $event.target.checked)"
        />
        {{ t('CRM.CUSTOMER_IMPORTS.CONFIRM_REASSIGNMENT') }}
      </label>
      <label class="flex items-start gap-2">
        <input
          type="checkbox"
          :checked="options.confirmations.primary_change"
          :disabled="disabled"
          @change="confirm('primary_change', $event.target.checked)"
        />
        {{ t('CRM.CUSTOMER_IMPORTS.CONFIRM_PRIMARY') }}
      </label>
    </div>
    <button
      type="submit"
      :class="primaryClass"
      :disabled="disabled"
    >
      {{ t('CRM.CUSTOMER_IMPORTS.REVIEW') }}
    </button>
  </form>
</template>
