<script setup>
import { ref, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import ContactsAPI from 'dashboard/api/contacts';
import { useCustomerMaster } from '../useCustomerMaster';
import { inputClass, buttonClass, errorMessage } from '../copy';
import { useFormDraft } from '../../crm/helpers/useFormDraft';

const props = defineProps({
  companyId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close', 'created']);
const { t } = useI18n();
const { enabled, canAccess } = useCustomerMaster();
const active = ref(true);
const busy = ref(false);
const error = ref('');
const candidates = ref([]);
const empty = () => ({
  name: '',
  email: '',
  phone_number: '',
  job_title: '',
  department: '',
});
const form = reactive(empty());
const draft = useFormDraft(
  'crm:new_contact:' + (props.companyId || 'standalone'),
  {
    active,
    snapshot: () => ({ ...form }),
    restore: value => Object.assign(form, value),
    reset: () => Object.assign(form, empty()),
  }
);
draft.open();
const close = () => {
  if (!busy.value) {
    draft.flush();
    active.value = false;
    emit('close');
  }
};
const created = (contact, savedKey = draft.key.value) => {
  draft.complete(savedKey);
  active.value = false;
  emit('created', contact);
};
const save = async () => {
  const savingDraftKey = draft.key.value;
  if (busy.value || (enabled.value && !canAccess.value)) return;
  busy.value = true;
  error.value = '';
  candidates.value = [];
  try {
    const { data } = enabled.value
      ? await API.saveContact({ ...form, company_id: props.companyId || null })
      : await ContactsAPI.create({
          name: form.name,
          email: form.email || undefined,
          phone_number: form.phone_number || undefined,
        });
    const contact = enabled.value ? data.payload : data.payload.contact;
    if (savingDraftKey !== draft.key.value) {
      draft.complete(savingDraftKey);
      return;
    }
    if (active.value) created(contact, savingDraftKey);
  } catch (err) {
    candidates.value =
      err.response?.data?.code === 'POSSIBLE_DUPLICATE'
        ? err.response.data.candidates || []
        : [];
    error.value = candidates.value.length
      ? t('CRM.CREATION.DUPLICATE_CONTACT')
      : errorMessage(err);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="active"
      class="fixed inset-0 z-[90] flex items-center justify-center bg-black/55 p-4"
      @click.self="close"
      @keydown.esc.stop="close"
    >
      <form
        role="dialog"
        aria-modal="true"
        :aria-label="t('CRM.CREATION.NEW_CONTACT')"
        class="max-h-[90vh] w-full max-w-lg space-y-4 overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-2 p-6 shadow-2xl"
        @submit.prevent="save"
      >
        <div class="flex items-center justify-between">
          <h3 class="text-xl font-bold">{{ t('CRM.CREATION.NEW_CONTACT') }}</h3>
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            :aria-label="t('CRM.CREATION.CLOSE')"
            @click="close"
          >
            <i class="i-lucide-x size-5" />
          </button>
        </div>
        <label class="block"
          >{{ t('CRM.CREATION.NAME')
          }}<input
            v-model="form.name"
            required
            maxlength="255"
            :class="inputClass"
        /></label>
        <label class="block"
          >{{ t('CRM.CREATION.EMAIL')
          }}<input
            v-model="form.email"
            type="email"
            :class="inputClass"
        /></label>
        <label class="block"
          >{{ t('CRM.CREATION.PHONE')
          }}<input
            v-model="form.phone_number"
            type="tel"
            :class="inputClass"
        /></label>
        <template v-if="enabled">
          <label class="block"
            >{{ t('CRM.CREATION.JOB_TITLE')
            }}<input
              v-model="form.job_title"
              :class="inputClass"
          /></label>
          <label class="block"
            >{{ t('CRM.CREATION.DEPARTMENT')
            }}<input
              v-model="form.department"
              :class="inputClass"
          /></label>
        </template>
        <p
          v-if="error"
          role="alert"
          class="text-n-ruby-11"
        >
          {{ error }}
        </p>
        <div
          v-if="candidates.length"
          class="max-h-48 overflow-y-auto rounded-lg border border-n-weak"
        >
          <button
            v-for="contact in candidates.filter(
              row => !companyId || String(row.company_id) === String(companyId)
            )"
            :key="contact.id"
            type="button"
            class="block w-full p-2 text-left"
            @click="created(contact)"
          >
            {{ contact.name }} · {{ contact.email || contact.phone_number }}
          </button>
        </div>
        <div class="flex justify-between gap-2">
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="draft.discard"
          >
            {{ t('CRM.CREATION.DISCARD') }}
          </button>
          <button
            type="submit"
            :class="buttonClass"
            :disabled="busy"
          >
            {{ t('CRM.CREATION.SAVE_CONTACT') }}
          </button>
        </div>
      </form>
    </div>
  </Teleport>
</template>
