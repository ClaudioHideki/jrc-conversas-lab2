<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useCustomerMaster } from '../useCustomerMaster';
import SegmentFilterPicker from './SegmentFilterPicker.vue';
import { buttonClass } from '../copy';

defineProps({ moduleKey: { type: String, required: true } });
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const { canAccess } = useCustomerMaster();
const selected = computed({
  get: () => route.query.customer_segment_id || '',
  set: value => {
    const query = { ...route.query };
    if (value) query.customer_segment_id = String(value);
    else delete query.customer_segment_id;
    delete query.page;
    router.replace({ query });
  },
});
</script>

<template>
  <div class="contents">
    <section
      v-if="canAccess || selected"
      class="mx-4 my-3 max-h-64 max-w-xl shrink-0 overflow-y-auto rounded-xl border border-n-violet-6 bg-n-violet-2 p-3 text-n-slate-12 sm:mx-6"
      :aria-label="t('CRM.CORPORATE_SEGMENTS.FILTER_LABEL')"
    >
      <h2 class="mb-2 text-sm font-semibold">
        {{ t('CRM.CORPORATE_SEGMENTS.FILTER_LABEL') }}
      </h2>
      <SegmentFilterPicker
        v-if="canAccess"
        v-model="selected"
        :module-key="moduleKey"
      />
      <button
        v-else
        type="button"
        :class="buttonClass"
        @click="selected = ''"
      >
        {{ t('CRM.CORPORATE_SEGMENTS.CLEAR_FILTER') }}
      </button>
      <p class="mt-2 text-xs text-n-slate-11">
        {{ t('CRM.CORPORATE_SEGMENTS.MODULE_FILTER_HELP') }}
      </p>
    </section>
  </div>
</template>
