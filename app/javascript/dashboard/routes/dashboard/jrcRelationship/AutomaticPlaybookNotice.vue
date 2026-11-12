<script setup>
import { useI18n } from 'vue-i18n';
import { date } from './definitions';
defineProps({
  attempt: { type: Object, default: null },
  formatting: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
</script>

<template>
  <div
    v-if="attempt?.state === 'deferred'"
    role="status"
    data-testid="automatic-playbook-deferred"
    class="my-3 min-w-0 rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm text-amber-950 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-100"
  >
    <p class="font-semibold">{{ t('RELATIONSHIP.PLAYBOOK_BUDGET.TITLE') }}</p>
    <p>
      {{
        t(
          attempt.reason === 'native_assignment_unavailable'
            ? 'RELATIONSHIP.PLAYBOOK_BUDGET.ASSIGNMENT'
            : 'RELATIONSHIP.PLAYBOOK_BUDGET.DAILY',
          { count: attempt.required_actions }
        )
      }}
    </p>
    <p>{{ t('RELATIONSHIP.PLAYBOOK_BUDGET.NOTE') }}</p>
    <p>
      {{ t('RELATIONSHIP.PLAYBOOK_BUDGET.ATTEMPTED') }}:
      {{ date(attempt.attempted_at, formatting) }}
    </p>
    <p v-if="attempt.eligible_after">
      {{ t('RELATIONSHIP.PLAYBOOK_BUDGET.ELIGIBLE') }}:
      {{ date(attempt.eligible_after, formatting) }}
    </p>
  </div>
</template>
