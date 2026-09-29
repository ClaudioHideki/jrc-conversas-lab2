<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({ contact: { type: Object, default: () => ({}) } });
const { t } = useI18n();
const phone = computed(() => (props.contact?.phone_number || '').replace(/[^\d+]/g, ''));
const actions = computed(() => [
  { key: 'WHATSAPP', icon: 'i-ri-whatsapp-fill', href: phone.value.startsWith('+') ? `https://wa.me/${phone.value.replace(/\D/g, '')}` : '', external: true },
  { key: 'CALL', icon: 'i-lucide-phone', href: phone.value ? `tel:${phone.value}` : '' },
  { key: 'EMAIL', icon: 'i-lucide-mail', href: props.contact?.email ? `mailto:${encodeURIComponent(props.contact.email)}` : '' },
]);
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <template v-for="action in actions" :key="action.key">
      <a v-if="action.href" :href="action.href" :target="action.external ? '_blank' : undefined" rel="noopener noreferrer" :title="t('CRM.HOMOLOGATION.CONTACT_EXTERNAL')" class="inline-flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-xs font-semibold text-n-slate-12 hover:bg-n-slate-3 focus-visible:ring-2 focus-visible:ring-n-brand">
        <i class="size-4" :class="action.icon" />{{ t(`CRM.HOMOLOGATION.${action.key}`) }}
      </a>
      <button v-else type="button" disabled :title="t('CRM.HOMOLOGATION.CONTACT_MISSING')" class="inline-flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-xs text-n-slate-11 disabled:cursor-not-allowed disabled:opacity-60">
        <i class="size-4" :class="action.icon" />{{ t(`CRM.HOMOLOGATION.${action.key}`) }}
      </button>
    </template>
  </div>
</template>
