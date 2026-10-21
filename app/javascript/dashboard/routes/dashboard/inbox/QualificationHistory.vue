<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { acwLabels } from './acwLabels';
const props = defineProps({ records: { type: Array, default: () => [] } });
const { t } = useI18n();
const labels = computed(() => acwLabels(t));
const completed = computed(() =>
  props.records.filter(record => record.completed_at)
);
const seconds = value =>
  `${Math.floor((value || 0) / 60)
    .toString()
    .padStart(2, '0')}:${((value || 0) % 60).toString().padStart(2, '0')}`;
</script>

<template>
  <section v-show="completed.length" class="space-y-3" aria-live="polite">
    <h3 class="text-sm font-semibold">
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.HISTORY') }}
    </h3>
    <article
      v-for="record in completed"
      :key="record.id"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 text-sm"
    >
      <p class="font-semibold">
        {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.COMPLETED') }}
      </p>
      <dl class="mt-3 grid grid-cols-1 gap-2 break-words">
        <div>
          <dt class="text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.CHANNEL') }}
          </dt>
          <dd>
            {{ labels.channels[record.channel] || record.channel }}
          </dd>
        </div>
        <div>
          <dt class="text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_REASON') }}
          </dt>
          <dd>
            {{ labels.reasons[record.reason_code] || record.reason_code }}
          </dd>
        </div>
        <div>
          <dt class="text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_RESULT') }}
          </dt>
          <dd>
            {{ labels.results[record.outcome_code] || record.outcome_code }}
          </dd>
        </div>
        <div>
          <dt class="text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.AGENT') }}
          </dt>
          <dd>{{ record.agent_name }}</dd>
        </div>
        <div>
          <dt class="text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DURATION') }}
          </dt>
          <dd>{{ seconds(record.duration_seconds) }}</dd>
        </div>
        <div v-if="record.attendance_seconds != null">
          <dt class="text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.ATTENDANCE_DURATION') }}
          </dt>
          <dd>{{ seconds(record.attendance_seconds) }}</dd>
        </div>
        <div>
          <dt class="text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.STATUS') }}
          </dt>
          <dd :class="record.overdue ? 'text-n-ruby-11' : 'text-n-teal-11'">
            {{
              record.overdue
                ? t('JRC_CONTACT_CENTER.ACW_OPERATION.HISTORY_OVERDUE')
                : t('JRC_CONTACT_CENTER.ACW_OPERATION.WITHIN_LIMIT')
            }}
          </dd>
        </div>
        <div v-if="record.notes">
          <dt class="text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_NOTE') }}
          </dt>
          <dd class="whitespace-pre-wrap">{{ record.notes }}</dd>
        </div>
      </dl>
    </article>
  </section>
</template>
