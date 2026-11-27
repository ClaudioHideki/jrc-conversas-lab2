<script setup>
import {
  computed,
  defineAsyncComponent,
  onBeforeUnmount,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import API from 'dashboard/api/jrcContactCenter';
import Button from 'dashboard/components-next/button/Button.vue';
import { useCustomerMaster } from '../../jrcCustomers/useCustomerMaster';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
  callSessionId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  enabled: { type: Boolean, default: false },
});
const emit = defineEmits(['updated']);
const ContactPicker = defineAsyncComponent(
  () => import('../../jrcCustomers/components/ContactPicker.vue')
);
const { t } = useI18n();
const master = useCustomerMaster();
const actor = useMapGetter('getCurrentUserID');
const open = ref(false);
const busy = ref(false);
const source = ref(null);
const contactId = ref(null);
const confirmed = ref(false);
const error = ref('');
let generation = 0;
let controller;
const allowed = computed(
  () =>
    props.enabled &&
    master.canAccess.value &&
    String(master.accountId.value) === String(props.accountId)
);
const identity = computed(() =>
  JSON.stringify([
    props.accountId,
    props.recordingId,
    props.callSessionId,
    props.callId,
    actor.value,
    master.identity.value,
    allowed.value,
  ])
);
const labels = computed(() => ({
  OPEN: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.OPEN'),
  REFRESH: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.REFRESH'),
  EXPLICIT_ONLY: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.EXPLICIT_ONLY'),
  CONFIRM: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.CONFIRM'),
  HISTORY: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.HISTORY'),
  SAVE: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.SAVE'),
  CANCEL: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.CANCEL'),
  DENIED: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.DENIED'),
  ERROR: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.ERROR'),
  STALE: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.STALE'),
  SAVE_ERROR: t('JRC_CONTACT_CENTER.CUSTOMER_LINK.SAVE_ERROR'),
}));
const label = key => labels.value[key];
const clear = () => {
  generation += 1;
  controller?.abort();
  open.value = false;
  busy.value = false;
  source.value = null;
  contactId.value = null;
  confirmed.value = false;
  error.value = '';
};
const exactSource = data =>
  data?.contract_version === 1 &&
  data.account_id === String(props.accountId) &&
  data.user_id === String(actor.value) &&
  data.recording_id === String(props.recordingId) &&
  data.call_session_id === String(props.callSessionId) &&
  data.call_id === props.callId &&
  Number.isSafeInteger(data.lock_version) &&
  data.lock_version >= 0;
async function load() {
  if (!allowed.value || busy.value) return;
  clear();
  const own = generation;
  const original = identity.value;
  controller = new AbortController();
  busy.value = true;
  try {
    const { data } = await API.recordingCustomerLink(
      props.accountId,
      props.recordingId,
      { signal: controller.signal }
    );
    if (own !== generation || original !== identity.value) return;
    if (
      !exactSource(data) ||
      typeof data.can_link !== 'boolean' ||
      data.already_linked !== !data.can_link
    )
      throw new Error('native_customer_link_source_mismatch');
    if (!data.can_link) {
      emit('updated');
      return;
    }
    source.value = data;
    open.value = true;
  } catch (failure) {
    if (own !== generation) return;
    error.value = [401, 403, 404].includes(failure.response?.status)
      ? 'DENIED'
      : 'ERROR';
  } finally {
    if (own === generation) busy.value = false;
  }
}
async function save() {
  if (
    !allowed.value ||
    busy.value ||
    !source.value ||
    !contactId.value ||
    !confirmed.value
  )
    return;
  const own = generation;
  const original = identity.value;
  const selected = String(contactId.value);
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.linkRecordingCustomer(
      props.accountId,
      props.recordingId,
      {
        contact_id: selected,
        call_session_id: String(props.callSessionId),
        call_id: props.callId,
        lock_version: source.value.lock_version,
        confirm: true,
      }
    );
    if (own !== generation || original !== identity.value) return;
    if (
      !exactSource(data) ||
      data.contact_id !== selected ||
      data.lock_version !== source.value.lock_version + 1
    )
      throw new Error('native_customer_link_receipt_mismatch');
    clear();
    emit('updated');
  } catch (failure) {
    if (own !== generation) return;
    confirmed.value = false;
    if ([401, 403, 404].includes(failure.response?.status)) {
      clear();
      error.value = 'DENIED';
    } else {
      error.value = failure.response?.status === 409 ? 'STALE' : 'SAVE_ERROR';
      source.value = null;
    }
  } finally {
    if (own === generation) busy.value = false;
  }
}
watch(identity, clear, { flush: 'sync' });
watch(contactId, () => {
  confirmed.value = false;
});
onBeforeUnmount(clear);
</script>

<template>
  <div class="min-w-0">
    <section
      v-if="allowed"
      class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 p-3"
      data-recording-customer-link
    >
      <p class="text-sm text-n-slate-11">{{ label('EXPLICIT_ONLY') }}</p>
      <Button
        data-open-recording-customer-link
        :label="label(open ? 'REFRESH' : 'OPEN')"
        :disabled="busy"
        :is-loading="busy"
        @click="load"
      />
      <p v-if="error" role="alert" class="break-words text-sm text-n-ruby-11">
        {{ label(error) }}
      </p>
      <form v-if="open" class="min-w-0 space-y-3" @submit.prevent="save">
        <ContactPicker
          :key="identity"
          v-model="contactId"
          :disabled="busy || !source"
        />
        <label class="flex items-start gap-2 text-sm">
          <input
            v-model="confirmed"
            type="checkbox"
            data-confirm-recording-customer-link
            :disabled="busy || !source || !contactId"
            class="mt-1 h-4 w-4 shrink-0"
          />
          <span>{{ label('CONFIRM') }}</span>
        </label>
        <p class="text-xs text-n-slate-11">{{ label('HISTORY') }}</p>
        <div class="flex flex-wrap gap-2">
          <Button
            data-save-recording-customer-link
            type="submit"
            :label="label('SAVE')"
            :disabled="busy || !source || !contactId || !confirmed"
            :is-loading="busy"
          />
          <Button
            type="button"
            :label="label('CANCEL')"
            :disabled="busy"
            @click="clear"
          />
        </div>
      </form>
    </section>
  </div>
</template>
