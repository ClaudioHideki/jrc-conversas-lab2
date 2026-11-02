<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Panel from './ServiceDeskPanel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  capacityPresentation,
  recentTicketActivity,
} from '../helpers/dashboardPresentation';
import { formatTimestamp } from '../helpers/presentation';
const props = defineProps({
  kind: { type: String, required: true },
  data: { type: Object, default: null },
  tickets: { type: Array, default: () => [] },
  canViewSla: Boolean,
  loading: Boolean,
});
const emit = defineEmits(['open', 'sla']);
const { t, locale } = useI18n();
const activity = computed(() => recentTicketActivity(props.tickets));
const members = computed(() =>
  (props.data?.capacity || []).map(row => ({
    ...row,
    measured: capacityPresentation(row),
  }))
);
</script>

<template>
  <Panel
    :title="t(`JRC_SERVICE_DESK.REFINEMENT.overview.${kind}`)"
    :icon="
      {
        activity: 'i-lucide-activity',
        team: 'i-lucide-users',
        risk: 'i-lucide-alarm-clock',
      }[kind]
    "
  >
    <template v-if="kind === 'risk'">
      <p v-if="data?.sla_coverage" class="mb-3 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.coverage', data.sla_coverage) }}
      </p>
      <template v-if="data?.sla">
        <p class="text-2xl font-semibold text-n-ruby-11">
          {{ data.sla.running_breached }}
        </p>
        <p class="mt-2 text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REFINEMENT.overview.breached_clocks') }}
        </p>
        <p class="mt-2 text-xs text-n-slate-11">
          {{
            t('JRC_SERVICE_DESK.REFINEMENT.overview.observed_cycles', {
              count: data.sla.observed_cycles,
            })
          }}
        </p>
        <p class="mt-2 text-xs text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REFINEMENT.overview.risk_limits') }}
        </p>
      </template>
      <p v-else class="text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.REFINEMENT.overview.unmeasured') }}
      </p>
      <Button
        v-if="canViewSla"
        class="mt-3"
        size="xs"
        variant="outline"
        :label="t('JRC_SERVICE_DESK.REDESIGN_DETAIL.view_sla')"
        @click="emit('sla')"
      />
    </template>
    <template v-else-if="kind === 'activity'">
      <p class="mb-3 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.REFINEMENT.overview.activity_notice') }}
      </p>
      <button
        v-for="row in activity"
        :key="row.id"
        type="button"
        class="mb-3 grid w-full gap-1 border-b border-n-weak pb-3 text-start text-xs focus-visible:ring-2 focus-visible:ring-n-blue-9"
        @click="emit('open', row.id)"
      >
        <strong class="break-words text-n-blue-11"
          >{{ row.number || row.id }} - {{ row.title }}</strong
        >
        <span>{{
          row.status?.name || t('JRC_SERVICE_DESK.COMMON.not_available')
        }}</span>
        <time :datetime="row.updated_at" class="text-n-slate-11">{{
          formatTimestamp(row.updated_at, locale)
        }}</time>
      </button>
      <p v-if="!activity.length" class="text-xs text-n-slate-11">
        {{
          t(
            loading
              ? 'JRC_SERVICE_DESK.STATES.loading'
              : 'JRC_SERVICE_DESK.COMMON.no_records'
          )
        }}
      </p>
    </template>
    <template v-else-if="kind === 'team'">
      <article
        v-for="member in members"
        :key="`${member.unit_id}:${member.id}`"
        class="mb-3 grid gap-2 rounded-lg bg-n-solid-2 p-3 text-xs"
      >
        <div class="flex flex-wrap justify-between gap-2">
          <strong>{{ member.name }}</strong
          ><span>{{
            t(`JRC_SERVICE_DESK.V2.availability.${member.availability}`)
          }}</span>
        </div>
        <template v-if="member.measured">
          <progress
            :value="member.measured.progress"
            :max="member.measured.maximum"
            class="w-full"
            :aria-label="member.name"
          />
          <span>{{
            t('JRC_SERVICE_DESK.REFINEMENT.overview.capacity', {
              active: member.active_tickets,
              total: member.capacity,
            })
          }}</span>
        </template>
        <span v-else>{{
          t('JRC_SERVICE_DESK.REFINEMENT.overview.no_capacity')
        }}</span>
      </article>
      <p v-if="!members.length" class="text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.REFINEMENT.overview.unmeasured') }}
      </p>
    </template>
  </Panel>
</template>
