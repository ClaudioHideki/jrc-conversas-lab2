<script setup>
// Test harness only: production controls and hook, real scoped Rails APIs, no SIP/provider.
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';
import PendingQualificationForm from 'dashboard/routes/dashboard/inbox/PendingQualificationForm.vue';
import QualificationDraftReview from 'dashboard/routes/dashboard/inbox/QualificationDraftReview.vue';
import QualificationDraftNavigation from 'dashboard/routes/dashboard/inbox/QualificationDraftNavigation.vue';
import { useAttendanceClosing } from 'dashboard/routes/dashboard/inbox/useAttendanceClosing';
import AgentStatePanel from 'dashboard/routes/dashboard/jrcContactCenter/views/AgentStatePanel.vue';

const route = useRoute();
const store = useStore();
const { t } = useI18n();
const context = ref(null);
const contextError = ref(false);
const now = ref(Date.now());
const props = reactive({
  accountId: route.params.accountId,
  currentCallId: route.params.callId,
  currentConversationId: null,
  ready: true,
});
const authorityKey = computed(() =>
  JSON.stringify([store.getters.getCurrentUser, context.value])
);
const canOperate = computed(() => context.value?.capabilities.operate === true);
const closing = useAttendanceClosing({
  props,
  authorityKey,
  enabled: computed(() => Boolean(context.value)),
  supportsClosing: computed(() => true),
  isVoice: computed(() => true),
  now,
  showClosing: () => {},
  restoreSelection: () => {},
});
const {
  pending,
  records,
  elapsed,
  limit,
  overdue,
  reason,
  result,
  note,
  draft,
  loading,
  saving,
  error,
  load,
  saveDraft,
  complete,
} = closing;
const { conflict, remote, canUseRemote, canReapply, canSave, saved } = draft;
const timer = setInterval(() => {
  now.value = Date.now();
}, 1000);
onBeforeUnmount(() => clearInterval(timer));
onMounted(async () => {
  try {
    context.value = (await ContactCenterAPI.context(props.accountId)).data;
  } catch {
    contextError.value = true;
  }
});
</script>

<template>
  <section class="mx-auto w-full min-w-0 max-w-3xl p-4" data-native-pending-acw>
    <AgentStatePanel
      v-if="route.query.with_pause === '1' && context"
      :account-id="props.accountId"
      :can-operate="canOperate"
      compact
      data-native-deferred-pause
    />
    <QualificationDraftNavigation
      :enabled="Boolean(context)"
      :dirty="draft.dirty.value"
      :conflict="conflict"
      :saving="saving"
      :authority-key="authorityKey"
    />
    <RouterLink
      :to="{
        name: 'jrc_contact_center_control_desk',
        params: { accountId: props.accountId },
      }"
      class="mb-4 inline-flex rounded-md border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12"
      data-qualification-leave-link
    >
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_LEAVE_BACK') }}
    </RouterLink>
    <h1 class="text-xl font-semibold text-n-slate-12">
      {{ t('JRC_CONTACT_CENTER.INBOX_360.FINISH_TABULATION') }}
    </h1>
    <p v-if="contextError || error" role="alert" data-qualification-error>
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_RELOAD') }}
    </p>
    <div
      v-if="pending"
      class="my-4 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    >
      <p
        class="text-sm text-n-slate-12"
        data-qualification-clock
        :data-overdue="overdue"
      >
        <span>{{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DURATION') }}</span>
        <span class="mx-2" data-acw-elapsed>{{ elapsed }}</span>
        <span>{{
          t('JRC_CONTACT_CENTER.ACW_OPERATION.APPLIED_LIMIT', { time: '' })
        }}</span>
        <span class="mx-2" data-acw-limit>{{ limit }}</span>
      </p>
    </div>
    <QualificationDraftReview
      v-if="conflict"
      :current="remote"
      :busy="saving || loading"
      :can-use-remote="canUseRemote"
      :can-reapply="canReapply"
      @reload="load"
      @use-remote="draft.useRemote"
      @reapply="draft.reapply"
    />
    <PendingQualificationForm
      v-if="pending || conflict"
      v-model:reason="reason"
      v-model:result="result"
      v-model:note="note"
      :disabled="!canOperate || saving || !pending"
      :conflict="conflict"
      :can-save="canSave"
      :saved="saved"
      :forms-present="closing.forms.present.value"
      :form-reason-codes="closing.forms.reasonCodes.value"
      :reason-options="closing.forms.reasonOptions.value"
      :reason-required="closing.forms.reasonRequired.value"
      :reason-revision="closing.forms.reasonRevision.value"
      :reason-confirmation="closing.confirmation.value"
      :confirmation-scope="closing.confirmationScope.value"
      :can-confirm-reason="closing.canConfirmReason.value"
      :confirmation-busy="saving"
      :confirmation-error="error"
      :selected-form="closing.forms.selected.value"
      :form-values="closing.forms.values.value"
      :form-loading="closing.forms.loading.value"
      :form-error="closing.forms.error.value"
      :form-ready="closing.forms.ready.value"
      @update-form-values="closing.forms.update"
      @reload-form="closing.forms.load"
      @save="saveDraft"
      @confirm-reason="closing.confirmReason"
      @complete="complete"
    />
    <p
      v-if="!pending && records.some(record => record.completed_at)"
      role="status"
      data-qualification-completed
    >
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.COMPLETED') }}
    </p>
  </section>
</template>
