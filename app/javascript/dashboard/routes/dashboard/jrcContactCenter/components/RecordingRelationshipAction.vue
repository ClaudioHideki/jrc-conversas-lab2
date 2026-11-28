<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { zonedTimeToUtc } from 'date-fns-tz';
import { useMapGetter } from 'dashboard/composables/store';
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import API from 'dashboard/api/jrcContactCenter';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import RelationshipActivityForm from '../../jrcRelationship/RelationshipActivityForm.vue';
import { destinationHistoryRoute } from '../../inbox/endingDestinationHistoryContract';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
  callSessionId: { type: [String, Number], required: true },
  callId: { type: String, required: true },
  contactId: { type: [String, Number], required: true },
  enabled: { type: Boolean, default: false },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();
const actor = useMapGetter('getCurrentUser');
const identity = computed(() =>
  JSON.stringify([
    props.accountId,
    props.recordingId,
    props.callSessionId,
    props.callId,
    props.contactId,
    props.enabled,
    actor.value?.id,
    accountMembershipAccess(
      actor.value?.accounts?.find(
        row => String(row.id) === String(props.accountId)
      )
    ),
  ])
);
const labels = computed(() => ({
  OPEN: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.OPEN'),
  HINT: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.HINT'),
  PORTFOLIO: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.PORTFOLIO'),
  PAGINATION: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.PAGINATION'),
  EMPTY: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.EMPTY'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.DENIED'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.ERROR'),
  INVALID: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.INVALID'),
  UNKNOWN: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.UNKNOWN'),
  RETRY_SAME: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.RETRY_SAME'),
  OPEN_ACTIVITY: t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.OPEN_ACTIVITY'),
}));
const text = key => labels.value[key];
const opened = ref(false);
const dialog = ref(null);
watch(dialog, instance => instance?.open(), { flush: 'post' });
const busy = ref(false);
const source = ref(null);
const choices = ref([]);
const meta = ref(null);
const selectedId = ref('');
const title = ref('');
const dueAt = ref('');
const error = ref('');
const receipt = ref(null);
const uncertainSignature = ref('');
const targetRoute = computed(() =>
  destinationHistoryRoute(receipt.value?.target, props.accountId)
);
let requestId;
let generation = 0;
let controller;
const forgetDraft = () => {
  source.value = null;
  choices.value = [];
  meta.value = null;
  selectedId.value = '';
  title.value = '';
  dueAt.value = '';
  requestId = undefined;
};
const close = () => {
  generation += 1;
  controller?.abort();
  opened.value = false;
  busy.value = false;
  error.value = '';
  receipt.value = null;
  uncertainSignature.value = '';
  forgetDraft();
};
const identifier = value =>
  typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);
const validPreview = (data, page) =>
  data?.contract_version === 1 &&
  data.account_id === String(props.accountId) &&
  data.user_id === String(actor.value?.id) &&
  data.recording_id === String(props.recordingId) &&
  data.call_session_id === String(props.callSessionId) &&
  data.call_id === props.callId &&
  data.contact_id === String(props.contactId) &&
  typeof data.time_zone === 'string' &&
  data.time_zone.length > 0 &&
  typeof data.origin_revision === 'string' &&
  /^[a-f0-9]{64}$/.test(data.origin_revision) &&
  Array.isArray(data.items) &&
  data.items.length <= 20 &&
  data.items.every(
    row =>
      identifier(row.id) &&
      typeof row.label === 'string' &&
      typeof row.can_work === 'boolean'
  ) &&
  new Set(data.items.map(row => row.id)).size === data.items.length &&
  data.meta?.page === page &&
  data.meta.per_page === 20 &&
  Number.isSafeInteger(data.meta.total) &&
  data.meta.total >= 0 &&
  data.meta.pages === Math.ceil(data.meta.total / 20);
