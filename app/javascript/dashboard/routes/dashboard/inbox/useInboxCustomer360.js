import { onBeforeUnmount, ref, watch } from 'vue';
import ContactAPI from 'dashboard/api/contacts';
import CustomerAPI from 'dashboard/api/jrcCustomers';
import { customersAPI } from 'dashboard/api/crm/commercialCycle';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';

// A projection of existing, permission-checked APIs; no customer data is cached
// across interactions or accounts.
export const useInboxCustomer360 = (identity, features) => {
  const contact = ref(null);
  const company = ref(null);
  const addresses = ref([]);
  const crm = ref(null);
  const cases = ref([]);
  const loading = ref(false);
  const failed = ref(false);
  const unavailable = ref(false);
  let generation = 0;

  watch(
    [identity, features],
    async ([selection, enabled]) => {
      generation += 1;
      const version = generation;
      contact.value = null;
      company.value = null;
      addresses.value = [];
      crm.value = null;
      cases.value = [];
      failed.value = false;
      unavailable.value = false;
      loading.value = false;
      if (!selection.contactId) return;
      if (Number(ContactAPI.accountIdFromRoute) !== Number(selection.accountId))
        return;
      loading.value = true;
      const results = await Promise.allSettled([
        ContactAPI.show(selection.contactId),
        enabled.crm
          ? customersAPI.show(selection.contactId)
          : Promise.resolve(null),
        ContactCenterAPI.cases(selection.accountId, { limit: 200 }),
        enabled.master
          ? CustomerAPI.contact(selection.contactId)
          : Promise.resolve(null),
      ]);
      if (version !== generation) return;
      const [contactResult, crmResult, caseResult, masterResult] = results;
      if (contactResult.status !== 'fulfilled') {
        failed.value = true;
        loading.value = false;
        return;
      }
      contact.value = contactResult.value.data.payload;
      crm.value =
        crmResult.status === 'fulfilled' ? crmResult.value?.data : null;
      cases.value =
        caseResult.status === 'fulfilled'
          ? (caseResult.value.data.items || []).filter(
              item =>
                Number(item.contact_id) === Number(selection.contactId) ||
                (selection.callId &&
                  Number(item.call_session_id) === Number(selection.callId))
            )
          : [];
      unavailable.value = results
        .slice(1)
        .some(result => result.status === 'rejected');
      const companyId =
        masterResult.status === 'fulfilled'
          ? masterResult.value?.data?.payload?.company_id
          : null;
      if (enabled.master && companyId) {
        try {
          const response = await CustomerAPI.company(companyId);
          if (version !== generation) return;
          company.value = response.data.payload;
          addresses.value = response.data.addresses || [];
        } catch {
          if (version === generation) unavailable.value = true;
        }
      }
      if (version === generation) loading.value = false;
    },
    { immediate: true }
  );

  onBeforeUnmount(() => {
    generation += 1;
  });
  return {
    contact,
    company,
    addresses,
    crm,
    cases,
    loading,
    failed,
    unavailable,
  };
};
