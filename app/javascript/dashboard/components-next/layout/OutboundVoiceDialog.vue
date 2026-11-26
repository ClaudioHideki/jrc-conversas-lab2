<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import InboxVoicePanel from 'dashboard/routes/dashboard/inbox/InboxVoicePanel.vue';
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
const active = computed(
  () => props.allowed && sameAccount.value && sip.hasCall.value
);
const activeStatus = computed(() => {
  if (sip.incoming.value) return 'VOICE_V4.INCOMING';
  if (sip.held.value) return 'VOICE_V4.ON_HOLD';
  return sip.established.value ? 'VOICE_V4.CONNECTED' : 'VOICE_V4.DIALING';
});
watch(active, (isActive, wasActive) => {
  if (!isActive && wasActive) dialog.value?.close();
});
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
    :title="t(active ? 'VOICE_V4.BAR_LABEL' : 'VOICE_V4.NEW_CALL')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :dismissible="!busy"
    :close-on-click-outside="!busy"
    :show-close-button="!busy"
    overflow-y-auto
    @close="emit('close')"
  >
    <div
      v-if="active"
      data-outbound-active
      class="space-y-4 rounded-2xl border border-n-teal-5 bg-n-teal-2 p-4"
    >
      <div
        class="flex flex-wrap items-center justify-between gap-2"
        role="status"
      >
        <div>
          <p class="m-0 font-semibold text-n-teal-11">{{ t(activeStatus) }}</p>
          <p class="m-0 text-sm text-n-slate-11">
            {{
              sip.remoteNumber.value || t('SOFTPHONE.CENTRAL.UNKNOWN_CUSTOMER')
            }}
          </p>
        </div>
        <span
          v-if="sip.established.value"
          class="text-sm tabular-nums text-n-teal-11"
        >
          {{ sip.duration.value }}
        </span>
      </div>
      <InboxVoicePanel
        :account-id="accountId"
        :allowed="allowed"
        :qualification-pending="qualificationPending"
        session-view
        controls-only
        inline-controls
      />
    </div>
    <form v-else class="space-y-4" @submit.prevent="dial">
      <div
        class="space-y-3 rounded-2xl border border-n-blue-5 bg-gradient-to-br from-n-blue-2 to-n-teal-2 p-4 sm:p-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div
            class="flex items-center gap-2 text-sm font-medium text-n-blue-11"
          >
            <span class="grid size-8 place-items-center rounded-lg bg-n-blue-3">
              <span class="i-lucide-headset size-4" aria-hidden="true" />
            </span>
            <label for="outbound-extension">{{ t('VOICE_V4.SOURCE') }}</label>
          </div>
          <input
            id="outbound-extension"
            data-outbound-source
            :value="sameAccount ? sip.credential.value?.extension || '' : ''"
            readonly
            class="!m-0 w-24 rounded-lg !border-n-blue-5 bg-n-solid-1 px-2 py-1 text-center text-sm font-semibold tabular-nums text-n-blue-11"
          />
        </div>
        <label
          for="outbound-number"
          class="block text-sm font-semibold text-n-slate-12"
        >
          {{ t('SOFTPHONE.CENTRAL.PHONE') }}
        </label>
        <div
          class="flex items-center gap-1 rounded-xl border border-n-blue-6 bg-n-solid-1 px-1 shadow-sm focus-within:ring-2 focus-within:ring-n-blue-8"
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
            class="!m-0 min-w-0 flex-1 !border-0 !bg-transparent px-3 py-3 text-2xl font-semibold tabular-nums text-n-slate-12 !shadow-none focus:!ring-0"
          />
          <button
            type="button"
            data-outbound-backspace
            :disabled="busy || !phone"
            :aria-label="t('VOICE_V4.BACKSPACE')"
            class="grid size-10 shrink-0 place-items-center rounded-lg bg-n-blue-2 text-n-blue-11 hover:bg-n-blue-4 focus-visible:ring-2 focus-visible:ring-n-blue-8 disabled:opacity-40"
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
            class="min-h-11 rounded-xl border border-n-blue-5 bg-n-solid-1 text-lg font-semibold text-n-slate-12 shadow-sm hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-8 disabled:opacity-40"
            @click="pressTone(tone)"
          >
            {{ tone }}
          </button>
        </div>
      </div>
      <p class="m-0 text-xs text-n-slate-11">{{ t('VOICE_V4.SOURCE_HINT') }}</p>
      <details class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
        <summary class="cursor-pointer text-sm font-semibold text-n-blue-11">
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
          class="inline-flex min-h-11 items-center gap-2 rounded-xl bg-n-teal-9 px-5 font-semibold text-white shadow-sm hover:bg-n-teal-10 focus-visible:ring-2 focus-visible:ring-n-teal-8 disabled:opacity-40"
          @click.prevent="dial"
        >
          <span class="i-lucide-phone size-4" aria-hidden="true" />
          {{ t('VOICE_V4.CALL') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
