<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useSipWebphone } from 'dashboard/routes/dashboard/webphone/useSipWebphone';
import { normalizeSipDialNumber } from 'dashboard/routes/dashboard/webphone/phoneNumber';
import { useCallsStore } from 'dashboard/stores/calls';
import { useWhatsappCallSession } from 'dashboard/composables/useWhatsappCallSession';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: Number, required: true },
  userId: { type: Number, required: true },
  allowed: { type: Boolean, default: false },
  qualificationPending: { type: Boolean, default: false },
  canLookup: { type: Boolean, default: false },
  initialPhone: { type: String, default: '' },
});
const emit = defineEmits(['started', 'close']);
const { t } = useI18n();
const sip = useSipWebphone();
const calls = useCallsStore();
const { isInitiating } = useWhatsappCallSession();
const dialog = ref(null);
const phone = ref(props.initialPhone);
const reason = ref('');
const observations = ref('');
const contacts = ref([]);
const contactId = ref('');
const busy = ref(false);
const failed = ref(false);
const contact = computed(() =>
  contacts.value.find(item => String(item.id) === contactId.value)
);
const sameAccount = computed(
  () => Number(sip.accountId.value) === props.accountId
);
const canDial = computed(
  () =>
    props.allowed &&
    sameAccount.value &&
    sip.registered.value &&
    sip.credential.value?.extension &&
    !sip.hasCall.value &&
    !calls.hasActiveCall &&
    !calls.hasIncomingCall &&
    !isInitiating.value &&
    !props.qualificationPending &&
    !busy.value &&
    reason.value.trim() &&
    /^\+?[\d\s().-]{2,30}$/.test(phone.value.trim()) &&
    normalizeSipDialNumber(phone.value)
);
watch(
  [phone, () => props.canLookup],
  ([number, allowed], _, cleanup) => {
    let current = true;
    let timer;
    contacts.value = [];
    contactId.value = '';
    cleanup(() => {
      current = false;
      clearTimeout(timer);
    });
    if (
      !allowed ||
      !/^\+?[\d\s().-]+$/.test(number) ||
      number.replace(/\D/g, '').length < 8
    )
      return;
    timer = setTimeout(async () => {
      try {
        const data = (
          await ContactCenterAPI.customerContext(props.accountId, number)
        ).data;
        if (!current || Number(data.account_id) !== props.accountId) return;
        contacts.value = data.contacts || [];
        if (!data.ambiguous && contacts.value.length === 1)
          contactId.value = String(contacts.value[0].id);
      } catch {
        /* Optional customer lookup does not block a manually reviewed destination. */
      }
    }, 350);
  },
  { immediate: true }
);
const dial = async () => {
  if (!canDial.value) return;
  const account = props.accountId;
  busy.value = true;
  failed.value = false;
  sip.destination.value = normalizeSipDialNumber(phone.value);
  try {
    const result = await sip.call();
    if (!sameAccount.value || account !== props.accountId) return;
    if (result === false || !sip.hasCall.value) {
      failed.value = true;
      return;
    }
    emit('started', {
      accountId: account,
      userId: props.userId,
      sessionId: sip.callId.value,
      phone: sip.destination.value,
      reason: reason.value.trim(),
      notes: observations.value.trim(),
    });
    dialog.value?.close();
  } catch {
    failed.value = true;
  } finally {
    busy.value = false;
  }
};
onMounted(() => dialog.value?.open());
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('VOICE_V4.NEW_CALL')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :dismissible="!busy"
    :close-on-click-outside="!busy"
    :show-close-button="!busy"
    @close="emit('close')"
  >
    <form class="space-y-4" @submit.prevent="dial">
      <label class="block text-sm"
        >{{ t('VOICE_V4.CONTACT') }}
        <select
          v-model="contactId"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1"
          :disabled="!contacts.length"
        >
          <option value="">{{ t('VOICE_V4.CUSTOMER_UNKNOWN') }}</option>
          <option
            v-for="item in contacts"
            :key="item.id"
            :value="String(item.id)"
          >
            {{ item.name }}
          </option>
        </select>
      </label>
      <label class="block text-sm"
        >{{ t('SOFTPHONE.CENTRAL.PHONE') }}
        <input
          v-model="phone"
          data-outbound-phone
          type="tel"
          required
          autocomplete="off"
          maxlength="30"
          :disabled="busy"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1"
        />
      </label>
      <label class="block text-sm"
        >{{ t('VOICE_V4.COMPANY') }}
        <input
          :value="contact?.company?.name || ''"
          readonly
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-alpha-2"
        />
      </label>
      <label class="block text-sm"
        >{{ t('VOICE_V4.SOURCE') }}
        <input
          data-outbound-source
          :value="sameAccount ? sip.credential.value?.extension || '' : ''"
          readonly
          required
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-alpha-2"
        />
        <span class="mt-1 block text-xs text-n-slate-10">{{
          t('VOICE_V4.SOURCE_HINT')
        }}</span>
      </label>
      <label class="block text-sm"
        >{{ t('VOICE_V4.REASON') }}
        <input
          v-model="reason"
          data-outbound-reason
          required
          maxlength="180"
          :disabled="busy"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1"
        />
      </label>
      <label class="block text-sm"
        >{{ t('VOICE_V4.OBSERVATIONS') }}
        <textarea
          v-model="observations"
          maxlength="700"
          rows="3"
          :disabled="busy"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1"
        />
      </label>
      <p class="text-xs text-n-slate-10">
        {{ t('VOICE_V4.OUTBOUND_PENDING') }}
      </p>
      <p v-if="failed" role="alert" class="text-sm text-n-ruby-11">
        {{ t('VOICE_V4.CALL_FAILED') }}
      </p>
      <div class="flex justify-end gap-3">
        <button
          type="button"
          class="min-h-11 rounded-lg border border-n-strong px-4"
          :disabled="busy"
          @click="dialog.close()"
        >
          {{ t('VOICE_V4.CANCEL') }}
        </button>
        <button
          type="submit"
          data-outbound-call
          :disabled="!canDial"
          class="min-h-11 rounded-lg bg-n-teal-9 px-5 font-semibold text-white shadow-[0_3px_0_0_rgba(0,0,0,0.2)] transition-transform duration-150 active:translate-y-0.5 active:duration-100 motion-reduce:transform-none motion-reduce:transition-none disabled:opacity-40"
          @click.prevent="dial"
        >
          {{ t('VOICE_V4.CALL') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
