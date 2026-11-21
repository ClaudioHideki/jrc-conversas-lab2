<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CalendarDetailsFields from './CalendarDetailsFields.vue';
import { useUnitCalendarEditor } from '../composables/useUnitCalendarEditor';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: String, required: true },
  timezone: { type: String, required: true },
  contextKey: { type: String, required: true },
  canManage: { type: Boolean, default: false },
});
const emit = defineEmits(['saved', 'denied']);
const { t } = useI18n();
const errors = computed(() => ({
  LOAD_ERROR: t('JRC_CONTACT_CENTER.CALENDAR.LOAD_ERROR'),
  SAVE_ERROR: t('JRC_CONTACT_CENTER.CALENDAR.SAVE_ERROR'),
  IDENTITY_CONFLICT: t('JRC_CONTACT_CENTER.CALENDAR.IDENTITY_CONFLICT'),
}));
const state = useUnitCalendarEditor({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  timezone: computed(() => props.timezone),
  contextKey: computed(() => props.contextKey),
  canManage: computed(() => props.canManage),
  onDenied: () => emit('denied'),
  onSaved: item => emit('saved', item),
});
const popup = state.dialog;
defineExpose({ open: id => state.open(id) });
</script>

<template>
  <Button
    type="button"
    color="blue"
    icon="i-lucide-calendar-plus"
    data-new-unit-calendar
    :label="t('JRC_CONTACT_CENTER.CALENDAR.NEW')"
    :disabled="!canManage || state.active.value || state.busy.value"
    @click="state.open()"
  />
  <p
    v-if="state.error.value && !state.active.value"
    role="alert"
    class="break-words text-sm text-n-ruby-11"
  >
    {{ errors[state.error.value] }}
  </p>
  <Dialog
    ref="popup"
    contained
    use-form
    :title="t('JRC_CONTACT_CENTER.CALENDAR.EDITOR')"
    :dismissible="!state.busy.value"
    @confirm="state.save"
    @close="state.clear"
  >
    <div
      v-if="state.draft.value"
      class="min-w-0 space-y-4 text-sm text-n-slate-12"
      data-unit-calendar-editor
    >
      <p class="break-words">
        {{ t('JRC_CONTACT_CENTER.CALENDAR.LOCAL_ONLY') }}
      </p>
      <p
        v-if="state.error.value"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ errors[state.error.value] }}
      </p>
      <p
        v-if="state.uncertain.value"
        role="alert"
        class="break-words rounded-lg bg-n-amber-2 p-3 text-n-amber-11"
      >
        {{ t('JRC_CONTACT_CENTER.CALENDAR.UNKNOWN_RESULT') }}
      </p>
      <CalendarDetailsFields
        v-model="state.draft.value.definition"
        :disabled="state.busy.value"
      />
      <label class="flex items-start gap-2 rounded-lg border border-n-weak p-3">
        <input
          v-model="state.draft.value.active"
          type="checkbox"
          data-calendar-active
          :disabled="state.busy.value"
          class="mt-1 shrink-0"
        />
        <span>{{ t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL') }}</span>
      </label>
      <section
        v-if="state.revision.state.conflict"
        class="min-w-0 space-y-3 rounded-lg border border-n-amber-6 p-3"
        data-calendar-revision-conflict
      >
        <p class="break-words">
          {{ t('JRC_CONTACT_CENTER.CALENDAR.CONFLICT') }}
        </p>
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.RELOAD')"
          :disabled="state.busy.value || state.revision.state.reloading"
          data-reload-calendar-revision
          @click="state.revision.reload"
        />
        <p
          v-if="state.revision.state.error"
          role="alert"
          class="text-n-ruby-11"
        >
          {{ t('JRC_CONTACT_CENTER.CALENDAR.LOAD_ERROR') }}
        </p>
        <template v-if="state.revision.state.latest">
          <h4 class="font-semibold">
            {{ t('JRC_CONTACT_CENTER.CALENDAR.CURRENT') }}
          </h4>
          <CalendarDetailsFields
            v-if="state.revision.state.latest.present"
            :model-value="state.revision.state.latest.definition"
            disabled
          />
          <p v-else class="break-words">
            {{ t('JRC_CONTACT_CENTER.CALENDAR.NOT_YET_CREATED') }}
          </p>
          <p v-if="state.revision.state.latest.present" class="break-words">
            {{
              state.revision.state.latest.active
                ? t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL')
                : t('JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL')
            }}
          </p>
          <p class="break-words">
            {{ t('JRC_CONTACT_CENTER.CALENDAR.DRAFT_PRESERVED') }}
          </p>
          <label
            class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3"
          >
            <input
              type="checkbox"
              data-review-calendar-revision
              class="mt-1 shrink-0"
              :disabled="state.busy.value"
              :checked="state.revision.reviewed()"
              @change="state.revision.review($event.target.checked)"
            />
            <span>{{ t('JRC_CONTACT_CENTER.CALENDAR.REVIEW_CHANGES') }}</span>
          </label>
        </template>
      </section>
      <label
        class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3"
      >
        <input
          v-model="state.reviewed.value"
          type="checkbox"
          data-review-unit-calendar
          :disabled="state.busy.value"
          class="mt-1 shrink-0"
        />
        <span>{{ t('JRC_CONTACT_CENTER.CALENDAR.REVIEW_SAVE') }}</span>
      </label>
    </div>
    <template #footer>
      <div class="flex w-full items-center justify-between gap-3">
        <Button
          type="button"
          variant="faded"
          color="slate"
          class="w-full"
          data-close-unit-calendar
          :label="t('JRC_CONTACT_CENTER.CALENDAR.CLOSE')"
          :disabled="state.busy.value"
          @click="popup.close()"
        />
        <Button
          type="button"
          color="blue"
          class="w-full"
          data-save-unit-calendar
          :label="t('JRC_CONTACT_CENTER.CALENDAR.SAVE_INTERNAL')"
          :disabled="!state.canSave.value"
          :is-loading="state.saving.value"
          @click="state.save"
        />
      </div>
    </template>
  </Dialog>
</template>
