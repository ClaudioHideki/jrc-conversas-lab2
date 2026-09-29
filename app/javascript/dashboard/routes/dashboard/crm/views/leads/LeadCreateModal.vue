<script setup>
import { crmControlClasses } from '../../crmControlClasses';
import { reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { leadsAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';

const props = defineProps({ contact: { type: Object, default: null } });
const emit = defineEmits(['close', 'created']);
const { t } = useI18n();
const saving = ref(false);
const errorMessage = ref('');
const contact = props.contact;
const form = reactive({
  name: contact?.name || '',
  company_name:
    contact?.company?.name ||
    contact?.companyName ||
    contact?.additionalAttributes?.companyName ||
    contact?.additional_attributes?.company_name ||
    '',
  email: contact?.email || '',
  phone: contact?.phoneNumber || contact?.phone_number || '',
  source: '',
  status: 'new',
  temperature: 'warm',
  notes: '',
});

const close = () => {
  if (!saving.value) emit('close');
};
const save = async () => {
  if (saving.value) return;
  errorMessage.value = '';
  saving.value = true;
  try {
    const { data, status } = await leadsAPI.create({
      lead: { ...form, ...(contact ? { contact_id: contact.id } : {}) },
    });
    useAlert(
      status === 201 ? t('CRM.LEAD_FORM.SUCCESS') : t('CRM.LEAD_FORM.EXISTING')
    );
    emit('created', data);
  } catch (error) {
    const errors = error.response?.data?.errors;
    errorMessage.value =
      [409, 422].includes(error.response?.status) && Array.isArray(errors)
        ? errors.join(', ')
        : t('CRM.LEAD_FORM.ERROR');
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      :class="crmControlClasses" class="fixed inset-0 z-[80] flex items-center justify-center bg-black/55 p-4"
      @click.self="close"
      @keydown.esc="close"
    >
      <form
        role="dialog"
        aria-modal="true"
        aria-labelledby="lead-create-title"
        class="max-h-[90vh] w-full max-w-lg space-y-4 overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-2 p-6 shadow-2xl"
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
              name: contact.name,
              id: contact.id,
            })
          }}
        </p>
        <label class="block text-sm text-n-slate-11">
          <span class="block">{{ t('CRM.LEAD_FORM.NAME') }}</span>
          <input
            v-model="form.name"
            name="name"
            required
            class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          />
        </label>
        <div class="grid gap-3 sm:grid-cols-2">
          <label class="text-sm text-n-slate-11">
            <span class="block">{{ t('CRM.LEAD_FORM.COMPANY') }}</span
            ><input
              v-model="form.company_name"
              name="company_name"
              class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          /></label>
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
              class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
          /></label>
          <label class="text-sm text-n-slate-11">
            <span class="block">{{ t('CRM.LEAD_FORM.PHONE') }}</span
            ><input
              v-model="form.phone"
              name="phone"
              type="tel"
              :placeholder="t('CRM.LEAD_FORM.PHONE_HINT')"
              class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-n-slate-12"
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
        <p v-if="!contact" class="text-xs text-n-slate-11">
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
