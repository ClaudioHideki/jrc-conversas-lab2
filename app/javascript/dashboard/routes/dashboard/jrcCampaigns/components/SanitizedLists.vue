<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import JrcCampaignsAPI from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';
import { parseContactList } from '../contactListParser';

defineProps({
  lists: { type: Array, default: () => [] },
});
const emit = defineEmits(['changed', 'useList']);
const { t } = useI18n();

const name = ref('');
const inputText = ref('');
const saving = ref(false);
const result = ref(null);

const error = ref('');
const parsed = computed(() => {
  try {
    return { entries: parseContactList(inputText.value), failed: false };
  } catch {
    return { entries: [], failed: true };
  }
});
const parsedEntries = computed(() => parsed.value.entries);
const loadCsv = async event => {
  const file = event.target.files?.[0];
  if (!file) return;
  error.value = '';
  result.value = null;
  try {
    inputText.value = await file.text();
    if (!name.value) name.value = file.name.replace(/\.csv$/i, '');
  } catch {
    inputText.value = '';
    error.value = t('JRC_CAMPAIGNS.SANITIZE.FILE_ERROR');
  }
};

const sanitize = async () => {
  if (saving.value || !name.value.trim() || !parsedEntries.value.length) return;
  error.value = '';
  saving.value = true;
  result.value = null;
  try {
    const { data } = await JrcCampaignsAPI.createSanitizedList({
      name: name.value,
      entries: parsedEntries.value,
    });
    result.value = data;
    name.value = '';
    inputText.value = '';
    useAlert(t('JRC_CAMPAIGNS.ALERTS.SANITIZED'));
    emit('changed');
  } catch (failure) {
    error.value =
      failure?.response?.data?.errors?.join(', ') ||
      t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED');
  } finally {
    saving.value = false;
  }
};

const removeList = async id => {
  await JrcCampaignsAPI.deleteSanitizedList(id);
  emit('changed');
};
</script>

