<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import BackofficeContractVersions from './BackofficeContractVersions.vue';
import BackofficeContractSigners from './BackofficeContractSigners.vue';
import BackofficeContractAuthority from './BackofficeContractAuthority.vue';
import { useBackofficePresentation } from './useBackofficePresentation';

defineProps({ record: { type: Object, required: true } });
const { text } = useBackofficePresentation();
const route = useRoute();
const router = useRouter();
const tab = computed(() =>
  ['signers', 'authority'].includes(route.query.contractTab)
    ? route.query.contractTab
    : 'versions'
);
const select = value =>
  router.replace({
    query: { ...route.query, tab: 'contracts', contractTab: value },
  });
</script>

<template>
  <section class="space-y-4">
    <nav
      class="flex gap-2 overflow-x-auto rounded-xl border border-n-weak bg-n-solid-2 p-2"
      :aria-label="text('CONTRACT_SIGNERS.NAVIGATION')"
    >
      <button
        v-for="item in ['versions', 'signers', 'authority']"
        :key="item"
        type="button"
        :aria-current="tab === item ? 'page' : undefined"
        class="shrink-0 rounded-lg border px-3 py-2 text-sm font-semibold"
        :class="
          tab === item
            ? 'border-n-blue-8 bg-n-blue-9 text-white'
            : 'border-n-violet-6 bg-n-violet-3 text-n-violet-12'
        "
        @click="select(item)"
      >
        {{ text(`CONTRACT_SIGNERS.TABS.${item}`) }}
      </button>
    </nav>
    <BackofficeContractVersions
      v-if="tab === 'versions'"
      :record="record"
    />
    <BackofficeContractSigners
      v-else-if="tab === 'signers'"
      :record="record"
    />
    <BackofficeContractAuthority
      v-else
      :record="record"
    />
  </section>
</template>
