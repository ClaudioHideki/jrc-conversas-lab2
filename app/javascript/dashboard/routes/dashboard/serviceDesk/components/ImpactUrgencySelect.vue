<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskOperationalRules';
import { useOperationalScope } from '../composables/useOperationalScope';
import { assertEnvelope } from '../helpers/operationalRules.mjs';
const props = defineProps({
  unitId: { type: String, required: true },
  impact: { type: String, default: '' },
  urgency: { type: String, default: '' },
  disabled: Boolean,
});
const emit = defineEmits(['update:impact', 'update:urgency']);
const { t } = useI18n();
const unit = ref(props.unitId);
watch(
  () => props.unitId,
  value => {
    unit.value = value;
  }
);
const scope = useOperationalScope(unit, context =>
  context?.units.some(
    row => row.id === unit.value && row.permissions.create_ticket
  )
);
const impacts = ref([]);
const urgencies = ref([]);
watch(
  [scope.identity, unit],
  async (_, previous) => {
    impacts.value = [];
    urgencies.value = [];
    if (previous?.length) {
      emit('update:impact', '');
      emit('update:urgency', '');
    }
    const lease = scope.begin();
    if (!lease) return;
    try {
      const result = assertEnvelope(
        await API.intake(lease.context.account_id, lease.unit, lease.signal),
        lease.context,
        lease.unit
      );
      if (!scope.live(lease)) return;
      if (!Array.isArray(result.impacts) || !Array.isArray(result.urgencies))
        return;
      impacts.value = result.impacts;
      urgencies.value = result.urgencies;
      if (!impacts.value.includes(props.impact)) emit('update:impact', '');
      if (!urgencies.value.includes(props.urgency)) emit('update:urgency', '');
    } catch {
      /* No configuration is inferred after a failed read. */
    }
  },
  { immediate: true }
);
</script>

<template>
  <fieldset
    v-if="impacts.length && urgencies.length"
    :disabled="disabled"
    class="grid gap-3 rounded border border-n-weak p-3 md:grid-cols-2"
  >
    <p class="text-sm md:col-span-2">
      {{ t('JRC_SERVICE_DESK.COMPLETION.matrix_help') }}
    </p>
    <label class="grid gap-1 text-sm"
      ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.fields.impact') }}</span
      ><select
        :value="impact"
        class="rounded border border-n-weak bg-n-solid-1 p-2"
        @change="emit('update:impact', $event.target.value)"
      >
        <option value="">{{ t('JRC_SERVICE_DESK.COMPLETION.select') }}</option>
        <option v-for="value in impacts" :key="value" :value="value">
          {{ value }}
        </option>
      </select></label
    >
    <label class="grid gap-1 text-sm"
      ><span>{{ t('JRC_SERVICE_DESK.COMPLETION.fields.urgency') }}</span
      ><select
        :value="urgency"
        class="rounded border border-n-weak bg-n-solid-1 p-2"
        @change="emit('update:urgency', $event.target.value)"
      >
        <option value="">{{ t('JRC_SERVICE_DESK.COMPLETION.select') }}</option>
        <option v-for="value in urgencies" :key="value" :value="value">
          {{ value }}
        </option>
      </select></label
    >
  </fieldset>
</template>
