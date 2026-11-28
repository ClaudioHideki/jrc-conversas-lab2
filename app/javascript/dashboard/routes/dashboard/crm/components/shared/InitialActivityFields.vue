<script setup>
import { useI18n } from 'vue-i18n';

const activity = defineModel({ type: Object, required: true });
const { t } = useI18n();
const types = [
  'call',
  'whatsapp',
  'email',
  'meeting',
  'demonstration',
  'follow_up',
  'proposal',
  'task',
];
const inputClass =
  'mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12';
</script>

<template>
  <div class="grid gap-3 text-sm sm:grid-cols-3">
    <label>
      {{ t('CRM.SALES_FLOW.TYPE') }}
      <select v-model="activity.activity_type" :class="inputClass">
        <option v-for="type in types" :key="type" :value="type">
          {{ t(`CRM.ACTIVITY_FILTERS.${type.toUpperCase()}`) }}
        </option>
      </select>
    </label>
    <label>
      {{ t('CRM.SALES_FLOW.DATE_TIME') }}
      <input
        v-model="activity.due_at"
        type="datetime-local"
        required
        :class="inputClass"
      />
    </label>
    <label>
      {{ t('CRM.SALES_FLOW.ACTIVITY_TITLE') }}
      <input v-model.trim="activity.title" required :class="inputClass" />
    </label>
    <label class="sm:col-span-3">
      {{ t('CRM.LEAD_FORM.NOTES') }}
      <textarea
        v-model.trim="activity.description"
        rows="2"
        :class="inputClass"
      />
    </label>
  </div>
</template>
