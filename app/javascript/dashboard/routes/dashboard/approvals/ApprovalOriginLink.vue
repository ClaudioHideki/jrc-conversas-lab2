<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { approvalOriginRoute } from './originRoute';
const props = defineProps({
  request: { type: Object, required: true },
  accountId: { type: [Number, String], default: null },
});
const emit = defineEmits(['authority']);
const { t } = useI18n();
const target = computed(() =>
  approvalOriginRoute(props.accountId, props.request)
);
const authority = computed(
  () => props.request.origin?.kind === 'contract_authority'
);
const distribution = computed(
  () => props.request.origin?.kind === 'portfolio_distribution'
);
</script>

<template>
  <RouterLink
    v-if="target"
    :to="target"
    target="_blank"
    rel="noopener noreferrer"
    class="inline-flex rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm font-semibold text-n-blue-12"
    >{{ t('JRC_APPROVALS.viewOrigin') }}</RouterLink
  >
  <button
    v-else-if="authority || distribution"
    type="button"
    class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm font-semibold text-n-blue-12"
    @click="emit('authority')"
  >
    {{
      t(
        distribution
          ? 'JRC_APPROVALS.viewDistributionOrigin'
          : 'JRC_APPROVALS.viewAuthorityOrigin'
      )
    }}
  </button>
  <p
    v-else
    class="text-sm text-n-slate-11"
  >
    {{ t('JRC_APPROVALS.originUnavailable') }}
  </p>
</template>
