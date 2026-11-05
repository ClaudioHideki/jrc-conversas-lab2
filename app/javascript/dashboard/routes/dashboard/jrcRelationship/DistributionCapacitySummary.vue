<script setup>
import { useI18n } from 'vue-i18n';
defineProps({ rows: { type: Array, default: () => [] } });
const { t } = useI18n();
</script>

<template>
  <section
    v-if="rows.length"
    class="my-3 min-w-0 space-y-3 rounded-xl border border-n-weak p-3"
  >
    <h3 class="font-semibold">{{ t('RELATIONSHIP.CAPACITY.REVIEW_TITLE') }}</h3>
    <p class="text-sm">{{ t('RELATIONSHIP.CAPACITY.REVIEW_NOTICE') }}</p>
    <div
      v-for="(row, index) in rows"
      :key="index"
      class="rounded-lg bg-n-alpha-2 p-3 text-sm"
    >
      <p class="font-medium">
        {{ t(`RELATIONSHIP.CAPACITY.SCOPES.${row.scope_key.split(':')[0]}`) }}
      </p>
      <p class="text-sm">
        {{ t(`RELATIONSHIP.CAPACITY.UNITS.${row.unit || 'customers'}`) }}
      </p>
      <p
        v-if="row.blocker"
        role="alert"
        class="text-n-ruby-11"
      >
        {{ t(`RELATIONSHIP.CAPACITY.BLOCKERS.${row.blocker}`) }}
      </p>
      <dl
        v-if="row.projected !== undefined"
        class="mt-2 grid gap-2 sm:grid-cols-2 lg:grid-cols-4"
      >
        <div
          v-for="key in [
            'current',
            'incoming',
            'projected',
            'effective_capacity',
            'available_after',
          ]"
          :key="key"
        >
          <dt>{{ t(`RELATIONSHIP.CAPACITY.FACTS.${key}`) }}</dt>
          <dd class="font-semibold">{{ row[key] }}</dd>
        </div>
      </dl>
    </div>
  </section>
</template>
