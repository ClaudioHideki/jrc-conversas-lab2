<script setup>
import { computed, onMounted, ref } from 'vue';
import { useMutationObserver } from '@vueuse/core';
import { Line } from 'vue-chartjs';
import {
  CategoryScale,
  Chart as ChartJS,
  Filler,
  Legend,
  LineElement,
  LinearScale,
  PointElement,
  Tooltip,
} from 'chart.js';

const props = defineProps({
  series: { type: Array, default: () => [] },
  labels: { type: Object, required: true },
});

ChartJS.register(
  CategoryScale,
  Filler,
  Legend,
  LineElement,
  LinearScale,
  PointElement,
  Tooltip
);

const dark = ref(false);
onMounted(() => {
  const updateTheme = () => {
    dark.value =
      document.body.classList.contains('dark') ||
      document.documentElement.classList.contains('dark');
  };
  updateTheme();
  useMutationObserver([document.body, document.documentElement], updateTheme, {
    attributes: true,
    attributeFilter: ['class'],
  });
});
const textColor = computed(() => (dark.value ? '#cbd5e1' : '#334155'));

const metrics = [
  { key: 'sent', color: '#2563eb' },
  { key: 'delivered', color: '#10b981' },
  { key: 'read', color: '#7c3aed' },
  { key: 'replied', color: '#0891b2' },
  { key: 'failed', color: '#e11d48' },
];

const chartData = computed(() => ({
  labels: props.series.map(item =>
    new Intl.DateTimeFormat(undefined, {
      day: '2-digit',
      month: '2-digit',
    }).format(new Date(`${item.date}T00:00:00`))
  ),
  datasets: metrics.map(metric => ({
    label: props.labels[metric.key],
    data: props.series.map(item => Number(item[metric.key] || 0)),
    borderColor: metric.color,
    backgroundColor: metric.color,
    borderWidth: 2,
    pointRadius: props.series.length > 45 ? 0 : 2,
    pointHoverRadius: 4,
    tension: 0.35,
    fill: false,
  })),
}));

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' },
  plugins: {
    legend: {
      position: 'bottom',
      labels: {
        boxWidth: 9,
        boxHeight: 9,
        usePointStyle: true,
        color: textColor.value,
        font: { weight: '500' },
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      ticks: { maxTicksLimit: 10, color: textColor.value },
    },
    y: {
      beginAtZero: true,
      grid: { color: dark.value ? '#334155' : '#e2e8f0' },
      ticks: { color: textColor.value },
    },
  },
}));
</script>

<template>
  <div class="h-72">
    <Line :data="chartData" :options="chartOptions" />
  </div>
</template>
