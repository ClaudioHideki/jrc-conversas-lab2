<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ConditionEditor from './ConditionEditor.vue';
import { copy, conditionCount } from './model';
const props = defineProps({
  modelValue: { type: Object, required: true },
  fields: { type: Object, required: true },
  options: { type: Object, required: true },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const patch = values =>
  emit('update:modelValue', { ...copy(props.modelValue), ...values });
const rules = computed(() => props.modelValue.assignees);
const choices = type =>
  props.options[
    {
      account_user: 'account_users',
      team: 'teams',
      custom_role: 'custom_roles',
    }[type]
  ] || [];
const rule = (index, values) => {
  const rows = copy(rules.value);
  rows[index] = { ...rows[index], ...values };
  patch({ assignees: rows });
};
const toggle = action =>
  patch({
    actions: props.modelValue.actions.includes(action)
      ? props.modelValue.actions.filter(a => a !== action)
      : [...props.modelValue.actions, action],
  });
</script>

<template>
  <fieldset class="space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-4">
    <legend class="px-1 font-semibold">{{ t('JRC_APPROVALS.step') }}</legend>
    <div class="grid gap-3 sm:grid-cols-3">
      <label class="text-sm"
        >{{ t('JRC_APPROVALS.code')
        }}<input
          :value="modelValue.code"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
          pattern="[a-z][a-z0-9_]{0,63}"
          @input="patch({ code: $event.target.value })" /></label
      ><label class="text-sm"
        >{{ t('JRC_APPROVALS.mode')
        }}<select
          :value="modelValue.mode"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
          @change="patch({ mode: $event.target.value })"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option value="any">{{ t('JRC_APPROVALS.enum_any') }}</option>
          <option value="all">{{ t('JRC_APPROVALS.enum_all') }}</option>
          <option value="quorum">{{ t('JRC_APPROVALS.enum_quorum') }}</option>
        </select></label
      ><label class="text-sm"
        >{{ t('JRC_APPROVALS.quorum')
        }}<input
          :value="modelValue.quorum"
          type="number"
          min="1"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
          @input="
            patch({
              quorum:
                $event.target.value === '' ? null : Number($event.target.value),
            })
          "
      /></label>
    </div>
    <p class="text-xs text-n-slate-11">{{ t('JRC_APPROVALS.rosterNotice') }}</p>
    <div
      v-for="(assignee, index) in rules"
      :key="index"
      class="flex flex-wrap gap-2"
    >
      <label class="text-sm"
        >{{ t('JRC_APPROVALS.assigneeType')
        }}<select
          :value="assignee.type"
          class="block rounded-lg border border-n-weak bg-n-solid-2 p-2"
          @change="rule(index, { type: $event.target.value, id: null })"
        >
          <option value="account_user">
            {{ t('JRC_APPROVALS.enum_account_user') }}
          </option>
          <option value="team">{{ t('JRC_APPROVALS.enum_team') }}</option>
          <option value="custom_role">
            {{ t('JRC_APPROVALS.enum_custom_role') }}
          </option>
        </select></label
      ><label class="min-w-0 grow text-sm"
        >{{ t('JRC_APPROVALS.assignee')
        }}<select
          :value="assignee.id"
          class="block w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
          @change="rule(index, { id: Number($event.target.value) })"
        >
          <option value="">{{ t('JRC_APPROVALS.select') }}</option>
          <option
            v-for="candidate in choices(assignee.type)"
            :key="candidate.id"
            :value="candidate.id"
          >
            {{ candidate.name }} (#{{ candidate.id }})
          </option>
        </select></label
      ><button
        type="button"
        class="text-sm text-n-ruby-11"
        @click="patch({ assignees: rules.filter((_, i) => i !== index) })"
      >
        {{ t('JRC_APPROVALS.remove') }}
      </button>
    </div>
    <button
      type="button"
      :disabled="rules.length >= 32"
      class="text-sm text-n-blue-11"
      @click="
        patch({ assignees: [...rules, { type: 'account_user', id: null }] })
      "
    >
      {{ t('JRC_APPROVALS.addAssignee') }}
    </button>
    <fieldset class="flex flex-wrap gap-3">
      <legend class="text-sm">{{ t('JRC_APPROVALS.actions') }}</legend>
      <label
        v-for="action in ['approved', 'rejected', 'returned', 'escalated']"
        :key="action"
        class="text-sm"
        ><input
          type="checkbox"
          :checked="modelValue.actions.includes(action)"
          :disabled="action === 'approved'"
          @change="toggle(action)"
        />
        {{ action }}</label
      >
    </fieldset>
    <label class="block text-sm"
      >{{ t('JRC_APPROVALS.onReject')
      }}<select
        :value="modelValue.on_reject"
        class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        @change="patch({ on_reject: $event.target.value })"
      >
        <option value="">{{ t('JRC_APPROVALS.select') }}</option>
        <option value="rejected">{{ t('JRC_APPROVALS.enum_rejected') }}</option>
        <option value="returned">{{ t('JRC_APPROVALS.enum_returned') }}</option>
        <option value="escalated">
          {{ t('JRC_APPROVALS.enum_escalated') }}
        </option>
      </select></label
    >
    <p class="text-sm font-medium">{{ t('JRC_APPROVALS.authority') }}</p>
    <ConditionEditor
      :model-value="modelValue.authority"
      :fields="fields"
      :budget="conditionCount(modelValue.authority)"
      @update:model-value="patch({ authority: $event })"
    />
  </fieldset>
</template>
