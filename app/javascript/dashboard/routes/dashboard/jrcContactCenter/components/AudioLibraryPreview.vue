<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';
import AudioVersionPreview from './AudioVersionPreview.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: String, required: true },
  asset: { type: Object, required: true },
  canManage: { type: Boolean, required: true },
});
const emit = defineEmits(['close', 'denied']);
const { t } = useI18n();
const dialog = ref(null);
const item = ref(null);
const loading = ref(true);
const error = ref('');
const errorText = computed(
  () =>
    ({
      VERSION_CHANGED: t(
        'JRC_CONTACT_CENTER.AUDIO_ROW_PREVIEW.VERSION_CHANGED'
      ),
      NOT_READY: t('JRC_CONTACT_CENTER.AUDIO_ROW_PREVIEW.NOT_READY'),
      ERROR: t('JRC_CONTACT_CENTER.AUDIO_ROW_PREVIEW.ERROR'),
    })[error.value] || ''
);
const verification = computed(
  () => item.value?.latest_version?.technical_verification
);
let alive = true;
const load = async () => {
  if (!props.canManage) {
    loading.value = false;
    emit('denied');
    return;
  }
  try {
    const response = await API.audioAsset(props.accountId, props.asset.id);
    if (!alive || !props.canManage) return;
    const current = response.data.item;
    if (
      String(response.data.account_id) !== String(props.accountId) ||
      current?.id !== props.asset.id ||
      current.unit_id !== props.unitId
    )
      throw new TypeError('Invalid current authorized audio identity');
    if (current.latest_version?.id !== props.asset.latest_version?.id) {
      error.value = 'VERSION_CHANGED';
      return;
    }
    if (current.latest_version?.technical_verification?.ready !== true) {
      error.value = 'NOT_READY';
      return;
    }
    item.value = current;
  } catch (failure) {
    if (!alive) return;
    if ([401, 403, 404].includes(failure?.response?.status)) emit('denied');
    else error.value = 'ERROR';
  } finally {
    if (alive) loading.value = false;
  }
};
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(() => {
  alive = false;
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('JRC_CONTACT_CENTER.AUDIO_ROW_PREVIEW.TITLE')"
    width="lg"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :close-on-click-outside="false"
    contained
    @close="emit('close')"
  >
    <div
      class="min-w-0 space-y-4 text-sm text-n-slate-12"
      data-audio-row-preview
    >
      <p class="break-words font-semibold">{{ asset.name }}</p>
      <p v-if="loading" role="status">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <p v-else-if="error" role="alert" class="break-words text-n-ruby-11">
        {{ errorText }}
      </p>
      <AudioVersionPreview
        v-if="item && canManage"
        :key="`${item.id}:${item.latest_version.id}`"
        :account-id="accountId"
        :asset-id="item.id"
        :version="item.latest_version"
        :inspection-id="verification.id"
        :metadata="verification.metadata"
        :can-manage="canManage"
        open-on-mount
        @denied="emit('denied')"
      />
      <button
        type="button"
        data-close-audio-row-preview
        class="rounded-lg border border-n-weak px-3 py-2 text-n-slate-12"
        @click="dialog.close()"
      >
        {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.CLOSE') }}
      </button>
    </div>
  </Dialog>
</template>
