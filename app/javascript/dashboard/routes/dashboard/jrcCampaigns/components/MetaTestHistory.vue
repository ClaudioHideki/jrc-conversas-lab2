<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import api from 'dashboard/api/jrcCampaigns';

const props = defineProps({ timezone: { type: String, default: 'UTC' } });
const { t } = useI18n();
const records = ref([]);
const busy = ref(false);
const error = ref(false);
const load = async () => {
  if (busy.value) return;
  busy.value = true;
  error.value = false;
  try {
    records.value = (await api.testDeliveries()).data;
  } catch {
    error.value = true;
  } finally {
    busy.value = false;
  }
};
const date = value =>
  value
    ? new Date(value).toLocaleString(undefined, {
        timeZone: props.timezone,
        timeZoneName: 'short',
      })
    : '—';
</script>

<template>
  <details
    class="mt-3 rounded-xl border border-n-weak p-3"
    @toggle="$event.target.open && load()"
  >
    <summary class="cursor-pointer text-sm font-medium">
      {{ t('JRC_CAMPAIGNS.META.HISTORY') }}
    </summary>
    <button
      type="button"
      :disabled="busy"
      class="my-2 text-xs text-n-brand"
      @click="load"
    >
      {{ t('JRC_CAMPAIGNS.META.REFRESH') }}
    </button>
    <p v-if="error" role="alert" class="text-xs text-n-ruby-11">
      {{ t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED') }}
    </p>
    <div class="max-h-80 space-y-2 overflow-y-auto">
      <article
        v-for="record in records"
        :key="record.id"
        class="rounded-lg bg-n-alpha-1 p-3 text-xs"
      >
        <p>
          {{ record.phone_number }} · {{ record.template }} ·
          {{ record.language }}
        </p>
        <p class="font-semibold">
          {{ record.provider_status || record.status }}
        </p>
        <p>{{ date(record.created_at) }}</p>
        <p v-if="record.accepted_at">
          {{ t('JRC_CAMPAIGNS.META.ACCEPTED_AT') }}:
          {{ date(record.accepted_at) }}
        </p>
        <p v-if="record.delivered_at">
          {{ t('JRC_CAMPAIGNS.META.DELIVERED_AT') }}:
          {{ date(record.delivered_at) }}
        </p>
        <p v-if="record.read_at">
          {{ t('JRC_CAMPAIGNS.META.READ_AT') }}: {{ date(record.read_at) }}
        </p>
        <code v-if="record.external_id" class="block break-all">
          {{ record.external_id }}
        </code>
        <p v-if="record.error_message" class="text-n-ruby-11">
          {{ record.error_code }} {{ record.error_message }}
        </p>
      </article>
    </div>
  </details>
</template>
