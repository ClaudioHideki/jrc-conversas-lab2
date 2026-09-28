<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { leadsAPI } from 'dashboard/api/crm';

const props = defineProps({ contact: { type: Object, required: true } });
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const lead = ref(null);
const ready = ref(false);
const busy = ref(false);
const hidden = ref(false);
const error = ref('');
const retry = ref(0);
let generation = 0;
const buttonLabel = computed(() => {
  if (!ready.value || busy.value) return t('CRM.CONTACT_LEAD.LOADING');
  return lead.value ? t('CRM.CONTACT_LEAD.VIEW') : t('CRM.CONTACT_LEAD.CREATE');
});

const showError = failure => {
  const status = failure.response?.status;
  if ([401, 403].includes(status)) hidden.value = true;
  else if (status === 409) error.value = t('CRM.CONTACT_LEAD.AMBIGUOUS');
  else if (status === 404) error.value = t('CRM.CONTACT_LEAD.UNAVAILABLE');
  else error.value = t('CRM.CONTACT_LEAD.ERROR');
};

watch(
  [() => props.contact.id, () => route.params.accountId, retry],
  async ([contactId], _, onCleanup) => {
    generation += 1;
    const request = generation;
    onCleanup(() => {
      generation += 1;
    });
    lead.value = null;
    ready.value = false;
    busy.value = false;
    hidden.value = false;
    error.value = '';
    try {
      const { data } = await leadsAPI.forContact(contactId);
      if (request !== generation) return;
      lead.value = data.lead;
      ready.value = true;
    } catch (failure) {
      if (request === generation) showError(failure);
    }
  },
  { immediate: true }
);

const openLead = () =>
  router.push({
    name: 'crm_leads',
    params: { accountId: route.params.accountId },
    query: { leadId: lead.value.id },
  });

const connect = async () => {
  if (!ready.value || busy.value) return;
  if (lead.value) {
    await openLead();
    return;
  }
  const request = generation;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await leadsAPI.fromContact(props.contact.id);
    if (request !== generation) return;
    lead.value = data.lead;
    await openLead();
  } catch (failure) {
    if (request === generation) {
      ready.value = false;
      showError(failure);
    }
  } finally {
    if (request === generation) busy.value = false;
  }
};
</script>

<template>
  <div>
    <div v-if="!hidden" class="mt-4 space-y-2">
      <p v-if="error" role="alert" class="text-xs text-n-ruby-11">
        {{ error }}
      </p>
      <button
        v-if="error"
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm"
        @click="retry++"
      >
        {{ t('CRM.CONTACT_LEAD.RETRY') }}
      </button>
      <button
        v-else
        type="button"
        :disabled="!ready || busy"
        class="w-full rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
        @click="connect"
      >
        {{ buttonLabel }}
      </button>
    </div>
  </div>
</template>
