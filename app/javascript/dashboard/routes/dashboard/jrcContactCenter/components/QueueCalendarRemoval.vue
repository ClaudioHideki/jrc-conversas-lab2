<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useQueueCalendarRemoval } from '../composables/useQueueCalendarRemoval';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: String, required: true },
  row: { type: Object, required: true },
  contextKey: { type: String, required: true },
  canManage: { type: Boolean, default: false },
  validateCurrent: { type: Function, required: true },
});
const emit = defineEmits(['lock', 'current', 'denied']);
const { t } = useI18n();
const state = useQueueCalendarRemoval({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  row: computed(() => props.row),
  contextKey: computed(() => props.contextKey),
  canManage: computed(() => props.canManage),
  validateCurrent: value => props.validateCurrent(value),
  onLock: value => emit('lock', value),
  onCurrent: value => emit('current', value),
  onDenied: () => emit('denied'),
});
const errors = computed(() => ({
  CONFLICT: t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.CONFLICT'),
  UNCERTAIN: t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.UNCERTAIN'),
  CURRENT_UNKNOWN: t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.CURRENT_UNKNOWN'),
}));
</script>

<template>
  <div class="min-w-0">
    <section
      v-if="row.binding || state.active.value"
      class="min-w-0 space-y-3 rounded-lg border border-n-ruby-6 p-3"
      data-calendar-removal
    >
      <Button
        v-if="!state.active.value"
        type="button"
        variant="faded"
        color="ruby"
        :label="t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.OPEN')"
        :disabled="!canManage"
        data-review-calendar-removal
        @click="state.open"
      />
      <template v-else>
        <h4 class="break-words font-semibold">
          {{ t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.TITLE') }}
        </h4>
        <p class="break-words">{{ row.queue_name }}</p>
        <p class="break-words">
          {{ row.binding.calendar_snapshot.definition.name }}
        </p>
        <p class="break-all">{{ row.binding.calendar_digest }}</p>
        <p class="break-words rounded-lg bg-n-amber-2 p-3 text-n-amber-11">
          {{ t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.LOCAL_ONLY') }}
        </p>
        <p
          v-if="state.error.value"
          role="alert"
          class="break-words text-n-ruby-11"
        >
          {{ errors[state.error.value] }}
        </p>
        <p v-if="state.busy.value" role="status">
          {{ t('JRC_CONTACT_CENTER.CALENDAR.LOADING') }}
        </p>
        <template v-if="state.receipt.value">
          <p
            role="status"
            class="break-words rounded-lg bg-n-teal-2 p-3 text-n-teal-11"
            data-calendar-removal-receipt
          >
            {{
              t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.CONFIRMED', {
                audit: state.receipt.value.audit_id,
              })
            }}
          </p>
          <p
            v-if="state.current.value"
            class="break-words"
            data-calendar-removal-current
          >
            {{ t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.CURRENT') }}
            {{
              state.current.value.binding?.calendar_snapshot.definition.name ||
              t('JRC_CONTACT_CENTER.CALENDAR_BINDING.NONE')
            }}
          </p>
          <Button
            v-if="!state.current.value"
            type="button"
            variant="faded"
            :label="t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.REFRESH')"
            :disabled="state.busy.value"
            data-refresh-calendar-removal
            @click="state.refresh"
          />
        </template>
        <label
          v-else-if="state.error.value !== 'CONFLICT'"
          class="flex items-start gap-2 rounded-lg border border-n-ruby-6 p-3"
        >
          <input
            v-model="state.reviewed.value"
            type="checkbox"
            class="mt-1 shrink-0"
            :disabled="state.busy.value"
            data-confirm-calendar-removal
          />
          <span>{{ t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.REVIEW') }}</span>
        </label>
        <div class="flex flex-wrap gap-2">
          <Button
            v-if="!state.payload.value || state.current.value"
            type="button"
            variant="faded"
            :label="t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.RETURN')"
            :disabled="state.busy.value"
            data-finish-calendar-removal
            @click="state.finish"
          />
          <Button
            v-if="state.error.value === 'CONFLICT'"
            type="button"
            variant="faded"
            :label="t('JRC_CONTACT_CENTER.CALENDAR.RELOAD')"
            :disabled="state.busy.value"
            data-reload-calendar-removal
            @click="state.reloadAfterConflict"
          />
          <Button
            v-if="!state.receipt.value"
            type="button"
            color="ruby"
            :label="t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.SUBMIT')"
            :disabled="!state.canSubmit.value"
            data-submit-calendar-removal
            @click="state.submit"
          />
        </div>
        <fieldset
          v-if="state.error.value === 'UNCERTAIN'"
          class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        >
          <label class="flex items-start gap-2">
            <input
              v-model="state.abandonReviewed.value"
              type="checkbox"
              class="mt-1 shrink-0"
              :disabled="state.busy.value"
              data-abandon-calendar-removal-review
            />
            <span>{{
              t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.ABANDON_WARNING')
            }}</span>
          </label>
          <Button
            type="button"
            variant="faded"
            :label="t('JRC_CONTACT_CENTER.CALENDAR_REMOVAL.ABANDON')"
            :disabled="state.busy.value || !state.abandonReviewed.value"
            data-abandon-calendar-removal
            @click="state.abandon"
          />
        </fieldset>
      </template>
    </section>
  </div>
</template>
