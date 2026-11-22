<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import CalendarDetailsFields from './CalendarDetailsFields.vue';
import { useIvrCalendarReference } from '../composables/useIvrCalendarReference';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: [String, Number], required: true },
  modelValue: { type: Object, default: null },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue', 'denied']);
const { t } = useI18n();
const picker = useIvrCalendarReference({
  accountId: computed(() => props.accountId),
  unitId: computed(() => props.unitId),
  disabled: computed(() => props.disabled),
  onConfirm: value => emit('update:modelValue', value),
  onDenied: () => emit('denied'),
});
const errors = computed(() => ({
  LOAD_ERROR: t('JRC_CONTACT_CENTER.CALENDAR.LOAD_ERROR'),
  DENIED: t('JRC_CONTACT_CENTER.IVR_CALENDAR.DENIED'),
}));
const remove = () => {
  if (props.disabled || picker.loading.value) return;
  picker.clear();
  emit('update:modelValue', null);
};
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-lg border border-n-blue-6 bg-n-blue-2 p-3"
    data-ivr-calendar-reference
  >
    <h5 class="font-semibold text-n-slate-12">
      {{ t('JRC_CONTACT_CENTER.IVR_CALENDAR.TITLE') }}
    </h5>
    <p class="break-words text-sm text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.IVR_CALENDAR.LOCAL_ONLY') }}
    </p>
    <div v-if="modelValue" class="min-w-0 space-y-2" data-ivr-calendar-pinned>
      <p class="break-words font-medium">
        {{ modelValue.snapshot.definition.name }}
      </p>
      <p class="break-words">{{ modelValue.snapshot.definition.timezone }}</p>
      <p>
        {{
          modelValue.snapshot.active
            ? t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL')
            : t('JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL')
        }}
      </p>
      <p class="break-words text-sm">
        {{ t('JRC_CONTACT_CENTER.IVR_CALENDAR.PINNED') }}
      </p>
      <details class="min-w-0">
        <summary>{{ t('JRC_CONTACT_CENTER.IVR_CALENDAR.DETAILS') }}</summary>
        <CalendarDetailsFields
          :model-value="modelValue.snapshot.definition"
          disabled
        />
      </details>
    </div>
    <p
      v-if="picker.error.value"
      role="alert"
      class="break-words text-sm text-n-ruby-11"
    >
      {{ errors[picker.error.value] }}
    </p>
    <div class="flex flex-wrap gap-2">
      <Button
        type="button"
        variant="faded"
        data-ivr-calendar-choose
        :disabled="disabled || !unitId || picker.loading.value"
        :label="
          modelValue
            ? t('JRC_CONTACT_CENTER.IVR_CALENDAR.CHANGE')
            : t('JRC_CONTACT_CENTER.IVR_CALENDAR.CHOOSE')
        "
        @click="picker.begin"
      />
      <Button
        v-if="modelValue"
        type="button"
        variant="faded"
        color="ruby"
        data-ivr-calendar-remove
        :label="t('JRC_CONTACT_CENTER.IVR_CALENDAR.REMOVE')"
        :disabled="disabled || picker.loading.value"
        @click="remove"
      />
    </div>
    <div
      v-if="picker.choosing.value"
      class="min-w-0 space-y-3"
      data-ivr-calendar-chooser
    >
      <form
        class="flex min-w-0 flex-wrap gap-2"
        @submit.prevent="picker.load(1)"
      >
        <input
          v-model="picker.query.value"
          type="search"
          maxlength="100"
          :disabled="disabled || picker.loading.value"
          :aria-label="t('JRC_CONTACT_CENTER.IVR_CALENDAR.SEARCH')"
          data-ivr-calendar-search
          class="h-10 min-w-0 flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
        />
        <Button
          type="submit"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.IVR_CALENDAR.SEARCH_BUTTON')"
          :disabled="disabled || picker.loading.value"
        />
      </form>
      <p v-if="picker.loading.value" role="status">
        {{ t('JRC_CONTACT_CENTER.CALENDAR.LOADING') }}
      </p>
      <p
        v-if="
          !picker.loading.value &&
          !picker.rows.value.length &&
          !picker.error.value
        "
        role="status"
      >
        {{ t('JRC_CONTACT_CENTER.CALENDAR.EMPTY') }}
      </p>
      <article
        v-for="row in picker.rows.value"
        :key="row.id"
        class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        :data-ivr-calendar-row="row.id"
      >
        <p class="break-words font-medium">{{ row.definition.name }}</p>
        <p class="break-words">{{ row.definition.timezone }}</p>
        <Button
          type="button"
          variant="faded"
          :data-ivr-calendar-select="row.id"
          :label="t('JRC_CONTACT_CENTER.IVR_CALENDAR.REVIEW')"
          :disabled="disabled || picker.loading.value"
          @click="picker.choose(row.id)"
        />
      </article>
      <nav
        v-if="picker.meta.value.pages > 1"
        class="flex flex-wrap gap-2"
        :aria-label="t('JRC_CONTACT_CENTER.CALENDAR.PAGINATION')"
      >
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.PREVIOUS')"
          :disabled="disabled || picker.loading.value || picker.page.value <= 1"
          @click="picker.load(picker.page.value - 1)"
        />
        <span>{{
          t('JRC_CONTACT_CENTER.CALENDAR.TOTAL', {
            total: picker.meta.value.total,
            page: picker.page.value,
          })
        }}</span>
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.NEXT')"
          :disabled="
            disabled ||
            picker.loading.value ||
            picker.page.value >= picker.meta.value.pages
          "
          @click="picker.load(picker.page.value + 1)"
        />
      </nav>
      <section
        v-if="picker.candidate.value"
        class="min-w-0 space-y-3"
        data-ivr-calendar-review
      >
        <p class="break-words text-sm" data-ivr-calendar-candidate-state>
          {{
            picker.candidate.value.snapshot.active
              ? t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL')
              : t('JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL')
          }}
        </p>
        <CalendarDetailsFields
          :model-value="picker.candidate.value.snapshot.definition"
          disabled
        />
        <label class="flex items-start gap-2 text-sm">
          <input
            v-model="picker.reviewed.value"
            type="checkbox"
            data-ivr-calendar-confirm
            :disabled="disabled || picker.loading.value"
            class="mt-1 shrink-0"
          />
          <span>{{ t('JRC_CONTACT_CENTER.IVR_CALENDAR.CONFIRM') }}</span>
        </label>
        <Button
          type="button"
          data-ivr-calendar-use
          :label="t('JRC_CONTACT_CENTER.IVR_CALENDAR.USE')"
          :disabled="!picker.canConfirm.value"
          @click="picker.confirm"
        />
      </section>
      <Button
        type="button"
        variant="faded"
        :label="t('JRC_CONTACT_CENTER.IVR_CALENDAR.CANCEL')"
        :disabled="disabled || picker.loading.value"
        @click="picker.clear"
      />
    </div>
  </section>
</template>
