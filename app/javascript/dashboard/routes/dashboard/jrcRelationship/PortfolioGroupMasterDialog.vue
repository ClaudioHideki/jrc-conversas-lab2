<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CompanyPicker from '../jrcCustomers/components/CompanyPicker.vue';
import PortfolioAssignmentForm from './PortfolioAssignmentForm.vue';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  group: { type: Object, required: true },
  metadata: { type: Object, required: true },
  disabled: Boolean,
  staged: Boolean,
});
const emit = defineEmits(['close', 'review', 'batch', 'masterBatch']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const masterCopy = computed(() => ({
  title: props.staged
    ? t('RELATIONSHIP.MASTER_ALLOCATION.TITLE')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.TITLE'),
  help: props.staged
    ? t('RELATIONSHIP.MASTER_ALLOCATION.HELP')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.HELP'),
  allocationNotice: props.staged
    ? t('RELATIONSHIP.MASTER_ALLOCATION.DRAFT_NOTICE')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.ALLOCATION_NOTICE'),
  allocate: props.staged
    ? t('RELATIONSHIP.MASTER_ALLOCATION.ADD_DRAFT')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.ALLOCATE'),
  selectionNotice: props.staged
    ? t('RELATIONSHIP.MASTER_ALLOCATION.DRAFT_NOTICE')
    : t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.SELECTION_NOTICE'),
}));
const dialog = ref(null);
const companyId = ref(null);
const candidate = ref(null);
const step = ref('select');
const busy = ref(false);
const error = ref('');
const created = ref(false);
const unconfirmed = ref(false);
const selection = ref([]);
const selectionPage = ref(1);
const selectionReason = ref('');
const selectionReasonLabel = computed(() =>
  t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.SELECTION_REASON')
);
const submitted = ref(false);
const locked = computed(() => busy.value || props.disabled || submitted.value);
const selectionPages = computed(() =>
  Math.max(1, Math.ceil(selection.value.length / 10))
);
const selectionRows = computed(() =>
  selection.value.slice(
    (selectionPage.value - 1) * 10,
    selectionPage.value * 10
  )
);
const alreadySelected = computed(
  () =>
    candidate.value &&
    selection.value.some(
      row =>
        (!props.staged && row.id === candidate.value.id) ||
        String(row.company_id) === String(candidate.value.company_id)
    )
);
const allowed = computed(
  () =>
    props.group.can_manage &&
    props.group.status === 'active' &&
    props.metadata.can_manage &&
    props.metadata.can_team
);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.group.id,
    props.group.version,
    props.staged,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
  ])
);
const defaults = computed(() => ({
  company_id: companyId.value,
  owner_id: props.group.owner_id || '',
  team_id: props.group.team_id || '',
  business_unit_id: props.group.business_unit_id || '',
  settings: { segment_id: props.group.segment_id || '' },
}));
let generation = 0;
let controller;
const validCandidate = row =>
  row &&
  ((Number.isSafeInteger(row.id) && row.id > 0) ||
    (props.staged && row.id === null && row.proposed_fields)) &&
  String(row.company_id) === String(companyId.value);
