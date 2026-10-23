<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { tones } from '../helpers/visualTheme';
defineProps({
  compact: { type: Boolean, default: false },
  interactive: { type: Boolean, default: false },
  label: { type: String, required: true },
  tone: {
    type: String,
    default: 'blue',
    validator: value => Object.hasOwn(tones, value),
  },
  icon: { type: String, default: 'i-lucide-chart-no-axes-combined' },
  value: {
    type: Number,
    default: null,
    validator: value =>
      value === null || (Number.isSafeInteger(value) && value >= 0),
  },
});
defineEmits(['activate']);
const { t } = useI18n();
</script>

<template>
  <component
    :is="interactive ? 'button' : 'section'"
    :type="interactive ? 'button' : undefined"
    class="flex flex-col gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-3 text-start focus-visible:ring-2 focus-visible:ring-n-blue-9"
    :class="interactive ? 'cursor-pointer hover:border-n-blue-8' : ''"
    :title="t('JRC_SERVICE_DESK.OVERVIEW.kpi_help')"
    :aria-label="`${label}: ${value === null ? t('JRC_SERVICE_DESK.OVERVIEW.kpi_label') : value}`"
    @click="interactive && $emit('activate')"
  >
    <div class="flex items-center justify-between gap-2">
      <span class="text-xs font-medium text-n-slate-11">
        {{ label }}
      </span>
      <span
        class="grid size-8 shrink-0 place-content-center rounded-lg"
        :class="tones[tone].soft"
      >
        <Icon :icon="icon" class="size-5" />
      </span>
    </div>
    <strong
      class="text-3xl leading-none font-bold tabular-nums"
      :class="value === null ? 'text-n-slate-11' : tones[tone].text"
    >
      {{ value === null ? t('JRC_SERVICE_DESK.COMMON.no_value') : value }}
    </strong>
    <span v-if="!compact" class="text-xs text-n-slate-11">
      {{
        t(
          value === null
            ? 'JRC_SERVICE_DESK.COMMON.not_available'
            : 'JRC_SERVICE_DESK.OPS.real_count'
        )
      }}
    </span>
  </component>
</template>
