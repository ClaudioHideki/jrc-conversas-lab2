<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CalendarDetailsFields from './CalendarDetailsFields.vue';
import QueueCalendarRemoval from './QueueCalendarRemoval.vue';
import { useQueueCalendarBindings } from '../composables/useQueueCalendarBindings';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: String, required: true },
  calendarId: { type: String, required: true },
  contextKey: { type: String, required: true },
  canManage: { type: Boolean, default: false },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const state = useQueueCalendarBindings({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  calendarId: computed(() => props.calendarId),
  contextKey: computed(() => props.contextKey),
  canManage: computed(() => props.canManage),
  onDenied: () => emit('denied'),
});
const popup = state.dialog;
const errors = computed(() => ({
  LOAD_ERROR: t('JRC_CONTACT_CENTER.CALENDAR.LOAD_ERROR'),
  CONFLICT: t('JRC_CONTACT_CENTER.CALENDAR_BINDING.CONFLICT'),
  UNCERTAIN: t('JRC_CONTACT_CENTER.CALENDAR_BINDING.UNCERTAIN'),
}));
</script>

<template>
  <Button
    type="button"
    variant="faded"
    :label="t('JRC_CONTACT_CENTER.CALENDAR_BINDING.OPEN')"
    :data-queue-calendar-bindings="calendarId"
    :disabled="!canManage || state.active.value"
    @click="state.open"
  />
  <Dialog
    ref="popup"
    contained
    :title="t('JRC_CONTACT_CENTER.CALENDAR_BINDING.TITLE')"
    :dismissible="!state.busy.value && !state.selectionLocked.value"
    @close="state.clear"
  >
    <div
      class="min-w-0 space-y-3 text-sm text-n-slate-12"
      data-queue-calendar-dialog
    >
      <p class="break-words rounded-lg bg-n-amber-2 p-3 text-n-amber-11">
        {{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.LOCAL_ONLY') }}
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
      <form class="grid min-w-0 gap-2" @submit.prevent="state.load(1)">
        <label class="grid gap-1">
          <span>{{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.SEARCH') }}</span>
          <input
            v-model="state.query.value"
            maxlength="100"
            :disabled="
              state.busy.value ||
              state.selectionLocked.value ||
              Boolean(state.payload.value)
            "
            data-calendar-queue-search
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          />
        </label>
        <Button
          type="submit"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR_BINDING.APPLY')"
          :disabled="
            state.busy.value ||
            state.selectionLocked.value ||
            Boolean(state.payload.value)
          "
        />
      </form>
      <p class="break-words">
        {{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.RESOURCES') }}
      </p>
      <p
        v-if="
          !state.busy.value && !state.rows.value.length && !state.error.value
        "
        role="status"
      >
        {{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.EMPTY') }}
      </p>
      <article
        v-for="row in state.rows.value"
        :key="row.queue_id"
        class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        :data-calendar-queue="row.queue_id"
      >
        <h4 class="break-words font-semibold">{{ row.queue_name }}</h4>
        <p class="break-words">
          {{
            row.binding
              ? row.binding.calendar_snapshot.definition.name
              : t('JRC_CONTACT_CENTER.CALENDAR_BINDING.NONE')
          }}
        </p>
        <p v-if="row.calendar_changed" class="break-words text-n-amber-11">
          {{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.CHANGED') }}
        </p>
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR_BINDING.REVIEW')"
          :data-review-queue-calendar="row.queue_id"
          :disabled="
            state.busy.value ||
            state.selectionLocked.value ||
            Boolean(state.payload.value)
          "
          @click="state.choose(row.queue_id)"
        />
      </article>
      <nav
        v-if="state.meta.value.pages > 1"
        class="flex flex-wrap items-center gap-2"
        :aria-label="t('JRC_CONTACT_CENTER.CALENDAR.PAGINATION')"
      >
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.PREVIOUS')"
          :disabled="
            state.busy.value ||
            state.selectionLocked.value ||
            Boolean(state.payload.value) ||
            state.page.value <= 1
          "
          @click="state.load(state.page.value - 1)"
        />
        <span>{{
          t('JRC_CONTACT_CENTER.CALENDAR.TOTAL', {
            total: state.meta.value.total,
            page: state.page.value,
          })
        }}</span>
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.NEXT')"
          :disabled="
            state.busy.value ||
            state.selectionLocked.value ||
            Boolean(state.payload.value) ||
            state.page.value >= state.meta.value.pages
          "
          @click="state.load(state.page.value + 1)"
        />
      </nav>
      <section
        v-if="state.selected.value && state.proposed.value"
        class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 p-3"
        data-calendar-queue-review
      >
        <h4 class="break-words font-semibold">
          {{ state.selected.value.queue_name }}
        </h4>
        <QueueCalendarRemoval
          v-if="state.selected.value.binding || state.selectionLocked.value"
          :account-id="accountId"
          :unit-id="unitId"
          :row="state.selected.value"
          :context-key="contextKey"
          :can-manage="canManage && !state.busy.value && !state.payload.value"
          :validate-current="state.validRow"
          @lock="state.lockSelection"
          @current="state.acceptCurrent"
          @denied="emit('denied')"
        />
        <p>{{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.PROPOSED') }}</p>
        <CalendarDetailsFields
          :model-value="state.proposed.value.item.definition"
          disabled
        />
        <p>
          {{
            state.proposed.value.item.active
              ? t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL')
              : t('JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL')
          }}
        </p>
        <details v-if="state.selected.value.binding" class="min-w-0 space-y-3">
          <summary>
            {{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.CURRENT') }}
          </summary>
          <p class="break-all">
            {{ state.selected.value.binding.calendar_digest }}
          </p>
          <CalendarDetailsFields
            :model-value="
              state.selected.value.binding.calendar_snapshot.definition
            "
            disabled
          />
          <p>
            {{
              state.selected.value.binding.calendar_snapshot.active
                ? t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL')
                : t('JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL')
            }}
          </p>
        </details>
        <p class="break-words" data-current-queue-calendar>
          {{
            state.selected.value.binding
              ? state.selected.value.binding.calendar_snapshot.definition.name
              : t('JRC_CONTACT_CENTER.CALENDAR_BINDING.NONE')
          }}
        </p>
        <p class="break-words">
          {{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.PINNED') }}
        </p>
        <Button
          v-if="state.error.value === 'CONFLICT'"
          type="button"
          variant="faded"
          data-reload-queue-calendar
          :label="t('JRC_CONTACT_CENTER.CALENDAR.RELOAD')"
          :disabled="state.busy.value || state.selectionLocked.value"
          @click="state.choose(state.selected.value.queue_id)"
        />
        <label
          v-if="!state.confirmed.value"
          class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3"
        >
          <input
            v-model="state.reviewed.value"
            type="checkbox"
            data-confirm-queue-calendar
            :disabled="
              state.busy.value ||
              state.selectionLocked.value ||
              state.error.value === 'CONFLICT'
            "
            class="mt-1 shrink-0"
          />
          <span>{{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.CONFIRM') }}</span>
        </label>
      </section>
      <p
        v-if="state.confirmed.value"
        role="status"
        class="break-words rounded-lg bg-n-teal-2 p-3 text-n-teal-11"
        data-queue-calendar-confirmed
      >
        {{ t('JRC_CONTACT_CENTER.CALENDAR_BINDING.SAVED') }}
      </p>
    </div>
    <template #footer>
      <div class="flex w-full items-center justify-between gap-3">
        <Button
          type="button"
          variant="faded"
          color="slate"
          class="w-full"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.CLOSE')"
          :disabled="state.busy.value || state.selectionLocked.value"
          @click="popup.close()"
        />
        <Button
          type="button"
          color="blue"
          class="w-full"
          :label="t('JRC_CONTACT_CENTER.CALENDAR_BINDING.SAVE')"
          :disabled="!state.canSave.value"
          data-save-queue-calendar
          @click="state.save"
        />
      </div>
    </template>
  </Dialog>
</template>
