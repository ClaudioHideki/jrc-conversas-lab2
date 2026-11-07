<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, date, message } from './definitions';
import { validOperationMetadata } from './reviewedOperationMetadata';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  actorId: { type: [String, Number], required: true },
  authorizationKey: { type: String, default: '' },
  portfolioGroupId: { type: Number, default: null },
  formatting: { type: Object, default: () => ({}) },
  disabled: Boolean,
});
const emit = defineEmits(['open', 'updated']);
const { t } = useI18n();
const opened = ref(false);
const rows = ref([]);
const status = ref('pending');
const meta = ref({ page: 1, per_page: 25, total: 0 });
const loading = ref(false);
const error = ref('');
const selected = ref(null);
const reason = ref('');
const saving = ref(false);
const uncertain = ref(false);
const stopError = ref('');
const dialog = ref(null);
const pages = computed(() =>
  Math.max(1, Math.ceil(meta.value.total / meta.value.per_page))
);
const identity = computed(() =>
  JSON.stringify([
    props.accountId,
    props.actorId,
    props.authorizationKey,
    props.portfolioGroupId,
  ])
);
let generation = 0;
let controller = new AbortController();
const unconfirmedIds = new Set();
const labels = computed(() => ({
  TITLE: t('RELATIONSHIP.REVIEWED_INVENTORY.TITLE'),
  HELP: t('RELATIONSHIP.REVIEWED_INVENTORY.HELP'),
  STATUS: t('RELATIONSHIP.REVIEWED_INVENTORY.STATUS'),
  PENDING: t('RELATIONSHIP.REVIEWED_INVENTORY.PENDING'),
  ALL: t('RELATIONSHIP.REVIEWED_INVENTORY.ALL'),
  RELOAD: t('RELATIONSHIP.REVIEWED_INVENTORY.RELOAD'),
  EMPTY: t('RELATIONSHIP.REVIEWED_INVENTORY.EMPTY'),
  OPEN: t('RELATIONSHIP.REVIEWED_INVENTORY.OPEN'),
  STOP: t('RELATIONSHIP.REVIEWED_INVENTORY.STOP'),
  PAGES: t('RELATIONSHIP.REVIEWED_INVENTORY.PAGES'),
  PREVIOUS: t('RELATIONSHIP.REVIEWED_INVENTORY.PREVIOUS'),
  NEXT: t('RELATIONSHIP.REVIEWED_INVENTORY.NEXT'),
  STOP_HELP: t('RELATIONSHIP.REVIEWED_INVENTORY.STOP_HELP'),
  REVISION: t('RELATIONSHIP.REVIEWED_INVENTORY.REVISION'),
  REASON: t('RELATIONSHIP.REVIEWED_INVENTORY.REASON'),
  CONFIRM_STOP: t('RELATIONSHIP.REVIEWED_INVENTORY.CONFIRM_STOP'),
  REREAD: t('RELATIONSHIP.REVIEWED_INVENTORY.REREAD'),
  REREAD_HELP: t('RELATIONSHIP.REVIEWED_INVENTORY.REREAD_HELP'),
  UNCONFIRMED: t('RELATIONSHIP.REVIEWED_INVENTORY.UNCONFIRMED'),
}));
const states = computed(() => ({
  previewed: t('RELATIONSHIP.REVIEWED_BATCH.STATES.previewed'),
  running: t('RELATIONSHIP.REVIEWED_BATCH.STATES.running'),
  completed: t('RELATIONSHIP.REVIEWED_BATCH.STATES.completed'),
  canceled: t('RELATIONSHIP.REVIEWED_BATCH.STATES.canceled'),
  attention: t('RELATIONSHIP.REVIEWED_BATCH.STATES.attention'),
}));
const operations = computed(() => ({
  assign: t('RELATIONSHIP.REVIEWED_BATCH.OPERATIONS.assign'),
  activity: t('RELATIONSHIP.REVIEWED_BATCH.OPERATIONS.activity'),
  playbook: t('RELATIONSHIP.REVIEWED_BATCH.OPERATIONS.playbook'),
  cadence: t('RELATIONSHIP.REVIEWED_BATCH.OPERATIONS.cadence'),
  portfolio_membership: t(
    'RELATIONSHIP.REVIEWED_BATCH.OPERATIONS.portfolio_membership'
  ),
}));
const label = key => labels.value[key];
const clearDenied = failure => {
  if (![401, 403, 404].includes(failure.response?.status)) return;
  selected.value = null;
  reason.value = '';
  rows.value = [];
  error.value = message(failure) || label('UNCONFIRMED');
};
const stateLabel = value => states.value[value];
const query = fields => ({
  ...fields,
  ...(props.portfolioGroupId
    ? { portfolio_group_id: props.portfolioGroupId }
    : {}),
});
const clearDialog = () => {
  if (saving.value) return;
  selected.value = null;
  reason.value = '';
  stopError.value = '';
  uncertain.value = false;
};
const reset = () => {
  generation += 1;
  controller.abort();
  controller = new AbortController();
  rows.value = [];
  opened.value = false;
  loading.value = false;
  error.value = '';
  saving.value = false;
  clearDialog();
  meta.value = { page: 1, per_page: 25, total: 0 };
  unconfirmedIds.clear();
};
const load = async (page = 1) => {
  if (!opened.value || props.disabled || saving.value || selected.value) return;
  generation += 1;
  const token = generation;
  controller.abort();
  controller = new AbortController();
  loading.value = true;
  rows.value = [];
  error.value = '';
  try {
    const { data } = await API.ownReviewedBatches(
      props.accountId,
      query({ page, per_page: 25, status: status.value }),
      { signal: controller.signal }
    );
    if (token !== generation) return;
    if (
      !Array.isArray(data.payload) ||
      data.payload.length > 25 ||
      !data.payload.every(validOperationMetadata) ||
      data.meta?.page !== page ||
      data.meta.per_page !== 25 ||
      !Number.isSafeInteger(data.meta.total) ||
      data.meta.total < 0
    )
      throw new Error(label('UNCONFIRMED'));
    rows.value = data.payload;
    data.payload.forEach(row => unconfirmedIds.delete(row.id));
    meta.value = data.meta;
  } catch (failure) {
    if (token === generation)
      error.value = message(failure) || label('UNCONFIRMED');
  } finally {
    if (token === generation) loading.value = false;
  }
};
const toggle = event => {
  if (event.target.open) {
    if (opened.value) return;
    opened.value = true;
    load();
  } else if (!saving.value) reset();
};
const choose = async row => {
  if (props.disabled || saving.value || loading.value) return;
  selected.value = { ...row, counts: { ...row.counts } };
  reason.value = '';
  uncertain.value = unconfirmedIds.has(row.id);
  stopError.value = '';
  await nextTick();
  dialog.value?.open();
};
const reread = async () => {
  if (!selected.value || saving.value || props.disabled) return;
  const token = generation;
  const id = selected.value.id;
  saving.value = true;
  stopError.value = '';
  try {
    const { data } = await API.ownReviewedBatches(
      props.accountId,
      query({ review_id: id, status: 'all', page: 1, per_page: 25 }),
      { signal: controller.signal }
    );
    if (token !== generation) return;
    const row = data.payload?.[0];
    if (
      data.payload?.length !== 1 ||
      !validOperationMetadata(row) ||
      row.id !== id ||
      row.operation !== selected.value.operation
    )
      throw new Error(label('UNCONFIRMED'));
    selected.value = row;
    unconfirmedIds.delete(id);
    uncertain.value = false;
    rows.value = rows.value.map(item => (item.id === id ? row : item));
  } catch (failure) {
    if (token === generation) {
      uncertain.value = true;
      unconfirmedIds.add(id);
      stopError.value = message(failure) || label('UNCONFIRMED');
      clearDenied(failure);
    }
  } finally {
    if (token === generation) saving.value = false;
  }
};
const stop = async () => {
  if (
    !selected.value?.can_cancel_pending ||
    saving.value ||
    props.disabled ||
    uncertain.value ||
    !reason.value.trim() ||
    reason.value.length > 4000
  )
    return;
  const token = generation;
  const current = selected.value;
  saving.value = true;
  stopError.value = '';
  try {
    const { data } = await API.stopOwnReviewedBatch(
      props.accountId,
      current.id,
      { expected_revision: current.revision, reason: reason.value.trim() },
      { signal: controller.signal }
    );
    if (token !== generation) return;
    if (
      !validOperationMetadata(data) ||
      data.id !== current.id ||
      data.operation !== current.operation ||
      data.revision < current.revision ||
      data.counts.total !== current.counts.total ||
      data.counts.applied < current.counts.applied ||
      data.counts.pending !== 0 ||
      data.can_cancel_pending
    )
      throw new Error(label('UNCONFIRMED'));
    selected.value = data;
    rows.value = rows.value.map(item => (item.id === data.id ? data : item));
    reason.value = '';
    emit('updated');
  } catch (failure) {
    if (token === generation) {
      uncertain.value = true;
      unconfirmedIds.add(current.id);
      stopError.value = message(failure) || label('UNCONFIRMED');
      clearDenied(failure);
    }
  } finally {
    if (token === generation) saving.value = false;
  }
};
watch(identity, reset);
onBeforeUnmount(reset);
</script>

