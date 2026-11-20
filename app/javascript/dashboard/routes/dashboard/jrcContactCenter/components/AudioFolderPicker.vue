<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: String, required: true },
  modelValue: { type: [String, Number], default: '' },
  currentName: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'denied', 'loading']);
const { t } = useI18n();
const labels = computed(() => ({
  SEARCH_PARENT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.SEARCH_PARENT'),
  PARENT_ERROR: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PARENT_ERROR'),
  PARENT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PARENT'),
  ROOT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.ROOT'),
  PAGINATION: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PAGINATION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.NEXT'),
}));
const label = key => labels.value[key];
const optionLabel = row =>
  [row.parent_name || label('ROOT'), row.name].join(' / ');
const query = ref('');
const page = ref(1);
const items = ref([]);
const pages = ref(0);
const loading = ref(false);
const error = ref(false);
let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  items.value = [];
  pages.value = 0;
  loading.value = true;
  error.value = false;
  emit('loading', true);
  try {
    const response = await API.audioFolders(props.accountId, {
      unit_id: props.unitId,
      q: query.value,
      page: page.value,
      per_page: 20,
    });
    if (version !== generation) return;
    items.value = response.data.items;
    pages.value = response.data.meta.pages;
  } catch (failure) {
    if (version === generation) {
      error.value = true;
      if ([401, 403, 404].includes(failure?.response?.status)) emit('denied');
    }
  } finally {
    if (version === generation) {
      loading.value = false;
      emit('loading', error.value);
    }
  }
};
watch([() => props.accountId, () => props.unitId, query, page], load, {
  immediate: true,
});
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <div class="min-w-0 space-y-3">
    <label class="block min-w-0">
      <span>{{ label('SEARCH_PARENT') }}</span>
      <input
        v-model="query"
        :disabled="disabled"
        maxlength="100"
        data-audio-asset-folder-search
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        @input="page = 1"
      />
    </label>
    <p v-if="error" role="alert" class="text-n-ruby-11">
      {{ label('PARENT_ERROR') }}
    </p>
    <label class="block min-w-0">
      <span>{{ label('PARENT') }}</span>

      <select
        :value="modelValue"
        :disabled="disabled || loading || error"
        data-audio-asset-folder
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        @change="emit('update:modelValue', $event.target.value)"
      >
        <option value="">{{ label('ROOT') }}</option>
        <option
          v-if="
            modelValue &&
            !items.some(row => String(row.id) === String(modelValue))
          "
          :value="modelValue"
        >
          {{ currentName || modelValue }}
        </option>
        <option v-for="row in items" :key="row.id" :value="row.id">
          {{ optionLabel(row) }}
        </option>
      </select>
    </label>
    <nav
      v-if="pages > 1"
      class="flex flex-wrap gap-3"
      :aria-label="label('PAGINATION')"
    >
      <button
        type="button"
        :disabled="disabled || loading || page <= 1"
        @click="page -= 1"
      >
        {{ label('PREVIOUS') }}
      </button>
      <button
        type="button"
        :disabled="disabled || loading || page >= pages"
        @click="page += 1"
      >
        {{ label('NEXT') }}
      </button>
    </nav>
  </div>
</template>
