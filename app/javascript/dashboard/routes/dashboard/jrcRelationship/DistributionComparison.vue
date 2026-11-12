<script setup>
import { useI18n } from 'vue-i18n';
defineProps({ rows: { type: Array, required: true } });
const { t } = useI18n();
</script>

<template>
  <section
    class="my-3 min-w-0 space-y-2"
    :aria-label="t('RELATIONSHIP.DISTRIBUTION.COMPARISON')"
  >
    <h4 class="font-semibold">
      {{ t('RELATIONSHIP.DISTRIBUTION.COMPARISON') }}
    </h4>
    <article
      v-for="row in rows"
      :key="row.assignment_id"
      class="grid min-w-0 gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-3 text-sm sm:grid-cols-3"
    >
      <strong class="break-words">{{ row.label }}</strong>
      <p class="break-words">
        {{ t('RELATIONSHIP.DISTRIBUTION.FROM') }}:
        {{ row.from_owner_name || t('RELATIONSHIP.UNASSIGNED') }}
      </p>
      <p class="break-words">
        {{ t('RELATIONSHIP.DISTRIBUTION.TO') }}:
        {{ row.to_owner_name || t('RELATIONSHIP.UNASSIGNED') }}
      </p>
    </article>
  </section>
</template>
