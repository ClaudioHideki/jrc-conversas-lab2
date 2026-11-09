<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({
  call: { type: Object, default: null },
  customer: { type: Object, default: null },
  customerStatus: { type: String, default: '' },
  elapsed: { type: String, default: '' },
});
const { t, locale } = useI18n();
const contact = computed(() =>
  !props.customer?.ambiguous && props.customer?.contacts?.length === 1
    ? props.customer.contacts[0]
    : null
);
const formatDate = value => {
  if (!value || Number.isNaN(Date.parse(value)))
    return t('SOFTPHONE.CENTRAL.UNAVAILABLE');
  return new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
};
const fields = computed(() => [
  [
    t('SOFTPHONE.CENTRAL.PHONE'),
    props.call?.direction === 'outbound' ? props.call?.dnis : props.call?.ani,
  ],
  [t('VOICE_V4.COMPANY'), contact.value?.company?.name],
  [t('SOFTPHONE.CENTRAL.QUEUE'), props.call?.queue?.name],
  [t('SOFTPHONE.CENTRAL.START'), formatDate(props.call?.started_at)],
  [
    t('SOFTPHONE.CENTRAL.DURATION'),
    props.call?.answered_at ? props.elapsed : null,
  ],
  [t('VOICE_V4.PROTOCOL'), props.call?.correlation_id],
  [t('VOICE_V4.RECORDING'), t('VOICE_V4.RECORDING_UNKNOWN')],
]);
</script>

<template>
  <section
    class="space-y-3 border-b border-n-weak bg-n-solid-1 p-4"
    data-voice-summary
  >
    <h3 class="m-0 text-base font-semibold">
      {{
        customer?.ambiguous
          ? t('JRC_CONTACT_CENTER.CALL.AMBIGUOUS')
          : contact?.name || t('VOICE_V4.CUSTOMER_UNKNOWN')
      }}
    </h3>
    <p
      v-if="customerStatus === 'error'"
      role="alert"
      class="m-0 rounded-lg bg-n-amber-2 p-3 text-xs text-n-amber-11"
    >
      {{ t('VOICE_V4.CUSTOMER_ERROR') }}
    </p>
    <p
      v-if="['restricted', 'unavailable'].includes(customerStatus)"
      role="status"
      class="m-0 text-xs text-n-slate-11"
    >
      {{ t('VOICE_V4.CUSTOMER_RESTRICTED') }}
    </p>
    <dl class="m-0 grid grid-cols-2 gap-x-4 gap-y-3 text-xs xl:grid-cols-3">
      <div v-for="[label, value] in fields" :key="label" class="min-w-0">
        <dt class="text-n-slate-10">{{ label }}</dt>
        <dd class="m-0 mt-1 break-words font-medium">
          {{ value || t('SOFTPHONE.CENTRAL.UNAVAILABLE') }}
        </dd>
      </div>
    </dl>
  </section>
</template>
