<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import api from 'dashboard/api/jrcCampaigns';
import { parseContactList } from '../contactListParser';

const props = defineProps({
  mode: { type: String, required: true },
  campaignName: { type: String, default: '' },
});
const emit = defineEmits(['selected']);
const { t } = useI18n();
const text = ref('');
const error = ref('');
const busy = ref(false);
const parsed = computed(() => {
  try {
    return { entries: parseContactList(text.value), failed: false };
  } catch {
    return { entries: [], failed: true };
  }
});
const loadFile = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  error.value = '';
  text.value = '';
  try {
    text.value = await file.text();
  } catch {
    error.value = t('JRC_CAMPAIGNS.SANITIZE.FILE_ERROR');
  }
};
const addList = async () => {
  if (busy.value || !props.campaignName.trim() || !parsed.value.entries.length)
    return;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await api.createSanitizedList({
      name: props.campaignName.trim(),
      entries: parsed.value.entries,
    });
    emit('selected', data);
  } catch (failure) {
    error.value =
      failure?.response?.data?.errors?.join(', ') ||
      t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED');
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section
    class="mt-4 space-y-3 rounded-xl border border-n-weak p-4"
    :aria-busy="busy"
  >
    <label v-if="mode === 'csv'" class="block text-sm text-n-slate-12">
      {{ t('JRC_CAMPAIGNS.SANITIZE.CSV') }}
      <input
        type="file"
        accept=".csv,text/csv"
        :disabled="busy"
        class="mt-2 block w-full text-sm"
        @change="loadFile"
      />
    </label>
    <label v-else class="block text-sm text-n-slate-12">
      {{ t('JRC_CAMPAIGNS.WIZARD.MANUAL_NUMBERS_HELP') }}
      <textarea
        v-model="text"
        rows="5"
        :disabled="busy"
        class="mt-2 w-full rounded-lg border border-n-weak bg-n-background p-3 font-mono text-sm"
      />
    </label>
    <p
      v-if="parsed.failed || error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ parsed.failed ? t('JRC_CAMPAIGNS.SANITIZE.PARSE_ERROR') : error }}
    </p>
    <p
      v-else-if="parsed.entries.length"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ t('JRC_CAMPAIGNS.SANITIZE.PARSED', { count: parsed.entries.length }) }}
    </p>
    <button
      type="button"
      :disabled="busy || !campaignName.trim() || !parsed.entries.length"
      class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
      @click="addList"
    >
      {{ t('JRC_CAMPAIGNS.WIZARD.ADD_LIST') }}
    </button>
  </section>
</template>
