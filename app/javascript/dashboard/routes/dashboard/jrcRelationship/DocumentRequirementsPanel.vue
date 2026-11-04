<script setup>
import { useI18n } from 'vue-i18n';
defineProps({ requirements: { type: Object, required: true } });
const emit = defineEmits(['openDocument']);
const { t } = useI18n();
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-xl border border-n-violet-6 bg-n-solid-2 p-4"
  >
    <h4 class="font-semibold">
      {{ t('RELATIONSHIP.V2.DOCS.REQUIRED_HEADING') }}
    </h4>
    <p class="break-words text-sm text-n-slate-11">
      {{ requirements.scope_key }} ·
      {{
        t('RELATIONSHIP.VERSION', {
          version: requirements.configuration_version,
        })
      }}
    </p>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.V2.DOCS.FILE_NOT_APPROVAL') }}
    </p>
    <p v-if="!requirements.entries.length">
      {{ t('RELATIONSHIP.V2.DOCS.NO_REQUIREMENTS') }}
    </p>
    <ul
      v-else
      class="grid min-w-0 list-none gap-3 p-0 sm:grid-cols-2"
    >
      <li
        v-for="entry in requirements.entries"
        :key="entry.code"
        class="min-w-0 space-y-1 rounded-lg border border-n-weak p-3"
      >
        <strong class="break-words">{{ entry.title }}</strong>
        <p class="text-sm">
          {{ t(`RELATIONSHIP.V2.DOCS.REQUIREMENT_STATES.${entry.state}`) }}
        </p>
        <button
          v-if="entry.document_id"
          type="button"
          class="rounded-lg border border-n-violet-6 px-3 py-2 text-sm text-n-violet-11"
          @click="emit('openDocument', entry.document_id)"
        >
          {{ t('RELATIONSHIP.V2.DOCS.VERSIONS') }}
        </button>
      </li>
    </ul>
  </section>
</template>
