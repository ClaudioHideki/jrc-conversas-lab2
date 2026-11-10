<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CompanyPage from '../CompanyPage.vue';
import { useCustomerMaster } from '../useCustomerMaster';

const props = defineProps({
  companyId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close', 'updated']);
const { t } = useI18n();
const { accountScopedRoute } = useCustomerMaster();
const selection = ref(props.companyId);
const dialog = ref(null);
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('CRM.CUSTOMER_MASTER_360.COMPANY_DETAILS')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    show-close-button
    overflow-y-auto
    contained
    width="5xl"
    @close="emit('close')"
  >
    <RouterLink
      class="mb-3 inline-block rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm text-n-blue-12"
      :to="accountScopedRoute('jrc_customer_company', { companyId: selection })"
    >
      {{ t('CRM.CUSTOMER_MASTER_360.OPEN_FULL_PAGE') }}
    </RouterLink>
    <CompanyPage
      :subject-id="selection"
      embedded
      @navigate-company="selection = $event"
      @updated="emit('updated', $event)"
      @denied="emit('close')"
    />
  </Dialog>
</template>
