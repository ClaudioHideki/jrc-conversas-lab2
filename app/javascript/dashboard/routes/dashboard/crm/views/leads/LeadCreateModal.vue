<script setup>
import {
  computed,
  reactive,
  ref,
  watch,
  onMounted,
  onBeforeUnmount,
} from 'vue';
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
import productsAPI from 'dashboard/api/crm/products';
import AgentsAPI from 'dashboard/api/agents';
import InitialActivityFields from '../../components/shared/InitialActivityFields.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  contact: { type: Object, default: null },
  source: { type: String, default: '' },
});
const emit = defineEmits(['close', 'created']);
const store = useStore();
const { enabled: hasCustomerMaster, canAccess: canBrowseContacts } =
  useCustomerMaster();
const canSelectOwner = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const canSearch = computed(
  () => !hasCustomerMaster.value || canBrowseContacts.value
);
const companyId = ref(null);
const selectedContactId = ref(null);
const linkedContactId = computed(
  () => props.contact?.id || selectedContactId.value
);
const { t } = useI18n();
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

const products = ref([]);
const agents = ref([]);
const metadataError = ref('');
const loadOptions = async () => {
  metadataError.value = '';
  const requests = [
    productsAPI.list({ active: true }).then(({ data }) => {
      if (isCurrent()) products.value = data;
    }),
  ];
  if (canSelectOwner.value) {
    requests.push(
      AgentsAPI.get().then(({ data }) => {
        if (isCurrent()) agents.value = data;
      })
    );
  }
  const results = await Promise.allSettled(requests);
  if (isCurrent() && results.some(result => result.status === 'rejected'))
    metadataError.value = t('CRM.SALES_FLOW.OPTIONS_ERROR');
};
onMounted(loadOptions);

const ownerId = ref('');
const newQualification = () => ({
  product_id: '',
  product_interest: '',
  quantity: '',
  budget: '',
  deadline: '',
  segment: '',
  city: '',
  fields: [],
});
const qualification = reactive(newQualification());
const newActivity = () => ({
  activity_type: 'follow_up',
  due_at: '',
  title: '',
  description: '',
});
const activity = ref(newActivity());
const schedule = ref(false);
const inputClass =
  'mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-n-slate-12 read-only:bg-n-alpha-1';
