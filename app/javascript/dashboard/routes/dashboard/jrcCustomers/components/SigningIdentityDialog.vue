<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { buttonClass, inputClass } from '../copy';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close', 'updated']);
const { t } = useI18n();
const copy = key => t(`CRM.CUSTOMER_SIGNING_IDENTITY.${key}`);
const { accountId, canAccess } = useCustomerMaster();
const user = useMapGetter('getCurrentUser');
const dialog = ref(null);
const contact = ref(null);
const identifier = ref('');
const revision = ref(0);
const loading = ref(false);
const saving = ref(false);
const error = ref('');
const notice = ref('');
const original = ref('');
let generation = 0;
let controller;
const identity = computed(
  () =>
    `${accountId.value}:${user.value?.id}:${props.contactId}:${canAccess.value}`
);
const busy = computed(() => loading.value || saving.value);
const changed = computed(() => identifier.value !== original.value);
const clear = () => {
  contact.value = null;
  identifier.value = '';
  original.value = '';
  revision.value = 0;
};
const apply = data => {
  contact.value = data.contact;
  identifier.value = data.payload.personal_tax_identifier || '';
  original.value = identifier.value;
  revision.value = data.payload.revision;
};
const failureMessage = failure => {
  const status = failure.response?.status;
  if ([401, 403, 404].includes(status)) return copy('DENIED');
  if (status === 409) return copy('CHANGED');
  if (failure.response?.data?.code === 'IDENTITY_UNAVAILABLE')
    return copy('UNAVAILABLE');
  return copy(status === 422 ? 'INVALID' : 'ERROR');
};
const load = async () => {
  generation += 1;
  const current = generation;
  controller?.abort();
  controller = new AbortController();
  clear();
  error.value = '';
  notice.value = '';
  loading.value = true;
  saving.value = false;
  if (!canAccess.value) {
    loading.value = false;
    emit('close');
    return;
  }
  try {
    const { data } = await API.signingIdentity(
      accountId.value,
      props.contactId,
      { signal: controller.signal }
    );
    if (current === generation) apply(data);
  } catch (failure) {
    if (current === generation) error.value = failureMessage(failure);
  } finally {
    if (current === generation) loading.value = false;
  }
};
const save = async () => {
  if (busy.value || !contact.value || !canAccess.value) return;
  const current = generation;
  const selectedAccount = accountId.value;
  const selectedContact = props.contactId;
  saving.value = true;
  error.value = '';
  notice.value = '';
  try {
    const { data } = await API.saveSigningIdentity(
      selectedAccount,
      selectedContact,
      {
        identity: { personal_tax_identifier: identifier.value },
        revision: revision.value,
      }
    );
    if (current !== generation) return;
    apply(data);
    notice.value = copy('SAVED');
    emit('updated');
  } catch (failure) {
    if (current === generation) {
      if ([401, 403, 404].includes(failure.response?.status)) clear();
      error.value = failureMessage(failure);
    }
  } finally {
    if (current === generation) saving.value = false;
  }
};
watch(identity, load, { immediate: true });
onMounted(() => dialog.value.open());
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  clear();
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="lg"
    :title="copy('TITLE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!saving"
    @close="emit('close')"
  >
    <form
      class="space-y-4"
      :aria-busy="busy"
      @submit.prevent="save"
    >
      <p
        class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
      >
        {{ copy('AUTHORITY_NOTE') }}
      </p>
      <p
        v-if="loading"
        role="status"
        class="text-sm text-n-slate-11"
      >
        {{ copy('LOADING') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="rounded-lg border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
      >
        {{ error }}
      </p>
      <p
        v-if="notice"
        role="status"
        class="rounded-lg border border-n-teal-6 bg-n-teal-3 p-3 text-sm text-n-teal-12"
      >
        {{ notice }}
      </p>
      <template v-if="contact">
        <div class="rounded-lg border border-n-weak p-3 text-sm">
          <p class="font-semibold">{{ contact.name }}</p>
          <p class="mt-1 text-n-slate-11">
            {{ contact.company_name || copy('UNLINKED') }}
          </p>
        </div>
        <label class="block text-sm font-semibold">
          <span>{{ copy('CPF') }}</span>
          <input
            v-model="identifier"
            name="personal_tax_identifier"
            required
            inputmode="numeric"
            maxlength="14"
            autocomplete="off"
            :disabled="busy"
            :class="inputClass"
          />
        </label>
        <p class="text-xs text-n-slate-11">{{ copy('HELP') }}</p>
      </template>
      <div class="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="load"
        >
          {{ copy('REFRESH') }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          :disabled="saving"
          @click="dialog.close()"
        >
          {{ copy('CLOSE') }}
        </button>
        <button
          type="submit"
          :disabled="busy || !contact || !changed || !identifier"
          class="rounded-lg bg-n-blue-9 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          {{ copy('SAVE') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
