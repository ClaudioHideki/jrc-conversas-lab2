<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
  query: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const sourceSection = computed(() =>
  ['integrations', 'pabx'].find(key =>
    props.context.cards?.some(card => card.key === key)
  )
);
const pendingAcw = computed(() => {
  const value = props.context.cards?.find(
    card => card.key === 'closures'
  )?.count;
  return Number.isSafeInteger(value) && value > 0 ? value : null;
});
const providerAlert = computed(() => {
  if (props.context.provider?.last_error === true)
    return t('JRC_CONTACT_CENTER.ADMIN.PENDING_ALERTS.SYNC_FAILED');
  if (props.context.provider?.configured === false)
    return t('JRC_CONTACT_CENTER.ADMIN.PENDING_ALERTS.NOT_CONFIGURED');
  return '';
});
const destination = section => ({
  name: 'jrc_contact_center_admin_section',
  params: { accountId: props.accountId, section },
  query: props.query,
});
</script>

<template>
  <div class="min-w-0">
    <section
      v-if="providerAlert || pendingAcw"
      class="min-w-0 space-y-3 rounded-xl border border-n-amber-6 bg-n-solid-2 p-4"
      data-administration-pending-alerts
    >
      <h2 class="flex items-center gap-2 font-semibold text-n-slate-12">
        <Icon
          icon="i-lucide-triangle-alert"
          class="size-5 shrink-0 text-n-amber-11"
        />
        {{ t('JRC_CONTACT_CENTER.ADMIN.PENDING_ALERTS.TITLE') }}
      </h2>
      <ul class="space-y-3 text-sm text-n-slate-12">
        <li
          v-if="providerAlert"
          class="min-w-0 space-y-1"
          data-native-provider-alert
        >
          <p>
            {{ providerAlert }}
          </p>
          <RouterLink
            v-if="sourceSection"
            :to="destination(sourceSection)"
            class="inline-flex min-h-9 items-center break-words rounded text-n-blue-11 underline focus-visible:ring-2 focus-visible:ring-n-blue-7"
            data-native-provider-alert-source
          >
            {{ t('JRC_CONTACT_CENTER.ADMIN.PENDING_ALERTS.PROVIDER_SOURCE') }}
          </RouterLink>
        </li>
        <li v-if="pendingAcw" class="min-w-0 space-y-1" data-native-acw-alert>
          <p>
            {{
              t('JRC_CONTACT_CENTER.ADMIN.PENDING_ALERTS.PENDING_ACW', {
                count: pendingAcw,
              })
            }}
          </p>
          <RouterLink
            v-if="context.capabilities?.supervise === true"
            :to="{
              name: 'jrc_contact_center_supervisor',
              params: { accountId },
              query,
            }"
            class="inline-flex min-h-9 items-center break-words rounded text-n-blue-11 underline focus-visible:ring-2 focus-visible:ring-n-blue-7"
            data-native-acw-alert-source
          >
            {{ t('JRC_CONTACT_CENTER.ADMIN.PENDING_ALERTS.ACW_SOURCE') }}
          </RouterLink>
        </li>
      </ul>
    </section>
  </div>
</template>
