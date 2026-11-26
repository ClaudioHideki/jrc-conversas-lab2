<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  value: { type: Object, default: null },
  options: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'cancel', 'remove']);
const { t } = useI18n();
const text = key =>
  t(`JRC_CONTACT_CENTER.ENDING_AUTOMATIONS.CRM_CONFIGURATION.${key}`);
const initialOperation = () => {
  if (!props.value) return '';
  return props.value.operation === 'create_activity'
    ? 'create_activity'
    : 'contact_lead';
};
const operation = ref(initialOperation());
const attributes = ref({
  activity_type: props.value?.parameters?.activity_type || '',
  title: props.value?.parameters?.title || '',
  description: props.value?.parameters?.description || '',
});
const reviewed = ref(false);
const valid = computed(
  () =>
    props.options.configuration_available === true &&
    reviewed.value &&
    (operation.value === 'contact_lead' ||
      (operation.value === 'create_activity' &&
        props.options.activity_types.includes(attributes.value.activity_type) &&
        attributes.value.title.trim() === attributes.value.title &&
        attributes.value.title.length > 0 &&
        attributes.value.title.length <= 240 &&
        attributes.value.description.length <= 6000))
);
const save = () => {
  if (props.disabled || !valid.value) return;
  emit(
    'save',
    operation.value === 'contact_lead'
      ? {}
      : { operation: 'create_activity', parameters: { ...attributes.value } }
  );
};
</script>

<template>
  <form
    class="min-w-0 space-y-4"
    data-ending-crm-configuration
    @submit.prevent="save"
  >
    <h3 class="text-base font-semibold">{{ text('TITLE') }}</h3>
    <p class="break-words text-sm text-n-slate-11">{{ text('AUTHORITY') }}</p>
    <fieldset :disabled="disabled" class="grid min-w-0 gap-3 sm:grid-cols-2">
      <label class="min-w-0 text-sm sm:col-span-2">
        {{ text('OPERATION') }}
        <select
          v-model="operation"
          required
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          data-ending-crm-operation
          @change="reviewed = false"
        >
          <option value="">{{ text('SELECT') }}</option>
          <option value="contact_lead">{{ text('CONTACT_LEAD') }}</option>
          <option value="create_activity">{{ text('CREATE_ACTIVITY') }}</option>
        </select>
      </label>
      <template v-if="operation === 'create_activity'">
        <label class="min-w-0 text-sm">
          {{ text('ACTIVITY_TYPE') }}
          <select
            v-model="attributes.activity_type"
            required
            class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-ending-crm-activity-type
            @change="reviewed = false"
          >
            <option value="">{{ text('SELECT') }}</option>
            <option
              v-for="type in options.activity_types"
              :key="type"
              :value="type"
            >
              {{ text(`ACTIVITY_TYPES.${type}`) }}
            </option>
          </select>
        </label>
        <label class="min-w-0 text-sm">
          {{ text('ACTIVITY_TITLE') }}
          <input
            v-model="attributes.title"
            required
            maxlength="240"
            class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-ending-crm-title
            @input="reviewed = false"
          />
        </label>
        <label class="min-w-0 text-sm sm:col-span-2">
          {{ text('DESCRIPTION') }}
          <textarea
            v-model="attributes.description"
            maxlength="6000"
            class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-ending-crm-description
            @input="reviewed = false"
          />
        </label>
      </template>
      <label class="flex min-w-0 items-start gap-2 text-sm sm:col-span-2">
        <input
          v-model="reviewed"
          type="checkbox"
          class="mt-1"
          data-ending-crm-reviewed
        />
        <span>{{ text('REVIEW') }}</span>
      </label>
    </fieldset>
    <div class="flex flex-wrap gap-3">
      <button
        type="submit"
        :disabled="disabled || !valid"
        class="rounded-lg bg-n-brand px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
        data-ending-crm-apply
      >
        {{ text('APPLY') }}
      </button>
      <button
        type="button"
        :disabled="disabled"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm"
        @click="emit('cancel')"
      >
        {{ text('CANCEL') }}
      </button>
      <button
        v-if="value"
        type="button"
        :disabled="disabled"
        class="rounded-lg border border-n-ruby-6 px-3 py-2 text-sm text-n-ruby-11"
        @click="emit('remove')"
      >
        {{ text('REMOVE') }}
      </button>
    </div>
  </form>
</template>
