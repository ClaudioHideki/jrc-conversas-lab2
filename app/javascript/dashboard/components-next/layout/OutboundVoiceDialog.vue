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
const tones = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
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
const pressTone = tone => {
  if (
    !busy.value &&
    props.allowed &&
    sameAccount.value &&
    phone.value.length < 30
  )
    phone.value += tone;
};
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
    /^\+?[\d\s().-]{2,30}$/.test(phone.value.trim()) &&
    normalizeSipDialNumber(phone.value)
);
const dialBlocked = computed(() => {
  if (!props.allowed || !sameAccount.value) return 'VOICE_V4.DIAL_RESTRICTED';
  if (
    sip.hasCall.value ||
    calls.hasActiveCall ||
    calls.hasIncomingCall ||
    isInitiating.value
  )
    return 'VOICE_V4.CALL_ALREADY_ACTIVE';
  if (props.qualificationPending)
    return 'SOFTPHONE.INBOX.QUALIFICATION_PENDING';
  if (!sip.registered.value || !sip.credential.value?.extension)
    return 'VOICE_V4.EXTENSION_REQUIRED';
  return null;
});
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
    <form class="space-y-3" @submit.prevent="dial">
      <div
        class="space-y-3 rounded-xl bg-n-slate-12 p-4 text-n-slate-1 dark:bg-n-solid-3 dark:text-n-slate-12"
      >
        <div class="flex items-center justify-between gap-2 text-xs">
          <label for="outbound-extension" class="!text-white">{{
            t('VOICE_V4.SOURCE')
          }}</label>
          <input
            id="outbound-extension"
            data-outbound-source
            :value="sameAccount ? sip.credential.value?.extension || '' : ''"
            readonly
            class="w-20 rounded-md border-0 bg-n-alpha-2 px-2 py-1 text-right !text-white"
          />
        </div>
        <label
          for="outbound-number"
          class="block text-sm font-medium !text-white"
        >
          {{ t('SOFTPHONE.CENTRAL.PHONE') }}
        </label>
        <div
          class="flex items-center gap-1 rounded-lg border border-n-slate-8 bg-n-alpha-2"
        >
          <input
            id="outbound-number"
            v-model="phone"
            data-outbound-phone
            type="tel"
            inputmode="tel"
            required
            autocomplete="off"
            maxlength="30"
            :disabled="busy"
            class="min-w-0 flex-1 border-0 bg-transparent px-3 py-3 text-xl tabular-nums !text-white focus:ring-0"
          />
          <button
            type="button"
            data-outbound-backspace
            :disabled="busy || !phone"
            :aria-label="t('VOICE_V4.BACKSPACE')"
            class="grid size-11 shrink-0 place-items-center rounded-lg hover:bg-n-alpha-2 disabled:opacity-40"
            @click="phone = phone.slice(0, -1)"
          >
            <span class="i-lucide-delete size-5" aria-hidden="true" />
          </button>
        </div>
        <div
          class="grid grid-cols-3 gap-2"
          :aria-label="t('SOFTPHONE.CENTRAL.KEYPAD')"
        >
          <button
            v-for="tone in tones"
            :key="tone"
            type="button"
            :data-outbound-tone="tone"
            :disabled="busy || !allowed || !sameAccount"
            class="min-h-11 rounded-lg bg-n-alpha-2 text-lg hover:bg-n-alpha-3 focus-visible:outline focus-visible:outline-2 disabled:opacity-40"
            @click="pressTone(tone)"
          >
            {{ tone }}
          </button>
        </div>
      </div>
      <p class="m-0 text-xs text-n-slate-11">{{ t('VOICE_V4.SOURCE_HINT') }}</p>
      <details class="rounded-lg border border-n-weak p-3">
        <summary class="cursor-pointer text-sm font-medium">
          {{ t('VOICE_V4.CALL_DETAILS') }}
        </summary>
        <div class="mt-3 space-y-3">
          <label class="block text-sm"
            >{{ t('VOICE_V4.CONTACT') }}
            <select
              v-model="contactId"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1"
              :disabled="!contacts.length || busy"
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
          <p v-if="contact?.company?.name" class="text-xs text-n-slate-11">
            {{ t('VOICE_V4.COMPANY') }}: {{ contact.company.name }}
          </p>
          <label class="block text-sm"
            >{{ t('VOICE_V4.REASON') }}
            <input
              v-model="reason"
              data-outbound-reason
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
        </div>
      </details>
      <p class="text-xs text-n-slate-10">
        {{ t('VOICE_V4.OUTBOUND_PENDING') }}
      </p>
      <p v-if="failed" role="alert" class="text-sm text-n-ruby-11">
        {{ sip.errorMessage.value || t('VOICE_V4.CALL_FAILED') }}
      </p>
      <p
        v-if="dialBlocked"
        data-outbound-blocked
        role="status"
        class="rounded-lg bg-n-amber-2 p-3 text-xs text-n-amber-11"
      >
        {{ t(dialBlocked) }}
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
