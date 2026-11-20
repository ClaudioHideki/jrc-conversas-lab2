<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import AcwRuleTarget from './AcwRuleTarget.vue';
import AcwRuleFormBinding from './AcwRuleFormBinding.vue';
import { acwLabels } from '../../inbox/acwLabels';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  modelValue: { type: Array, required: true },
  disabled: { type: Boolean, default: false },
  reasonCatalog: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);
const bindings = defineModel('bindings', { type: Array, default: () => [] });
const bindingFor = ruleId =>
  bindings.value.find(row => row.rule_id === ruleId) || null;
const setBinding = (ruleId, value) => {
  if (props.disabled) return;
  bindings.value = [
    ...bindings.value.filter(row => row.rule_id !== ruleId),
    ...(value ? [value] : []),
  ];
};
const { t } = useI18n();
const reasons = computed(() => {
  const choices = Object.assign(Object.create(null), acwLabels(t).reasons);
  props.reasonCatalog.forEach(row => {
    if (row.active) choices[row.code] = row.name;
    else delete choices[row.code];
  });
  return choices;
});
const labels = {
  TITLE: t('JRC_CONTACT_CENTER.ACW_RULES.TITLE'),
  HINT: t('JRC_CONTACT_CENTER.ACW_RULES.HINT'),
  REASON: t('JRC_CONTACT_CENTER.ACW_RULES.REASON'),
  SCOPE: t('JRC_CONTACT_CENTER.ACW_RULES.SCOPE'),
  GENERAL: t('JRC_CONTACT_CENTER.ACW_RULES.GENERAL'),
  TEAM: t('JRC_CONTACT_CENTER.ACW_RULES.TEAM'),
  QUEUE: t('JRC_CONTACT_CENTER.ACW_RULES.QUEUE'),
  TIME: t('JRC_CONTACT_CENTER.ACW_RULES.TIME'),
  ADD: t('JRC_CONTACT_CENTER.ACW_RULES.ADD'),
  REMOVE: t('JRC_CONTACT_CENTER.ACW_RULES.REMOVE'),
};
const update = (index, attributes) =>
  emit(
    'update:modelValue',
    props.modelValue.map((row, i) =>
      i === index ? { ...row, ...attributes } : row
    )
  );
const add = () => {
  if (props.disabled || props.modelValue.length >= 100) return;
  emit('update:modelValue', [
    ...props.modelValue,
    {
      id: crypto.randomUUID(),
      reason_code: '',
      scope: 'general',
      scope_id: null,
      active: false,
      limit_seconds: null,
    },
  ]);
};
const remove = index => {
  if (props.disabled || bindingFor(props.modelValue[index].id)) return;
  emit(
    'update:modelValue',
    props.modelValue.filter((_, i) => i !== index)
  );
};
const time = seconds =>
  Number.isInteger(seconds) && seconds % 60 === 0
    ? `${String(Math.floor(seconds / 3600)).padStart(2, '0')}:${String((seconds / 60) % 60).padStart(2, '0')}`
    : '';
const setTime = (index, value) => {
  const valid = /^\d{2}:[0-5]\d$/.test(value);
  const [hours, minutes] = valid ? value.split(':').map(Number) : [];
  const seconds = valid ? (hours * 60 + minutes) * 60 : null;
  update(index, {
    limit_seconds: seconds >= 60 && seconds <= 3600 ? seconds : null,
  });
};
</script>

<template>
  <fieldset
    class="min-w-0 space-y-3 text-n-slate-12 sm:col-span-2"
    :disabled="disabled"
    data-acw-scoped-rules
  >
    <legend class="font-semibold">{{ labels.TITLE }}</legend>
    <p class="text-sm text-n-slate-11">{{ labels.HINT }}</p>
    <section
      v-for="(rule, index) in modelValue"
      :key="rule.id"
      class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
      data-acw-rule-row
    >
      <div class="grid min-w-0 gap-3 sm:grid-cols-2">
        <label class="block min-w-0 text-sm">
          <span class="block">{{ labels.REASON }}</span>
          <select
            :value="rule.reason_code"
            required
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-acw-rule-reason
            @change="update(index, { reason_code: $event.target.value })"
          >
            <option value="">{{ t('JRC_CONTACT_CENTER.ADMIN.SELECT') }}</option>
            <option
              v-if="rule.reason_code && !reasons[rule.reason_code]"
              :value="rule.reason_code"
            >
              {{ rule.reason_code }}
            </option>
            <option v-for="(name, code) in reasons" :key="code" :value="code">
              {{ name }}
            </option>
          </select>
        </label>
        <label class="block min-w-0 text-sm">
          <span class="block">{{ labels.SCOPE }}</span>
          <select
            :value="rule.scope"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-acw-rule-scope
            @change="
              update(index, { scope: $event.target.value, scope_id: null })
            "
          >
            <option
              v-for="scope in ['general', 'team', 'queue']"
              :key="scope"
              :value="scope"
            >
              {{ labels[scope.toUpperCase()] }}
            </option>
          </select>
        </label>
        <AcwRuleTarget
          v-if="rule.scope !== 'general'"
          :account-id="accountId"
          :scope="rule.scope"
          :model-value="rule.scope_id || ''"
          :disabled="disabled"
          @update:model-value="update(index, { scope_id: $event })"
        />
        <label class="block min-w-0 text-sm">
          <span class="block">{{ labels.TIME }}</span>
          <input
            :value="time(rule.limit_seconds)"
            :required="!rule.limit_seconds"
            pattern="[0-9]{2}:[0-5][0-9]"
            :placeholder="t('JRC_CONTACT_CENTER.ADMIN.TIME_FORMAT')"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            data-acw-rule-time
            @input="setTime(index, $event.target.value)"
          />
          <span
            v-if="rule.limit_seconds && !time(rule.limit_seconds)"
            class="mt-1 block text-xs text-n-slate-11"
          >
            {{
              t('JRC_CONTACT_CENTER.ACW_RULES.EXACT_SECONDS', {
                seconds: rule.limit_seconds,
              })
            }}
          </span>
        </label>
      </div>
      <AcwRuleFormBinding
        :account-id="accountId"
        :rule-id="rule.id"
        :model-value="bindingFor(rule.id)"
        :disabled="disabled"
        @update:model-value="setBinding(rule.id, $event)"
      />
      <p v-if="bindingFor(rule.id)" class="text-xs text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.ACW_FORMS.UNLINK_BEFORE_REMOVE') }}
      </p>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <label class="flex gap-2 text-sm">
          <input
            :checked="rule.active"
            type="checkbox"
            data-acw-rule-active
            @change="update(index, { active: $event.target.checked })"
          />
          <span>{{ t('JRC_CONTACT_CENTER.ADMIN.ACTIVE') }}</span>
        </label>
        <button
          type="button"
          class="rounded-md border border-n-weak px-3 py-2 text-sm text-n-ruby-11"
          :disabled="disabled || Boolean(bindingFor(rule.id))"
          data-remove-acw-rule
          @click="remove(index)"
        >
          {{ labels.REMOVE }}
        </button>
      </div>
    </section>
    <button
      type="button"
      :disabled="disabled || modelValue.length >= 100"
      class="rounded-md border border-n-weak px-3 py-2 text-sm text-n-slate-12 disabled:opacity-50"
      data-add-acw-rule
      @click="add"
    >
      {{ labels.ADD }}
    </button>
  </fieldset>
</template>
