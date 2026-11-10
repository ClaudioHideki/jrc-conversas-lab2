<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import api from 'dashboard/api/crm/backofficeSigners';
import SignerContactPicker from './SignerContactPicker.vue';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  requestId: { type: [String, Number], required: true },
  contextKey: { type: String, required: true },
  overview: { type: Object, required: true },
});
const emit = defineEmits(['close', 'saved', 'denied', 'refresh']);
const { text } = useBackofficePresentation();
const dialog = ref(null);
const party = ref('customer');
const modes = ref({
  customer: props.overview.current?.customer_mode || 'single',
  issuer: props.overview.current?.issuer_mode || 'single',
});
const people = ref([...(props.overview.current?.signers || [])]);
const reason = ref('');
const saving = ref(false);
const error = ref('');
const stale = ref(false);
const controller = new AbortController();
let active = true;
let intent;
const selected = computed(() =>
  people.value.filter(item => item.party === party.value)
);
const validParties = computed(() =>
  ['customer', 'issuer'].every(side => {
    const count = people.value.filter(item => item.party === side).length;
    return modes.value[side] === 'single'
      ? count === 1
      : count >= 2 && count <= 10;
  })
);
const canSave = computed(
  () =>
    validParties.value &&
    reason.value.trim().length > 0 &&
    !saving.value &&
    !stale.value
);
const choose = person => {
  if (
    saving.value ||
    stale.value ||
    people.value.some(item => item.contact_id === person.id)
  )
    return;
  if (modes.value[party.value] === 'single')
    people.value = people.value.filter(item => item.party !== party.value);
  if (selected.value.length >= 10) return;
  people.value.push({
    contact_id: person.id,
    party: party.value,
    name: person.name,
    email: person.email,
    personal_tax_identifier_masked: person.personal_tax_identifier_masked,
  });
};
const remove = person => {
  people.value = people.value.filter(item => item !== person);
};
const save = async () => {
  if (!canSave.value) return;
  const payload = {
    customer_mode: modes.value.customer,
    issuer_mode: modes.value.issuer,
    signers: people.value.map(item => ({
      contact_id: item.contact_id,
      party: item.party,
    })),
    expected_revision: props.overview.current?.revision || 0,
    expected_source_digest: props.overview.contract.source_digest,
    change_reason: reason.value.trim(),
  };
  const input = JSON.stringify(payload);
  if (intent?.input !== input) intent = { input, key: crypto.randomUUID() };
  payload.idempotency_key = intent.key;
  saving.value = true;
  error.value = '';
  try {
    const { data } = await api.create(
      props.accountId,
      props.requestId,
      payload,
      { signal: controller.signal }
    );
    if (!active) return;
    if (!data?.id || !data.revision)
      throw new Error('Signer proposal was not acknowledged');
    intent = null;
    emit('saved');
  } catch (failure) {
    if (!active) return;
    const status = failure.response?.status;
    if ([401, 403, 404].includes(status)) {
      people.value = [];
      reason.value = '';
      emit('denied');
    } else if (status === 409) {
      stale.value = true;
      error.value = text('CONTRACT_SIGNERS.CHANGED');
    } else {
      error.value =
        failure.response?.data?.message || text('CONTRACT_SIGNERS.ERROR');
    }
  } finally {
    if (active) saving.value = false;
  }
};
onMounted(() => dialog.value.open());
onBeforeUnmount(() => {
  active = false;
  controller.abort();
  people.value = [];
  reason.value = '';
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    :title="text('CONTRACT_SIGNERS.EDIT')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!saving"
    @close="emit('close')"
  >
    <form class="space-y-4" :aria-busy="saving" @submit.prevent="save">
      <p
        class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
      >
        {{ text('CONTRACT_SIGNERS.AUTHORITY_NOTE') }}
      </p>
      <div
        class="flex gap-2"
        role="group"
        :aria-label="text('CONTRACT_SIGNERS.PARTY')"
      >
        <button
          v-for="side in ['customer', 'issuer']"
          :key="side"
          type="button"
          :disabled="saving"
          :aria-pressed="party === side"
          class="rounded-lg border px-4 py-2 text-sm font-semibold disabled:opacity-50"
          :class="
            party === side
              ? 'border-n-blue-8 bg-n-blue-9 text-white'
              : 'border-n-violet-6 bg-n-violet-3 text-n-violet-12'
          "
          @click="party = side"
        >
          {{ text(`CONTRACT_SIGNERS.PARTIES.${side}`) }}
        </button>
      </div>
      <label class="block text-sm font-semibold">
        <span>{{ text('CONTRACT_SIGNERS.MODE') }}</span>
        <select
          v-model="modes[party]"
          :disabled="saving || stale"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm text-n-slate-12"
        >
          <option value="single">
            {{ text('CONTRACT_SIGNERS.MODES.single') }}
          </option>
          <option value="joint">
            {{ text('CONTRACT_SIGNERS.MODES.joint') }}
          </option>
        </select>
      </label>
      <p class="text-xs text-n-slate-11">
        {{ text('CONTRACT_SIGNERS.JOINT_HELP') }}
      </p>
      <ul class="space-y-2">
        <li
          v-for="person in selected"
          :key="person.contact_id"
          class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-n-violet-6 bg-n-violet-3 p-3 text-sm"
        >
          <div class="min-w-0">
            <b class="block">{{ person.name }}</b>
            <span class="block break-all">{{ person.email }}</span>
            <span class="text-xs text-n-slate-11">{{
              [
                person.personal_tax_identifier_masked,
                text('CONTRACT_SIGNERS.REQUIRED'),
              ].join(' · ')
            }}</span>
          </div>
          <button
            type="button"
            :disabled="saving || stale"
            class="rounded-lg border border-n-ruby-6 bg-n-ruby-3 px-3 py-2 text-n-ruby-12 disabled:opacity-50"
            @click="remove(person)"
          >
            {{ text('CONTRACT_SIGNERS.REMOVE') }}
          </button>
        </li>
      </ul>
      <SignerContactPicker
        :account-id="accountId"
        :request-id="requestId"
        :context-key="contextKey"
        :party="party"
        :disabled="saving || stale"
        :selected-ids="people.map(item => item.contact_id)"
        @choose="choose"
        @denied="emit('denied')"
      />
      <label class="block text-sm font-semibold">
        <span>{{ text('CONTRACT_VERSIONS.REASON') }}</span>
        <textarea
          v-model="reason"
          required
          maxlength="2000"
          rows="3"
          :disabled="saving || stale"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm text-n-slate-12"
        />
      </label>
      <p class="text-xs text-n-slate-11">
        {{ text('CONTRACT_SIGNERS.VERSION_HELP') }}
      </p>
      <p v-if="!validParties" role="status" class="text-sm text-n-amber-12">
        {{ text('CONTRACT_SIGNERS.INCOMPLETE') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
      >
        {{ error }}
      </p>
      <div class="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          :disabled="saving"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          @click="dialog.close()"
        >
          {{ text('CONTRACT_SIGNERS.CLOSE') }}
        </button>
        <button
          v-if="stale"
          type="button"
          class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-n-blue-12"
          @click="emit('refresh')"
        >
          {{ text('REFRESH') }}
        </button>
        <button
          type="submit"
          :disabled="!canSave"
          class="rounded-lg bg-n-blue-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
        >
          {{ text('CONTRACT_SIGNERS.SAVE') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
