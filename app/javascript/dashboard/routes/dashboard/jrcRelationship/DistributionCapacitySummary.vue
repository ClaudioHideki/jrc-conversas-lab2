<script setup>
import { useI18n } from 'vue-i18n';
defineProps({
  rows: { type: Array, default: () => [] },
  currentOnly: Boolean,
  showOwner: Boolean,
  owners: { type: Array, default: () => [] },
});
const { t } = useI18n();
</script>

<template>
  <section
    v-if="rows.length"
    class="my-3 min-w-0 space-y-3 rounded-xl border border-n-weak p-3"
  >
    <h3 class="font-semibold">
      {{
        t(
          currentOnly
            ? 'RELATIONSHIP.CAPACITY.CURRENT_TITLE'
            : 'RELATIONSHIP.CAPACITY.REVIEW_TITLE'
        )
      }}
    </h3>
    <p class="text-sm">
      {{
        t(
          currentOnly
            ? 'RELATIONSHIP.CAPACITY.CURRENT_NOTICE'
            : 'RELATIONSHIP.CAPACITY.REVIEW_NOTICE'
        )
      }}
    </p>
    <div
      v-for="(row, index) in rows"
      :key="index"
      class="rounded-lg bg-n-alpha-2 p-3 text-sm"
    >
      <p class="font-medium">
        {{ t(`RELATIONSHIP.CAPACITY.SCOPES.${row.scope_key.split(':')[0]}`) }}
        <span v-if="currentOnly && row.scope_key.includes(':')">
          {{
            t('RELATIONSHIP.CAPACITY.CURRENT_SCOPE_ID', {
              id: row.scope_key.split(':')[1],
            })
          }}
        </span>
      </p>
      <p
        v-if="showOwner"
        class="min-w-0 break-words font-medium"
      >
        {{
          owners.find(owner => owner[0] === row.user_id)?.[1] ||
          t('RELATIONSHIP.CAPACITY.OWNER_ID', { id: row.user_id })
        }}
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
        v-if="
          currentOnly ? row.current !== undefined : row.projected !== undefined
        "
        class="mt-2 grid gap-2 sm:grid-cols-2 lg:grid-cols-4"
      >
        <div
          v-for="key in currentOnly
            ? ['current', 'effective_capacity', 'available_after']
            : [
                'current',
                'incoming',
                'projected',
                'effective_capacity',
                'available_after',
              ]"
          :key="key"
        >
          <dt>
            {{
              t(
                currentOnly && key === 'available_after'
                  ? 'RELATIONSHIP.CAPACITY.CURRENT_REMAINING'
                  : `RELATIONSHIP.CAPACITY.FACTS.${key}`
              )
            }}
          </dt>
          <dd class="font-semibold">{{ row[key] }}</dd>
        </div>
      </dl>
      <p
        v-if="currentOnly && row.current !== undefined"
        class="mt-2 text-sm"
      >
        {{
          t('RELATIONSHIP.CAPACITY.CURRENT_FORMULA', {
            maximum: row.maximum,
            availability: row.availability,
            dedication: row.dedication,
          })
        }}
      </p>
      <p
        v-if="currentOnly && row.current > row.effective_capacity"
        role="status"
        class="mt-2 font-medium text-n-ruby-11"
      >
        {{ t('RELATIONSHIP.CAPACITY.CURRENT_OVERLOAD') }}
      </p>
    </div>
  </section>
</template>
