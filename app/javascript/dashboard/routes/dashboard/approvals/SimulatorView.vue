<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ResourcePicker from './ResourcePicker.vue';
import TypedValue from './TypedValue.vue';
const props = defineProps({
  context: { type: Object, required: true },
  catalogs: { type: Array, required: true },
  result: { type: Object, default: null },
  busy: Boolean,
});
const emit = defineEmits(['simulate']);
const { t } = useI18n();
const key = ref('');
const mode = ref('resource');
const resource = ref('');
const values = ref({});
const scopeIndex = ref('');
const scopes = computed(() =>
  props.context.scopes.filter(scope =>
    scope.capabilities.includes('policy_manage')
  )
);
const fields = computed(
  () => props.catalogs.find(row => row.key === key.value)?.fields || {}
);
const simulate = () => {
  const scope = scopes.value[Number(scopeIndex.value)];
  emit(
    'simulate',
    mode.value === 'resource'
      ? { key: key.value, resource_id: resource.value }
      : {
          key: key.value,
          context: {
            issuer_company_id: scope.issuer_company_id,
            business_unit_id: scope.business_unit_id,
            values: values.value,
          },
        }
  );
};
</script>

<template>
  <section class="space-y-4">
    <h2 class="text-xl font-semibold">{{ t('JRC_APPROVALS.simulate') }}</h2>
    <p class="rounded-xl bg-n-blue-3 p-3 text-sm">
      {{ t('JRC_APPROVALS.simulationNotice') }}
    </p>
    <div class="grid gap-3 sm:grid-cols-2">
      <label class="text-sm"
        >{{ t('JRC_APPROVALS.event')
        }}<select
          v-model="key"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option
            v-for="row in catalogs"
            :key="row.key"
          >
            {{ row.key }}
          </option>
        </select></label
      ><label class="text-sm"
        >{{ t('JRC_APPROVALS.contextType')
        }}<select
          v-model="mode"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="resource">{{ t('JRC_APPROVALS.resource') }}</option>
          <option value="synthetic">{{ t('JRC_APPROVALS.synthetic') }}</option>
        </select></label
      >
    </div>
    <ResourcePicker
      v-if="mode === 'resource'"
      v-model="resource"
      :account-id="context.account_id"
      :resource-key="key"
    /><template v-else>
      <label class="block text-sm"
        >{{ t('JRC_APPROVALS.scope')
        }}<select
          v-model="scopeIndex"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option
            v-for="(scope, index) in scopes"
            :key="index"
            :value="String(index)"
          >
            {{ scope.company_name || 'GROUP' }} / {{ scope.unit_name || '—' }}
          </option>
        </select></label
      >
      <div class="grid gap-4 sm:grid-cols-2">
        <TypedValue
          v-for="(type, field) in fields"
          :key="field"
          v-model="values[field]"
          :type="type"
          :label="field"
        />
      </div> </template
    ><Button
      :label="t('JRC_APPROVALS.simulate')"
      :disabled="
        busy || !key || (mode === 'resource' ? !resource : scopeIndex === '')
      "
      @click="simulate"
    />
    <div
      v-if="result"
      class="space-y-3 rounded-xl border border-n-weak p-4"
    >
      <h3 class="font-semibold">{{ result.predicted_state }}</h3>
      <p
        v-if="result.conflict"
        role="alert"
      >
        {{ result.conflict }}
      </p>
      <article
        v-for="version in result.versions"
        :key="version.id"
        class="space-y-2 rounded-lg bg-n-alpha-2 p-3"
      >
        <p>
          {{ t('JRC_APPROVALS.version') }} #{{ version.id }} ·
          {{ version.priority }} · {{ version.selection_mode }}
        </p>
        <p
          v-for="step in version.plan"
          :key="step.code"
        >
          {{ step.code }} · {{ t('JRC_APPROVALS.quorum') }} {{ step.quorum }} ·
          {{ t('JRC_APPROVALS.eligible') }} {{ step.principal_ids.length }}
        </p>
      </article>
      <p
        v-if="Array.isArray(result.effects) && result.effects.length === 0"
        class="font-mono text-sm"
      >
        {{ t('JRC_APPROVALS.effectsLabel') }}
      </p>
      <p
        v-if="Array.isArray(result.effects) && result.effects.length === 0"
        class="text-sm"
      >
        {{ t('JRC_APPROVALS.noEffects') }}
      </p>
      <p
        v-else
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('JRC_APPROVALS.unexpectedEffects') }}
      </p>
    </div>
  </section>
</template>
