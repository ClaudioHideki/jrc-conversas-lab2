<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { acwLabels } from './acwLabels';

const props = defineProps({
  current: { type: Object, default: null },
  busy: { type: Boolean, default: false },
  canUseRemote: { type: Boolean, default: false },
  canReapply: { type: Boolean, default: false },
});
const emit = defineEmits(['reload', 'useRemote', 'reapply']);
const { t } = useI18n();
const labels = computed(() => acwLabels(t));
const labelFor = (group, value) =>
  Object.hasOwn(group, value) ? group[value] : value;
const remoteFields = computed(() => [
  {
    key: 'reason_code',
    label: t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_REASON'),
    value: labelFor(labels.value.reasons, props.current?.reason_code),
  },
  {
    key: 'outcome_code',
    label: t('JRC_CONTACT_CENTER.INBOX_360.CLOSING_RESULT'),
    value: labelFor(labels.value.results, props.current?.outcome_code),
  },
  {
    key: 'notes',
    label: t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_REMOTE_NOTE'),
    value: props.current?.notes,
  },
]);
</script>

<template>
  <div
    role="alert"
    class="mb-3 rounded-xl border border-n-amber-6 bg-n-amber-2 p-4 text-sm text-n-amber-11"
  >
    <p class="m-0 font-semibold">
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_CONFLICT') }}
    </p>
    <p class="mt-2 text-xs">
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_REVIEW_HINT') }}
    </p>
    <dl
      v-if="canUseRemote && current"
      class="mt-3 grid min-w-0 grid-cols-1 gap-2 text-xs"
    >
      <div
        v-for="field in remoteFields"
        :key="field.key"
        :data-qualification-remote-field="field.key"
        class="min-w-0 rounded-md border border-n-amber-6 p-2"
      >
        <dt class="font-semibold">
          {{ field.label }}
        </dt>
        <dd class="m-0 whitespace-pre-wrap break-words">
          {{ field.value || t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_EMPTY') }}
        </dd>
      </div>
    </dl>
    <p v-else-if="canUseRemote" class="mt-2 text-xs">
      {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_NO_PENDING') }}
    </p>
    <div class="mt-3 flex flex-wrap gap-2">
      <button
        type="button"
        :disabled="busy"
        class="rounded-md border border-n-amber-6 bg-n-solid-1 px-3 py-2 text-xs disabled:opacity-40"
        data-qualification-review="reload"
        @click="emit('reload')"
      >
        {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_RELOAD') }}
      </button>
      <button
        type="button"
        :disabled="busy || !canUseRemote"
        class="rounded-md border border-n-amber-6 bg-n-solid-1 px-3 py-2 text-xs disabled:opacity-40"
        data-qualification-review="remote"
        @click="emit('useRemote')"
      >
        {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_USE_REMOTE') }}
      </button>
      <button
        type="button"
        :disabled="busy || !canReapply"
        class="rounded-md border border-n-amber-6 bg-n-solid-1 px-3 py-2 text-xs disabled:opacity-40"
        data-qualification-review="reapply"
        @click="emit('reapply')"
      >
        {{ t('JRC_CONTACT_CENTER.ACW_OPERATION.DRAFT_REAPPLY') }}
      </button>
    </div>
  </div>
</template>
