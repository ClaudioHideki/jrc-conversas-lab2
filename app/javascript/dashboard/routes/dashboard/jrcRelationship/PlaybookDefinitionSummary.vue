<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({ book: { type: Object, required: true } });
const { t, tm, rt } = useI18n();
const trigger = computed(
  () => tm('RELATIONSHIP.TRIGGERS')[props.book.trigger_kind]
);
const kinds = computed(() => tm('RELATIONSHIP.PLAYBOOK_STEPS'));
const fields = computed(() =>
  tm('RELATIONSHIP.PLAYBOOK_RESTORE.CONDITION_FIELDS')
);
const operators = computed(() => tm('RELATIONSHIP.PLAYBOOK_RESTORE.OPERATORS'));
</script>

<template>
  <div class="min-w-0 space-y-3 rounded-lg border border-n-weak p-3">
    <h4 class="break-words font-semibold">
      {{ book.name || t('RELATIONSHIP.UNAVAILABLE') }}
    </h4>
    <p class="text-sm">
      {{ trigger ? rt(trigger) : t('RELATIONSHIP.UNAVAILABLE') }}
    </p>
    <p class="text-sm">
      {{ t('RELATIONSHIP.PLAYBOOK_RESTORE.ACTIVE') }}
      {{
        book.active === true
          ? t('RELATIONSHIP.YES')
          : book.active === false
            ? t('RELATIONSHIP.NO')
            : t('RELATIONSHIP.UNAVAILABLE')
      }}
    </p>
    <ol class="space-y-2">
      <li
        v-for="(step, index) in book.steps || []"
        :key="step.step_key || index"
        class="break-words text-sm"
      >
        {{
          t('RELATIONSHIP.PLAYBOOK_RESTORE.STEP', {
            index: index + 1,
            title: step.title,
            days: step.after_days,
            kind: kinds[step.kind]
              ? rt(kinds[step.kind])
              : t('RELATIONSHIP.UNAVAILABLE'),
          })
        }}
      </li>
    </ol>
    <p class="break-words text-xs text-n-slate-11">
      {{
        t('RELATIONSHIP.PLAYBOOK_RESTORE.CONDITIONS', {
          count: book.conditions?.length ?? t('RELATIONSHIP.UNAVAILABLE'),
        })
      }}
    </p>
    <ul class="space-y-2">
      <li
        v-for="(condition, index) in book.conditions || []"
        :key="index"
        class="break-words text-sm"
      >
        {{
          t('RELATIONSHIP.PLAYBOOK_RESTORE.CONDITION', {
            field: fields[condition.field]
              ? rt(fields[condition.field])
              : t('RELATIONSHIP.UNAVAILABLE'),
            operator: operators[condition.operator]
              ? rt(operators[condition.operator])
              : t('RELATIONSHIP.UNAVAILABLE'),
            value: condition.value,
          })
        }}
      </li>
    </ul>
  </div>
</template>
