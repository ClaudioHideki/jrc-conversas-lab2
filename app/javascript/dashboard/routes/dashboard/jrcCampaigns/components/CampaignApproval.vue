<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import JrcCampaignsAPI from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';

const props = defineProps({ campaign: { type: Object, required: true } });
const emit = defineEmits(['close', 'approved']);
const { t } = useI18n();
const review = ref(null);
const accepted = ref(false);
const saving = ref(false);
const errorMessage = ref('');
const detail = (key, value) => {
  const labels = {
    REVIEW: t('JRC_CAMPAIGNS.GOVERNANCE.REVIEW'),
    SCHEDULE: t('JRC_CAMPAIGNS.GOVERNANCE.SCHEDULE'),
    INTERVAL: t('JRC_CAMPAIGNS.GOVERNANCE.INTERVAL'),
    WINDOW: t('JRC_CAMPAIGNS.GOVERNANCE.WINDOW'),
    INBOXES: t('JRC_CAMPAIGNS.GOVERNANCE.INBOXES'),
    FOLLOW_UP: t('JRC_CAMPAIGNS.GOVERNANCE.FOLLOW_UP'),
    AUDIENCE: t('JRC_CAMPAIGNS.GOVERNANCE.AUDIENCE'),
    ROTATION: t('JRC_CAMPAIGNS.GOVERNANCE.ROTATION'),
    RECURRENCE: t('JRC_CAMPAIGNS.GOVERNANCE.RECURRENCE'),
    CONVERSATION: t('JRC_CAMPAIGNS.GOVERNANCE.CONVERSATION'),
  };
  return `${labels[key]}: ${value}`;
};

onMounted(async () => {
  try {
    const { data } = await JrcCampaignsAPI.requestReview(props.campaign.id);
    review.value = data;
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.errors?.join(', ') ||
      t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED');
  }
});

