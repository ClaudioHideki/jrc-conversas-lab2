<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { approvalClient } from 'dashboard/api/approvals';
const props = defineProps({
  accountId: { type: [Number, String], required: true },
  resourceKey: { type: String, required: true },
  modelValue: { type: [Number, String], default: '' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const rows = ref([]);
const page = ref(1);
const total = ref(0);
const error = ref(false);
const busy = ref(false);
let generation = 0;
watch([() => props.accountId, () => props.resourceKey], () => {
  page.value = 1;
  rows.value = [];
  emit('update:modelValue', '');
});
watch(
  [() => props.accountId, () => props.resourceKey, page],
  async ([account, key, number]) => {
    generation += 1;
    const current = generation;
    rows.value = [];
    error.value = false;
    if (!key || key === 'crm.price_exception') return;
    busy.value = true;
    try {
      const result = await approvalClient(account).get('resources', {
        key,
        page: number,
        per_page: 25,
      });
      if (current === generation) {
        rows.value = result.data;
        total.value = Number(result.headers['x-total-count']);
      }
    } catch {
      if (current === generation) error.value = true;
    } finally {
      if (current === generation) busy.value = false;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="space-y-2">
    <label class="block text-sm"
      >{{ t('JRC_APPROVALS.resource')
      }}<select
        :value="modelValue"
        :disabled="busy"
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        @change="emit('update:modelValue', Number($event.target.value))"
      >
        <option value="">{{ t('JRC_APPROVALS.select') }}</option>
        <option
          v-for="row in rows"
          :key="row.id"
          :value="row.id"
        >
          #{{ row.id }} · {{ row.label }}
        </option>
      </select></label
    >
    <p
      v-if="busy"
      role="status"
    >
      {{ t('JRC_APPROVALS.loading') }}
    </p>
    <p
      v-if="error"
      role="alert"
    >
      {{ t('JRC_APPROVALS.loadError') }}
    </p>
    <p
      v-if="!busy && !error && !rows.length"
      class="text-xs"
    >
      {{ t('JRC_APPROVALS.empty') }}
    </p>
    <div class="flex gap-2 text-xs">
      <button
        :disabled="page <= 1"
        @click="page -= 1"
      >
        {{ t('JRC_APPROVALS.previous') }}</button
      ><span>{{ page }} · {{ total }}</span
      ><button
        :disabled="page * 25 >= total"
        @click="page += 1"
      >
        {{ t('JRC_APPROVALS.next') }}
      </button>
    </div>
  </div>
</template>
