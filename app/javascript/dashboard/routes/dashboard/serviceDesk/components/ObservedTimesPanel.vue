<script setup>
import { useI18n } from 'vue-i18n';
defineProps({ measurement: { type: Object, default: null } });
const { t, locale } = useI18n();
const secondsLabel = value =>
  new Intl.NumberFormat(locale.value.replaceAll('_', '-')).format(value);
</script>

<template>
  <section
    v-if="measurement"
    class="grid gap-3 rounded-lg border border-n-weak p-4"
    data-testid="observed-times"
  >
    <h4 class="font-semibold">
      {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.observed_title') }}
    </h4>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.observed_help') }}
    </p>
    <p
      v-if="measurement.result === 'unavailable'"
      class="text-sm text-n-amber-11"
    >
      {{
        t(
          `JRC_SERVICE_DESK.SIMPLE_SLA.pending.${measurement.pending_reason || 'result_unavailable'}`
        )
      }}
      {{ t('JRC_SERVICE_DESK.SIMPLE_SLA.result_unavailable') }}
    </p>
    <dl class="grid gap-3 md:grid-cols-3">
      <div
        v-for="kind in ['first_response', 'resolution', 'closure']"
        :key="kind"
      >
        <dt class="text-sm font-medium">
          {{ t(`JRC_SERVICE_DESK.SIMPLE_SLA.times.${kind}`) }}
        </dt>
        <dd class="m-0 text-sm">
          {{
            measurement[kind]
              ? t('JRC_SERVICE_DESK.SIMPLE_SLA.wall_seconds', {
                  seconds: secondsLabel(measurement[kind].elapsed_seconds),
                })
              : t('JRC_SERVICE_DESK.SIMPLE_SLA.no_event')
          }}
        </dd>
      </div>
    </dl>
  </section>
</template>
