<script setup>
import { useI18n } from 'vue-i18n';
import { buttonClass, inputClass } from './definitions';

defineProps({
  title: { type: String, default: '' },
  dueAt: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  deadlineRequired: { type: Boolean, default: false },
  titleMaxLength: { type: Number, default: undefined },
});
const emit = defineEmits(['update:title', 'update:dueAt', 'submit']);
const { t } = useI18n();
</script>

<template>
  <form
    class="mt-4 flex min-w-0 flex-wrap items-end gap-2"
    data-native-relationship-activity-form
    @submit.prevent="!disabled && emit('submit')"
  >
    <label class="w-full min-w-0 flex-1 text-sm sm:min-w-52">
      {{ t('RELATIONSHIP.NEW_ACTIVITY') }}
      <input
        :value="title"
        :class="inputClass"
        :disabled="disabled"
        :maxlength="titleMaxLength"
        required
        data-native-relationship-activity-title
        @input="emit('update:title', $event.target.value)"
      />
    </label>
    <label class="min-w-0 text-sm">
      {{ t('RELATIONSHIP.FIELDS.due_at') }}
      <input
        :value="dueAt"
        type="datetime-local"
        :class="inputClass"
        :disabled="disabled"
        :required="deadlineRequired"
        data-native-relationship-activity-deadline
        @input="emit('update:dueAt', $event.target.value)"
      />
    </label>
    <button
      type="submit"
      :class="buttonClass"
      :disabled="disabled"
    >
      {{ t('RELATIONSHIP.SAVE') }}
    </button>
  </form>
</template>
