<script setup>
import { computed, getCurrentInstance } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import AudioFolderPicker from './AudioFolderPicker.vue';
import { useSelectedAudioCopies } from '../composables/useSelectedAudioCopies';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: String, required: true },
  contextKey: { type: String, required: true },
  canManage: { type: Boolean, default: false },
  admitted: { type: Boolean, default: false },
  selection: { type: Array, default: () => [] },
  folderId: { type: String, default: '' },
});
const emit = defineEmits(['denied', 'settled']);
const { t } = useI18n();
const { uid } = getCurrentInstance();
const labels = computed(() => ({
  OPEN: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.OPEN'),
  TITLE: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.TITLE'),
  EXPLANATION: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.EXPLANATION'),
  NAME: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.NAME'),
  FOLDER: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.FOLDER'),
  COPY: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.COPY'),
  RETRY: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.RETRY'),
  REVIEW: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.REVIEW'),
  PENDING: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.PENDING'),
  SENDING: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.SENDING'),
  CONFIRMED: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.CONFIRMED'),
  UNCERTAIN: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.UNCERTAIN'),
  BLOCKED: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.BLOCKED'),
  PARTIAL: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.PARTIAL'),
  COMPLETE: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.COMPLETE'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.ERROR'),
  SOURCE_CHANGED: t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.SOURCE_CHANGED'),
}));
const label = key => labels.value[key];
const state = useSelectedAudioCopies({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  contextKey: computed(() => props.contextKey),
  canManage: computed(() => props.canManage),
  admitted: computed(() => props.admitted),
  selection: computed(() => props.selection),
  initialFolderId: computed(() => props.folderId),
  onDenied: () => emit('denied'),
  onSettled: outcome => emit('settled', outcome),
});
const popup = state.dialog;
const pending = computed(
  () =>
    state.items.value.filter(row => ['pending', 'sending'].includes(row.status))
      .length
);
const counts = computed(() =>
  t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.COUNTS', {
    confirmed: state.confirmed.value.length,
    uncertain: state.uncertain.value.length,
    blocked: state.items.value.filter(row => row.status === 'blocked').length,
    pending: pending.value,
    total: state.items.value.length,
  })
);
const nameId = row => `selected-audio-copy-${uid}-${row.assetId}`;
const denyFolderAccess = () => {
  state.forget();
  emit('denied');
};
</script>

<template>
  <button
    type="button"
    data-open-audio-selected-copies
    :disabled="!state.allowed.value || state.active.value || state.busy.value"
    class="inline-flex min-w-0 items-center gap-2 rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
    @click="state.open"
  >
    <Icon icon="i-lucide-copy" class="size-4 shrink-0" />
    <span>{{ label('OPEN') }}</span>
  </button>
  <Dialog
    ref="popup"
    contained
    use-form
    :title="label('TITLE')"
    :confirm-button-label="
      state.uncertain.value.length ? label('RETRY') : label('COPY')
    "
    :cancel-button-label="t('JRC_CONTACT_CENTER.AUDIO_FILES.CANCEL')"
    :show-confirm-button="!state.complete.value"
    :disable-confirm-button="!state.canSave.value"
    :is-loading="state.saving.value"
    :dismissible="!state.busy.value"
    @confirm="state.save"
    @close="state.dismiss"
  >
    <div
      class="min-w-0 space-y-3 text-sm text-n-slate-12"
      data-audio-selected-copies-dialog
    >
      <p>{{ label('EXPLANATION') }}</p>
      <p
        role="status"
        data-audio-selected-copies-counts
        :data-confirmed="state.confirmed.value.length"
        :data-uncertain="state.uncertain.value.length"
      >
        {{ counts }}
      </p>
      <p v-if="state.opening.value" role="status">
        {{ t('JRC_CONTACT_CENTER.AUDIO_FILES.LOADING') }}
      </p>
      <p
        v-if="state.error.value"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ label(state.error.value) }}
      </p>
      <p
        v-if="state.complete.value"
        role="status"
        class="rounded-lg bg-n-teal-2 p-3 text-n-teal-11"
        data-audio-selected-copies-complete
      >
        {{ label('COMPLETE') }}
      </p>
      <p v-else class="break-words">{{ label('PARTIAL') }}</p>
      <p class="font-semibold">{{ label('FOLDER') }}</p>
      <AudioFolderPicker
        :model-value="state.folderId.value"
        :account-id="accountId"
        :unit-id="unitId"
        :disabled="state.busy.value || state.locked.value"
        @update:model-value="state.folderId.value = $event"
        @loading="state.folderLoading.value = $event"
        @denied="denyFolderAccess"
      />
      <section
        v-for="row in state.items.value"
        :key="row.assetId"
        class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        :data-audio-selected-copy-item="row.assetId"
        :data-copy-status="row.status"
      >
        <p class="break-words">
          {{
            t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.SOURCE', {
              id: row.assetId,
              version: row.number,
            })
          }}
        </p>
        <p class="break-all">{{ row.sha256 }}</p>
        <label :for="nameId(row)" class="block">{{ label('NAME') }}</label>
        <input
          :id="nameId(row)"
          v-model="row.name"
          :data-audio-selected-copy-name="row.assetId"
          required
          maxlength="120"
          :disabled="state.busy.value || Boolean(row.payload)"
          class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
        <p
          class="break-words"
          :class="
            row.status === 'confirmed' ? 'text-n-teal-11' : 'text-n-slate-11'
          "
        >
          {{ label(row.status.toUpperCase()) }}
        </p>
        <p
          v-if="row.receipt"
          class="break-words"
          :data-audio-selected-copy-created="row.receipt.item.id"
        >
          {{
            t('JRC_CONTACT_CENTER.AUDIO_SELECTED_COPIES.CREATED', {
              name: row.receipt.item.name || row.name,
              id: row.receipt.item.id,
            })
          }}
        </p>
      </section>
      <label
        class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3"
      >
        <input
          v-model="state.reviewed.value"
          type="checkbox"
          data-review-audio-selected-copies
          :disabled="
            state.busy.value || !state.verified.value || state.complete.value
          "
          class="mt-1 shrink-0"
        />
        <span>{{ label('REVIEW') }}</span>
      </label>
    </div>
    <template #footer>
      <div class="flex w-full items-center justify-between gap-3">
        <Button
          type="button"
          variant="faded"
          color="slate"
          class="w-full"
          :label="t('JRC_CONTACT_CENTER.AUDIO_FILES.CANCEL')"
          :disabled="state.busy.value"
          data-audio-selected-copies-close
          @click="popup.close()"
        />
        <Button
          v-if="!state.complete.value"
          type="button"
          color="blue"
          class="w-full"
          :label="state.uncertain.value.length ? label('RETRY') : label('COPY')"
          :disabled="!state.canSave.value"
          :is-loading="state.saving.value"
          data-audio-selected-copies-confirm
          @click="state.save"
        />
      </div>
    </template>
  </Dialog>
</template>
