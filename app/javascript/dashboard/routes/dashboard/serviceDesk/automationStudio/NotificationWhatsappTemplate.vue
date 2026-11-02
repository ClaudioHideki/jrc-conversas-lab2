<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({
  modelValue: { type: Object, default: null },
  inbox: { type: Object, default: null },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'selected']);
const { t } = useI18n();
const tr = key =>
  t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.whatsapp_template.${key}`);
const choices = computed(() => props.inbox?.whatsapp_templates || []);
const choice = computed(() =>
  choices.value.find(row => row.fingerprint === props.modelValue?.fingerprint)
);
const inputClass =
  'w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm';
function update(configuration) {
  emit('update:modelValue', configuration);
  if (!configuration) return;
  const row = choices.value.find(
    item => item.fingerprint === configuration.fingerprint
  );
  if (!row) return;
  const content = row.text.replace(
    /\{\{\s*(\w+)\s*\}\}/g,
    (_, key) => configuration.params.processed_params.body[key]
  );
  emit('selected', {
    content,
    version: `${configuration.params.name}:${configuration.params.language}`,
  });
}
function select(fingerprint) {
  const row = choices.value.find(item => item.fingerprint === fingerprint);
  update(
    row
      ? JSON.parse(
          JSON.stringify({
            inbox_id: row.inbox_id,
            params: row.params,
            fingerprint: row.fingerprint,
          })
        )
      : null
  );
}
function parameter(key, value) {
  const configuration = JSON.parse(JSON.stringify(props.modelValue));
  configuration.params.processed_params.body[key] = value;
  update(configuration);
}
</script>

<template>
  <section
    class="grid min-w-0 gap-3 rounded-xl border border-n-teal-5 bg-n-teal-2 p-4"
  >
    <label class="grid gap-1 text-sm">
      {{ tr('title') }}
      <select
        :value="choice?.fingerprint || ''"
        :class="inputClass"
        :disabled="disabled"
        @change="select($event.target.value)"
      >
        <option value="">{{ tr('free_text') }}</option>
        <option
          v-for="row in choices"
          :key="row.fingerprint"
          :value="row.fingerprint"
        >
          {{ row.params.name }} — {{ row.params.language }}
        </option>
      </select>
    </label>
    <p class="text-xs">{{ tr('help') }}</p>
    <p
      v-if="modelValue && !choice"
      class="text-xs text-n-ruby-11"
    >
      {{ tr('changed') }}
    </p>
    <p
      v-if="choice"
      class="whitespace-pre-wrap rounded-lg bg-n-solid-1 p-3 text-sm"
    >
      {{ choice.text }}
    </p>
    <label
      v-for="(value, key) in modelValue?.params?.processed_params?.body || {}"
      :key="key"
      class="grid gap-1 text-sm"
    >
      {{ tr('parameter') }} {{ key }}
      <input
        :value="value"
        :class="inputClass"
        :disabled="disabled"
        maxlength="4000"
        @input="parameter(key, $event.target.value)"
      />
    </label>
  </section>
</template>
