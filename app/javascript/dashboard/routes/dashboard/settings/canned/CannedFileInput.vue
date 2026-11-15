<script setup>
import { computed, onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({
  initialFile: { type: Object, default: null },
  disabled: Boolean,
});
const emit = defineEmits(['change']);
const { t } = useI18n();
const input = ref(null);
const selected = ref(null);
const removed = ref(false);
const preview = ref('');
const filename = computed(
  () => selected.value?.name || (!removed.value && props.initialFile?.filename)
);
const release = () => {
  if (preview.value) URL.revokeObjectURL(preview.value);
  preview.value = '';
};
const select = event => {
  const file = event.target.files?.[0];
  if (!file) return;
  release();
  selected.value = file;
  removed.value = false;
  if (
    ['image/jpeg', 'image/png', 'image/webp', 'image/gif'].includes(file.type)
  )
    preview.value = URL.createObjectURL(file);
  emit('change', { file, remove_file: false });
};
const remove = () => {
  release();
  selected.value = null;
  removed.value = true;
  if (input.value) input.value.value = '';
  emit('change', { file: null, remove_file: true });
};
onBeforeUnmount(release);
</script>

<template>
  <div class="space-y-2 rounded-lg border border-n-weak p-3 text-n-slate-12">
    <p class="m-0 text-sm">{{ t('CANNED_MGMT.QUICK.FILE_HELP') }}</p>
    <input
      ref="input"
      type="file"
      class="hidden"
      :disabled="disabled"
      @change="select"
    />
    <div class="flex flex-wrap gap-2">
      <Button
        type="button"
        :label="t('CANNED_MGMT.QUICK.ATTACH')"
        icon="i-ph-paperclip"
        :disabled="disabled"
        @click="input.click()"
      />
      <Button
        v-if="filename"
        type="button"
        :label="t('CANNED_MGMT.QUICK.REMOVE')"
        variant="faded"
        :disabled="disabled"
        @click="remove"
      />
    </div>
    <p v-if="filename" class="m-0 break-words text-sm">{{ filename }}</p>
    <img
      v-if="preview"
      :src="preview"
      :alt="filename"
      class="max-h-40 max-w-full rounded-lg object-contain"
    />
  </div>
</template>
