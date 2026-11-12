<script setup>
import { computed, reactive, ref, onMounted, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { buttonClass, inputClass, STATES } from './definitions';
import { isWaitingStatus, validWaitingReview } from './waitingReview';
import { alertReviewLabels } from './alertReview';
const props = defineProps({
  record: { type: Object, required: true },
  busy: Boolean,
  error: { type: String, default: '' },
  initialTab: { type: String, default: 'result' },
});
const emit = defineEmits(['save', 'close']);
const { t } = useI18n();
const reviewLabels = computed(() => alertReviewLabels(t));
const dialog = ref(null);
const tab = ref(props.initialTab);
const localTime = value => {
  if (!value) return '';
  const date = new Date(value);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
};
const form = reactive({
  status: props.record.status,
  result: props.record.result || '',
  next_step: props.record.next_step || '',
  return_at: localTime(props.record.return_at),
  customer_confirmation: props.record.customer_confirmation || 'pending',
  customer_feedback: props.record.customer_feedback || '',
  waiting_reason: props.record.metadata?.waiting_reason || '',
});
const waiting = computed(() => isWaitingStatus(form.status));
const alertReview = reactive({
  status: props.record.alert_review?.status || 'pending',
  note: props.record.alert_review?.note || '',
});
const reviewChanged = computed(
  () =>
    alertReview.status !== (props.record.alert_review?.status || 'pending') ||
    alertReview.note !== (props.record.alert_review?.note || '')
);
const reviewError = ref(false);
const attemptedReview = ref(false);
const waitingError = computed(
  () => attemptedReview.value && waiting.value && !validWaitingReview(form)
);
watch(
  () => form.status,
  status => {
    if (isWaitingStatus(status)) tab.value = 'followup';
  }
);
const invalidField = async event => {
  const fieldTab = event.target.closest('[data-action-tab]')?.dataset.actionTab;
  if (fieldTab) tab.value = fieldTab;
  if (waiting.value && fieldTab === 'followup') attemptedReview.value = true;
  await nextTick();
  event.target.focus();
};
const submit = () => {
  if (props.busy) return;
  if (
    props.record.alert_review?.available &&
    reviewChanged.value &&
    !alertReview.note.trim()
  ) {
    reviewError.value = true;
    tab.value = 'result';
    return;
  }
  if (waiting.value && !validWaitingReview(form)) {
    attemptedReview.value = true;
    tab.value = 'followup';
    return;
  }
  emit('save', {
    ...form,
    ...(props.record.alert_review?.available && reviewChanged.value
      ? {
          alert_review_status: alertReview.status,
          alert_review_note: alertReview.note,
        }
      : {}),
    return_at: form.return_at ? new Date(form.return_at).toISOString() : null,
  });
};
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    width="2xl"
    :title="t('RELATIONSHIP.V2.RECORD_RESULT')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!busy"
    @close="emit('close')"
  >
    <form
      class="space-y-4"
      @submit.prevent="submit"
      @invalid.capture="invalidField"
    >
      <div
        class="flex gap-2"
        role="tablist"
        :aria-label="t('RELATIONSHIP.V2.RECORD_RESULT')"
      >
        <button
          v-for="key in ['result', 'followup']"
          :key="key"
          type="button"
          role="tab"
          :aria-selected="tab === key"
          :class="[
            buttonClass,
            tab === key && 'border-n-violet-8 bg-n-violet-3 text-n-violet-12 ',
          ]"
          @click="tab = key"
        >
          {{ t(`RELATIONSHIP.V2.TABS.${key}`) }}
        </button>
      </div>
      <p
        v-if="error"
        role="alert"
        class="text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p
        v-if="waitingError"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('RELATIONSHIP.V2.WAITING_REVIEW_REQUIRED') }}
      </p>
      <div
        v-show="tab === 'result'"
        data-action-tab="result"
        class="space-y-3"
      >
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.FIELDS.status')
          }}<select
            v-model="form.status"
            data-testid="action-status"
            :class="inputClass"
          >
            <option
              v-for="status in STATES.actions"
              :key="status"
              :value="status"
            >
              {{ t(`RELATIONSHIP.STATES.${status}`) }}
            </option>
          </select></label
        >
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.FIELDS.result')
          }}<textarea
            v-model="form.result"
            :class="inputClass"
            rows="3"
            :required="form.status === 'completed'"
            maxlength="8000"
          />
        </label>
        <fieldset
          v-if="record.alert_review?.available"
          class="space-y-3 rounded-lg border border-n-violet-6 bg-n-violet-2 p-3"
          data-testid="alert-review-editor"
        >
          <legend class="text-sm font-semibold">
            {{ t('RELATIONSHIP.ALERT_REVIEW.TITLE') }}
          </legend>
          <p class="text-xs text-n-slate-11">
            {{ t('RELATIONSHIP.ALERT_REVIEW.NOTICE') }}
          </p>
          <p
            v-if="reviewError"
            role="alert"
            class="text-sm text-n-ruby-11"
          >
            {{ t('RELATIONSHIP.ALERT_REVIEW.REQUIRED') }}
          </p>
          <p
            v-if="record.alert_review.stale"
            class="text-sm text-n-amber-11"
          >
            {{ t('RELATIONSHIP.ALERT_REVIEW.STALE') }}
          </p>
          <label class="block text-sm">
            {{ t('RELATIONSHIP.ALERT_REVIEW.ASSESSMENT') }}
            <select
              v-model="alertReview.status"
              :class="inputClass"
              data-testid="alert-review-status"
            >
              <option
                v-for="(label, value) in reviewLabels"
                :key="value"
                :value="value"
              >
                {{ label }}
              </option>
            </select>
          </label>
          <label class="block text-sm">
            {{ t('RELATIONSHIP.ALERT_REVIEW.REASON') }}
            <textarea
              v-model="alertReview.note"
              data-testid="alert-review-note"
              :class="inputClass"
              rows="3"
              maxlength="4000"
              :required="reviewChanged"
            />
          </label>
        </fieldset>
        <p
          class="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900 dark:border-amber-800 dark:bg-amber-950/50 dark:text-amber-200"
        >
          {{ t('RELATIONSHIP.V2.TECHNICAL_NOT_CONFIRMATION') }}
        </p>
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.FIELDS.customer_confirmation')
          }}<select
            v-model="form.customer_confirmation"
            :class="inputClass"
          >
            <option
              v-for="value in [
                'pending',
                'confirmed',
                'unresolved',
                'not_applicable',
              ]"
              :key="value"
              :value="value"
            >
              {{ t(`RELATIONSHIP.V2.CONFIRMATION.${value}`) }}
            </option>
          </select></label
        >
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.FIELDS.customer_feedback')
          }}<textarea
            v-model="form.customer_feedback"
            :class="inputClass"
            rows="2"
            maxlength="8000"
            :required="
              ['confirmed', 'unresolved'].includes(form.customer_confirmation)
            "
          />
        </label>
      </div>
      <div
        v-show="tab === 'followup'"
        data-action-tab="followup"
        class="space-y-3"
      >
        <label
          v-if="waiting"
          class="block text-sm"
        >
          {{ t('RELATIONSHIP.FIELDS.waiting_reason') }}
          <textarea
            v-model="form.waiting_reason"
            data-testid="action-waiting-reason"
            :class="inputClass"
            rows="3"
            maxlength="4000"
            required
          />
        </label>
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.FIELDS.next_step')
          }}<textarea
            v-model="form.next_step"
            data-testid="action-next-step"
            :class="inputClass"
            rows="3"
            maxlength="4000"
            :required="waiting || !!form.return_at"
          />
        </label>
        <label class="block text-sm"
          >{{ t('RELATIONSHIP.FIELDS.return_at')
          }}<input
            v-model="form.return_at"
            data-testid="action-return-at"
            type="datetime-local"
            :class="inputClass"
            :required="
              waiting ||
              (!!form.next_step &&
                !['completed', 'dismissed'].includes(form.status))
            "
        /></label>
      </div>
      <div class="flex justify-end gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="dialog.close()"
        >
          {{ t('RELATIONSHIP.CLOSE') }}</button
        ><button
          type="submit"
          class="rounded-lg bg-n-violet-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
          :disabled="busy"
        >
          {{ t(busy ? 'RELATIONSHIP.LOADING' : 'RELATIONSHIP.SAVE') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