const check = async () => {
  if (
    locked.value ||
    !allowed.value ||
    !companyId.value ||
    selection.value.length >= 50
  )
    return;
  generation += 1;
  const current = generation;
  controller?.abort();
  controller = new AbortController();
  busy.value = true;
  error.value = '';
  candidate.value = null;
  created.value = false;
  step.value = 'select';
  try {
    const { data } = await API.portfolio(
      route.params.accountId,
      { company_id: companyId.value, page: 1, per_page: 1 },
      { signal: controller.signal }
    );
    if (current !== generation) return;
    if (
      data.meta.total === 1 &&
      data.payload.length === 1 &&
      validCandidate(data.payload[0])
    ) {
      candidate.value = data.payload[0];
      step.value = 'ready';
    } else if (data.meta.total === 0 && data.payload.length === 0)
      step.value = 'allocate';
    else throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.UNCONFIRMED'));
    unconfirmed.value = false;
  } catch (err) {
    if (current === generation) {
      error.value =
        message(err) || t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.UNCONFIRMED');
    }
  } finally {
    if (current === generation) busy.value = false;
  }
};
const allocate = async fields => {
  if (
    locked.value ||
    unconfirmed.value ||
    !allowed.value ||
    selection.value.length >= 50 ||
    step.value !== 'allocate' ||
    String(fields.company_id) !== String(companyId.value)
  )
    return;
  if (props.staged) {
    const proposal = {
      ...fields,
      company_id: Number(fields.company_id),
      owner_id: fields.owner_id || null,
      team_id: fields.team_id || null,
      business_unit_id: fields.business_unit_id || null,
    };
    if (!proposal.exception_reason?.trim()) delete proposal.exception_reason;
    else proposal.exception_reason = proposal.exception_reason.trim();
    candidate.value = {
      id: null,
      company_id: proposal.company_id,
      name: t('RELATIONSHIP.MASTER_ALLOCATION.CUSTOMER_ID', {
        id: proposal.company_id,
      }),
      proposed_fields: proposal,
    };
    step.value = 'ready';
    return;
  }
  const current = generation;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.saveAssignment(route.params.accountId, {
      ...fields,
      owner_id: fields.owner_id || null,
      team_id: fields.team_id || null,
      business_unit_id: fields.business_unit_id || null,
    });
    if (current !== generation) return;
    if (!validCandidate(data)) {
      unconfirmed.value = true;
      throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.UNCONFIRMED'));
    }
    candidate.value = data;
    created.value = true;
    step.value = 'ready';
  } catch (err) {
    if (current === generation) {
      if (!err.response || err.response.status >= 500) unconfirmed.value = true;
      error.value =
        message(err) || t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.UNCONFIRMED');
    }
  } finally {
    if (current === generation) busy.value = false;
  }
};
const review = () => {
  if (
    !props.staged &&
    !locked.value &&
    !selection.value.length &&
    allowed.value &&
    validCandidate(candidate.value)
  )
    emit('review', candidate.value);
};
const addToSelection = () => {
  if (
    locked.value ||
    !allowed.value ||
    unconfirmed.value ||
    !validCandidate(candidate.value) ||
    alreadySelected.value ||
    selection.value.length >= 50
  )
    return;
  selection.value = [
    ...selection.value,
    {
      id: candidate.value.id,
      company_id: candidate.value.company_id,
      name: candidate.value.name,
      ...(props.staged && candidate.value.proposed_fields
        ? { proposed_fields: candidate.value.proposed_fields }
        : {}),
    },
  ];
  selectionPage.value = selectionPages.value;
  companyId.value = null;
  candidate.value = null;
  created.value = false;
  step.value = 'select';
};
const removeSelection = id => {
  if (locked.value || !allowed.value) return;
  selection.value = selection.value.filter(row =>
    props.staged ? row.company_id !== id : row.id !== id
  );
  selectionPage.value = Math.min(selectionPage.value, selectionPages.value);
};
const reviewSelection = () => {
  if (
    locked.value ||
    !allowed.value ||
    unconfirmed.value ||
    companyId.value ||
    !selection.value.length ||
    selection.value.length > 50 ||
    !selectionReason.value.trim() ||
    selectionReason.value.length > 4000 ||
    !Number.isSafeInteger(props.group.version) ||
    props.group.version < 0
  )
    return;
  submitted.value = true;
  if (props.staged) {
    emit('masterBatch', {
      company_ids: selection.value.map(row => Number(row.company_id)),
      creations: selection.value
        .filter(row => row.proposed_fields)
        .map(row => row.proposed_fields),
      expected_version: props.group.version,
      reason: selectionReason.value.trim(),
    });
    return;
  }
  emit('batch', {
    assignment_ids: selection.value.map(row => row.id),
    active: true,
    expected_version: props.group.version,
    reason: selectionReason.value.trim(),
  });
};
watch(
  [identity, allowed],
  (_, previous) => {
    generation += 1;
    controller?.abort();
    candidate.value = null;
    selection.value = [];
    selectionReason.value = '';
    submitted.value = false;
    if (previous?.length) emit('close');
  },
  { immediate: true }
);
watch(companyId, () => {
  generation += 1;
  controller?.abort();
  candidate.value = null;
  error.value = '';
  step.value = 'select';
  unconfirmed.value = false;
});
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
    :title="masterCopy.title"
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
        {{ masterCopy.help }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p
        v-if="busy"
        role="status"
      >
        {{ t('RELATIONSHIP.LOADING') }}
      </p>
      <CompanyPicker
        v-if="step === 'select'"
        v-model="companyId"
        :disabled="locked || !allowed || selection.length >= 50"
      />
      <button
        v-if="step === 'select' || unconfirmed"
        type="button"
        :class="buttonClass"
        :disabled="locked || !allowed || !companyId || selection.length >= 50"
        @click="check"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.CHECK') }}
      </button>
      <template v-if="step === 'allocate'">
        <p class="rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11">
          {{ masterCopy.allocationNotice }}
        </p>
        <PortfolioAssignmentForm
          :metadata="metadata"
          :initial-value="defaults"
          :disabled="
            locked || !allowed || unconfirmed || selection.length >= 50
          "
          lock-company
          :submit-label="masterCopy.allocate"
          @submit="allocate"
        />
      </template>
      <template v-if="step === 'ready' && candidate">
        <p
          role="status"
          class="rounded-lg bg-n-teal-2 p-3 text-sm text-n-teal-11"
        >
          {{
            staged && candidate.proposed_fields
              ? t('RELATIONSHIP.MASTER_ALLOCATION.DRAFT_READY')
              : created
                ? t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.CREATED')
                : t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.EXISTING')
          }}
        </p>
        <p class="break-words font-semibold">{{ candidate.name }}</p>
        <button
          v-if="!staged"
          type="button"
          :class="buttonClass"
          :disabled="locked || !allowed || selection.length > 0"
          @click="review"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.REVIEW') }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          :disabled="
            locked || !allowed || alreadySelected || selection.length >= 50
          "
          data-test="master-add-selection"
          @click="addToSelection"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.ADD_SELECTION') }}
        </button>
        <p
          v-if="alreadySelected"
          class="text-sm"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.ALREADY_SELECTED') }}
        </p>
      </template>
      <button
        v-if="companyId"
        type="button"
        :class="buttonClass"
        :disabled="locked"
        data-test="master-another-customer"
        @click="companyId = null"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.ANOTHER_CUSTOMER') }}
      </button>
      <section
        v-if="selection.length"
        class="min-w-0 space-y-3 rounded-xl border border-n-violet-6 bg-n-solid-2 p-3"
      >
        <h3 class="font-semibold">
          {{
            t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.SELECTION_TITLE', {
              count: selection.length,
            })
          }}
        </h3>
        <p class="break-words text-sm text-n-slate-11">
          {{ masterCopy.selectionNotice }}
        </p>
        <ul class="space-y-2">
          <li
            v-for="row in selectionRows"
            :key="staged ? row.company_id : row.id"
            class="flex min-w-0 flex-wrap items-center justify-between gap-2"
            data-test="master-selection-row"
          >
            <span class="min-w-0 break-words">{{ row.name }}</span>
            <button
              type="button"
              :class="buttonClass"
              :disabled="locked || !allowed"
              data-test="master-remove-selection"
              :aria-label="
                t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.REMOVE_SELECTION', {
                  name: row.name,
                })
              "
              @click="removeSelection(staged ? row.company_id : row.id)"
            >
              {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.REMOVE') }}
            </button>
          </li>
        </ul>
        <nav
          class="flex flex-wrap items-center gap-2"
          :aria-label="
            t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.SELECTION_PAGES')
          "
        >
          <button
            type="button"
            :class="buttonClass"
            :disabled="locked || selectionPage <= 1"
            data-test="master-selection-previous"
            @click="selectionPage -= 1"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.PREVIOUS') }}
          </button>
          <span>{{
            t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.SELECTION_PAGE', {
              page: selectionPage,
              pages: selectionPages,
            })
          }}</span>
          <button
            type="button"
            :class="buttonClass"
            :disabled="locked || selectionPage >= selectionPages"
            data-test="master-selection-next"
            @click="selectionPage += 1"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.NEXT') }}
          </button>
        </nav>
        <form
          class="space-y-3"
          data-test="master-selection-review"
          @submit.prevent="reviewSelection"
        >
          <label class="block text-sm">
            <span>{{ selectionReasonLabel }}</span>
            <textarea
              v-model="selectionReason"
              :class="inputClass"
              required
              maxlength="4000"
              :disabled="locked || !allowed"
              data-test="master-selection-reason"
            />
          </label>
          <p
            v-if="companyId"
            class="text-sm text-n-amber-11"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.CURRENT_CHOICE') }}
          </p>
          <button
            type="submit"
            :class="buttonClass"
            :disabled="
              locked ||
              !allowed ||
              unconfirmed ||
              !!companyId ||
              !selectionReason.trim()
            "
            data-test="master-review-selection"
          >
            {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.REVIEW_SELECTION') }}
          </button>
        </form>
      </section>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="emit('close')"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.CANCEL') }}
      </button>
    </div>
  </Dialog>
</template>
