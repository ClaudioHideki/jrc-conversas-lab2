<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  historyFields,
  historyChanges,
  sameHistoryScope,
} from '../helpers/historyPresentation.js';
import { formatTimestamp } from '../helpers/presentation.js';
const props = defineProps({
  event: { type: Object, required: true },
  ticket: { type: Object, required: true },
});
const { t, locale } = useI18n();
const fields = computed(() => historyFields(props.event, props.ticket));
const changes = computed(() => historyChanges(props.event, props.ticket));
</script>

<template>
  <div
    v-if="sameHistoryScope(event, ticket)"
    class="grid gap-3 border-s-2 border-n-blue-7 ps-4 py-1"
  >
    <div class="flex flex-wrap items-start justify-between gap-2">
      <h4 class="font-semibold text-sm">
        {{ t(`JRC_SERVICE_DESK.OPS.EVENTS.${event.event_type}`) }}
      </h4>
      <time class="text-xs text-n-slate-11" :datetime="event.created_at">{{
        formatTimestamp(event.created_at, locale)
      }}</time>
    </div>
    <p class="text-xs text-n-slate-11">
      {{
        t('JRC_SERVICE_DESK.EXPERIENCE.history.author', {
          name:
            event.author?.name || t('JRC_SERVICE_DESK.COMMON.not_available'),
        })
      }}
    </p>
    <dl v-if="fields.length" class="grid gap-2 sm:grid-cols-2">
      <div v-for="field in fields" :key="field.key" class="min-w-0">
        <dt class="text-xs text-n-slate-11">
          {{ t(`JRC_SERVICE_DESK.EXPERIENCE.history.fields.${field.key}`) }}
        </dt>
        <dd class="text-sm break-words">{{ field.value }}</dd>
      </div>
    </dl>
    <p v-if="!fields.length && !changes.length" class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.history.restricted') }}
    </p>
    <dl v-if="changes.length" class="grid gap-2">
      <div v-for="change in changes" :key="change.key">
        <dt class="text-xs text-n-slate-11">
          {{ t(`JRC_SERVICE_DESK.EXPERIENCE.history.fields.${change.key}`) }}
        </dt>
        <dd class="text-sm break-words">
          {{
            t('JRC_SERVICE_DESK.EXPERIENCE.history.changed', {
              before: change.before ?? t('JRC_SERVICE_DESK.COMMON.no_value'),
              after: change.after ?? t('JRC_SERVICE_DESK.COMMON.no_value'),
            })
          }}
        </dd>
      </div>
    </dl>
    <details class="text-xs text-n-slate-11">
      <summary class="cursor-pointer">
        {{ t('JRC_SERVICE_DESK.EXPERIENCE.history.technical') }}
      </summary>
      <p class="my-2">
        {{ t('JRC_SERVICE_DESK.EXPERIENCE.history.projected_only') }}
      </p>
      <pre
        class="max-h-48 overflow-auto whitespace-pre-wrap break-words rounded-lg border border-n-weak p-3"
        >{{ JSON.stringify(event.data, null, 2) }}</pre
      >
    </details>
  </div>
</template>
