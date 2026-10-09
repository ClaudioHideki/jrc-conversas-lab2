<script setup>
import { computed } from 'vue';
import { helpdeskDraftChoices } from './helpdeskDraftInput';
const props = defineProps({
  modelValue: { type: Object, required: true },
  choices: { type: Object, default: null },
  groupKey: { type: String, required: true },
  ruleKey: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const choices = computed(() => helpdeskDraftChoices(props.choices));
const campaign = computed(
  () => props.groupKey === 'C1' && props.ruleKey === 'R04'
);
const knowledge = computed(() => props.groupKey === 'E');
function update(part, key, value) {
  emit('update:modelValue', {
    ...props.modelValue,
    [part]: { ...props.modelValue[part], [key]: value },
  });
}
</script>

<template>
  <fieldset
    class="space-y-3 rounded border border-n-weak p-3"
    data-testid="helpdesk-draft-fields"
  >
    <legend>{{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_HUMAN') }}</legend>
    <p class="text-xs text-n-slate-11">
      {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_ONLY') }}
    </p>
    <p v-if="!choices" class="text-xs text-n-slate-11">
      {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_LOAD_CHOICES') }}
    </p>
    <template v-if="campaign && choices?.campaign">
      <label class="block text-xs">
        {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_INCIDENT') }}
        <select
          :value="modelValue.campaign?.incident_id || ''"
          :disabled="disabled"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-draft-incident"
          @change="update('campaign', 'incident_id', $event.target.value)"
        >
          <option value="">{{ $t('JRC_NICO_HELPDESK.EMPTY') }}</option>
          <option
            v-for="row in choices.campaign.incidents"
            :key="row.id"
            :value="row.id"
          >
            {{ row.title }}
          </option>
        </select>
      </label>
      <label class="block text-xs">
        {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_INBOX') }}
        <select
          :value="modelValue.campaign?.inbox_id || ''"
          :disabled="disabled"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-draft-inbox"
          @change="update('campaign', 'inbox_id', $event.target.value)"
        >
          <option value="">{{ $t('JRC_NICO_HELPDESK.EMPTY') }}</option>
          <option
            v-for="row in choices.campaign.inboxes"
            :key="row.id"
            :value="row.id"
          >
            {{ row.name }}
          </option>
        </select>
      </label>
      <label class="block text-xs">
        {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_NAME') }}
        <input
          :value="modelValue.campaign?.name || ''"
          :disabled="disabled"
          maxlength="200"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-draft-name"
          @input="update('campaign', 'name', $event.target.value)"
        />
      </label>
    </template>
    <template v-if="knowledge && choices?.knowledge">
      <label class="block text-xs">
        {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_CLOSED_CASE') }}
        <select
          :value="modelValue.knowledge?.closed_transition_id || ''"
          :disabled="disabled"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-draft-closed-case"
          @change="
            update('knowledge', 'closed_transition_id', $event.target.value)
          "
        >
          <option value="">{{ $t('JRC_NICO_HELPDESK.EMPTY') }}</option>
          <option
            v-for="row in choices.knowledge.closed_cases"
            :key="row.id"
            :value="row.id"
          >
            {{ row.title }}
          </option>
        </select>
      </label>
      <label class="block text-xs">
        {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_KNOWLEDGE_TITLE') }}
        <input
          :value="modelValue.knowledge?.title || ''"
          :disabled="disabled"
          maxlength="200"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-draft-title"
          @input="update('knowledge', 'title', $event.target.value)"
        />
      </label>
      <label class="block text-xs">
        {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_GENERALIZED_BODY') }}
        <textarea
          :value="modelValue.knowledge?.body || ''"
          :disabled="disabled"
          maxlength="4000"
          rows="4"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-draft-body"
          @input="update('knowledge', 'body', $event.target.value)"
        />
      </label>
      <label class="flex items-center gap-2 text-xs">
        <input
          :checked="modelValue.knowledge?.generalization_reviewed === true"
          :disabled="disabled"
          type="checkbox"
          data-testid="helpdesk-draft-reviewed"
          @change="
            update(
              'knowledge',
              'generalization_reviewed',
              $event.target.checked
            )
          "
        />
        {{ $t('JRC_NICO_HELPDESK.GROUP_DRAFT_GENERALIZATION_REVIEWED') }}
      </label>
    </template>
  </fieldset>
</template>
