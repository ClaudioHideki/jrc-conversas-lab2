<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({
  modelValue: { type: Object, required: true },
  users: { type: Array, required: true },
  addresses: { type: Array, default: () => [] },
  disabled: Boolean,
  authorityOnly: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const authorities = [
  'commercial_gratuity_principal_id',
  'commercial_gratuity_substitute_id',
  'financial_gratuity_principal_id',
  'financial_gratuity_substitute_id',
];
const fields = computed(() =>
  props.authorityOnly
    ? ['authorization_reference']
    : ['legal_name', 'legal_representative', 'authorization_reference']
);
const patch = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value || null });
</script>

<template>
  <fieldset
    class="space-y-3 rounded-xl border border-n-weak p-4"
    :disabled="disabled"
  >
    <legend class="px-1 text-sm font-semibold">
      {{ t('CRM.CORPORATE.PROFILE') }}
    </legend>
    <p class="text-xs text-n-slate-11">{{ t('CRM.CORPORATE.PENDING_NOTE') }}</p>
    <div class="grid gap-3 md:grid-cols-2">
      <label v-if="!authorityOnly" class="text-sm">
        {{ t('CRM.CORPORATE.fiscal_address_id') }}
        <select
          :value="modelValue.fiscal_address_id || ''"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2.5"
          @change="
            patch(
              'fiscal_address_id',
              $event.target.value ? Number($event.target.value) : null
            )
          "
        >
          <option value="">{{ t('CRM.CORPORATE.PENDING') }}</option>
          <option
            v-for="address in addresses"
            :key="address.id"
            :value="address.id"
          >
            {{ address.label }}
          </option>
        </select>
      </label>
      <label v-for="field in fields" :key="field" class="text-sm">
        {{ t(`CRM.CORPORATE.${field}`) }}
        <input
          :value="modelValue[field] || ''"
          maxlength="255"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2.5"
          @input="patch(field, $event.target.value)"
        />
      </label>
      <label v-for="field in authorities" :key="field" class="text-sm">
        {{ t(`CRM.CORPORATE.${field}`) }}
        <select
          :value="modelValue[field] || ''"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2.5"
          @change="
            patch(
              field,
              $event.target.value ? Number($event.target.value) : null
            )
          "
        >
          <option value="">{{ t('CRM.ORGANIZATION.SELECT_USER') }}</option>
          <option
            v-for="user in users"
            :key="user.account_user_id"
            :value="user.account_user_id"
          >
            {{ user.name }}
          </option>
        </select>
      </label>
    </div>
    <label v-if="!authorityOnly" class="block text-sm">
      {{ t('CRM.CORPORATE.responsible_account_user_ids') }}
      <select
        multiple
        :value="modelValue.responsible_account_user_ids || []"
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2.5"
        @change="
          emit('update:modelValue', {
            ...modelValue,
            responsible_account_user_ids: Array.from(
              $event.target.selectedOptions,
              option => Number(option.value)
            ),
          })
        "
      >
        <option
          v-for="user in users"
          :key="user.account_user_id"
          :value="user.account_user_id"
        >
          {{ user.name }}
        </option>
      </select>
    </label>
    <p class="text-xs text-n-slate-11">
      {{ t('CRM.CORPORATE.AUTHORITY_NOTE') }}
    </p>
  </fieldset>
</template>
