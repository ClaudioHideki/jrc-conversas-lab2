<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import api from 'dashboard/api/jrcCampaigns';
import {
  templateParts,
  variables,
  templateErrors,
} from '../templateConfiguration';

const props = defineProps({
  inboxId: { type: [Number, String], required: true },
  template: { type: Object, default: null },
  modelValue: { type: Object, required: true },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const parts = computed(() => templateParts(props.template));
const processed = computed(() => props.modelValue.processed_params || {});
const mediaKind = computed(() =>
  ['IMAGE', 'VIDEO', 'DOCUMENT'].includes(parts.value.header?.format)
    ? parts.value.header.format.toLowerCase()
    : null
);
const busy = ref(false);
const error = ref('');
const url = ref('');
const errors = computed(() => templateErrors(props.template, props.modelValue));
const setValue = (section, key, value) => {
  const next = {
    ...processed.value,
    [section]: { ...(processed.value[section] || {}), [key]: value },
  };
  emit('update:modelValue', { ...props.modelValue, processed_params: next });
};
const setButton = (index, value) => {
  const buttons = [...(processed.value.buttons || [])];
  while (buttons.length <= index) buttons.push({});
  buttons[index] = { type: 'url', parameter: value };
  emit('update:modelValue', {
    ...props.modelValue,
    processed_params: { ...processed.value, buttons },
  });
};
const removeMedia = () => {
  const next = { ...processed.value };
  delete next.header;
  emit('update:modelValue', { ...props.modelValue, processed_params: next });
};
const importMedia = async file => {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const response = file
      ? await api.uploadMedia(file, mediaKind.value, true)
      : await api.importMetaMedia(url.value, mediaKind.value);
    const asset = response.data;
    emit('update:modelValue', {
      ...props.modelValue,
      processed_params: {
        ...processed.value,
        header: {
          media_type: mediaKind.value,
          media_asset_id: asset.id,
          media_url: asset.url,
          media_name: asset.file_name,
        },
      },
    });
  } catch (failure) {
    error.value =
      failure?.response?.data?.errors?.join(', ') ||
      t('JRC_CAMPAIGNS.META.MEDIA_ERROR');
  } finally {
    busy.value = false;
  }
};
let mediaRequest = 0;
watch(
  () => [props.template, props.inboxId],
  async () => {
    mediaRequest += 1;
    const request = mediaRequest;
    if (
      !mediaKind.value ||
      !props.inboxId ||
      processed.value.header?.media_asset_id
    )
      return;
    busy.value = true;
    error.value = '';
    try {
      const { data } = await api.templateMedia(
        props.inboxId,
        props.template.name,
        props.template.language
      );
      if (request !== mediaRequest || processed.value.header?.media_asset_id)
        return;
      emit('update:modelValue', {
        ...props.modelValue,
        processed_params: {
          ...processed.value,
          header: {
            media_type: mediaKind.value,
            media_asset_id: data.id,
            media_url: data.url,
            media_name: data.file_name,
          },
        },
      });
    } catch {
      if (request === mediaRequest)
        error.value = t('JRC_CAMPAIGNS.META.EXAMPLE_UNAVAILABLE');
    } finally {
      if (request === mediaRequest) busy.value = false;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="space-y-3" data-testid="meta-template-editor">
    <p
      v-if="errors.includes('UNSUPPORTED')"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_CAMPAIGNS.META.UNSUPPORTED') }}
    </p>
    <div v-if="mediaKind" class="space-y-2 rounded-xl border border-n-weak p-3">
      <label class="block text-xs font-medium">
        {{ t('JRC_CAMPAIGNS.META.MEDIA', { kind: mediaKind }) }}
        <input
          type="file"
          :disabled="busy"
          :accept="
            mediaKind === 'image'
              ? 'image/jpeg,image/png'
              : mediaKind === 'video'
                ? 'video/mp4,video/3gpp'
                : 'application/pdf'
          "
          class="mt-2 block w-full text-sm"
          @change="importMedia($event.target.files?.[0])"
        />
      </label>
      <div class="flex flex-wrap gap-2">
        <input
          v-model="url"
          type="url"
          :placeholder="t('JRC_CAMPAIGNS.META.HTTPS_URL')"
          :disabled="busy"
          :aria-label="t('JRC_CAMPAIGNS.META.HTTPS_URL')"
          class="min-w-0 flex-1 rounded-lg border border-n-weak bg-n-background p-2 text-sm"
        />
        <button
          type="button"
          :disabled="busy || !url.startsWith('https://')"
          class="rounded-lg bg-n-alpha-2 p-2 text-xs"
          @click="importMedia(null)"
        >
          {{ t('JRC_CAMPAIGNS.META.IMPORT_URL') }}
        </button>
      </div>
      <p v-if="busy" role="status">{{ t('JRC_CAMPAIGNS.META.UPLOADING') }}</p>
      <p v-if="processed.header?.media_asset_id" class="text-xs text-n-teal-11">
        {{ t('JRC_CAMPAIGNS.META.UPLOADED') }} ·
        {{ processed.header.media_name }}
      </p>
      <button
        v-if="processed.header?.media_asset_id"
        type="button"
        :disabled="busy"
        class="text-xs text-n-ruby-11"
        @click="removeMedia"
      >
        {{ t('JRC_CAMPAIGNS.META.REMOVE') }}
      </button>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
    </div>
    <template v-for="section in ['header', 'body']" :key="section">
      <label
        v-for="variable in variables(parts[section]?.text)"
        :key="`${section}:${variable}`"
        class="block text-xs"
      >
        {{ t('JRC_CAMPAIGNS.META.VARIABLE', { section, variable }) }}
        <input
          :value="processed[section]?.[variable] || ''"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-background p-2 text-sm"
          list="campaign-template-mappings"
          @input="setValue(section, variable, $event.target.value)"
        />
      </label>
    </template>
    <datalist id="campaign-template-mappings">
      <option value="{{nome}}" />
      <option value="{{telefone}}" />
      <option value="{{email}}" />
    </datalist>
    <template v-for="(button, index) in parts.buttons" :key="index">
      <label
        v-if="button.type === 'URL' && variables(button.url).length"
        class="block text-xs"
      >
        {{ t('JRC_CAMPAIGNS.META.BUTTON_VARIABLE', { name: button.text }) }}
        <input
          :value="processed.buttons?.[index]?.parameter || ''"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-background p-2 text-sm"
          @input="setButton(index, $event.target.value)"
        />
      </label>
    </template>
    <p v-if="errors.length" role="status" class="text-xs text-n-ruby-11">
      {{ t('JRC_CAMPAIGNS.META.INCOMPLETE') }}
    </p>
  </div>
</template>
