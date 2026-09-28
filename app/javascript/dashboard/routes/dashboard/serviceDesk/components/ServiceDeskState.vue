<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
const props = defineProps({ status: { type: String, default: 'pending' }, compact: { type: Boolean, default: false }, retry: { type: Boolean, default: false }, description: { type: String, default: '' } });
const emit = defineEmits(['retry']);
const { t } = useI18n();
const state = computed(() => ['idle', 'loading', 'pending', 'denied', 'unauthenticated', 'error', 'invalid_contract', 'invalid_request', 'not_found', 'empty', 'disabled'].includes(props.status) ? props.status : 'idle');
const icon = computed(() => ['denied', 'unauthenticated', 'disabled'].includes(state.value) ? 'i-lucide-lock-keyhole' : ['error', 'invalid_contract', 'invalid_request'].includes(state.value) ? 'i-lucide-circle-alert' : 'i-lucide-inbox');
</script>
<template>
  <div
    class="sd-state"
    :class="{ 'sd-state-compact': compact }"
    role="status"
    aria-live="polite"
    :aria-busy="state === 'loading'"
  >
    <Spinner v-if="state === 'loading'" class="text-n-blue-11" :size="24" />
    <Icon v-else :icon="icon" class="size-7 text-n-slate-10" />
    <h3 class="text-sm text-n-slate-12 font-semibold m-0">
      {{ t(`JRC_SERVICE_DESK.STATES.${state}`) }}
    </h3>
    <p class="text-sm text-n-slate-11 m-0 max-w-xl">
      {{ description || t(`JRC_SERVICE_DESK.STATES.${state}_help`) }}
    </p>
    <Button
      v-if="retry && !['loading', 'empty', 'disabled'].includes(state)"
      :label="t('JRC_SERVICE_DESK.COMMON.retry')"
      variant="outline"
      color="slate"
      size="sm"
      @click="emit('retry')"
    />
  </div>
</template>
