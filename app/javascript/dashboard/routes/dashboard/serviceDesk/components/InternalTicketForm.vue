<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import PortalIcon from '../../../../../portal/requester/PortalIcon.vue';
import PortalHeading from '../../../../../portal/requester/PortalHeading.vue';
import portalPt from '../../../../../portal/requester/pt_BR.json';
import portalEn from '../../../../../portal/requester/en.json';
import { useServiceDesk } from '../composables/useServiceDesk';
import { newRequestKey, ticketFileFingerprints } from '../helpers/drafts';
import { confirmedCreationTicket } from '../helpers/ticketReceipt';
import ServiceDefinitionSelect from './ServiceDefinitionSelect.vue';
import CatalogueAnswers from './CatalogueAnswers.vue';
import TicketCreationReceipt from './TicketCreationReceipt.vue';
import WriteFeedback from './WriteFeedback.vue';

const emit = defineEmits(['cancel', 'open']);
const { t } = useI18n({
  useScope: 'local',
  messages: { pt_BR: portalPt, en: portalEn },
});
const session = useServiceDesk();
const units = computed(() =>
  (session.state.context?.units || []).filter(
    row => row.internal_intake && row.permissions.create_ticket
  )
);
const unitId = ref('');
const unit = computed(() => units.value.find(row => row.id === unitId.value));
const draft = reactive({
  service: '',
  title: '',
  description: '',
  answers: {},
});
const files = ref([]);
const fileInput = ref(null);
const filesError = ref(false);
const ready = ref(false);
const hashing = ref(false);
const receipt = ref(null);
const key = 'ticket:internal:write';
const mutation = computed(
  () => session.operations?.mutation(key) || { status: 'idle' }
);
const busy = computed(
  () => hashing.value || mutation.value.status === 'saving'
);
const locked = computed(
  () =>
    busy.value ||
    ['readback_pending', 'error', 'invalid_contract', 'interrupted'].includes(
      mutation.value.status
    )
);
const created = computed(() =>
  confirmedCreationTicket(
    receipt.value,
    session.state,
    session.accountId.value,
    session.userId.value
  )
);
let payload = null;
let epoch = 0;
const reset = () => {
  epoch += 1;
  payload = null;
  Object.assign(draft, {
    service: '',
    title: '',
    description: '',
    answers: {},
  });
  files.value = [];
  filesError.value = false;
  receipt.value = null;
  session.operations?.dismissConfirmation(key);
  if (fileInput.value) fileInput.value.value = '';
  unitId.value = units.value.length === 1 ? units.value[0].id : '';
};
watch(() => session.state.context, reset, { immediate: true });
watch(
  () => draft.service,
  () => {
    ready.value = false;
  }
);
watch(unitId, () => {
  draft.service = '';
  draft.answers = {};
  ready.value = false;
});
const chooseFiles = selected => {
  if (locked.value) return;
  const next = Array.from(selected || []);
  filesError.value =
    next.length > 5 ||
    next.some(file => file.size <= 0 || file.size > 20 * 1024 * 1024);
  files.value = filesError.value ? [] : next;
};
const maySave = computed(
  () =>
    unit.value &&
    draft.service &&
    ready.value &&
    draft.title.trim() &&
    draft.description.trim() &&
    !filesError.value &&
    !locked.value
);
const submit = async () => {
  if (busy.value || (!payload && !maySave.value)) return;
  const context = session.state.context;
  const turn = epoch;
  if (!payload) {
    hashing.value = true;
    try {
      const fingerprints = await ticketFileFingerprints(files.value);
      if (turn !== epoch || context !== session.state.context) return;
      payload = {
        unit_id: unitId.value,
        internal_request: true,
        service_id: draft.service,
        ticket: {
          title: draft.title,
          description: draft.description,
          service_fields: { ...draft.answers },
        },
        requestKey: newRequestKey(),
        files: [...files.value],
        file_fingerprints: fingerprints,
      };
    } catch {
      filesError.value = true;
      return;
    } finally {
      hashing.value = false;
    }
  }
  const confirmed = await session.operations.write(key, 'create', payload);
  if (context !== session.state.context || turn !== epoch) return;
  if (confirmed)
    receipt.value = {
      ticket: confirmed,
      account_id: context.account_id,
      user_id: context.user_id,
    };
  else if (mutation.value.status === 'invalid_input') payload = null;
};
onBeforeUnmount(() => {
  epoch += 1;
  session.operations?.cancel(key);
});
defineExpose({ busy: locked });
</script>

