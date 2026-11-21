<script setup>
import { computed, getCurrentInstance } from 'vue';
import { useI18n } from 'vue-i18n';
import AudioVersionPreview from './AudioVersionPreview.vue';
import { useIvrAudioReference } from '../composables/useIvrAudioReference';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: [String, Number], required: true },
  modelValue: { type: Object, default: null },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { uid } = getCurrentInstance();
const assetInputId = `ivr-menu-audio-asset-${uid}`;
const versionInputId = `ivr-menu-audio-version-${uid}`;
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.IVR_AUDIO.TITLE'),
  LIMITS: t('JRC_CONTACT_CENTER.IVR_AUDIO.LIMITS'),
  CHOOSE: t('JRC_CONTACT_CENTER.IVR_AUDIO.CHOOSE'),
  CHANGE: t('JRC_CONTACT_CENTER.IVR_AUDIO.CHANGE'),
  REMOVE: t('JRC_CONTACT_CENTER.IVR_AUDIO.REMOVE'),
  SEARCH: t('JRC_CONTACT_CENTER.IVR_AUDIO.SEARCH'),
  SEARCH_BUTTON: t('JRC_CONTACT_CENTER.IVR_AUDIO.SEARCH_BUTTON'),
  ASSET: t('JRC_CONTACT_CENTER.IVR_AUDIO.ASSET'),
  VERSION: t('JRC_CONTACT_CENTER.IVR_AUDIO.VERSION'),
  SELECT_ASSET: t('JRC_CONTACT_CENTER.IVR_AUDIO.SELECT_ASSET'),
  SELECT_VERSION: t('JRC_CONTACT_CENTER.IVR_AUDIO.SELECT_VERSION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.IVR_AUDIO.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.IVR_AUDIO.NEXT'),
  LOADING: t('JRC_CONTACT_CENTER.IVR_AUDIO.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.IVR_AUDIO.ERROR'),
  UNAVAILABLE: t('JRC_CONTACT_CENTER.IVR_AUDIO.UNAVAILABLE'),
  EMPTY: t('JRC_CONTACT_CENTER.IVR_AUDIO.EMPTY'),
  UNVERIFIED: t('JRC_CONTACT_CENTER.IVR_AUDIO.UNVERIFIED'),
  CONFIRM: t('JRC_CONTACT_CENTER.IVR_AUDIO.CONFIRM'),
  CANCEL: t('JRC_CONTACT_CENTER.IVR_AUDIO.CANCEL'),
  RETRY: t('JRC_CONTACT_CENTER.IVR_AUDIO.RETRY'),
}));
const text = (key, values = {}) => {
  if (key === 'PAGE') return t('JRC_CONTACT_CENTER.IVR_AUDIO.PAGE', values);
  if (key === 'PINNED') return t('JRC_CONTACT_CENTER.IVR_AUDIO.PINNED', values);
  if (key === 'VERSION_OPTION')
    return t('JRC_CONTACT_CENTER.IVR_AUDIO.VERSION_OPTION', values);
  return labels.value[key];
};
const picker = useIvrAudioReference({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  reference: computed(() => props.modelValue),
});
const { choosing, pinned, candidate, error, assets, versions, busy } = picker;
const preview = computed(() =>
  choosing.value ? candidate.value : pinned.value
);
const confirm = () => {
  if (
    props.disabled ||
    busy.value ||
    !candidate.value ||
    !picker.ready(candidate.value)
  )
    return;
  emit('update:modelValue', picker.versionReference(candidate.value));
};
const remove = () => {
  if (props.disabled) return;
  picker.cancel();
  emit('update:modelValue', null);
};
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 bg-n-blue-2 p-3"
    data-ivr-audio-reference
  >
    <h5 class="text-sm font-semibold text-n-slate-12">{{ text('TITLE') }}</h5>
    <p class="break-words text-xs text-n-slate-11">{{ text('LIMITS') }}</p>
    <p
      v-if="pinned"
      class="break-words text-sm text-n-slate-12"
      data-ivr-audio-pinned
    >
      {{ text('PINNED', { number: pinned.number, file: pinned.file_name }) }}
    </p>
    <p v-if="error" role="alert" class="break-words text-sm text-n-ruby-11">
      {{ text(error) }}
    </p>
    <div class="flex flex-wrap gap-2">
      <button
        type="button"
        :disabled="disabled || !unitId || busy"
        data-ivr-audio-choose
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
        @click="picker.begin"
      >
        {{ text(modelValue ? 'CHANGE' : 'CHOOSE') }}
      </button>
      <button
        v-if="modelValue"
        type="button"
        :disabled="disabled || busy"
        data-ivr-audio-remove
        class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-ruby-11"
        @click="remove"
      >
        {{ text('REMOVE') }}
      </button>
      <button
        v-if="modelValue && error"
        type="button"
        :disabled="disabled || busy"
        class="rounded-lg px-3 py-2 text-sm text-n-blue-11"
        @click="picker.checkPinned"
      >
        {{ text('RETRY') }}
      </button>
    </div>
    <div v-if="choosing" class="min-w-0 space-y-3" data-ivr-audio-chooser>
      <div class="flex min-w-0 flex-wrap gap-2">
        <input
          v-model="assets.q"
          type="search"
          :aria-label="text('SEARCH')"
          :disabled="disabled || busy"
          class="h-9 min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
          @keydown.enter.prevent="picker.loadAssets()"
        />
        <button
          type="button"
          :disabled="disabled || busy"
          class="rounded-lg border border-n-weak px-3 text-sm text-n-blue-11"
          @click="picker.loadAssets()"
        >
          {{ text('SEARCH_BUTTON') }}
        </button>
      </div>
      <p v-if="busy" role="status" class="text-sm text-n-slate-11">
        {{ text('LOADING') }}
      </p>
      <p v-else-if="!assets.items.length" class="text-sm text-n-slate-11">
        {{ text('EMPTY') }}
      </p>
      <div class="min-w-0">
        <label :for="assetInputId" class="block text-sm text-n-slate-12">{{
          text('ASSET')
        }}</label>
        <select
          :id="assetInputId"
          :value="versions.assetId"
          :disabled="disabled || busy"
          data-ivr-audio-asset
          class="mt-1 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2"
          @change="picker.loadVersions($event.target.value)"
        >
          <option value="">{{ text('SELECT_ASSET') }}</option>
          <option
            v-for="asset in assets.items"
            :key="asset.id"
            :value="asset.id"
          >
            {{ asset.name }}
          </option>
        </select>
      </div>
      <div
        v-if="assets.pages > 1"
        class="flex flex-wrap items-center gap-2 text-xs"
      >
        <button
          type="button"
          :disabled="disabled || busy || assets.page <= 1"
          @click="picker.loadAssets(assets.page - 1)"
        >
          {{ text('PREVIOUS') }}
        </button>
        <span>{{
          text('PAGE', { page: assets.page, pages: assets.pages })
        }}</span>
        <button
          type="button"
          :disabled="disabled || busy || assets.page >= assets.pages"
          @click="picker.loadAssets(assets.page + 1)"
        >
          {{ text('NEXT') }}
        </button>
      </div>
      <div v-if="versions.assetId" class="min-w-0">
        <label :for="versionInputId" class="block text-sm text-n-slate-12">{{
          text('VERSION')
        }}</label>
        <select
          :id="versionInputId"
          :value="candidate?.id || ''"
          :disabled="disabled || busy"
          data-ivr-audio-version
          class="mt-1 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2"
          @change="picker.select($event.target.value)"
        >
          <option value="">{{ text('SELECT_VERSION') }}</option>
          <option
            v-for="version in versions.items"
            :key="version.id"
            :value="version.id"
            :disabled="!picker.ready(version)"
          >
            {{
              text('VERSION_OPTION', {
                number: version.number,
                file: version.file_name,
                state: !picker.ready(version) ? text('UNVERIFIED') : '',
              })
            }}
          </option>
        </select>
      </div>
      <div
        v-if="versions.pages > 1"
        class="flex flex-wrap items-center gap-2 text-xs"
      >
        <button
          type="button"
          :disabled="disabled || busy || versions.page <= 1"
          @click="picker.loadVersions(versions.assetId, versions.page - 1)"
        >
          {{ text('PREVIOUS') }}
        </button>
        <span>{{
          text('PAGE', { page: versions.page, pages: versions.pages })
        }}</span>
        <button
          type="button"
          :disabled="disabled || busy || versions.page >= versions.pages"
          @click="picker.loadVersions(versions.assetId, versions.page + 1)"
        >
          {{ text('NEXT') }}
        </button>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          :disabled="disabled || busy || !candidate"
          data-ivr-audio-confirm
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
          @click="confirm"
        >
          {{ text('CONFIRM') }}
        </button>
        <button
          type="button"
          :disabled="disabled"
          class="rounded-lg px-3 py-2 text-sm text-n-blue-11"
          @click="picker.cancel"
        >
          {{ text('CANCEL') }}
        </button>
      </div>
    </div>
    <AudioVersionPreview
      v-if="preview"
      :key="`${preview.id}:${preview.technical_verification.id}`"
      :account-id="accountId"
      :asset-id="preview.audio_asset_id"
      :version="preview"
      :inspection-id="preview.technical_verification.id"
      :can-manage="!disabled"
      @denied="picker.denied"
    />
  </section>
</template>
