<script setup>
import { computed, reactive, ref, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import ContactPicker from 'dashboard/routes/dashboard/jrcCustomers/components/ContactPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import { crmControlClasses } from '../../crmControlClasses';
import { useFormDraft } from '../../helpers/useFormDraft';
import { useI18n } from 'vue-i18n';
import { leadsAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  contact: { type: Object, default: null },
  source: { type: String, default: '' },
});
const emit = defineEmits(['close', 'created']);
const { enabled: hasCustomerMaster, canAccess: canBrowseContacts } =
  useCustomerMaster();
const companyId = ref(null);
const selectedContactId = ref(null);
const linkedContactId = computed(
  () => props.contact?.id || selectedContactId.value
);
const { t } = useI18n();
const store = useStore();
const route = useRoute();
const identity = () =>
  `${route.params.accountId}:${authorityScope(store.getters)}`;
const initialIdentity = identity();
const invalidated = ref(false);
let disposed = false;
const isCurrent = () =>
  !disposed && !invalidated.value && identity() === initialIdentity;
onBeforeUnmount(() => {
  disposed = true;
});
const saving = ref(false);
const errorMessage = ref('');
const contact = props.contact;
companyId.value = contact?.company_id || contact?.companyId || null;
const contactFields = person => ({
  name:
    person?.name?.trim() ||
    person?.email ||
    person?.phone_number ||
    person?.phoneNumber ||
    (person?.id ? t('CRM.LEAD_FORM.CONTACT_FALLBACK', { id: person.id }) : ''),
  email: person?.email || '',
  phone: person?.phoneNumber || person?.phone_number || '',
});
const form = reactive({
  ...contactFields(contact),
  company_name:
    contact?.company?.name ||
    contact?.companyName ||
    contact?.additionalAttributes?.companyName ||
    contact?.additional_attributes?.company_name ||
    '',
  source: props.source,
  status: 'new',
  temperature: 'warm',
  notes: '',
});

