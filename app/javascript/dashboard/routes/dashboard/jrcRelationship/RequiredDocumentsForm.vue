<script setup>
import { useI18n } from 'vue-i18n';
import { buttonClass, inputClass } from './definitions';
const props = defineProps({
  modelValue: { type: Array, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const update = (index, field, value) => {
  if (props.disabled) return;
  emit(
    'update:modelValue',
    props.modelValue.map((row, i) =>
      i === index ? { ...row, [field]: value } : row
    )
  );
};
const add = () => {
  if (!props.disabled && props.modelValue.length < 50)
    emit('update:modelValue', [
      ...props.modelValue,
      { code: '', title: '', category: 'registration' },
    ]);
};
const remove = index => {
  if (!props.disabled)
    emit(
      'update:modelValue',
      props.modelValue.filter((_, i) => i !== index)
    );
};
</script>

<template>
  <section
    class="mt-5 min-w-0 space-y-3 rounded-xl border border-n-violet-6 bg-n-solid-2 p-4"
  >
    <h3 class="font-semibold">
      {{ t('RELATIONSHIP.V2.DOCS.REQUIRED_HEADING') }}
    </h3>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.V2.DOCS.CATALOG_HELP') }}
    </p>
    <article
      v-for="(entry, index) in modelValue"
      :key="index"
      class="grid min-w-0 gap-3 rounded-lg border border-n-weak p-3 sm:grid-cols-2"
    >
      <label class="grid min-w-0 gap-1 text-sm">
        {{ t('RELATIONSHIP.V2.DOCS.REQUIREMENT_CODE') }}
        <input
          :value="entry.code"
          required
          pattern="[a-z][a-z0-9_-]{0,59}"
          maxlength="60"
          :disabled="disabled"
          :class="inputClass"
          @input="update(index, 'code', $event.target.value)"
        />
      </label>
      <label class="grid min-w-0 gap-1 text-sm">
        {{ t('RELATIONSHIP.V2.DOCS.TITLE') }}
        <input
          :value="entry.title"
          required
          maxlength="120"
          :disabled="disabled"
          :class="inputClass"
          @input="update(index, 'title', $event.target.value)"
        />
      </label>
      <label class="grid min-w-0 gap-1 text-sm">
        {{ t('RELATIONSHIP.V2.DOCS.CATEGORY') }}
        <select
          :value="entry.category"
          :disabled="disabled"
          :class="inputClass"
          @change="update(index, 'category', $event.target.value)"
        >
          <option
            v-for="category in [
              'registration',
              'contract',
              'evidence',
              'other',
            ]"
            :key="category"
            :value="category"
          >
            {{ t(`RELATIONSHIP.V2.DOCS.CATEGORIES.${category}`) }}
          </option>
        </select>
      </label>
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled"
        @click="remove(index)"
      >
        {{ t('RELATIONSHIP.REMOVE_ITEM') }}
      </button>
    </article>
    <p
      v-if="!modelValue.length"
      class="text-sm text-n-slate-11"
    >
      {{ t('RELATIONSHIP.V2.DOCS.NO_REQUIREMENTS') }}
    </p>
    <button
      type="button"
      :class="buttonClass"
      :disabled="disabled || modelValue.length >= 50"
      @click="add"
    >
      {{ t('RELATIONSHIP.ADD_ITEM') }}
    </button>
  </section>
</template>
