<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { buttonClass } from './definitions';
const props = defineProps({
  rows: { type: Array, default: () => [] },
  ownerName: { type: String, default: '' },
});
const { t } = useI18n();
const page = ref(1);
const entries = computed(() =>
  props.rows.flatMap(row =>
    row.entries.map(entry => ({ ...entry, customerLabel: row.label }))
  )
);
const pages = computed(() => Math.max(1, Math.ceil(entries.value.length / 10)));
const visible = computed(() =>
  entries.value.slice((page.value - 1) * 10, page.value * 10)
);
watch(
  () => props.rows,
  () => {
    page.value = 1;
  }
);
</script>

<template>
  <section
    v-if="rows.length"
    class="my-3 min-w-0 space-y-3 rounded-xl border border-n-weak p-3"
  >
    <h3 class="font-semibold">
      {{ t('RELATIONSHIP.RESPONSIBILITIES.TITLE') }}
    </h3>
    <p class="text-sm">{{ t('RELATIONSHIP.RESPONSIBILITIES.NOTICE') }}</p>
    <p
      v-for="row in rows"
      :key="row.assignment_id"
      class="text-sm"
      :role="
        row.state === 'ready' || row.state === 'executed' ? undefined : 'alert'
      "
    >
      {{ t(`RELATIONSHIP.RESPONSIBILITIES.STATES.${row.state}`) }}
      <span
        v-for="blocker in row.blockers"
        :key="blocker"
        class="block text-n-ruby-11"
        >{{ t(`RELATIONSHIP.RESPONSIBILITIES.BLOCKERS.${blocker}`) }}</span
      >
    </p>
    <article
      v-for="row in visible"
      :key="`${row.kind}:${row.id}`"
      class="grid min-w-0 gap-2 rounded-lg bg-n-alpha-2 p-3 text-sm sm:grid-cols-3"
    >
      <p class="break-words">
        <span
          v-if="row.customerLabel"
          class="block"
          >{{ t('RELATIONSHIP.FIELDS.customer') }}:
          {{ row.customerLabel }}</span
        >
        <strong>{{
          t(`RELATIONSHIP.RESPONSIBILITIES.KINDS.${row.kind}`)
        }}</strong
        ><span class="block">{{ row.label }}</span>
      </p>
      <p class="break-words">
        {{ t('RELATIONSHIP.DISTRIBUTION.FROM') }}:
        {{ row.from_owner_name || t('RELATIONSHIP.UNASSIGNED') }}
      </p>
      <p class="break-words">
        {{ t('RELATIONSHIP.DISTRIBUTION.TO') }}:
        {{
          ownerName || t('RELATIONSHIP.RESPONSIBILITIES.REVIEWED_DESTINATION')
        }}
      </p>
    </article>
    <div
      v-if="pages > 1"
      class="flex flex-wrap items-center gap-2"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="page === 1"
        @click="page--"
      >
        {{ t('RELATIONSHIP.RESPONSIBILITIES.PREVIOUS') }}
      </button>
      <span>{{
        t('RELATIONSHIP.RESPONSIBILITIES.PAGE', { page, pages })
      }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="page === pages"
        @click="page++"
      >
        {{ t('RELATIONSHIP.RESPONSIBILITIES.NEXT') }}
      </button>
    </div>
  </section>
</template>
