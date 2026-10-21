<script setup>
import { onMounted, ref } from 'vue';
import JrcCampaignsAPI from 'dashboard/api/jrcCampaigns';

const props = defineProps({ campaign: { type: Object, required: true } });
const emit = defineEmits(['close']);
const loading = ref(true);
const report = ref(null);
const page = ref(1);

const load = async targetPage => {
  loading.value = true;
  const { data } = await JrcCampaignsAPI.report(props.campaign.id, { page: targetPage, per_page: 50 });
  report.value = data;
  page.value = targetPage;
  loading.value = false;
};

const exportReport = () => {
  window.open(JrcCampaignsAPI.exportUrl(props.campaign.id), '_blank');
};

onMounted(() => load(1));
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-stretch justify-end bg-black/40">
    <div class="flex h-full w-full max-w-6xl flex-col bg-n-background shadow-xl">
      <div class="flex items-center justify-between border-b border-n-weak px-6 py-4">
        <div>
          <h2 class="text-xl font-semibold text-n-slate-12">{{ $t('JRC_CAMPAIGNS.REPORTS.TITLE') }} · {{ campaign.name }}</h2>
          <p class="mt-1 text-sm text-n-slate-10">{{ $t('JRC_CAMPAIGNS.REPORTS.SUBTITLE') }}</p>
        </div>
        <div class="flex gap-2">
          <button type="button" class="flex items-center gap-2 rounded-lg border border-n-strong px-3 py-2 text-sm text-n-slate-12" @click="exportReport"><span class="i-lucide-download size-4" />{{ $t('JRC_CAMPAIGNS.EXPORT') }}</button>
          <button type="button" class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-2" @click="emit('close')"><span class="i-lucide-x size-5" /></button>
        </div>
      </div>
      <div class="flex-1 overflow-y-auto p-6">
        <div v-if="loading" class="p-12 text-center text-sm text-n-slate-10">{{ $t('JRC_CAMPAIGNS.LOADING') }}</div>
        <template v-else-if="report">
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
            <div v-for="item in [
              ['TOTAL', report.summary.total], ['SENT', report.summary.sent], ['DELIVERED', report.summary.delivered],
              ['READ', report.summary.read], ['REPLIED', report.summary.replied], ['FAILED', report.summary.failed]
            ]" :key="item[0]" class="rounded-xl border border-n-weak p-4">
              <div class="text-xs text-n-slate-10">{{ $t(`JRC_CAMPAIGNS.REPORTS.${item[0]}`) }}</div>
              <div class="mt-1 text-2xl font-semibold text-n-slate-12">{{ item[1] }}</div>
            </div>
          </div>

          <div class="mt-6 overflow-x-auto rounded-xl border border-n-weak">
            <table class="w-full min-w-[900px] text-left text-sm">
              <thead class="bg-n-alpha-2 text-xs text-n-slate-10">
                <tr>
                  <th class="px-4 py-3">{{ $t('JRC_CAMPAIGNS.TABLE.NAME') }}</th>
                  <th class="px-4 py-3">{{ $t('JRC_CAMPAIGNS.REPORTS.DESTINATION') }}</th>
                  <th class="px-4 py-3">{{ $t('JRC_CAMPAIGNS.REPORTS.INBOX') }}</th>
                  <th class="px-4 py-3">{{ $t('JRC_CAMPAIGNS.REPORTS.EXECUTION') }}</th>
                  <th class="px-4 py-3">{{ $t('JRC_CAMPAIGNS.REPORTS.STATUS') }}</th>
                  <th class="px-4 py-3">{{ $t('JRC_CAMPAIGNS.REPORTS.SENT_AT') }}</th>
                  <th class="px-4 py-3">{{ $t('JRC_CAMPAIGNS.REPORTS.ERROR') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="recipient in report.recipients" :key="recipient.id" class="border-t border-n-weak">
                  <td class="px-4 py-3 font-medium text-n-slate-12">{{ recipient.name || '-' }}</td>
                  <td class="px-4 py-3 text-n-slate-11">{{ recipient.destination || recipient.email || recipient.phone_number }}</td>
                  <td class="px-4 py-3 text-n-slate-11">{{ recipient.inbox_name || '-' }}</td>
                  <td class="px-4 py-3 text-n-slate-11">#{{ recipient.execution_number }}</td>
                  <td class="px-4 py-3"><span class="rounded-full bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11">{{ recipient.status }}</span></td>
                  <td class="px-4 py-3 text-n-slate-10">{{ recipient.sent_at ? new Date(recipient.sent_at).toLocaleString() : '-' }}</td>
                  <td class="max-w-xs px-4 py-3 text-xs text-n-ruby-11">{{ recipient.error_message || '-' }}</td>
                </tr>
                <tr v-if="!report.recipients.length"><td colspan="7" class="p-10 text-center text-sm text-n-slate-10">{{ $t('JRC_CAMPAIGNS.REPORTS.NO_DATA') }}</td></tr>
              </tbody>
            </table>
          </div>

          <div v-if="report.pagination.pages > 1" class="mt-4 flex justify-end gap-2">
            <button type="button" class="rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-40" :disabled="page <= 1" @click="load(page - 1)">‹</button>
            <span class="px-2 py-1.5 text-sm text-n-slate-10">{{ page }} / {{ report.pagination.pages }}</span>
            <button type="button" class="rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-40" :disabled="page >= report.pagination.pages" @click="load(page + 1)">›</button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
