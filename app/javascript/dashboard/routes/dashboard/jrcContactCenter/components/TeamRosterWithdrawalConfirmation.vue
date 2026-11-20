<script setup>
import { useI18n } from 'vue-i18n';
import { computed } from 'vue';

const props = defineProps({
  state: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  showSubmit: { type: Boolean, default: false },
});
const emit = defineEmits(['confirm', 'submit', 'cancel']);
const { t } = useI18n();
const text = computed(() => {
  const values = { team: props.state.review?.team_name };
  if (props.state.review?.operation === 'deactivate_source') {
    return {
      title: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DEACTIVATE_TITLE', values),
      confirm: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DEACTIVATE_CONFIRM'),
      apply: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DEACTIVATE_APPLY'),
    };
  }
  if (props.state.review?.operation === 'delete_team') {
    return {
      title: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DELETE_TITLE', values),
      confirm: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DELETE_CONFIRM'),
      apply: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DELETE_APPLY'),
    };
  }
  return {
    title: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.TITLE', values),
    confirm: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.CONFIRM'),
    apply: t('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.APPLY'),
  };
});
</script>

<template>
  <section
    data-team-roster-withdrawal-review
    class="min-w-0 space-y-3 rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-slate-12 sm:col-span-2"
  >
    <template v-if="state.error">
      <p role="alert" class="text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.INVALID') }}
      </p>
      <button
        v-if="showSubmit"
        type="button"
        :disabled="busy"
        class="rounded-lg border border-n-weak px-3 py-2"
        @click="emit('cancel')"
      >
        {{ t('JRC_CONTACT_CENTER.ADMIN.CANCEL') }}
      </button>
    </template>
    <template v-else-if="state.review">
      <h3 class="break-words font-semibold">{{ text.title }}</h3>
      <ul class="space-y-2">
        <li
          v-for="queue in state.review.queues"
          :key="queue.queue_id"
          class="break-words"
          role="alert"
        >
          {{
            t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.IMPACT', {
              queue: queue.queue_name,
              before: queue.previous_count,
              after: queue.remaining_count,
            })
          }}
        </li>
      </ul>
      <p class="text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.QUEUE_WITHDRAWAL.LOCAL_ONLY') }}
      </p>
      <label class="flex items-start gap-2">
        <input
          type="checkbox"
          :checked="state.confirmed"
          :disabled="busy"
          data-team-manager-withdrawal-confirm
          @change="emit('confirm', $event.target.checked)"
        />
        <span>{{ text.confirm }}</span>
      </label>
      <div v-if="showSubmit" class="flex flex-wrap gap-2">
        <button
          type="button"
          :disabled="busy || state.confirmed !== true"
          class="rounded-lg bg-n-brand px-3 py-2 text-white disabled:opacity-40"
          data-apply-team-withdrawal
          @click="emit('submit')"
        >
          {{ text.apply }}
        </button>
        <button
          type="button"
          :disabled="busy"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="emit('cancel')"
        >
          {{ t('JRC_CONTACT_CENTER.ADMIN.CANCEL') }}
        </button>
      </div>
    </template>
  </section>
</template>
