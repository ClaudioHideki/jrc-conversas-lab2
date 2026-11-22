<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { validPauseOrigin } from './pauseOriginPresentation';
const props = defineProps({ request: { type: Object, required: true } });
const { t } = useI18n();
const verified = computed(() => validPauseOrigin(props.request));
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm text-n-slate-12"
    data-native-pause-approval-origin
  >
    <template v-if="verified">
      <h3 class="font-semibold">
        {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.ORIGIN_TITLE') }}
      </h3>
      <p>{{ request.origin.reason_label }}</p>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.ORIGIN_SCOPE_ONLY') }}
      </p>
      <p
        v-for="(name, index) in request.origin.scope_unit_names"
        :key="request.origin.scope_unit_ids[index]"
        class="break-words"
      >
        {{ name }}
      </p>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.ORIGIN_HISTORICAL') }}
      </p>
      <code class="block break-all text-xs">{{
        request.origin.context_digest
      }}</code>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.ORIGIN_PRIVATE') }}
      </p>
    </template>
    <p
      v-else
      role="alert"
    >
      {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.ORIGIN_UNVERIFIED') }}
    </p>
  </section>
</template>