const activeDraft = ref(true);
const initialForm = { ...form };
const initialCompany = companyId.value;
const clearPerson = () => {
  selectedContactId.value = null;
  Object.assign(form, contactFields(null));
};
const selectCompany = company => {
  companyId.value = company?.id || null;
  form.company_name = company?.name || '';
  if (selectedContactId.value) clearPerson();
};
const selectPerson = person => {
  errorMessage.value = '';
  if (!person) {
    clearPerson();
    return;
  }
  selectedContactId.value = person.id;
  Object.assign(form, contactFields(person));
  if (!companyId.value && person.company_id) {
    companyId.value = person.company_id;
    form.company_name = person.company_name || '';
  }
};
const draft = useFormDraft('crm:new_lead:' + (contact?.id || 'standalone'), {
  active: activeDraft,
  snapshot: () => ({
    form: { ...form },
    company_id: companyId.value,
    contact_id: selectedContactId.value,
  }),
  restore: value => {
    Object.assign(form, value.form || {});
    if (contact) {
      Object.assign(form, contactFields(contact), {
        company_name: initialForm.company_name,
      });
    } else {
      companyId.value = canBrowseContacts.value
        ? value.company_id || null
        : null;
      selectedContactId.value = canBrowseContacts.value
        ? value.contact_id || null
        : null;
      if (value.contact_id && !selectedContactId.value) clearPerson();
    }
  },
  reset: () => {
    Object.assign(form, initialForm);
    companyId.value = initialCompany;
    selectedContactId.value = null;
  },
});
draft.open();
watch(
  identity,
  () => {
    if (invalidated.value) return;
    draft.flush();
    activeDraft.value = false;
    invalidated.value = true;
    errorMessage.value = '';
    saving.value = false;
    emit('close');
  },
  { flush: 'sync' }
);
const close = () => {
  if (!saving.value) {
    draft.flush();
    activeDraft.value = false;
    emit('close');
  }
};
const save = async () => {
  const savingDraftKey = draft.key.value;
  if (saving.value || !isCurrent()) return;
  errorMessage.value = '';
  saving.value = true;
  try {
    const { data, status } = await leadsAPI.create({
      lead: {
        ...form,
        ...(hasCustomerMaster.value ? { company_id: companyId.value } : {}),
        ...(linkedContactId.value ? { contact_id: linkedContactId.value } : {}),
      },
    });
    if (!isCurrent() || !draft.complete(savingDraftKey)) return;
    useAlert(
      status === 201 ? t('CRM.LEAD_FORM.SUCCESS') : t('CRM.LEAD_FORM.EXISTING')
    );
    activeDraft.value = false;
    emit('created', data);
  } catch (error) {
    if (!isCurrent()) return;
    const errors = error.response?.data?.errors;
    errorMessage.value =
      [409, 422].includes(error.response?.status) && Array.isArray(errors)
        ? errors.join(', ')
        : t('CRM.LEAD_FORM.ERROR');
  } finally {
    if (isCurrent()) saving.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="!invalidated"
      :class="crmControlClasses"
      class="fixed inset-0 z-[80] flex items-center justify-center bg-black/55 p-4"
      @keydown.esc="close"
    >
      <form
        role="dialog"
        aria-modal="true"
        aria-labelledby="lead-create-title"
        class="max-h-[90dvh] w-full max-w-2xl space-y-4 overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-2xl sm:p-6"
        @submit.prevent="save"
      >
        <div class="flex items-center justify-between">
          <h3 id="lead-create-title" class="text-xl font-bold text-n-slate-12">
            {{ t('CRM.LEAD_FORM.TITLE') }}
          </h3>
          <button
            type="button"
            :disabled="saving"
            :aria-label="t('CRM.LEAD_FORM.CLOSE')"
            class="rounded-lg p-2 text-n-slate-11"
            @click="close"
          >
            <i class="i-lucide-x size-5" />
          </button>
        </div>
        <p
          v-if="contact"
          class="rounded-xl bg-n-blue-3 p-3 text-sm text-n-blue-11"
        >
          {{
            t('CRM.LEAD_FORM.LINKED_CONTACT', {
              name: form.name,
              id: contact.id,
            })
          }}
        </p>
        <div class="grid gap-3 sm:grid-cols-2">
          <div
            v-if="hasCustomerMaster && canBrowseContacts && !contact"
            class="min-w-0 text-sm text-n-slate-11"
          >
            <p class="mb-1">{{ t('CRM.LEAD_FORM.COMPANY') }}</p>
            <CompanyPicker
              :model-value="companyId"
              :disabled="saving"
              @selected="selectCompany"
            />
          </div>
          <label v-else class="text-sm text-n-slate-11">
            <span class="block">{{ t('CRM.LEAD_FORM.COMPANY') }}</span
            ><input
              v-model="form.company_name"
              name="company_name"
              :readonly="!!contact || !!companyId"
              class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          /></label>
          <div
            v-if="!contact && canBrowseContacts"
            class="min-w-0 text-sm text-n-slate-11"
          >
            <p class="mb-1">
              {{
                t(
                  companyId
                    ? 'CRM.LEAD_FORM.COMPANY_CONTACT'
                    : 'CRM.LEAD_FORM.EXISTING_CONTACT'
                )
              }}
            </p>
            <ContactPicker
              :key="companyId ?? 'unscoped'"
              :model-value="selectedContactId"
              :company-id="companyId"
              :disabled="saving"
              browse-company
              @selected="selectPerson"
              @update:model-value="
                id => {
                  if (!id && selectedContactId) clearPerson();
                }
              "
            />
          </div>
          <label class="text-sm text-n-slate-11">
            <span class="block">{{ t('CRM.LEAD_FORM.NAME') }}</span>
            <input
              v-model="form.name"
              name="name"
              required
              :readonly="!!linkedContactId"
              class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12 read-only:bg-n-alpha-1"
            />
          </label>
          <label class="text-sm text-n-slate-11">
            <span class="block">{{ t('CRM.LEAD_FORM.SOURCE') }}</span
            ><input
              v-model="form.source"
              name="source"
              class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          /></label>
          <label class="text-sm text-n-slate-11">
            <span class="block">{{ t('CRM.LEAD_FORM.EMAIL') }}</span
            ><input
              v-model="form.email"
              name="email"
              type="email"
              :readonly="!!linkedContactId"
              class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12 read-only:bg-n-alpha-1"
          /></label>
          <label class="text-sm text-n-slate-11">
            <span class="block">{{ t('CRM.LEAD_FORM.PHONE') }}</span
            ><input
              v-model="form.phone"
              name="phone"
              type="tel"
              :readonly="!!linkedContactId"
              :placeholder="t('CRM.LEAD_FORM.PHONE_HINT')"
              class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12 read-only:bg-n-alpha-1"
          /></label>
        </div>
        <label class="block text-sm text-n-slate-11">
          <span class="block">{{ t('CRM.LEAD_FORM.STATUS') }}</span>
          <select
            v-model="form.status"
            name="status"
            class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          >
            <option value="new">{{ t('CRM.INDICATORS.STATUS.NEW') }}</option>
            <option value="in_contact">
              {{ t('CRM.INDICATORS.STATUS.IN_CONTACT') }}
            </option>
            <option value="qualified">
              {{ t('CRM.INDICATORS.STATUS.QUALIFIED') }}
            </option>
          </select>
        </label>
        <label class="block text-sm text-n-slate-11">
          <span class="block">{{ t('CRM.LEAD_FORM.NOTES') }}</span
          ><textarea
            v-model="form.notes"
            name="notes"
            rows="3"
            class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          />
        </label>
        <p v-if="!linkedContactId" class="text-xs text-n-slate-11">
          {{ t('CRM.LEAD_FORM.IDENTITY_HINT') }}
        </p>
        <p
          v-if="errorMessage"
          role="alert"
          class="rounded-xl bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
        >
          {{ errorMessage }}
        </p>
        <div class="flex justify-end gap-2">
          <button
            type="button"
            :disabled="saving"
            class="mr-auto rounded-xl border border-n-weak px-3 py-2"
            @click="draft.discard"
          >
            {{ t('CRM.CREATION.DISCARD') }}
          </button>
          <button
            type="button"
            :disabled="saving"
            class="rounded-xl border border-n-weak px-4 py-2.5 font-semibold text-n-slate-12 disabled:opacity-50"
            @click="close"
          >
            {{ t('CRM.CANCEL') }}
          </button>
          <button
            type="submit"
            :disabled="saving"
            class="rounded-xl bg-n-brand px-5 py-2.5 font-semibold text-white disabled:opacity-50"
          >
            {{ saving ? t('CRM.LEAD_FORM.SAVING') : t('CRM.LEAD_FORM.SAVE') }}
          </button>
        </div>
      </form>
    </div>
  </Teleport>
</template>