const qualificationPayload = () => {
  const { budget, fields, ...values } = qualification;
  const product = products.value.find(item => item.id === values.product_id);
  return Object.fromEntries(
    Object.entries({
      ...values,
      product_interest: product?.name || values.product_interest,
      budget_cents: budget === '' ? '' : Math.round(Number(budget) * 100),
      fields: fields.filter(field => field.label.trim() && field.value.trim()),
    }).filter(
      ([, value]) => value !== '' && (!Array.isArray(value) || value.length)
    )
  );
};

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
    ownerId: ownerId.value,
    qualification: { ...qualification },
    activity: { ...activity.value },
    schedule: schedule.value,
  }),
  restore: value => {
    Object.assign(form, value.form || {});
    Object.assign(qualification, value.qualification || {});
    ownerId.value = value.ownerId || '';
    activity.value = { ...newActivity(), ...value.activity };
    schedule.value = Boolean(value.schedule);
    if (contact) {
      Object.assign(form, contactFields(contact), {
        company_name: initialForm.company_name,
      });
    } else {
      companyId.value = canBrowseContacts.value
        ? value.company_id || null
        : null;
      selectedContactId.value = canSearch.value
        ? value.contact_id || null
        : null;
      if (value.contact_id && !selectedContactId.value) clearPerson();
    }
  },
  reset: () => {
    Object.assign(form, initialForm);
    Object.assign(qualification, newQualification());
    ownerId.value = '';
    activity.value = newActivity();
    schedule.value = false;
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
const save = async event => {
  const savingDraftKey = draft.key.value;
  if (saving.value || !isCurrent()) return;
  const keepOpen = event?.submitter?.value === 'another' && !contact;
  if (!linkedContactId.value && !form.email.trim() && !form.phone.trim()) {
    errorMessage.value = t('CRM.LEAD_FORM.IDENTITY_HINT');
    return;
  }
  const leadQualification = qualificationPayload();
  errorMessage.value = '';
  saving.value = true;
  try {
    const { data, status } = await leadsAPI.create({
      lead: {
        ...form,
        ...(canSelectOwner.value && ownerId.value
          ? { owner_id: ownerId.value }
          : {}),
        ...(Object.keys(leadQualification).length
          ? { qualification: leadQualification }
          : {}),
        ...(hasCustomerMaster.value ? { company_id: companyId.value } : {}),
        ...(linkedContactId.value ? { contact_id: linkedContactId.value } : {}),
      },
      ...(schedule.value ? { next_activity: { ...activity.value } } : {}),
    });
    if (!isCurrent() || !draft.complete(savingDraftKey)) return;
    useAlert(
      status === 201 ? t('CRM.LEAD_FORM.SUCCESS') : t('CRM.LEAD_FORM.EXISTING')
    );
    if (keepOpen) draft.discard();
    else activeDraft.value = false;
    emit('created', data, { keepOpen });
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
      class="fixed inset-0 z-[80] flex items-center justify-center bg-slate-950/55 p-3 sm:p-5"
      @keydown.esc="close"
    >
      <form
        role="dialog"
        aria-modal="true"
        aria-labelledby="lead-create-title"
        class="flex max-h-[94dvh] w-full max-w-4xl flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-2xl"
        @submit.prevent="save"
      >
        <header
          class="flex items-center gap-3 border-b border-n-weak bg-gradient-to-r from-n-blue-3 to-n-solid-2 px-5 py-4"
        >
          <span
            class="grid size-11 shrink-0 place-items-center rounded-xl bg-n-blue-4 text-n-blue-11"
          >
            <i class="i-lucide-user-round-plus size-6" />
          </span>
          <div class="min-w-0 flex-1">
            <h3
              id="lead-create-title"
              class="text-xl font-bold text-n-slate-12"
            >
              {{ t('CRM.LEAD_FORM.TITLE') }}
            </h3>
            <p class="text-sm text-n-slate-11">
              {{ t('CRM.SALES_FLOW.LEAD_SUBTITLE') }}
            </p>
          </div>
          <button
            type="button"
            :disabled="saving"
            :aria-label="t('CRM.LEAD_FORM.CLOSE')"
            class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-2"
            @click="close"
          >
            <i class="i-lucide-x size-5" />
          </button>
        </header>

        <div
          class="min-h-0 space-y-4 overflow-y-auto px-5 py-4 text-n-slate-12"
        >
          <p
            v-if="contact"
            class="rounded-lg bg-n-blue-3 p-3 text-sm text-n-blue-11"
          >
            {{
              t('CRM.LEAD_FORM.LINKED_CONTACT', {
                name: form.name,
                id: contact.id,
              })
            }}
          </p>
          <div v-else-if="canSearch">
            <ContactPicker
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
            <p v-if="!linkedContactId" class="mt-2 text-xs text-n-slate-11">
              {{ t('CRM.SALES_FLOW.NEW_CONTACT_HINT') }}
            </p>
          </div>

          <section class="space-y-3 border-t border-n-weak pt-3">
            <h4 class="font-bold">{{ t('CRM.SALES_FLOW.ESSENTIALS') }}</h4>
            <div class="grid gap-3 text-sm sm:grid-cols-2">
              <label>
                {{ t('CRM.LEAD_FORM.NAME') }}
                <input
                  v-model.trim="form.name"
                  name="name"
                  required
                  :readonly="!!linkedContactId"
                  :class="inputClass"
                />
              </label>
              <div v-if="hasCustomerMaster && canBrowseContacts && !contact">
                <p class="mb-1">{{ t('CRM.LEAD_FORM.COMPANY') }}</p>
                <CompanyPicker
                  :model-value="companyId"
                  :disabled="saving"
                  @selected="selectCompany"
                />
              </div>
              <label v-else>
                {{ t('CRM.LEAD_FORM.COMPANY') }}
                <input
                  v-model.trim="form.company_name"
                  name="company_name"
                  :readonly="!!contact || !!companyId"
                  :class="inputClass"
                />
              </label>
              <label>
                {{ t('CRM.LEAD_FORM.PHONE') }}
                <input
                  v-model.trim="form.phone"
                  name="phone"
                  type="tel"
                  autocomplete="tel"
                  :readonly="!!linkedContactId"
                  :placeholder="t('CRM.LEAD_FORM.PHONE_HINT')"
                  :class="inputClass"
                />
              </label>
              <label>
                {{ t('CRM.LEAD_FORM.EMAIL') }}
                <input
                  v-model.trim="form.email"
                  name="email"
                  type="email"
                  autocomplete="email"
                  :readonly="!!linkedContactId"
                  :class="inputClass"
                />
              </label>
            </div>
            <p v-if="!linkedContactId" class="text-xs text-n-slate-11">
              {{ t('CRM.LEAD_FORM.IDENTITY_HINT') }}
            </p>
          </section>

          <section class="space-y-3 border-t border-n-weak pt-3">
            <h4 class="font-bold">{{ t('CRM.SALES_FLOW.COMMERCIAL') }}</h4>
            <div class="grid gap-3 text-sm sm:grid-cols-3">
              <label>
                {{ t('CRM.LEAD_FORM.SOURCE') }}
                <input
                  v-model.trim="form.source"
                  name="source"
                  :class="inputClass"
                />
              </label>
              <label v-if="canSelectOwner">
                {{ t('CRM.SALES_FLOW.OWNER') }}
                <select v-model="ownerId" :class="inputClass">
                  <option value="">
                    {{ t('CRM.SALES_FLOW.CURRENT_USER') }}
                  </option>
                  <option
                    v-for="agent in agents"
                    :key="agent.id"
                    :value="agent.id"
                  >
                    {{ agent.name || agent.email }}
                  </option>
                </select>
              </label>
              <label>
                {{ t('CRM.LEAD_FORM.STATUS') }}
                <select v-model="form.status" name="status" :class="inputClass">
                  <option value="new">
                    {{ t('CRM.INDICATORS.STATUS.NEW') }}
                  </option>
                  <option value="in_contact">
                    {{ t('CRM.INDICATORS.STATUS.IN_CONTACT') }}
                  </option>
                  <option value="qualified">
                    {{ t('CRM.INDICATORS.STATUS.QUALIFIED') }}
                  </option>
                </select>
              </label>
            </div>
            <details class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-3">
              <summary class="cursor-pointer font-semibold text-n-blue-11">
                {{ t('CRM.SALES_FLOW.QUALIFICATION') }}
              </summary>
              <div class="mt-3 grid gap-3 text-sm sm:grid-cols-2">
                <label v-if="products.length">
                  {{ t('CRM.SALES_FLOW.PRODUCT') }}
                  <select
                    v-model="qualification.product_id"
                    :class="inputClass"
                  >
                    <option value="">
                      {{ t('CRM.SALES_FLOW.NO_PRODUCT') }}
                    </option>
                    <option
                      v-for="product in products"
                      :key="product.id"
                      :value="product.id"
                    >
                      {{ product.name }}
                    </option>
                  </select>
                </label>
                <label v-if="!qualification.product_id">
                  {{ t('CRM.SALES_FLOW.INTEREST') }}
                  <input
                    v-model.trim="qualification.product_interest"
                    :class="inputClass"
                  />
                </label>
                <label>
                  {{ t('CRM.SALES_FLOW.QUANTITY') }}
                  <input
                    v-model.number="qualification.quantity"
                    type="number"
                    min="1"
                    :class="inputClass"
                  />
                </label>
                <label>
                  {{ t('CRM.SALES_FLOW.BUDGET') }}
                  <input
                    v-model.number="qualification.budget"
                    type="number"
                    min="0"
                    step="0.01"
                    :class="inputClass"
                  />
                </label>
                <label>
                  {{ t('CRM.SALES_FLOW.DEADLINE') }}
                  <input
                    v-model="qualification.deadline"
                    type="date"
                    :class="inputClass"
                  />
                </label>
              </div>
            </details>
          </section>

          <section class="space-y-3 border-t border-n-weak pt-3">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h4 class="font-bold">{{ t('CRM.SALES_FLOW.EXTRA') }}</h4>
              <button
                type="button"
                class="rounded-lg border border-n-blue-7 px-3 py-1.5 text-sm font-semibold text-n-blue-11"
                @click="qualification.fields.push({ label: '', value: '' })"
              >
                {{ t('CRM.SALES_FLOW.ADD_FIELD') }}
              </button>
            </div>
            <div class="grid gap-3 text-sm sm:grid-cols-2">
              <label>
                {{ t('CRM.SALES_FLOW.SEGMENT') }}
                <input
                  v-model.trim="qualification.segment"
                  :class="inputClass"
                />
              </label>
              <label>
                {{ t('CRM.SALES_FLOW.CITY') }}
                <input v-model.trim="qualification.city" :class="inputClass" />
              </label>
            </div>
            <div
              v-for="(field, index) in qualification.fields"
              :key="index"
              class="flex items-end gap-2 text-sm"
            >
              <label class="min-w-0 flex-1">
                {{ t('CRM.SALES_FLOW.FIELD_LABEL') }}
                <input
                  v-model.trim="field.label"
                  maxlength="80"
                  required
                  :class="inputClass"
                />
              </label>
              <label class="min-w-0 flex-1">
                {{ t('CRM.SALES_FLOW.FIELD_VALUE') }}
                <input
                  v-model.trim="field.value"
                  maxlength="500"
                  required
                  :class="inputClass"
                />
              </label>
              <button
                type="button"
                :aria-label="t('CRM.SALES_FLOW.REMOVE_FIELD')"
                class="rounded-lg p-2.5 text-n-ruby-11 hover:bg-n-ruby-3"
                @click="qualification.fields.splice(index, 1)"
              >
                <i class="i-lucide-trash-2 size-4" />
              </button>
            </div>
          </section>

          <section class="space-y-3 border-t border-n-weak pt-3">
            <label class="flex items-center gap-2 text-sm font-semibold">
              <input v-model="schedule" type="checkbox" />
              {{ t('CRM.SALES_FLOW.SCHEDULE') }}
            </label>
            <InitialActivityFields v-if="schedule" v-model="activity" />
            <label class="block text-sm">
              {{ t('CRM.LEAD_FORM.NOTES') }}
              <textarea
                v-model.trim="form.notes"
                name="notes"
                rows="2"
                :class="inputClass"
              />
            </label>
          </section>
          <p v-if="metadataError" role="status" class="text-sm text-n-amber-11">
            {{ metadataError }}
            <button
              type="button"
              class="font-semibold underline"
              @click="loadOptions"
            >
              {{ t('CRM.DEAL_CREATION.RETRY') }}
            </button>
          </p>
          <p
            v-if="errorMessage"
            role="alert"
            class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
          >
            {{ errorMessage }}
          </p>
        </div>

        <footer
          class="flex flex-wrap items-center justify-end gap-2 border-t border-n-weak bg-n-solid-2 px-5 py-3"
        >
          <button
            type="button"
            :disabled="saving"
            class="mr-auto px-2 py-2 text-sm text-n-slate-11"
            @click="draft.discard"
          >
            {{ t('CRM.CREATION.DISCARD') }}
          </button>
          <button
            type="button"
            :disabled="saving"
            class="rounded-lg border border-n-weak px-4 py-2 text-sm font-semibold"
            @click="close"
          >
            {{ t('CRM.CANCEL') }}
          </button>
          <button
            v-if="!contact"
            type="submit"
            value="another"
            :disabled="saving"
            class="rounded-lg border border-n-blue-8 px-4 py-2 text-sm font-semibold text-n-blue-11 disabled:opacity-50"
          >
            {{ t('CRM.SALES_FLOW.SAVE_ANOTHER') }}
          </button>
          <button
            type="submit"
            :disabled="saving"
            class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
          >
            {{ t(saving ? 'CRM.LEAD_FORM.SAVING' : 'CRM.LEAD_FORM.SAVE') }}
          </button>
        </footer>
      </form>
    </div>
  </Teleport>
</template>
