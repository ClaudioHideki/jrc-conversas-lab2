<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

defineProps({
  sla: { type: Array, default: () => [] },
  notifications: { type: Array, default: () => [] },
  surveys: { type: Array, default: () => [] },
});
const { t, locale } = useI18n();
const percentSign = '%';
const labels = computed(() => ({
  kinds: {
    first_response: t('SERVICE_DESK.clock_kinds.first_response'),
    attendance: t('SERVICE_DESK.clock_kinds.attendance'),
    resolution: t('SERVICE_DESK.clock_kinds.resolution'),
    ola: t('SERVICE_DESK.clock_kinds.ola'),
  },
  clockStates: {
    running: t('SERVICE_DESK.clock_states.running'),
    paused: t('SERVICE_DESK.clock_states.paused'),
    completed: t('SERVICE_DESK.clock_states.completed'),
    stopped: t('SERVICE_DESK.clock_states.stopped'),
  },
  basis: {
    business: t('SERVICE_DESK.clock_basis.business'),
    calendar: t('SERVICE_DESK.clock_basis.calendar'),
  },
  channels: {
    email: t('SERVICE_DESK.delivery_channels.email'),
    whatsapp: t('SERVICE_DESK.delivery_channels.whatsapp'),
  },
  deliveryStates: {
    blocked: t('SERVICE_DESK.delivery_states.blocked'),
    queued: t('SERVICE_DESK.delivery_states.queued'),
    dispatching: t('SERVICE_DESK.delivery_states.dispatching'),
    sent: t('SERVICE_DESK.delivery_states.sent'),
    delivered: t('SERVICE_DESK.delivery_states.delivered'),
    read: t('SERVICE_DESK.delivery_states.read'),
    failed: t('SERVICE_DESK.delivery_states.failed'),
    unknown: t('SERVICE_DESK.delivery_states.unknown'),
  },
  surveys: {
    nps: t('SERVICE_DESK.survey_kinds.nps'),
    csat: t('SERVICE_DESK.survey_kinds.csat'),
    ces: t('SERVICE_DESK.survey_kinds.ces'),
    custom: t('SERVICE_DESK.survey_kinds.custom'),
  },
}));
const date = (value, timeZone) =>
  new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
    ...(timeZone ? { timeZone } : {}),
  }).format(new Date(value));
const number = value =>
  new Intl.NumberFormat(locale.value, { maximumFractionDigits: 1 }).format(
    value
  );
const duration = seconds =>
  t('SERVICE_DESK.duration_minutes', { value: number(seconds / 60) });
</script>

<template>
  <section v-if="sla.length" class="grid gap-3" data-testid="portal-sla">
    <h4 class="font-medium">{{ t('SERVICE_DESK.sla') }}</h4>
    <article
      v-for="clock in sla"
      :key="clock.kind"
      class="grid gap-2 rounded-lg border border-n-weak p-3 text-sm"
    >
      <header class="flex flex-wrap items-center justify-between gap-2">
        <h5 class="font-medium">{{ labels.kinds[clock.kind] }}</h5>
        <span>{{ labels.clockStates[clock.state] }}</span>
      </header>
      <p
        :class="
          clock.breached ? 'font-medium text-n-ruby-11' : 'text-n-teal-11'
        "
      >
        {{
          clock.breached
            ? t('SERVICE_DESK.breached')
            : t('SERVICE_DESK.within_budget')
        }}
      </p>
      <dl class="grid grid-cols-2 gap-2">
        <dt>{{ t('SERVICE_DESK.budget') }}</dt>
        <dd>{{ duration(clock.budget_seconds) }}</dd>
        <dt>{{ t('SERVICE_DESK.elapsed') }}</dt>
        <dd>{{ duration(clock.elapsed_seconds) }}</dd>
        <dt>{{ t('SERVICE_DESK.remaining') }}</dt>
        <dd>{{ duration(clock.remaining_seconds) }}</dd>
        <dt>{{ t('SERVICE_DESK.consumed') }}</dt>
        <dd>{{ number(clock.consumed_percent) }}{{ percentSign }}</dd>
        <dt>{{ t('SERVICE_DESK.time_basis') }}</dt>
        <dd>{{ labels.basis[clock.time_basis] }}</dd>
        <dt>{{ t('SERVICE_DESK.due') }}</dt>
        <dd>
          <time :datetime="clock.due_at">{{
            date(clock.due_at, clock.timezone)
          }}</time>
        </dd>
        <dt>{{ t('SERVICE_DESK.observed') }}</dt>
        <dd>
          <time :datetime="clock.observed_at">{{
            date(clock.observed_at, clock.timezone)
          }}</time>
        </dd>
        <template v-if="clock.achieved_at">
          <dt>{{ t('SERVICE_DESK.achieved') }}</dt>
          <dd>
            <time :datetime="clock.achieved_at">{{
              date(clock.achieved_at, clock.timezone)
            }}</time>
          </dd>
        </template>
      </dl>
      <p>{{ clock.timezone }}</p>
    </article>
  </section>
  <section
    v-if="notifications.length"
    class="grid gap-3"
    data-testid="portal-notifications"
  >
    <h4 class="font-medium">{{ t('SERVICE_DESK.notifications') }}</h4>
    <p class="text-sm">{{ t('SERVICE_DESK.notification_evidence') }}</p>
    <article
      v-for="receipt in notifications"
      :key="receipt.id"
      class="grid gap-2 rounded-lg border border-n-weak p-3 text-sm"
    >
      <header class="flex flex-wrap justify-between gap-2">
        <span>{{ labels.channels[receipt.channel] }}</span>
        <span>{{ labels.deliveryStates[receipt.state] }}</span>
      </header>
      <p>{{ t('SERVICE_DESK.attempt', { value: receipt.attempt_number }) }}</p>
      <p v-if="receipt.body !== null" class="whitespace-pre-wrap">
        {{ receipt.body }}
      </p>
      <dl class="grid grid-cols-2 gap-2">
        <dt>{{ t('SERVICE_DESK.created') }}</dt>
        <dd>
          <time :datetime="receipt.created_at">{{
            date(receipt.created_at)
          }}</time>
        </dd>
        <dt>{{ t('SERVICE_DESK.updated') }}</dt>
        <dd>
          <time :datetime="receipt.updated_at">{{
            date(receipt.updated_at)
          }}</time>
        </dd>
        <template v-if="receipt.sent_at">
          <dt>{{ t('SERVICE_DESK.sent_at') }}</dt>
          <dd>
            <time :datetime="receipt.sent_at">{{ date(receipt.sent_at) }}</time>
          </dd>
        </template>
        <template v-if="receipt.delivered_at">
          <dt>{{ t('SERVICE_DESK.delivered_at') }}</dt>
          <dd>
            <time :datetime="receipt.delivered_at">{{
              date(receipt.delivered_at)
            }}</time>
          </dd>
        </template>
      </dl>
    </article>
  </section>
  <section
    v-if="surveys.length"
    class="grid gap-3"
    data-testid="portal-surveys"
  >
    <h4 class="font-medium">{{ t('SERVICE_DESK.surveys') }}</h4>
    <a
      v-for="survey in surveys"
      :key="survey.id"
      :href="survey.path"
      target="_blank"
      rel="noopener noreferrer"
      class="grid gap-2 rounded-lg border border-n-weak p-3 text-sm"
    >
      <span class="font-medium">{{ labels.surveys[survey.kind] }}</span>
      <span>{{
        t('SERVICE_DESK.survey_expires', { value: date(survey.expires_at) })
      }}</span>
    </a>
  </section>
</template>