const load = async (page = 1, redirected = false) => {
  if (busy.value || !props.enabled || !opened.value || uncertainSignature.value)
    return;
  generation += 1;
  const current = generation;
  const origin = identity.value;
  controller?.abort();
  controller = new AbortController();
  source.value = null;
  choices.value = [];
  meta.value = null;
  selectedId.value = '';
  error.value = '';
  busy.value = true;
  try {
    const { data } = await API.recordingRelationshipActivities(
      props.accountId,
      props.recordingId,
      page,
      { signal: controller.signal }
    );
    if (current !== generation || origin !== identity.value) return;
    if (!validPreview(data, page))
      throw new TypeError('Invalid native Relationship recording source');
    const last = Math.max(1, data.meta.pages);
    if (page > last) {
      if (redirected)
        throw new TypeError('Native portfolio page changed again');
      busy.value = false;
      await load(last, true);
      return;
    }
    source.value = data;
    choices.value = data.items;
    meta.value = data.meta;
    requestId ||= crypto.randomUUID();
  } catch (failure) {
    if (current !== generation || origin !== identity.value) return;
    if ([401, 403, 404].includes(failure.response?.status)) {
      forgetDraft();
      error.value = 'DENIED';
    } else error.value = 'ERROR';
  } finally {
    if (current === generation && origin === identity.value) busy.value = false;
  }
};
const open = async () => {
  if (!props.enabled || busy.value) return;
  close();
  opened.value = true;
  requestId = crypto.randomUUID();
  await load();
};
const validReceipt = (data, assignmentId) =>
  data?.contract_version === 1 &&
  data.account_id === String(props.accountId) &&
  data.recording_id === String(props.recordingId) &&
  data.call_session_id === String(props.callSessionId) &&
  data.assignment_id === assignmentId &&
  identifier(data.activity_id) &&
  typeof data.replayed === 'boolean' &&
  (data.target === null ||
    (data.target?.kind === 'crm_activity' &&
      data.target.id === data.activity_id));
const save = async () => {
  const choice = choices.value.find(
    row => row.id === selectedId.value && row.can_work === true
  );
  if (
    busy.value ||
    !props.enabled ||
    !source.value ||
    !choice ||
    !requestId ||
    !dueAt.value
  )
    return;
  const current = generation;
  const origin = identity.value;
  let input;
  try {
    input = {
      assignment_id: choice.id,
      request_id: requestId,
      title: title.value,
      due_at: zonedTimeToUtc(dueAt.value, source.value.time_zone).toISOString(),
      origin_revision: source.value.origin_revision,
    };
  } catch {
    error.value = 'INVALID';
    return;
  }
  const signature = JSON.stringify(input);
  if (uncertainSignature.value && uncertainSignature.value !== signature) {
    error.value = 'UNKNOWN';
    return;
  }
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.createRecordingRelationshipActivity(
      props.accountId,
      props.recordingId,
      input
    );
    if (current !== generation || origin !== identity.value) return;
    if (!validReceipt(data, choice.id))
      throw new TypeError('Invalid native Relationship activity receipt');
    receipt.value = data;
    uncertainSignature.value = '';
    forgetDraft();
    emit('changed');
  } catch (failure) {
    if (current !== generation || origin !== identity.value) return;
    const status = failure.response?.status;
    if ([401, 403, 404].includes(status)) {
      forgetDraft();
      uncertainSignature.value = '';
      error.value = 'DENIED';
    } else if (
      uncertainSignature.value ||
      !status ||
      status >= 500 ||
      status === 409
    ) {
      uncertainSignature.value = signature;
      error.value = 'UNKNOWN';
    } else error.value = 'INVALID';
  } finally {
    if (current === generation && origin === identity.value) busy.value = false;
  }
};
watch(identity, close, { flush: 'sync' });
onBeforeUnmount(close);
</script>

