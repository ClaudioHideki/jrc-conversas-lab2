<script setup>
import { computed, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { approvalClient } from 'dashboard/api/approvals';
import ConditionEditor from './ConditionEditor.vue';
import StepEditor from './StepEditor.vue';
import {
  copy,
  emptyDefinition,
  emptyStep,
  conditionCount,
  describeCondition,
  scopeLabel,
} from './model';
const props = defineProps({
  policy: { type: Object, default: null },
  context: { type: Object, required: true },
  busy: Boolean,
});
const emit = defineEmits(['save', 'operation', 'versions']);
const { t } = useI18n();
const draft = ref({});
const tab = ref('general');
const scopeIndex = ref('');
const catalogs = ref([]);
const options = ref({});
const loadError = ref('');
const confirmation = ref(null);
const tabs = [
  'general',
  'conditions',
  'steps',
  'behavior',
  'security',
  'summary',
];

const tabKey = event => {
  const current = tabs.indexOf(tab.value);
  const moves = {
    ArrowRight: (current + 1) % tabs.length,
    ArrowLeft: (current + tabs.length - 1) % tabs.length,
    Home: 0,
    End: tabs.length - 1,
  };
  if (!Object.hasOwn(moves, event.key)) return;
  event.preventDefault();
  const group = event.currentTarget.parentElement;
  tab.value = tabs[moves[event.key]];
  nextTick(() =>
    group.querySelectorAll('[role="tab"]')[moves[event.key]].focus()
  );
};
const scopes = computed(() =>
  props.context.scopes.filter(scope =>
    scope.capabilities.includes('policy_manage')
  )
);
const scope = computed(() =>
  scopeIndex.value === '' ? null : scopes.value[Number(scopeIndex.value)]
);
const key = computed({
  get: () => `${draft.value.module_key || ''}.${draft.value.event_key || ''}`,
  set: value => {
    [draft.value.module_key, draft.value.event_key] = value.split('.', 2);
  },
});
const fields = computed(
  () => catalogs.value.find(row => row.key === key.value)?.fields || {}
);
const definition = computed(() => draft.value.draft_definition);
const dirty = computed(
  () =>
    !props.policy ||
    JSON.stringify(draft.value) !== JSON.stringify(props.policy)
);
let generation = 0;
watch(
  () => props.policy,
  policy => {
    draft.value = policy
      ? copy(policy)
      : {
          name: '',
          code: '',
          module_key: '',
          event_key: '',
          issuer_company_id: null,
          business_unit_id: null,
          draft_definition: emptyDefinition(),
        };
    const index = scopes.value.findIndex(
      row =>
        row.issuer_company_id === draft.value.issuer_company_id &&
        row.business_unit_id === draft.value.business_unit_id
    );
    scopeIndex.value = policy && index >= 0 ? String(index) : '';
  },
  { immediate: true }
);
watch(
  scopeIndex,
  async value => {
    generation += 1;
    const current = generation;
    catalogs.value = [];
    options.value = {};
    loadError.value = '';
    if (value === '' || !scope.value) return;
    const params = {
      issuer_company_id: scope.value.issuer_company_id,
      business_unit_id: scope.value.business_unit_id,
    };
    Object.assign(draft.value, params);
    try {
      const api = approvalClient(props.context.account_id);
      const results = await Promise.all([
        api.get('catalogs', params),
        api.get('options', params),
      ]);
      if (current === generation) {
        catalogs.value = results[0].data;
        options.value = results[1].data;
      }
    } catch {
      if (current === generation)
        loadError.value = t('JRC_APPROVALS.loadError');
    }
  },
  { immediate: true }
);
const save = () => {
  const body = props.policy
    ? { name: draft.value.name, definition: copy(definition.value) }
    : {
        name: draft.value.name,
        code: draft.value.code,
        module_key: draft.value.module_key,
        event_key: draft.value.event_key,
        issuer_company_id: draft.value.issuer_company_id,
        business_unit_id: draft.value.business_unit_id,
        definition: copy(definition.value),
      };
  emit('save', body);
};
const operation = name => {
  if (name === 'publish' || name === 'retire') {
    confirmation.value.showModal();
    confirmation.value.dataset.operation = name;
  } else emit('operation', name);
};
const confirm = () => {
  const name = confirmation.value.dataset.operation;
  confirmation.value.close();
  emit('operation', name);
};
</script>

<template>
  <section
    v-if="definition"
    class="space-y-5"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-xl font-semibold">
          {{ policy ? policy.name : t('JRC_APPROVALS.newPolicy') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ policy?.state || 'draft' }} · {{ t('JRC_APPROVALS.version') }}
          {{ policy?.current_version || '—' }} · {{ t('JRC_APPROVALS.scope') }}
          {{ scopeLabel(context, draft) || t('JRC_APPROVALS.groupScope') }}
        </p>
      </div>
      <Button
        v-if="policy"
        :label="t('JRC_APPROVALS.versions')"
        variant="faded"
        @click="emit('versions')"
      />
    </div>
    <p
      v-if="policy?.current_version_id"
      class="rounded-xl bg-n-amber-3 p-3 text-sm"
    >
      {{ t('JRC_APPROVALS.immutableNotice') }}
    </p>
    <div
      role="tablist"
      :aria-label="t('JRC_APPROVALS.editor')"
      class="flex flex-wrap gap-2"
    >
      <button
        v-for="name in tabs"
        :key="name"
        role="tab"
        :tabindex="tab === name ? 0 : -1"
        @keydown="tabKey"
        :aria-selected="tab === name"
        class="rounded-lg border border-n-weak px-3 py-2 text-sm focus-visible:outline-blue-500"
        :class="tab === name ? 'bg-n-blue-3 text-n-blue-11' : 'bg-n-solid-2'"
        @click="tab = name"
      >
        {{ t(`JRC_APPROVALS.${name}`) }}
      </button>
    </div>
    <p
      v-if="loadError"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ loadError }}
    </p>
    <div
      v-show="tab === 'general'"
      class="grid gap-4 md:grid-cols-2"
    >
      <label class="text-sm"
        >{{ t('JRC_APPROVALS.name')
        }}<input
          v-model="draft.name"
          required
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2" /></label
      ><label class="text-sm"
        >{{ t('JRC_APPROVALS.code')
        }}<input
          v-model="draft.code"
          :disabled="!!policy"
          required
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 disabled:opacity-60"
      /></label>
      <label class="text-sm"
        >{{ t('JRC_APPROVALS.scope')
        }}<select
          v-model="scopeIndex"
          :disabled="!!policy"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option
            v-for="(row, index) in scopes"
            :key="index"
            :value="String(index)"
          >
            {{ row.company_name || 'GROUP' }} / {{ row.unit_name || '—' }}
          </option>
        </select></label
      >
      <label class="text-sm"
        >{{ t('JRC_APPROVALS.event')
        }}<select
          v-model="key"
          :disabled="!!policy"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value=".">{{ t('JRC_APPROVALS.select') }}</option>
          <option
            v-for="row in catalogs"
            :key="row.key"
            :value="row.key"
          >
            {{ row.key }}
          </option>
        </select></label
      >
    </div>
    <ConditionEditor
      v-if="tab === 'conditions'"
      v-model="definition.condition"
      :fields="fields"
      :budget="conditionCount(definition.condition)"
    />
    <div
      v-if="tab === 'steps'"
      class="space-y-4"
    >
      <div
        v-for="(step, index) in definition.steps"
        :key="index"
        class="space-y-2"
      >
        <StepEditor
          v-model="definition.steps[index]"
          :fields="fields"
          :options="options"
        /><button
          class="text-sm text-n-ruby-11"
          @click="definition.steps.splice(index, 1)"
        >
          {{ t('JRC_APPROVALS.remove') }}
        </button>
      </div>
      <Button
        :disabled="definition.steps.length >= 16"
        :label="t('JRC_APPROVALS.addStep')"
        variant="faded"
        @click="definition.steps.push(emptyStep())"
      />
    </div>
    <div
      v-show="tab === 'behavior'"
      class="grid gap-4 md:grid-cols-2"
    >
      <label class="text-sm"
        >{{ t('JRC_APPROVALS.priority')
        }}<input
          v-model.number="definition.selection.priority"
          type="number"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2" /></label
      ><label class="text-sm"
        >{{ t('JRC_APPROVALS.selection')
        }}<select
          v-model="definition.selection.mode"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option value="exclusive">
            {{ t('JRC_APPROVALS.enum_exclusive') }}
          </option>
          <option value="accumulate">
            {{ t('JRC_APPROVALS.enum_accumulate') }}
          </option>
        </select></label
      ><label class="text-sm"
        >{{ t('JRC_APPROVALS.execution')
        }}<select
          v-model="definition.execution"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option value="sequential">
            {{ t('JRC_APPROVALS.enum_sequential') }}
          </option>
          <option value="parallel">
            {{ t('JRC_APPROVALS.enum_parallel') }}
          </option>
        </select></label
      ><label class="text-sm"
        >{{ t('JRC_APPROVALS.expiry')
        }}<input
          v-model.number="definition.expires_in_seconds"
          type="number"
          min="1"
          max="31536000"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
      /></label>
      <p class="text-sm">
        {{ t('JRC_APPROVALS.completion') }}:
        {{ t('JRC_APPROVALS.enum_all_steps') }}
      </p>
    </div>
    <div
      v-show="tab === 'security'"
      class="space-y-4"
    >
      <label class="block text-sm"
        ><input
          v-model="definition.allow_self_approval"
          type="checkbox"
        />
        {{ t('JRC_APPROVALS.selfApproval') }}</label
      ><label class="block text-sm"
        ><input
          v-model="definition.delegation_allowed"
          type="checkbox"
        />
        {{ t('JRC_APPROVALS.allowDelegation') }}</label
      ><label class="block text-sm"
        >{{ t('JRC_APPROVALS.reopen')
        }}<select
          v-model="definition.reopen_mode"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        >
          <option value="disabled">
            {{ t('JRC_APPROVALS.enum_disabled') }}
          </option>
          <option value="restart_all">
            {{ t('JRC_APPROVALS.enum_restart_all') }}
          </option>
        </select></label
      >
    </div>
    <div
      v-show="tab === 'summary'"
      class="space-y-3 rounded-xl border border-n-weak p-4"
    >
      <p>
        {{
          t('JRC_APPROVALS.humanSummary', {
            event: key,
            company: scope?.company_name || 'GROUP',
            unit: scope?.unit_name || '—',
            count: definition.steps.length,
            mode: definition.execution || '—',
          })
        }}
      </p>
      <ul class="space-y-2">
        <li
          v-for="step in definition.steps"
          :key="step.code"
        >
          {{ step.code || '—' }} · {{ step.mode || '—' }} ·
          {{ t('JRC_APPROVALS.quorum') }} {{ step.quorum || '—' }} ·
          {{ step.actions.join(', ') }}
        </li>
      </ul>
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_APPROVALS.presentationOnly') }}
        <span class="block mt-2 font-medium">{{
          describeCondition(definition.condition)
        }}</span>
      </p>
      <p
        v-for="step in policy?.validation_plan || []"
        :key="step.code"
        class="text-sm"
      >
        {{ step.code }}: {{ t('JRC_APPROVALS.eligible') }}
        {{ step.eligible_count }} / {{ t('JRC_APPROVALS.quorum') }}
        {{ step.quorum }}
      </p>
    </div>
    <div class="flex flex-wrap gap-2 border-t border-n-weak pt-4">
      <Button
        :label="t('JRC_APPROVALS.saveDraft')"
        :disabled="busy || scopeIndex === '' || !key || key === '.'"
        @click="save"
      /><Button
        v-if="policy"
        variant="faded"
        :label="t('JRC_APPROVALS.validate')"
        :disabled="busy || dirty"
        @click="operation('validate')"
      /><Button
        v-if="policy"
        :label="t('JRC_APPROVALS.publish')"
        :disabled="busy || dirty || policy.state !== 'validated'"
        @click="operation('publish')"
      /><Button
        v-if="policy?.enabled"
        variant="faded"
        :label="t('JRC_APPROVALS.retire')"
        :disabled="busy || dirty"
        @click="operation('retire')"
      />
    </div>
    <p
      v-if="dirty && policy"
      class="text-sm text-n-slate-11"
    >
      {{ t('JRC_APPROVALS.saveFirst') }}
    </p>
    <dialog
      ref="confirmation"
      class="max-w-lg rounded-xl border border-n-weak bg-n-solid-2 p-6 text-n-slate-12 shadow-xl"
    >
      <h3 class="text-lg font-semibold">
        {{ t('JRC_APPROVALS.confirmPublication') }}
      </h3>
      <p class="my-4">
        {{ draft.name }} · {{ key }} · {{ policy?.current_version || 0 }} ·
        {{ scope?.company_name || 'GROUP' }} / {{ scope?.unit_name || '—' }}
      </p>
      <p class="mb-4 text-sm">{{ t('JRC_APPROVALS.noRollout') }}</p>
      <div class="flex gap-3">
        <Button
          :label="t('JRC_APPROVALS.confirm')"
          @click="confirm"
        /><Button
          :label="t('JRC_APPROVALS.cancel')"
          variant="faded"
          @click="confirmation.close()"
        />
      </div>
    </dialog>
  </section>
</template>
