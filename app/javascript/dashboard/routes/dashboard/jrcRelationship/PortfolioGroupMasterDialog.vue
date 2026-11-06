<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CompanyPicker from '../jrcCustomers/components/CompanyPicker.vue';
import PortfolioAssignmentForm from './PortfolioAssignmentForm.vue';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, message } from './definitions';
const props = defineProps({
  group: { type: Object, required: true },
  metadata: { type: Object, required: true },
});
const emit = defineEmits(['close', 'review']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const companyId = ref(null);
const candidate = ref(null);
const step = ref('select');
const busy = ref(false);
const error = ref('');
const created = ref(false);
const unconfirmed = ref(false);
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
  Number.isSafeInteger(row.id) &&
  row.id > 0 &&
  String(row.company_id) === String(companyId.value);
const check = async () => {
  if (busy.value || !allowed.value || !companyId.value) return;
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
    busy.value ||
    unconfirmed.value ||
    !allowed.value ||
    step.value !== 'allocate' ||
    String(fields.company_id) !== String(companyId.value)
  )
    return;
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
  if (!busy.value && allowed.value && validCandidate(candidate.value))
    emit('review', candidate.value);
};
watch(
  [identity, allowed],
  (_, previous) => {
    generation += 1;
    controller?.abort();
    candidate.value = null;
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
    :title="t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.TITLE')"
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
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.HELP') }}
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
        :disabled="busy || !allowed"
      />
      <button
        v-if="step === 'select' || unconfirmed"
        type="button"
        :class="buttonClass"
        :disabled="busy || !allowed || !companyId"
        @click="check"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.CHECK') }}
      </button>
      <template v-if="step === 'allocate'">
        <p class="rounded-lg bg-n-amber-2 p-3 text-sm text-n-amber-11">
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.ALLOCATION_NOTICE') }}
        </p>
        <PortfolioAssignmentForm
          :metadata="metadata"
          :initial-value="defaults"
          :disabled="busy || !allowed || unconfirmed"
          lock-company
          :submit-label="t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.ALLOCATE')"
          @submit="allocate"
        />
      </template>
      <template v-if="step === 'ready' && candidate">
        <p
          role="status"
          class="rounded-lg bg-n-teal-2 p-3 text-sm text-n-teal-11"
        >
          {{
            created
              ? t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.CREATED')
              : t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.EXISTING')
          }}
        </p>
        <p class="break-words font-semibold">{{ candidate.name }}</p>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || !allowed"
          @click="review"
        >
          {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.MASTER.REVIEW') }}
        </button>
      </template>
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