const approve = async () => {
  if (!accepted.value || !review.value) return;
  saving.value = true;
  try {
    await JrcCampaignsAPI.approve(
      props.campaign.id,
      review.value.review_digest
    );
    useAlert(t('JRC_CAMPAIGNS.GOVERNANCE.APPROVED'));
    emit('approved');
  } catch (error) {
    errorMessage.value =
      error?.response?.data?.errors?.join(', ') ||
      t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED');
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-6"
    role="dialog"
    aria-modal="true"
    :aria-label="t('JRC_CAMPAIGNS.GOVERNANCE.REVIEW')"
  >
    <div
      class="max-h-full w-full max-w-3xl overflow-y-auto rounded-xl bg-n-background p-6 text-n-slate-12"
    >
      <div class="flex items-center justify-between gap-4">
        <h2 class="text-xl font-semibold">
          {{ detail('REVIEW', campaign.name) }}
        </h2>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="emit('close')"
        >
          {{ t('JRC_CAMPAIGNS.CLOSE') }}
        </button>
      </div>
      <p class="my-4 text-sm">{{ t('JRC_CAMPAIGNS.GOVERNANCE.POLICY') }}</p>
      <p
        v-if="
          review?.review_snapshot?.configuration?.evolution_connectors?.length
        "
        class="my-4 text-sm text-n-amber-11"
        role="note"
      >
        {{ t('JRC_CAMPAIGNS.EVOLUTION.WARNING') }}
      </p>
      <p v-if="errorMessage" role="alert" class="my-3 text-n-ruby-11">
        {{ errorMessage }}
      </p>
      <template v-if="review">
        <p
          v-for="connector in review.review_snapshot?.configuration
            ?.evolution_connectors || []"
          :key="connector.inbox_id"
          class="my-3 text-sm font-medium"
        >
          {{ t('JRC_CAMPAIGNS.EVOLUTION.SENDER') }}
          {{ connector.sender_number }} ·
          {{ t('JRC_CAMPAIGNS.EVOLUTION.CONNECTOR_LABEL') }}
        </p>
        <div class="space-y-3 rounded-lg border border-n-weak p-4">
          <p>
            {{
              detail(
                'SCHEDULE',
                review.scheduled_at || t('JRC_CAMPAIGNS.GOVERNANCE.MANUAL')
              )
            }}
          </p>
          <p>
            {{
              detail(
                'INTERVAL',
                t('JRC_CAMPAIGNS.GOVERNANCE.SECONDS', {
                  min: review.delay_min_seconds,
                  max: review.delay_max_seconds,
                })
              )
            }}
          </p>
          <p>
            {{
              detail(
                'WINDOW',
                `${review.sending_window.days.join(', ')} · ${review.sending_window.start}–${review.sending_window.end}`
              )
            }}
          </p>
          <p>
            {{
              detail(
                'INBOXES',
                review.campaign_inboxes.map(link => link.name).join(', ') ||
                  review.inbox_id
              )
            }}
          </p>
          <div
            v-for="step in review.steps"
            :key="step.id"
            class="rounded-lg bg-n-alpha-2 p-3"
          >
            <p class="font-medium">
              {{ `${step.kind} · ${step.template_name || step.body}` }}
            </p>
            <p v-if="step.subject">{{ step.subject }}</p>
            <p v-if="step.template_language">{{ step.template_language }}</p>
            <p v-if="step.media_url" class="break-all">{{ step.media_url }}</p>
            <p v-if="step.follow_up_after_hours">
              {{
                detail(
                  'FOLLOW_UP',
                  t('JRC_CAMPAIGNS.GOVERNANCE.HOURS', {
                    count: step.follow_up_after_hours,
                  })
                )
              }}
            </p>
            <div
              v-if="Object.keys(step.template_params || {}).length"
              class="whitespace-pre-wrap text-sm"
            >
              {{ JSON.stringify(step.template_params, null, 2) }}
            </div>
            <div
              v-for="(override, inboxId) in step.inbox_overrides"
              :key="inboxId"
              class="mt-2 rounded-lg border border-n-weak p-2"
            >
              <p>{{ detail('INBOXES', inboxId) }}</p>
              <p>{{ override.body || override.template_name }}</p>
              <p>{{ override.template_language }}</p>
              <p class="break-all">{{ override.media_url }}</p>
              <div class="whitespace-pre-wrap text-sm">
                {{ JSON.stringify(override.template_params || {}, null, 2) }}
              </div>
            </div>
          </div>
          <p>{{ detail('ROTATION', review.rotation_mode) }}</p>
          <p>
            {{ detail('RECURRENCE', JSON.stringify(review.recurrence_config)) }}
          </p>
          <p>{{ detail('CONVERSATION', review.conversation_mode) }}</p>
        </div>
        <h3 class="mt-4 font-semibold">
          {{ detail('AUDIENCE', review.review_snapshot.recipients.length) }}
        </h3>
        <div
          class="my-3 max-h-56 overflow-y-auto rounded-lg border border-n-weak p-3"
        >
          <p
            v-for="recipient in review.review_snapshot.recipients"
            :key="recipient.destination || recipient.phone_number"
            class="py-1 text-sm"
          >
            {{
              `${recipient.name || ''} · ${recipient.destination || recipient.email || recipient.phone_number}`
            }}
          </p>
          <p v-if="!review.review_snapshot.recipients.length">
            {{ t('JRC_CAMPAIGNS.GOVERNANCE.EMPTY_AUDIENCE') }}
          </p>
        </div>
        <label class="flex items-start gap-3 py-3">
          <input v-model="accepted" type="checkbox" class="mt-1" />
          <span>{{ t('JRC_CAMPAIGNS.GOVERNANCE.ATTEST') }}</span>
        </label>
        <button
          type="button"
          class="mt-3 rounded-lg bg-n-brand px-4 py-2 text-white disabled:opacity-40"
          :disabled="!accepted || saving"
          @click="approve"
        >
          {{ t('JRC_CAMPAIGNS.GOVERNANCE.APPROVE') }}
        </button>
      </template>
      <p v-else-if="!errorMessage">{{ t('JRC_CAMPAIGNS.LOADING') }}</p>
    </div>
  </div>
</template>
