<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  scope: { type: String, required: true },
  modelValue: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const q = ref('');
const page = ref(1);
const pages = ref(0);
const items = ref([]);
const loading = ref(false);
const failed = ref(false);
let generation = 0;
watch(
  () => [props.accountId, props.scope],
  () => {
    q.value = '';
    page.value = 1;
  }
);
watch(q, () => {
  page.value = 1;
});
watch(
  () => [props.accountId, props.scope, q.value, page.value],
  async () => {
    generation += 1;
    const version = generation;
    loading.value = true;
    failed.value = false;
    items.value = [];
    pages.value = 0;
    try {
      const params = { q: q.value, page: page.value, per_page: 20 };
      const response =
        props.scope === 'queue'
          ? await API.queues(props.accountId, params)
          : await API.administrativeList(props.accountId, 'teams', params);
      if (generation !== version) return;
      items.value = response.data.items;
      pages.value = response.data.meta.pages;
    } catch {
      if (generation === version) failed.value = true;
    } finally {
      if (generation === version) loading.value = false;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <div class="min-w-0 space-y-2" data-acw-rule-target>
    <label class="block min-w-0 text-sm">
      {{ t('JRC_CONTACT_CENTER.ACW_RULES.TARGET_SEARCH') }}
      <input
        v-model="q"
        :disabled="disabled"
        type="search"
        maxlength="100"
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      />
    </label>
    <label class="block min-w-0 text-sm">
      {{ t('JRC_CONTACT_CENTER.ACW_RULES.TARGET') }}
      <select
        :value="modelValue"
        :disabled="disabled || loading"
        required
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        @change="emit('update:modelValue', $event.target.value)"
      >
        <option value="">{{ t('JRC_CONTACT_CENTER.ADMIN.SELECT') }}</option>
        <option
          v-if="modelValue && !items.some(row => String(row.id) === modelValue)"
          :value="modelValue"
        >
          {{ '#' + modelValue }}
        </option>
        <option v-for="item in items" :key="item.id" :value="String(item.id)">
          {{ item.name }}
        </option>
      </select>
    </label>
    <p v-if="loading" role="status" class="text-xs text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p v-if="failed" role="alert" class="text-xs text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        :disabled="disabled || loading || page <= 1"
        class="rounded-md border border-n-weak px-2 py-1 text-xs disabled:opacity-50"
        @click="page -= 1"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.PREVIOUS') }}
      </button>
      <button
        type="button"
        :disabled="disabled || loading || page >= pages"
        class="rounded-md border border-n-weak px-2 py-1 text-xs disabled:opacity-50"
        @click="page += 1"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.NEXT') }}
      </button>
    </div>
  </div>
</template>
