<script setup>
import { computed, ref, watch } from 'vue';
import { RouterLink, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { buttonClass } from './definitions';
const props = defineProps({ rows: { type: Array, default: () => [] } });
const route = useRoute();
const { t } = useI18n();
const page = ref(1);
const proofs = computed(() =>
  props.rows
    .filter(row => row.state !== 'unavailable')
    .flatMap(row =>
      (row.project_handoffs || []).map(proof => ({
        ...proof,
        assignmentId: row.assignment_id,
        customerLabel: row.label,
      }))
    )
);
const pages = computed(() => Math.max(1, Math.ceil(proofs.value.length / 10)));
const visible = computed(() =>
  proofs.value.slice((page.value - 1) * 10, page.value * 10)
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
    v-if="proofs.length"
    data-testid="project-handoff-proofs"
    class="min-w-0 space-y-3 rounded-lg border border-n-weak p-3"
  >
    <h4 class="font-semibold">
      {{ t('RELATIONSHIP.RESPONSIBILITIES.PROJECTS.TITLE') }}
    </h4>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.RESPONSIBILITIES.PROJECTS.NOTICE') }}
    </p>
    <div
      v-for="proof in visible"
      :key="`${proof.assignmentId}:${proof.id}`"
      data-testid="project-handoff-proof"
      class="min-w-0 space-y-1 rounded-lg bg-n-alpha-2 p-3 text-sm"
    >
      <p class="break-words">{{ proof.customerLabel }}</p>
      <RouterLink
        :to="{
          name: 'jrc_projects_detail',
          params: { accountId: route.params.accountId, projectId: proof.id },
        }"
        class="block break-words text-n-blue-11 underline"
      >
        {{ proof.label }}
      </RouterLink>
      <p class="break-words">
        {{ t(`RELATIONSHIP.RESPONSIBILITIES.PROJECTS.STATES.${proof.state}`) }}
      </p>
    </div>
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
