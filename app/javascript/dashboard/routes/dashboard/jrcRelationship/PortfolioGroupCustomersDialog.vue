<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  group: { type: Object, required: true },
  customer: { type: Object, default: null },
  initialCustomer: { type: Object, default: null },
  busy: Boolean,
  error: { type: String, default: '' },
  conflict: Boolean,
});
const emit = defineEmits(['close', 'save', 'reviewed', 'batch']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const rows = ref([]);
const selected = ref(new Map());
const query = ref('');
const reason = ref('');
const step = ref(props.customer || props.initialCustomer ? 'review' : 'select');
const loading = ref(false);
const loadError = ref('');
const title = computed(() =>
  props.customer
    ? t('RELATIONSHIP.NAMED_PORTFOLIOS.REMOVE_REVIEW')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.ADD_CUSTOMERS')
);
const help = computed(() =>
  props.customer
    ? t('RELATIONSHIP.NAMED_PORTFOLIOS.REMOVE_HELP')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.CUSTOMERS_HELP')
);
const pagination = ref({ page: 1, per_page: 25, total: 0 });
const expectedVersion = ref(props.group.version);
const refreshed = ref(false);
const pages = computed(() =>
  Math.max(1, Math.ceil(pagination.value.total / pagination.value.per_page))
);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.group.id,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
  ])
);
let generation = 0;
let controller;
const load = async (page = 1) => {
  controller?.abort();
  controller = new AbortController();
  const signal = controller.signal;
  generation += 1;
  const token = generation;
  const current = identity.value;
  rows.value = [];
  loading.value = true;
  loadError.value = '';
  try {
    const { data } = await API.portfolio(
      route.params.accountId,
      {
        q: query.value,
        page,
        business_unit_id: props.group.business_unit_id || undefined,
      },
      { signal }
    );
    if (signal.aborted || token !== generation || current !== identity.value)
      return;
    rows.value = data.payload;
    pagination.value = data.meta;
  } catch (err) {
    if (signal.aborted || token !== generation || current !== identity.value)
      return;
    loadError.value = message(err);
    if ([401, 403, 404].includes(err.response?.status)) selected.value.clear();
  } finally {
    if (token === generation && current === identity.value)
      loading.value = false;
  }
};
const toggle = row => {
  const id = Number(row.id);
  if (selected.value.has(id)) selected.value.delete(id);
  else if (selected.value.size < 50) selected.value.set(id, row);
};
const reloadReview = async () => {
  if (props.busy || loading.value || !selected.value.size) return;
  const ids = [...selected.value.keys()];
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  const signal = controller.signal;
  loading.value = true;
  loadError.value = '';
  refreshed.value = false;
  try {
    const { data } = await API.portfolioGroupCustomerReview(
      route.params.accountId,
      props.group.id,
      { assignment_ids: ids },
      { signal }
    );
    if (signal.aborted || token !== generation) return;
    if (
      String(data.group?.id) !== String(props.group.id) ||
      !Number.isSafeInteger(data.group.version) ||
      data.group.version < expectedVersion.value ||
      !Array.isArray(data.payload) ||
      data.payload.length !== ids.length ||
      !data.payload.every(
        row => row && ids.includes(row.id) && typeof row.linked === 'boolean'
      ) ||
      new Set(data.payload.map(row => row.id)).size !== ids.length
    ) {
      throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.SAVE_UNCONFIRMED'));
    }
    selected.value = new Map(data.payload.map(row => [row.id, row]));
    expectedVersion.value = data.group.version;
    step.value = 'review';
    refreshed.value = true;
    emit('reviewed');
  } catch (err) {
    if (signal.aborted || token !== generation) return;
    loadError.value = message(err);
    if ([401, 403, 404].includes(err.response?.status)) selected.value.clear();
  } finally {
    if (token === generation && !signal.aborted) loading.value = false;
  }
};
const save = (mode = 'save') => {
  if (
    props.busy ||
    props.conflict ||
    loading.value ||
    !selected.value.size ||
    !reason.value.trim()
  )
    return;
  const fields = {
    assignment_ids: [...selected.value.keys()],
    active: !props.customer,
    expected_version: expectedVersion.value,
    reason: reason.value.trim(),
  };
  if (mode === 'batch') emit('batch', fields);
  else emit('save', fields);
};
watch(
  identity,
  (_, previous) => {
    controller?.abort();
    generation += 1;
    rows.value = [];
    selected.value.clear();
    if (previous !== undefined) {
      emit('close');
      return;
    }
    if (props.customer)
      selected.value.set(Number(props.customer.id), props.customer);
    else if (props.initialCustomer)
      selected.value.set(
        Number(props.initialCustomer.id),
        props.initialCustomer
      );
    else load();
  },
  { immediate: true }
);
onMounted(() => dialog.value.open());
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="2xl"
    :title="title"
    :use-form="false"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :show-close-button="!busy"
    :dismissible="!busy"
    :close-on-click-outside="false"
    overflow-y-auto
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-4">
      <p class="break-words font-semibold">{{ group.name }}</p>
      <p class="text-sm text-n-slate-11">
        {{ help }}
      </p>
      <p
        v-if="error || loadError"
        role="alert"
        class="break-words text-sm text-n-ruby-11"
      >
        {{ loadError || error }}
      </p>
      <button
        v-if="conflict"
        type="button"
        :class="buttonClass"
        :disabled="busy || loading || !selected.size"
        @click="reloadReview"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.RELOAD_REVIEW') }}
      </button>
      <p
        v-if="refreshed"
        role="status"
        class="text-sm text-n-teal-11"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.REVIEW_RELOADED') }}
      </p>
      <p
        v-if="loading"
        role="status"
      >
        {{ t('RELATIONSHIP.LOADING') }}
      </p>
      <template v-if="step === 'select'">
        <form
          class="flex min-w-0 flex-wrap gap-2"
          @submit.prevent="load(1)"
        >
          <label class="min-w-0 flex-1">
            <span>{{
              t('RELATIONSHIP.NAMED_PORTFOLIOS.SEARCH_CUSTOMERS')
            }}</span>
            <input
              v-model="query"
              :class="inputClass"
              maxlength="100"
              :disabled="busy || loading"
            />
          </label>
          <button
            type="submit"
            :class="buttonClass"
            :disabled="busy || loading"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.APPLY') }}
          </button>
        </form>
        <ul class="max-h-80 space-y-2 overflow-y-auto">
          <li
            v-for="row in rows"
            :key="row.id"
            class="min-w-0 rounded-lg border border-n-weak p-3"
          >
            <label class="flex min-w-0 items-start gap-3">
              <input
                type="checkbox"
                :checked="selected.has(Number(row.id))"
                :disabled="
                  busy || (!selected.has(Number(row.id)) && selected.size >= 50)
                "
                @change="toggle(row)"
              />
              <span class="min-w-0 break-words">
                <strong>{{ row.name }}</strong>
                <span class="block text-xs text-n-slate-11">{{
                  row.owner?.name || '—'
                }}</span>
              </span>
            </label>
          </li>
        </ul>
        <footer class="flex flex-wrap items-center justify-between gap-2">
          <span class="text-sm">{{
            t('RELATIONSHIP.NAMED_PORTFOLIOS.SELECTED', {
              count: selected.size,
            })
          }}</span>
          <div class="flex items-center gap-2">
            <button
              type="button"
              :class="buttonClass"
              :disabled="busy || loading || pagination.page <= 1"
              @click="load(pagination.page - 1)"
            >
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.PREVIOUS') }}
            </button>
            <span class="text-xs">{{
              t('RELATIONSHIP.NAMED_PORTFOLIOS.PAGE', {
                page: pagination.page,
                pages,
              })
            }}</span>
            <button
              type="button"
              :class="buttonClass"
              :disabled="busy || loading || pagination.page >= pages"
              @click="load(pagination.page + 1)"
            >
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.NEXT_PAGE') }}
            </button>
          </div>
        </footer>
        <button
          type="button"
          :disabled="busy || loading || !selected.size"
          :class="buttonClass"
          @click="step = 'review'"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.REVIEW_CUSTOMERS') }}
        </button>
      </template>
      <form
        v-else
        class="space-y-3"
        @submit.prevent="save"
      >
        <ul
          v-if="!loading"
          class="max-h-64 space-y-2 overflow-y-auto"
        >
          <li
            v-for="row in selected.values()"
            :key="row.id"
            class="break-words rounded-lg border border-n-weak p-2"
          >
            <p>{{ row.name }}</p>
            <span
              v-if="typeof row.linked === 'boolean'"
              class="block text-xs text-n-slate-11"
            >
              {{
                row.linked
                  ? t(
                      'RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.CURRENTLY_LINKED'
                    )
                  : t(
                      'RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.CURRENTLY_UNLINKED'
                    )
              }}
            </span>
          </li>
        </ul>
        <label class="block">
          <span>{{ t('RELATIONSHIP.NAMED_PORTFOLIOS.REASON') }}</span>
          <textarea
            v-model="reason"
            :class="inputClass"
            maxlength="4000"
            required
            :disabled="busy"
          />
        </label>
        <footer class="flex flex-wrap justify-end gap-2">
          <button
            type="button"
            :class="buttonClass"
            :disabled="
              busy || conflict || loading || !selected.size || !reason.trim()
            "
            @click="save('batch')"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.PREPARE') }}
          </button>
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="emit('close')"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CANCEL') }}
          </button>
          <button
            v-if="!customer"
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="step = 'select'"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.BACK') }}
          </button>
          <button
            type="submit"
            :disabled="
              busy || conflict || loading || !selected.size || !reason.trim()
            "
            class="rounded-lg bg-n-violet-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CONFIRM_CUSTOMERS') }}
          </button>
        </footer>
      </form>
    </div>
  </Dialog>
</template>
