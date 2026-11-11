<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';
const props = defineProps({
  accountId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const channelLabels = computed(() => ({
  voice: t('JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.voice'),
  whatsapp: t('JRC_CONTACT_CENTER.ACW_OPERATION.LIMIT_LABELS.whatsapp'),
}));
const limits = ref(null);
const voiceRequired = ref(null);
const saving = ref(false);
const failed = ref(false);
const saved = ref(false);
let generation = 0;
watch(
  () => props.accountId,
  async () => {
    generation += 1;
    const version = generation;
    limits.value = null;
    voiceRequired.value = null;
    failed.value = false;
    saved.value = false;
    try {
      const response = await ContactCenterAPI.acwPolicy(props.accountId);
      if (version === generation) {
        limits.value = response.data.item.limits;
        voiceRequired.value =
          typeof response.data.item.voice_required === 'boolean'
            ? response.data.item.voice_required
            : null;
      }
    } catch {
      if (version === generation) failed.value = true;
    }
  },
  { immediate: true }
);
const save = async () => {
  const version = generation;
  saving.value = true;
  failed.value = false;
  saved.value = false;
  try {
    const response = await ContactCenterAPI.updateAcwPolicy(
      props.accountId,
      {
        voice: Number(limits.value.voice),
        whatsapp: Number(limits.value.whatsapp),
      },
      typeof voiceRequired.value === 'boolean'
        ? { voice_required: voiceRequired.value }
        : {}
    );
    if (version === generation) {
      limits.value = response.data.item.limits;
      voiceRequired.value =
        typeof response.data.item.voice_required === 'boolean'
          ? response.data.item.voice_required
          : null;
      saved.value = true;
    }
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) saving.value = false;
  }
};
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section class="mt-5 rounded-xl border border-n-weak bg-n-solid-1 p-5">
    <h2 class="text-lg font-semibold">
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.POLICY_TITLE') }}
    </h2>
    <p class="mt-2 text-sm text-n-slate-11">
      {{ t('VOICE_V4.TABULATION_POLICY_HINT') }}
    </p>
    <form
      v-if="limits"
      class="mt-4 grid gap-4 sm:grid-cols-2"
      @submit.prevent="save"
    >
      <label
        v-if="typeof voiceRequired === 'boolean'"
        class="flex items-start gap-3 rounded-lg bg-n-alpha-2 p-3 text-sm sm:col-span-2"
      >
        <input
          v-model="voiceRequired"
          data-voice-tabulation-required
          type="checkbox"
          :disabled="saving"
          class="mt-1"
        />
        <span
          >{{ t('VOICE_V4.TABULATION_REQUIRED')
          }}<span class="mt-1 block text-xs text-n-slate-11">{{
            t('VOICE_V4.TABULATION_OPTIONAL_HINT')
          }}</span></span
        >
      </label>
      <label
        v-for="channel in ['voice', 'whatsapp']"
        :key="channel"
        class="text-sm font-medium"
      >
        {{ channelLabels[channel] }}
        <input
          v-model.number="limits[channel]"
          type="number"
          min="1"
          max="3600"
          required
          class="mt-1 h-10 w-full rounded-md border border-n-weak bg-n-solid-1 px-3"
        />
      </label>
      <button
        :disabled="saving"
        class="rounded-md bg-n-brand p-3 text-sm font-semibold text-white disabled:opacity-50"
        type="submit"
      >
        {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.SAVE_POLICY') }}
      </button>
    </form>
    <p v-if="failed" role="alert" class="mt-3 text-sm text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <p v-if="saved" role="status" class="mt-3 text-sm text-n-teal-11">
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.POLICY_SAVED') }}
    </p>
  </section>
</template>