<template>
  <details
    :open="opened"
    class="my-3 min-w-0 rounded-xl border border-n-violet-6 bg-n-solid-2 p-3"
    @toggle="toggle"
  >
    <summary class="cursor-pointer font-semibold">{{ label('TITLE') }}</summary>
    <section
      v-if="opened"
      class="mt-3 min-w-0 space-y-3"
    >
      <p class="text-sm text-n-slate-11">{{ label('HELP') }}</p>
      <div class="flex flex-wrap items-end gap-2">
        <label class="min-w-0 text-sm">
          <span>{{ label('STATUS') }}</span>
          <select
            v-model="status"
            :class="inputClass"
            :disabled="loading || saving || !!selected || disabled"
            data-test="inventory-status"
            @change="load(1)"
          >
            <option
              v-for="value in [
                'pending',
                'all',
                'previewed',
                'running',
                'completed',
                'canceled',
                'attention',
              ]"
              :key="value"
              :value="value"
            >
              {{
                ['pending', 'all'].includes(value)
                  ? label(value.toUpperCase())
                  : stateLabel(value)
              }}
            </option>
          </select>
        </label>
        <button
          type="button"
          :class="buttonClass"
          :disabled="loading || saving || !!selected || disabled"
          data-test="inventory-reload"
          @click="load(meta.page)"
        >
          {{ label('RELOAD') }}
        </button>
      </div>
      <p
        v-if="loading"
        role="status"
      >
        {{ t('RELATIONSHIP.LOADING') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p v-if="!loading && !error && !rows.length">{{ label('EMPTY') }}</p>
      <ul class="space-y-2">
        <li
          v-for="row in rows"
          :key="row.id"
          class="min-w-0 rounded-lg border border-n-weak p-3 text-sm"
          data-test="inventory-row"
        >
          <p class="break-words font-medium">
            {{
              t('RELATIONSHIP.REVIEWED_INVENTORY.IDENTITY', {
                id: row.id,
                operation: operations[row.operation],
                state: stateLabel(row.state),
              })
            }}
          </p>
          <p>{{ date(row.updated_at, formatting) }}</p>
          <p class="break-words">
            {{ t('RELATIONSHIP.REVIEWED_INVENTORY.COUNTS', row.counts) }}
          </p>
          <div class="mt-2 flex flex-wrap gap-2">
            <button
              v-if="
                row.operation !== 'portfolio_membership' || portfolioGroupId
              "
              type="button"
              :class="buttonClass"
              :disabled="loading || saving || !!selected || disabled"
              data-test="inventory-open"
              @click="emit('open', row.id)"
            >
              {{ label('OPEN') }}
            </button>
            <button
              v-if="row.can_cancel_pending"
              type="button"
              :class="buttonClass"
              :disabled="loading || saving || !!selected || disabled"
              data-test="inventory-stop"
              @click="choose(row)"
            >
              {{ label('STOP') }}
            </button>
          </div>
        </li>
      </ul>
      <nav
        class="flex flex-wrap items-center gap-2"
        :aria-label="label('PAGES')"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="
            loading || saving || !!selected || disabled || meta.page <= 1
          "
          data-test="inventory-previous"
          @click="load(meta.page - 1)"
        >
          {{ label('PREVIOUS') }}
        </button>
        <span>{{
          t('RELATIONSHIP.REVIEWED_INVENTORY.PAGE_SUMMARY', {
            page: meta.page,
            pages,
            total: meta.total,
          })
        }}</span>
        <button
          type="button"
          :class="buttonClass"
          :disabled="
            loading || saving || !!selected || disabled || meta.page >= pages
          "
          data-test="inventory-next"
          @click="load(meta.page + 1)"
        >
          {{ label('NEXT') }}
        </button>
      </nav>
    </section>
  </details>
  <Dialog
    v-if="selected"
    ref="dialog"
    :title="label('STOP')"
    :description="label('STOP_HELP')"
    :show-confirm-button="false"
    :use-form="false"
    :dismissible="!saving"
    :show-cancel-button="!saving"
    :show-close-button="!saving"
    width="lg"
    @close="clearDialog"
  >
    <p class="break-words">
      {{
        t('RELATIONSHIP.REVIEWED_INVENTORY.CURRENT', {
          id: selected.id,
          revision: selected.revision,
          state: stateLabel(selected.state),
        })
      }}
    </p>
    <p>
      {{ t('RELATIONSHIP.REVIEWED_INVENTORY.COUNTS', selected.counts) }}
    </p>
    <p
      v-if="stopError"
      role="alert"
      class="mt-2 break-words text-n-ruby-11"
    >
      {{ stopError }}
    </p>
    <p
      v-if="uncertain"
      class="my-2 text-sm"
    >
      {{ label('REREAD_HELP') }}
    </p>
    <form
      v-if="selected.can_cancel_pending"
      class="mt-3 space-y-3"
      @submit.prevent="stop"
    >
      <label class="block text-sm">
        <span>{{ label('REASON') }}</span>
        <textarea
          v-model="reason"
          :class="inputClass"
          maxlength="4000"
          required
          :disabled="saving || disabled"
          data-test="inventory-reason"
        />
      </label>
      <button
        type="submit"
        :class="buttonClass"
        :disabled="saving || disabled || uncertain || !reason.trim()"
        data-test="inventory-confirm"
      >
        {{ label('CONFIRM_STOP') }}
      </button>
    </form>
    <button
      v-if="uncertain"
      type="button"
      class="mt-3"
      :class="[buttonClass]"
      :disabled="saving || disabled"
      data-test="inventory-reread"
      @click="reread"
    >
      {{ label('REREAD') }}
    </button>
  </Dialog>
</template>
