<script setup>
import { useI18n } from 'vue-i18n';
import { computed } from 'vue';
import VisualShowcasePage from '../../components/visual/VisualShowcasePage.vue';
import { contactCenterScreen } from '../../demo/contactCenterVisualCatalog';

const props = defineProps({
  screenKey: { type: String, required: true },
});

const { t } = useI18n();

const screen = computed(() => contactCenterScreen(props.screenKey, t));
</script>

<template>
  <VisualShowcasePage :screen="screen" />
</template>
