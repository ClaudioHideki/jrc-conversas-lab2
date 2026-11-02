<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import api from 'dashboard/api/crm/backofficeAuthorities';
import AuthorityDocumentPicker from './AuthorityDocumentPicker.vue';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  requestId: { type: [String, Number], required: true },
  overview: { type: Object, required: true },
});
const emit = defineEmits(['close', 'saved', 'denied']);
const { text } = useBackofficePresentation();
const dialog = ref(null);
const people = ref([...props.overview.signers.signers]);
const proofs = ref(
  people.value.map(person => {
    const previous = props.overview.current?.proposal.proofs.find(
      row => row.signer_key === person.key
    );
    return previous
      ? JSON.parse(JSON.stringify(previous))
      : {
          signer_key: person.key,
          basis: '',
          reason: '',
          valid_from: '',
          valid_until: '',
          no_expiry: false,
          document_version_ids: [],
        };
  })
);
const index = ref(0);
const current = computed(() => proofs.value[index.value]);
const reason = ref('');
const saving = ref(false);
const stale = ref(false);
const error = ref('');
const controller = new AbortController();
let active = true;
let intent;
const valid = computed(
  () =>
    reason.value.trim() &&
    proofs.value.length === people.value.length &&
    proofs.value.every(
      row =>
        row.basis &&
        row.reason.trim() &&
        row.document_version_ids.length &&
        row.valid_from &&
        (row.no_expiry || row.valid_until)
    )
);
const choose = row => {
  if (
    !current.value.document_version_ids.includes(row.id) &&
    current.value.document_version_ids.length < 10
  )
    current.value.document_version_ids.push(row.id);
};
const remove = id => {
  current.value.document_version_ids =
    current.value.document_version_ids.filter(value => value !== id);
};
const deny = () => {
  people.value = [];
  proofs.value = [];
  reason.value = '';
  emit('denied');
};
const save = async () => {
  if (!valid.value || saving.value || stale.value) return;
  const payload = {
    version_id: props.overview.version.id,
    expected_source_digest: props.overview.version.source_digest,
    expected_revision: props.overview.current?.proposal.revision || 0,
    change_reason: reason.value.trim(),
    proofs: proofs.value.map(row => ({
      ...row,
      reason: row.reason.trim(),
      valid_until: row.no_expiry ? null : row.valid_until,
    })),
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
    if (!data?.proposal?.id || !data?.status?.requests?.length)
      throw new Error('Representation case was not acknowledged');
    intent = null;
    emit('saved');
  } catch (failure) {
    if (!active) return;
    const status = failure.response?.status;
    const code = failure.response?.data?.code;
    if ([401, 403, 404].includes(status)) deny();
    else if (code === 'POLICY_REQUIRED')
      error.value = text('CONTRACT_AUTHORITY.POLICY_REQUIRED');
    else if (status === 409) {
      stale.value = true;
      error.value = text('CONTRACT_AUTHORITY.CHANGED');
    } else
      error.value =
        failure.response?.data?.message || text('CONTRACT_AUTHORITY.ERROR');
  } finally {
    if (active) saving.value = false;
  }
};
onMounted(() => dialog.value.open());
onBeforeUnmount(() => {
  active = false;
  controller.abort();
  people.value = [];
  proofs.value = [];
  reason.value = '';
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="3xl"
    :title="text('CONTRACT_AUTHORITY.PROPOSE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :dismissible="!saving"
    contained
    show-close-button
    @close="emit('close')"
  >
    <form class="space-y-4" :aria-busy="saving" @submit.prevent="save">
      <p
        class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
      >
        {{ text('CONTRACT_AUTHORITY.NOTE') }}
      </p>
      <fieldset :disabled="saving || stale" class="space-y-4">
        <div
          class="flex gap-2 overflow-x-auto"
          role="group"
          :aria-label="text('CONTRACT_AUTHORITY.PEOPLE')"
        >
          <button
            v-for="(person, position) in people"
            :key="person.key"
            type="button"
            :aria-pressed="index === position"
            class="shrink-0 rounded-lg border px-3 py-2 text-sm font-semibold"
            :class="
              index === position
                ? 'border-n-violet-8 bg-n-violet-9 text-white'
                : 'border-n-violet-6 bg-n-violet-3 text-n-violet-12'
            "
            @click="index = position"
          >
            {{ person.name }}
          </button>
        </div>
        <section
          v-if="current"
          class="space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        >
          <h4 class="font-semibold">
            {{
              [
                people[index].name,
                text(`CONTRACT_SIGNERS.PARTIES.${people[index].party}`),
              ].join(' · ')
            }}
          </h4>
          <p class="text-sm text-n-slate-11">
            {{
              [
                people[index].personal_tax_identifier_masked,
                text('CONTRACT_SIGNERS.REQUIRED'),
              ].join(' · ')
            }}
          </p>
          <label class="block text-sm"
            ><span>{{ text('CONTRACT_AUTHORITY.BASIS') }}</span>
            <select
              v-model="current.basis"
              required
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-n-slate-12"
            >
              <option disabled value="">
                {{ text('CONTRACT_AUTHORITY.SELECT_BASIS') }}
              </option>
              <option
                v-for="basis in [
                  'self',
                  'legal_representative',
                  'power_of_attorney',
                ]"
                :key="basis"
                :value="basis"
              >
                {{ text(`CONTRACT_AUTHORITY.BASES.${basis}`) }}
              </option>
            </select>
          </label>
          <div class="grid gap-3 sm:grid-cols-2">
            <label class="text-sm"
              ><span>{{ text('CONTRACT_AUTHORITY.VALID_FROM') }}</span
              ><input
                v-model="current.valid_from"
                required
                type="date"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-n-slate-12"
            /></label>
            <label class="text-sm"
              ><span>{{ text('CONTRACT_AUTHORITY.VALID_UNTIL') }}</span
              ><input
                v-model="current.valid_until"
                :required="!current.no_expiry"
                :disabled="current.no_expiry"
                type="date"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-n-slate-12 disabled:opacity-50"
            /></label>
          </div>
          <label class="flex items-center gap-2 text-sm"
            ><input v-model="current.no_expiry" type="checkbox" />{{
              text('CONTRACT_AUTHORITY.NO_EXPIRY_DECLARATION')
            }}</label
          >
          <label class="block text-sm"
            ><span>{{ text('CONTRACT_AUTHORITY.PERSON_REASON') }}</span
            ><textarea
              v-model="current.reason"
              required
              maxlength="2000"
              rows="3"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-n-slate-12"
            />
          </label>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="id in current.document_version_ids"
              :key="id"
              type="button"
              class="rounded-lg border border-n-ruby-6 bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-12"
              @click="remove(id)"
            >
              {{ `${text('CONTRACT_AUTHORITY.REMOVE_EVIDENCE')} #${id}` }}
            </button>
          </div>
          <AuthorityDocumentPicker
            :key="current.signer_key"
            :account-id="accountId"
            :request-id="requestId"
            :selected="current.document_version_ids"
            @choose="choose"
            @denied="deny"
          />
        </section>
        <label class="block text-sm font-semibold"
          ><span>{{ text('CONTRACT_AUTHORITY.REASON') }}</span
          ><textarea
            v-model="reason"
            required
            maxlength="2000"
            rows="3"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm text-n-slate-12"
          />
        </label>
      </fieldset>
      <p
        v-if="error"
        role="alert"
        class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
      >
        {{ error }}
      </p>
      <p v-if="!valid" class="text-sm text-n-slate-11">
        {{ text('CONTRACT_AUTHORITY.COMPLETE_ALL') }}
      </p>
      <div class="flex justify-end gap-2">
        <button
          type="button"
          :disabled="saving"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="emit('close')"
        >
          {{ text('CONTRACT_SIGNERS.CLOSE') }}
        </button>
        <button
          type="submit"
          :disabled="!valid || saving || stale"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          {{ text('CONTRACT_AUTHORITY.SUBMIT') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