<template>
  <section
    class="mx-auto min-w-0 max-w-5xl rounded-2xl bg-gradient-to-br from-blue-50 via-white to-sky-100 p-4 text-slate-900 sm:p-6 [&_*]:border-solid"
    data-testid="internal-ticket-form"
  >
    <PortalHeading icon="headset" :title="t('PORTAL.NEW')" />
    <TicketCreationReceipt
      v-if="created"
      :ticket="created"
      @open="emit('open', $event)"
      @list="emit('cancel')"
      @create-another="reset"
    />
    <form
      v-else
      class="mt-5 grid min-w-0 grid-cols-1 gap-5 rounded-2xl border border-blue-100 bg-white/95 p-4 shadow-sm sm:p-6"
      @submit.prevent="submit"
    >
      <dl
        v-if="unit"
        class="grid min-w-0 grid-cols-1 gap-5 rounded-2xl bg-blue-50 p-5 md:grid-cols-2"
      >
        <div class="flex min-w-0 gap-3">
          <span class="self-start rounded-xl bg-blue-100 p-3 text-blue-700"
            ><PortalIcon name="user"
          /></span>
          <div class="min-w-0">
            <dt class="text-xs text-slate-600">{{ t('PORTAL.NAME') }}</dt>
            <dd class="mt-1 break-words font-bold">
              {{ unit.internal_intake.requester.name }}
            </dd>
          </div>
        </div>
        <div class="flex min-w-0 gap-3">
          <span class="self-start rounded-xl bg-blue-100 p-3 text-blue-700"
            ><PortalIcon name="mail"
          /></span>
          <div class="min-w-0">
            <dt class="text-xs text-slate-600">{{ t('PORTAL.EMAIL') }}</dt>
            <dd class="mt-1 break-all font-bold">
              {{ unit.internal_intake.requester.email }}
            </dd>
          </div>
        </div>
      </dl>
      <label v-if="units.length > 1" class="block text-sm font-semibold">
        {{ t('PORTAL.UNIT') }}
        <select
          v-model="unitId"
          required
          :disabled="locked"
          class="mt-2 w-full rounded-xl border border-blue-200 bg-white p-3"
        >
          <option value="">{{ t('PORTAL.SELECT') }}</option>
          <option v-for="row in units" :key="row.id" :value="row.id">
            {{ row.name }}
          </option>
        </select>
      </label>
      <div
        class="[&_.w-fit]:w-full [&_select]:w-full [&_select]:rounded-xl [&_select]:border-blue-200 [&_select]:bg-white [&_select]:p-3"
      >
        <ServiceDefinitionSelect
          v-model="draft.service"
          :unit-id="unitId"
          :disabled="locked"
        />
      </div>
      <label class="block text-sm font-semibold"
        >{{ t('PORTAL.SUBJECT') }}
        <input
          v-model="draft.title"
          required
          maxlength="255"
          :readonly="locked"
          :placeholder="t('PORTAL.SUBJECT')"
          class="mt-2 w-full rounded-xl border border-blue-200 bg-white p-3 focus:ring-2 focus:ring-blue-200"
        />
      </label>
      <label class="block text-sm font-semibold"
        >{{ t('PORTAL.DESCRIPTION') }}
        <textarea
          v-model="draft.description"
          required
          maxlength="20000"
          rows="4"
          :readonly="locked"
          :placeholder="t('PORTAL.DESCRIPTION')"
          class="mt-2 w-full rounded-xl border border-blue-200 bg-white p-3 focus:ring-2 focus:ring-blue-200"
        />
      </label>
      <CatalogueAnswers
        v-if="draft.service"
        v-model="draft.answers"
        :service-id="draft.service"
        :unit-id="unitId"
        :disabled="locked"
        @ready="ready = $event"
      />
      <div
        class="rounded-xl border border-dashed border-blue-300 bg-blue-50/50 p-4"
        @dragover.prevent
        @drop.prevent="chooseFiles($event.dataTransfer.files)"
      >
        <label
          for="internal-ticket-files"
          class="block text-sm font-semibold"
          >{{ t('JRC_SERVICE_DESK.TICKET.tabs.files') }}</label
        >
        <input
          id="internal-ticket-files"
          ref="fileInput"
          type="file"
          multiple
          :disabled="locked"
          class="mt-3 max-w-full text-sm file:mr-3 file:rounded-lg file:border-0 file:bg-blue-100 file:px-4 file:py-2 file:font-semibold file:text-blue-800"
          @change="chooseFiles($event.target.files)"
        />
        <p class="mb-0 mt-2 text-xs text-slate-600">
          {{ t('JRC_SERVICE_DESK.FORM.attachments_help') }}
        </p>
        <ul v-if="files.length" class="mb-0 mt-2 break-all text-sm">
          <li v-for="file in files" :key="file.name">{{ file.name }}</li>
        </ul>
      </div>
      <p v-if="filesError" role="alert" class="text-sm text-red-700">
        {{ t('JRC_SERVICE_DESK.REDESIGN_DETAIL.invalid_files') }}
      </p>
      <WriteFeedback :status="mutation.status" />
      <div class="flex flex-wrap justify-end gap-3">
        <button
          type="button"
          :disabled="locked"
          class="rounded-xl border border-blue-200 px-5 py-3 font-semibold text-blue-800 disabled:opacity-50"
          @click="emit('cancel')"
        >
          {{ t('JRC_SERVICE_DESK.COMMON.cancel') }}
        </button>
        <button
          type="submit"
          :disabled="payload ? busy : !maySave"
          class="flex items-center gap-2 rounded-xl bg-gradient-to-b from-sky-500 to-blue-800 px-5 py-3 font-semibold text-white shadow-sm disabled:opacity-50"
        >
          <PortalIcon name="send" class="h-5 w-5" />{{
            payload
              ? t('JRC_SERVICE_DESK.QUICK.recover_creation')
              : t('PORTAL.NEW')
          }}
        </button>
      </div>
    </form>
  </section>
</template>
