<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import AudioFolderPicker from './AudioFolderPicker.vue';
import { useSelectedAudioMove } from '../composables/useSelectedAudioMove';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: String, required: true },
  contextKey: { type: String, required: true },
  canManage: { type: Boolean, required: true },
  selection: { type: Array, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['saved', 'denied']);
const { t } = useI18n();
const pickerShown = ref(false);
const state = useSelectedAudioMove({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  contextKey: computed(() => props.contextKey),
  canManage: computed(() => props.canManage),
  selection: computed(() => props.selection),
  onDenied: () => emit('denied'),
  onSaved: rows => emit('saved', rows),
});
const dialog = state.dialog;
const open = async () => {
  if (!state.canOpen.value || props.disabled) return;
  pickerShown.value = true;
  await state.open();
};
const close = () => {
  pickerShown.value = false;
  state.clear();
};
</script>

<template>
  <button
    type="button"
    :disabled="!state.canOpen.value || state.busy.value || disabled"
    data-open-audio-selected-move
    class="rounded-lg border border-n-blue-6 bg-n-solid-1 px-3 py-2 text-n-blue-11 disabled:opacity-40"
    @click="open"
  >
    <Icon
      icon="i-lucide-folder"
      class="mr-2 inline-block size-4"
      aria-hidden="true"
    />
    {{ t('JRC_CONTACT_CENTER.AUDIO_MOVE.OPEN') }}
  </button>
  <Dialog
    ref="dialog"
    contained
    use-form
    :title="t('JRC_CONTACT_CENTER.AUDIO_MOVE.TITLE')"
    :confirm-button-label="t('JRC_CONTACT_CENTER.AUDIO_MOVE.SAVE')"
    :cancel-button-label="t('JRC_CONTACT_CENTER.AUDIO_FILES.CANCEL')"
    :disable-confirm-button="!state.canSave.value"
    :is-loading="state.saving.value"
    :dismissible="!state.busy.value"
    @confirm="state.save"
    @close="close"
  >
    <div
      class="min-w-0 space-y-3 text-sm text-n-slate-12"
      data-audio-selected-move-dialog
    >
      <p class="break-words">
        {{ t('JRC_CONTACT_CENTER.AUDIO_MOVE.EXPLANATION') }}
      </p>
      <p v-if="state.opening.value" role="status">
        {{ t('JRC_CONTACT_CENTER.AUDIO_FILES.LOADING') }}
      </p>
      <p
        v-if="state.error.value"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{
          state.error.value === 'SOURCE_CHANGED'
            ? t('JRC_CONTACT_CENTER.AUDIO_MOVE.SOURCE_CHANGED')
            : t('JRC_CONTACT_CENTER.AUDIO_MOVE.ERROR')
        }}
      </p>
      <AudioFolderPicker
        v-if="pickerShown"
        v-model="state.folderId.value"
        :account-id="accountId"
        :unit-id="unitId"
        :disabled="state.busy.value"
        @denied="emit('denied')"
        @loading="state.folderLoading.value = $event"
      />
      <ul class="max-h-64 min-w-0 space-y-3 overflow-y-auto overscroll-contain">
        <li
          v-for="item in state.items.value"
          :key="item.assetId"
          :data-audio-selected-move-item="item.assetId"
          class="min-w-0 space-y-1 rounded-lg border border-n-weak p-3"
        >
          <p class="break-words font-semibold">{{ item.name }}</p>
          <p v-if="item.versionId" class="break-words">
            {{
              t('JRC_CONTACT_CENTER.AUDIO_MOVE.SOURCE_VERSION', {
                id: item.assetId,
                version: item.number,
              })
            }}
          </p>
          <p v-if="item.versionId" class="break-all">{{ item.sha256 }}</p>
          <p v-else class="break-words" data-audio-selected-no-file>
            {{ t('JRC_CONTACT_CENTER.AUDIO_MOVE.NO_FILE') }}
          </p>
          <p
            v-if="state.usages.value[item.assetId] !== undefined"
            class="break-words"
          >
            {{
              t('JRC_CONTACT_CENTER.AUDIO_ARCHIVE.LOCAL_USAGES', {
                count: state.usages.value[item.assetId],
              })
            }}
          </p>
        </li>
      </ul>
      <label
        class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3"
      >
        <input
          v-model="state.reviewed.value"
          type="checkbox"
          :disabled="
            !state.verified.value ||
            state.busy.value ||
            state.folderLoading.value
          "
          data-review-audio-selected-move
        />
        <span>{{ t('JRC_CONTACT_CENTER.AUDIO_MOVE.REVIEW') }}</span>
      </label>
    </div>
  </Dialog>
</template>