<template>
  <div class="space-y-6">
    <div>
      <h2 class="text-xl font-semibold text-n-slate-12">
        {{ $t('JRC_CAMPAIGNS.SANITIZE.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ $t('JRC_CAMPAIGNS.SANITIZE.SUBTITLE') }}
      </p>
      <p class="mt-3 rounded-lg bg-n-blue-2 p-3 text-sm text-n-slate-11">
        {{ t('JRC_CAMPAIGNS.SANITIZE.NOT_AUTHORIZATION') }}
      </p>
    </div>

    <div class="rounded-xl border border-n-weak p-5">
      <div class="grid gap-4 md:grid-cols-2">
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.NAME') }}
          <input
            v-model="name"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-background px-3 py-2"
            :placeholder="$t('JRC_CAMPAIGNS.SANITIZE.NAME_PLACEHOLDER')"
          />
        </label>
        <label class="text-sm font-medium text-n-slate-12">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.CSV') }}
          <input
            type="file"
            accept=".csv,text/csv"
            class="mt-1 block w-full rounded-lg border border-n-weak bg-n-background px-3 py-2 text-sm"
            @change="loadCsv"
          />
        </label>
      </div>
      <label class="mt-4 block text-sm font-medium text-n-slate-12">
        {{ $t('JRC_CAMPAIGNS.SANITIZE.PASTE') }}
        <textarea
          v-model="inputText"
          rows="9"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-background px-3 py-2 font-mono text-xs"
        />
      </label>
      <p class="mt-2 text-xs text-n-slate-11">
        {{ t('JRC_CAMPAIGNS.SANITIZE.FORMAT_HELP') }}
      </p>
      <p
        v-if="parsed.failed || error"
        role="alert"
        class="mt-3 text-sm text-n-ruby-11"
      >
        {{ parsed.failed ? t('JRC_CAMPAIGNS.SANITIZE.PARSE_ERROR') : error }}
      </p>
      <p
        v-else-if="parsedEntries.length"
        role="status"
        class="mt-3 text-sm text-n-slate-11"
      >
        {{
          t('JRC_CAMPAIGNS.SANITIZE.PARSED', { count: parsedEntries.length })
        }}
      </p>
      <div class="mt-4 flex justify-end">
        <button
          type="button"
          class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
          :disabled="saving || !name.trim() || !parsedEntries.length"
          @click="sanitize"
        >
          {{ $t('JRC_CAMPAIGNS.SANITIZE.PROCESS') }}
        </button>
      </div>
    </div>

    <div
      v-if="result"
      class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-7"
    >
      <div class="rounded-xl border border-n-weak p-4">
        <div class="text-xs text-n-slate-10">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.TOTAL') }}
        </div>
        <div class="mt-1 text-2xl font-semibold">
          {{ result.stats.total || 0 }}
        </div>
      </div>
      <div class="rounded-xl border border-n-weak p-4">
        <div class="text-xs text-n-slate-10">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.VALID') }}
        </div>
        <div class="mt-1 text-2xl font-semibold text-n-teal-11">
          {{ result.stats.valid || 0 }}
        </div>
      </div>
      <div class="rounded-xl border border-n-weak p-4">
        <div class="text-xs text-n-slate-10">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.INVALID') }}
        </div>
        <div class="mt-1 text-2xl font-semibold text-n-ruby-11">
          {{ result.stats.invalid || 0 }}
        </div>
      </div>
      <div class="rounded-xl border border-n-weak p-4">
        <div class="text-xs text-n-slate-10">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.DUPLICATE') }}
        </div>
        <div class="mt-1 text-2xl font-semibold">
          {{ result.stats.duplicate || 0 }}
        </div>
      </div>
      <div class="rounded-xl border border-n-weak p-4">
        <div class="text-xs text-n-slate-10">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.BLACKLISTED') }}
        </div>
        <div class="mt-1 text-2xl font-semibold">
          {{ result.stats.blacklisted || 0 }}
        </div>
      </div>
      <div class="rounded-xl border border-n-weak p-4">
        <div class="text-xs text-n-slate-10">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.VALID_PHONE') }}
        </div>
        <div class="mt-1 text-2xl font-semibold text-n-teal-11">
          {{ result.stats.valid_phone || 0 }}
        </div>
      </div>
      <div class="rounded-xl border border-n-weak p-4">
        <div class="text-xs text-n-slate-10">
          {{ $t('JRC_CAMPAIGNS.SANITIZE.VALID_EMAIL') }}
        </div>
        <div class="mt-1 text-2xl font-semibold text-n-blue-11">
          {{ result.stats.valid_email || 0 }}
        </div>
      </div>
    </div>

    <section
      v-if="result"
      class="space-y-3 rounded-xl border border-n-weak p-4"
    >
      <button
        type="button"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white"
        @click="emit('useList', result)"
      >
        {{ t('JRC_CAMPAIGNS.SANITIZE.USE_LIST') }}
      </button>
      <details v-if="result.entries?.length">
        <summary class="cursor-pointer text-sm text-n-slate-12">
          {{ t('JRC_CAMPAIGNS.SANITIZE.DETAILS') }}
        </summary>
        <div class="mt-3 overflow-auto">
          <table class="w-full text-left text-sm text-n-slate-11">
            <thead>
              <tr>
                <th class="p-2">{{ t('JRC_CAMPAIGNS.SANITIZE.CONTACT') }}</th>
                <th class="p-2">
                  {{ t('JRC_CAMPAIGNS.SANITIZE.DESTINATION') }}
                </th>
                <th class="p-2">{{ t('JRC_CAMPAIGNS.SANITIZE.RESULT') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="entry in result.entries.slice(0, 50)"
                :key="entry.id"
                class="border-t border-n-weak"
              >
                <td class="p-2">{{ entry.name }}</td>
                <td class="p-2">
                  {{ entry.normalized_phone || entry.phone_number }}<br />{{
                    entry.normalized_email || entry.email
                  }}
                </td>
                <td class="p-2">
                  {{ entry.reason || t('JRC_CAMPAIGNS.SANITIZE.VALID') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </section>
    <div>
      <h3 class="mb-3 font-semibold text-n-slate-12">
        {{ $t('JRC_CAMPAIGNS.SANITIZE.LISTS') }}
      </h3>
      <div
        v-if="!lists.length"
        class="rounded-xl border border-dashed border-n-weak p-8 text-center text-sm text-n-slate-10"
      >
        {{ $t('JRC_CAMPAIGNS.SANITIZE.NO_LISTS') }}
      </div>
      <div v-else class="overflow-hidden rounded-xl border border-n-weak">
        <div
          v-for="list in lists"
          :key="list.id"
          class="flex items-center justify-between border-b border-n-weak p-4 last:border-b-0"
        >
          <div>
            <div class="font-medium text-n-slate-12">{{ list.name }}</div>
            <div class="mt-1 text-xs text-n-slate-10">
              {{
                $t('JRC_CAMPAIGNS.SANITIZE.LIST_COUNTS', {
                  whatsapp: list.stats?.valid_phone ?? list.stats?.valid ?? 0,
                  email: list.stats?.valid_email || 0,
                  total: list.stats?.total || 0,
                })
              }}
            </div>
          </div>
          <div class="flex items-center gap-2">
            <button
              type="button"
              class="rounded-lg border border-n-strong px-3 py-2 text-sm text-n-blue-11"
              @click="emit('useList', list)"
            >
              {{ t('JRC_CAMPAIGNS.SANITIZE.USE_LIST') }}
            </button>
            <button
              type="button"
              class="rounded-lg p-2 text-n-ruby-11 hover:bg-n-ruby-3"
              :title="$t('JRC_CAMPAIGNS.DELETE')"
              @click="removeList(list.id)"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
