<script setup>
import { onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import JrcCampaignsAPI from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const entries = ref([]);
const saving = ref(false);
const form = reactive({ phone_number: '', reason: '', source: 'manual' });

const load = async () => {
  const { data } = await JrcCampaignsAPI.blacklists();
  entries.value = data;
};

const add = async () => {
  if (!form.phone_number.trim()) return;
  saving.value = true;
  try {
    await JrcCampaignsAPI.createBlacklist(form);
    form.phone_number = '';
    form.reason = '';
    useAlert(t('JRC_CAMPAIGNS.ALERTS.BLACKLIST_ADDED'));
    await load();
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.join(', ') ||
        t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED')
    );
  } finally {
    saving.value = false;
  }
};

const remove = async id => {
  await JrcCampaignsAPI.deleteBlacklist(id);
  await load();
};

onMounted(load);
</script>

<template>
  <div class="space-y-6">
    <div>
      <h2 class="text-xl font-semibold text-n-slate-12">
        {{ $t('JRC_CAMPAIGNS.BLACKLIST.TITLE') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ $t('JRC_CAMPAIGNS.BLACKLIST.SUBTITLE') }}
      </p>
    </div>
    <div
      class="grid gap-3 rounded-xl border border-n-weak p-5 md:grid-cols-[1fr_2fr_auto]"
    >
      <input
        v-model="form.phone_number"
        class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
        :placeholder="$t('JRC_CAMPAIGNS.BLACKLIST.PHONE')"
      />
      <input
        v-model="form.reason"
        class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
        :placeholder="$t('JRC_CAMPAIGNS.BLACKLIST.REASON')"
      />
      <button
        type="button"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
        :disabled="saving || !form.phone_number.trim()"
        @click="add"
      >
        {{ $t('JRC_CAMPAIGNS.BLACKLIST.ADD') }}
      </button>
    </div>
    <div
      v-if="!entries.length"
      class="rounded-xl border border-dashed border-n-weak p-8 text-center text-sm text-n-slate-11"
    >
      {{ $t('JRC_CAMPAIGNS.BLACKLIST.EMPTY') }}
    </div>
    <div v-else class="overflow-hidden rounded-xl border border-n-weak">
      <div
        v-for="entry in entries"
        :key="entry.id"
        class="grid grid-cols-[1fr_2fr_auto] items-center gap-4 border-b border-n-weak p-4 last:border-b-0"
      >
        <div class="font-medium text-n-slate-12">{{ entry.phone_number }}</div>
        <div class="text-sm text-n-slate-11">{{ entry.reason || '-' }}</div>
        <button
          type="button"
          class="rounded-lg p-2 text-n-ruby-11 hover:bg-n-ruby-3"
          :title="$t('JRC_CAMPAIGNS.DELETE')"
          @click="remove(entry.id)"
        >
          <span class="i-lucide-trash-2 size-4" />
        </button>
      </div>
    </div>
  </div>
</template>
