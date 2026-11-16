<script setup>
import { computed, ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { MESSAGE_STATUS } from './constants';

import Icon from 'next/icon/Icon.vue';

const { status, statusLabel } = defineProps({
  status: {
    type: String,
    required: true,
    validator: value => Object.values(MESSAGE_STATUS).includes(value),
  },
  statusLabel: { type: String, default: '' },
});

const { t } = useI18n();

const progresIconSequence = [
  'i-lucide-clock-1',
  'i-lucide-clock-2',
  'i-lucide-clock-3',
  'i-lucide-clock-4',
  'i-lucide-clock-5',
  'i-lucide-clock-6',
  'i-lucide-clock-7',
  'i-lucide-clock-8',
  'i-lucide-clock-9',
  'i-lucide-clock-10',
  'i-lucide-clock-11',
  'i-lucide-clock-12',
];

const progessIcon = ref(progresIconSequence[0]);

const rotateIcon = () => {
  const currentIndex = progresIconSequence.indexOf(progessIcon.value);
  const nextIndex = (currentIndex + 1) % progresIconSequence.length;
  progessIcon.value = progresIconSequence[nextIndex];
};

useIntervalFn(rotateIcon, 500, {
  immediate: status === MESSAGE_STATUS.PROGRESS,
  immediateCallback: false,
});

const statusIcon = computed(() => {
  const statusIconMap = {
    [MESSAGE_STATUS.SENT]: 'i-lucide-check',
    [MESSAGE_STATUS.DELIVERED]: 'i-lucide-check-check',
    [MESSAGE_STATUS.READ]: 'i-lucide-check-check',
  };

  return statusIconMap[status];
});

const statusColor = computed(() => {
  const statusIconMap = {
    [MESSAGE_STATUS.SENT]: 'text-n-slate-10',
    [MESSAGE_STATUS.DELIVERED]: 'text-n-slate-10',
    [MESSAGE_STATUS.READ]: 'text-[#7EB6FF]',
  };

  return statusIconMap[status];
});

const tooltipText = computed(() => {
  const statusTextMap = {
    [MESSAGE_STATUS.SENT]: t('CHAT_LIST.SENT'),
    [MESSAGE_STATUS.DELIVERED]: t('CHAT_LIST.DELIVERED'),
    [MESSAGE_STATUS.READ]: t('CHAT_LIST.MESSAGE_READ'),
    [MESSAGE_STATUS.PROGRESS]: t('CHAT_LIST.SENDING'),
  };

  return statusLabel || statusTextMap[status];
});
</script>

<template>
  <Icon
    v-if="status === MESSAGE_STATUS.PROGRESS"
    v-tooltip.top-start="tooltipText"
    :icon="progessIcon"
    :aria-label="tooltipText"
    class="text-n-slate-10"
  />
  <Icon
    v-else
    v-tooltip.top-start="tooltipText"
    :icon="statusIcon"
    :aria-label="tooltipText"
    :class="statusColor"
    class="size-[14px]"
  />
</template>