<template>
  <div class="min-w-0 space-y-2" data-recording-relationship-action>
    <button
      v-if="enabled"
      type="button"
      :disabled="busy"
      class="max-w-full rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm text-n-blue-12"
      data-open-recording-relationship
      @click="open"
    >
      {{ text('OPEN') }}
    </button>
    <Dialog
      v-if="enabled && opened"
      ref="dialog"
      :title="text('OPEN')"
      width="2xl"
      contained
      overflow-y-auto
      :use-form="false"
      :show-confirm-button="false"
      :show-cancel-button="false"
      show-close-button
      :dismissible="!busy"
      :close-on-click-outside="false"
      @close="close"
    >
      <div class="min-w-0 space-y-3" data-recording-relationship-editor>
        <p class="break-words text-sm text-n-slate-11">{{ text('HINT') }}</p>
        <p v-if="error" role="alert" class="break-words text-sm text-n-ruby-11">
          {{ text(error) }}
        </p>
        <p v-if="busy" role="status" class="text-sm">
          {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
        </p>
        <template v-if="receipt">
          <p role="status" data-recording-relationship-receipt>
            {{
              t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.SUCCESS', {
                id: receipt.activity_id,
              })
            }}
          </p>
          <RouterLink
            v-if="targetRoute"
            :to="targetRoute"
            data-recording-relationship-target
            class="text-n-blue-11 underline"
          >
            <span>{{ text('OPEN_ACTIVITY') }}</span>
          </RouterLink>
        </template>
        <template v-else-if="source">
          <p
            class="break-all text-xs text-n-slate-11"
            data-recording-relationship-origin
          >
            {{
              t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.CALL', {
                id: source.call_id,
              })
            }}
          </p>
          <label class="block min-w-0 text-sm">
            {{ text('PORTFOLIO') }}
            <select
              v-model="selectedId"
              :disabled="busy || !!uncertainSignature"
              data-recording-relationship-portfolio
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="">
                {{ t('JRC_CONTACT_CENTER.ADMIN.SELECT') }}
              </option>
              <option
                v-for="row in choices"
                :key="row.id"
                :value="row.id"
                :disabled="!row.can_work"
              >
                {{
                  t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.CHOICE', {
                    label: row.label,
                    id: row.id,
                  })
                }}
              </option>
            </select>
          </label>
          <p v-if="!choices.length" class="text-sm">{{ text('EMPTY') }}</p>
          <nav
            v-if="meta.pages > 1"
            class="flex flex-wrap gap-3 text-sm"
            :aria-label="text('PAGINATION')"
          >
            <button
              type="button"
              data-recording-relationship-previous
              :disabled="busy || !!uncertainSignature || meta.page <= 1"
              @click="load(meta.page - 1)"
            >
              {{ t('JRC_CONTACT_CENTER.ADMIN.PREVIOUS') }}
            </button>
            <span>{{
              t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.PAGINATION_VALUE', {
                page: meta.page,
                pages: meta.pages,
              })
            }}</span>
            <button
              type="button"
              data-recording-relationship-next
              :disabled="
                busy || !!uncertainSignature || meta.page >= meta.pages
              "
              @click="load(meta.page + 1)"
            >
              {{ t('JRC_CONTACT_CENTER.ADMIN.NEXT') }}
            </button>
          </nav>
          <RelationshipActivityForm
            v-if="selectedId"
            v-model:title="title"
            v-model:due-at="dueAt"
            :disabled="busy || !!uncertainSignature"
            :title-max-length="250"
            deadline-required
            @submit="save"
          />
          <p
            class="text-xs text-n-slate-11"
            data-recording-relationship-time-zone
          >
            {{
              t('JRC_CONTACT_CENTER.RECORDING_RELATIONSHIP.TIME_ZONE', {
                zone: source.time_zone,
              })
            }}
          </p>
          <button
            v-if="uncertainSignature"
            type="button"
            :disabled="busy"
            data-retry-recording-relationship
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
            @click="save"
          >
            {{ text('RETRY_SAME') }}
          </button>
        </template>
        <button
          v-if="error && !uncertainSignature && !receipt"
          type="button"
          :disabled="busy"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm"
          @click="load()"
        >
          {{ t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.RETRY') }}
        </button>
      </div>
    </Dialog>
  </div>
</template>
