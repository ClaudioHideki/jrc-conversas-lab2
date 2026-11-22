<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import API from 'dashboard/api/jrcContactCenter';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CalendarEditorDialog from './CalendarEditorDialog.vue';
import QueueCalendarBindings from './QueueCalendarBindings.vue';
import CalendarIvrUsages from './CalendarIvrUsages.vue';
import {
  calendarIntervalsError,
  formatCalendarIntervals,
} from 'dashboard/routes/dashboard/serviceDesk/automationStudio/calendarIntervals';
import { validCalendarDefinition } from '../helpers/calendarForm';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const currentUser = useMapGetter('getCurrentUser');
const units = computed(() => props.context.units || []);
const member = computed(() =>
  currentUser.value?.accounts?.find(
    row => String(row.id) === String(props.accountId)
  )
);
const unitId = computed(() =>
  String(route.query.calendar_unit || units.value[0]?.id || '')
);
const unitAllowed = computed(() =>
  units.value.some(row => String(row.id) === unitId.value)
);
const actorScope = computed(() => {
  const entry = member.value;
  return JSON.stringify([
    currentUser.value?.id,
    entry?.role,
    entry?.custom_role_id,
    entry?.contact_center_eligible,
    [...(entry?.permissions || [])].sort(),
    props.context.capabilities?.configure,
    units.value.map(row => String(row.id)).sort(),
  ]);
});
const blocked = ref(false);
const canManage = computed(
  () =>
    Boolean(currentUser.value?.id && member.value) &&
    props.context.capabilities?.configure === true &&
    unitAllowed.value &&
    !blocked.value
);
const page = computed(() =>
  Math.min(
    1_000_000,
    Math.max(1, Math.floor(Number(route.query.calendar_page)) || 1)
  )
);
const query = ref('');
const status = ref('all');
const items = ref([]);
const meta = ref({ total: 0, pages: 0 });
const unitTimezone = ref('');
const loading = ref(false);
const error = ref(false);
const editor = ref(null);
const lastSaved = ref(null);
const previewDialog = ref(null);
const previewId = ref('');
const previewDate = ref('');
const preview = ref(null);
const previewLoading = ref(false);
const previewError = ref(false);
const precedenceLabels = computed(() => ({
  exception: t('JRC_CONTACT_CENTER.CALENDAR.PREVIEW_EXCEPTION'),
  holiday: t('JRC_CONTACT_CENTER.CALENDAR.PREVIEW_HOLIDAY'),
  weekly: t('JRC_CONTACT_CENTER.CALENDAR.PREVIEW_WEEKLY'),
}));
let generation = 0;
let detailGeneration = 0;
const navigate = values =>
  router.replace({ query: { ...route.query, ...values } });
const resetPreview = () => {
  detailGeneration += 1;
  previewId.value = '';
  previewDate.value = '';
  preview.value = null;
  previewLoading.value = false;
  previewError.value = false;
};
const closePreview = () => {
  resetPreview();
  previewDialog.value?.close();
};
const denied = () => {
  generation += 1;
  blocked.value = true;
  items.value = [];
  meta.value = { total: 0, pages: 0 };
  lastSaved.value = null;
  closePreview();
};
const load = async () => {
  generation += 1;
  const current = generation;
  items.value = [];
  meta.value = { total: 0, pages: 0 };
  unitTimezone.value = '';
  error.value = false;
  closePreview();
  if (!canManage.value) {
    loading.value = false;
    return;
  }
  loading.value = true;
  try {
    const response = await API.unitCalendars(props.accountId, unitId.value, {
      q: route.query.calendar_q || '',
      status: route.query.calendar_status || 'all',
      page: page.value,
      per_page: 20,
    });
    if (current !== generation) return;
    const data = response.data;
    if (
      data.account_id !== String(props.accountId) ||
      data.unit_id !== unitId.value ||
      !Array.isArray(data.items) ||
      data.local_only !== true ||
      data.pabx_confirmed !== false ||
      typeof data.unit_timezone !== 'string'
    )
      throw new Error('Invalid native calendar list scope');
    if (
      !data.items.every(
        row =>
          row &&
          typeof row.id === 'string' &&
          [true, false].includes(row.active) &&
          validCalendarDefinition(row.definition)
      ) ||
      !data.meta ||
      data.meta.page !== page.value ||
      data.meta.per_page !== 20 ||
      !Number.isInteger(data.meta.total) ||
      data.meta.total < 0 ||
      !Number.isInteger(data.meta.pages) ||
      data.meta.pages < 0
    )
      throw new Error('Invalid native calendar list contract');
    items.value = data.items;
    meta.value = data.meta;
    unitTimezone.value = data.unit_timezone;
  } catch (problem) {
    if (current === generation) {
      if ([401, 403, 404].includes(problem?.response?.status)) denied();
      else error.value = true;
    }
  } finally {
    if (current === generation || blocked.value) loading.value = false;
  }
};
const saved = value => {
  lastSaved.value = value;
  load();
};
const openPreview = row => {
  closePreview();
  previewId.value = row.id;
  previewDialog.value?.open();
};
const calculate = async () => {
  if (!previewDate.value || previewLoading.value || !canManage.value) return;
  detailGeneration += 1;
  const current = detailGeneration;
  previewLoading.value = true;
  previewError.value = false;
  preview.value = null;
  try {
    const response = await API.previewUnitCalendar(
      props.accountId,
      unitId.value,
      previewId.value,
      previewDate.value
    );
    if (current !== detailGeneration) return;
    const result = response.data.preview;
    if (
      response.data.account_id !== String(props.accountId) ||
      result.unit_id !== unitId.value ||
      result.calendar_id !== previewId.value ||
      result.date !== previewDate.value ||
      result.local_only !== true ||
      result.pabx_confirmed !== false
    )
      throw new Error('Invalid native calendar preview scope');
    if (
      typeof result.name !== 'string' ||
      !result.name.trim() ||
      typeof result.timezone !== 'string' ||
      ![true, false].includes(result.active) ||
      !Object.hasOwn(precedenceLabels.value, result.precedence) ||
      !Number.isSafeInteger(result.working_seconds) ||
      result.working_seconds < 0 ||
      calendarIntervalsError(result.intervals)
    )
      throw new Error('Invalid native calendar preview calculation');
    preview.value = result;
  } catch (problem) {
    if (current === detailGeneration) {
      if ([401, 403, 404].includes(problem?.response?.status)) denied();
      else previewError.value = true;
    }
  } finally {
    if (current === detailGeneration) previewLoading.value = false;
  }
};
watch(
  [() => props.accountId, unitId, actorScope],
  () => {
    generation += 1;
    blocked.value = false;
    lastSaved.value = null;
    items.value = [];
    meta.value = { total: 0, pages: 0 };
    unitTimezone.value = '';
    loading.value = false;
    closePreview();
  },
  { immediate: true, flush: 'sync' }
);
watch(
  [
    () => props.accountId,
    unitId,
    actorScope,
    page,
    () => route.query.calendar_q,
    () => route.query.calendar_status,
  ],
  () => {
    query.value = route.query.calendar_q || '';
    status.value = route.query.calendar_status || 'all';
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  detailGeneration += 1;
});
</script>

<template>
  <section class="min-w-0 space-y-4" data-unit-calendar-library>
    <h3 class="text-lg font-semibold text-n-slate-12">
      {{ t('JRC_CONTACT_CENTER.CALENDAR.TITLE') }}
    </h3>
    <p
      role="status"
      class="break-words rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
    >
      {{ t('JRC_CONTACT_CENTER.CALENDAR.LOCAL_ONLY') }}
    </p>
    <form
      class="grid min-w-0 gap-3 rounded-lg border border-n-weak bg-n-solid-1 p-3 sm:grid-cols-2"
      @submit.prevent="
        navigate({
          calendar_q: query || undefined,
          calendar_status: status,
          calendar_page: 1,
        })
      "
    >
      <label class="grid min-w-0 gap-1 text-sm">
        <span>{{ t('JRC_CONTACT_CENTER.CALENDAR.UNIT') }}</span>
        <select
          :value="unitId"
          data-calendar-unit
          class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          @change="
            navigate({
              calendar_unit: $event.target.value,
              calendar_q: undefined,
              calendar_status: undefined,
              calendar_page: 1,
            })
          "
        >
          <option v-for="unit in units" :key="unit.id" :value="String(unit.id)">
            {{ unit.name }}
          </option>
        </select>
      </label>
      <label class="grid min-w-0 gap-1 text-sm">
        <span>{{ t('JRC_CONTACT_CENTER.CALENDAR.SEARCH') }}</span>
        <input
          v-model="query"
          maxlength="100"
          data-calendar-search
          class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        />
      </label>
      <label class="grid min-w-0 gap-1 text-sm">
        <span>{{ t('JRC_CONTACT_CENTER.CALENDAR.STATUS') }}</span>
        <select
          v-model="status"
          data-calendar-status
          class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="all">
            {{ t('JRC_CONTACT_CENTER.CALENDAR.ALL') }}
          </option>
          <option value="active">
            {{ t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL') }}
          </option>
          <option value="inactive">
            {{ t('JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL') }}
          </option>
        </select>
      </label>
      <div class="flex flex-wrap items-end gap-2">
        <Button
          type="submit"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.FILTER')"
          :disabled="loading || !canManage"
        />
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.CLEAR')"
          :disabled="loading"
          @click="
            navigate({
              calendar_q: undefined,
              calendar_status: undefined,
              calendar_page: 1,
            })
          "
        />
      </div>
    </form>
    <p v-if="!unitAllowed" role="status" class="break-words text-sm">
      {{ t('JRC_CONTACT_CENTER.CALENDAR.NO_UNIT') }}
    </p>
    <p
      v-if="error || blocked"
      role="alert"
      class="break-words text-sm text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.CALENDAR.LOAD_ERROR') }}
    </p>
    <CalendarEditorDialog
      ref="editor"
      :account-id="accountId"
      :unit-id="unitId"
      :timezone="unitTimezone"
      :context-key="actorScope"
      :can-manage="canManage && !loading"
      @saved="saved"
      @denied="denied"
    />
    <p v-if="loading" role="status" class="text-sm">
      {{ t('JRC_CONTACT_CENTER.CALENDAR.LOADING') }}
    </p>
    <p
      v-else-if="canManage && !items.length && !error"
      role="status"
      class="text-sm"
    >
      {{ t('JRC_CONTACT_CENTER.CALENDAR.EMPTY') }}
    </p>
    <p
      v-if="lastSaved"
      role="status"
      data-calendar-saved
      class="break-words rounded-lg bg-n-teal-2 p-3 text-sm text-n-teal-11"
    >
      {{
        t('JRC_CONTACT_CENTER.CALENDAR.SAVED', {
          name: lastSaved.definition.name,
        })
      }}
      <button
        type="button"
        class="ml-2 underline"
        :disabled="loading"
        @click="editor.open(lastSaved.id)"
      >
        {{ t('JRC_CONTACT_CENTER.CALENDAR.OPEN') }}
      </button>
    </p>
    <article
      v-for="row in items"
      :key="row.id"
      :data-unit-calendar="row.id"
      class="min-w-0 space-y-2 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12"
    >
      <h4 class="break-words font-semibold">{{ row.definition.name }}</h4>
      <p class="break-words">{{ row.definition.timezone }}</p>
      <p>
        {{
          row.active
            ? t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL')
            : t('JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL')
        }}
      </p>
      <div class="flex flex-wrap gap-2">
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.EDIT')"
          :disabled="loading || !canManage"
          :data-edit-unit-calendar="row.id"
          @click="editor.open(row.id)"
        />
        <Button
          type="button"
          variant="faded"
          :label="t('JRC_CONTACT_CENTER.CALENDAR.PREVIEW')"
          :disabled="loading || !canManage"
          :data-preview-unit-calendar="row.id"
          @click="openPreview(row)"
        />
        <QueueCalendarBindings
          :account-id="accountId"
          :unit-id="unitId"
          :calendar-id="row.id"
          :context-key="actorScope"
          :can-manage="canManage && !loading"
          @denied="denied"
        />
        <CalendarIvrUsages
          :account-id="accountId"
          :unit-id="unitId"
          :calendar-id="row.id"
          :context-key="actorScope"
          :can-manage="canManage && !loading"
          @denied="denied"
        />
      </div>
    </article>
    <nav
      v-if="meta.pages > 1"
      :aria-label="t('JRC_CONTACT_CENTER.CALENDAR.PAGINATION')"
      class="flex flex-wrap items-center gap-2 text-sm"
    >
      <Button
        type="button"
        variant="faded"
        :label="t('JRC_CONTACT_CENTER.CALENDAR.PREVIOUS')"
        :disabled="loading || page <= 1"
        data-calendar-previous
        @click="navigate({ calendar_page: page - 1 })"
      />
      <span>{{
        t('JRC_CONTACT_CENTER.CALENDAR.TOTAL', { total: meta.total, page })
      }}</span>
      <Button
        type="button"
        variant="faded"
        :label="t('JRC_CONTACT_CENTER.CALENDAR.NEXT')"
        :disabled="loading || page >= meta.pages"
        data-calendar-next
        @click="navigate({ calendar_page: page + 1 })"
      />
    </nav>
    <Dialog
      ref="previewDialog"
      contained
      use-form
      :title="t('JRC_CONTACT_CENTER.CALENDAR.PREVIEW')"
      :confirm-button-label="t('JRC_CONTACT_CENTER.CALENDAR.CALCULATE')"
      :cancel-button-label="t('JRC_CONTACT_CENTER.CALENDAR.CLOSE')"
      :disable-confirm-button="!previewDate || previewLoading"
      :is-loading="previewLoading"
      @confirm="calculate"
      @close="resetPreview"
    >
      <div
        class="min-w-0 space-y-3 text-sm text-n-slate-12"
        data-unit-calendar-preview
      >
        <p class="break-words">
          {{ t('JRC_CONTACT_CENTER.CALENDAR.PREVIEW_HELP') }}
        </p>
        <label class="grid gap-1">
          <span>{{ t('JRC_CONTACT_CENTER.CALENDAR.PREVIEW_DATE') }}</span>
          <input
            v-model="previewDate"
            type="date"
            required
            data-calendar-preview-date
            :disabled="previewLoading"
            class="w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            @input="preview = null"
          />
        </label>
        <p v-if="previewError" role="alert" class="text-n-ruby-11">
          {{ t('JRC_CONTACT_CENTER.CALENDAR.LOAD_ERROR') }}
        </p>
        <section
          v-if="preview"
          class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
          data-calendar-preview-result
        >
          <h4 class="break-words font-semibold">{{ preview.name }}</h4>
          <p>{{ preview.date }}</p>
          <p class="break-words">{{ preview.timezone }}</p>
          <p data-calendar-preview-precedence>
            {{ precedenceLabels[preview.precedence] }}
          </p>
          <p>
            {{
              formatCalendarIntervals(preview.intervals) ||
              t('JRC_CONTACT_CENTER.CALENDAR.CLOSED_DAY')
            }}
          </p>
          <p>
            {{
              t('JRC_CONTACT_CENTER.CALENDAR.WORKING_SECONDS', {
                seconds: preview.working_seconds,
              })
            }}
          </p>
          <p>
            {{
              preview.active
                ? t('JRC_CONTACT_CENTER.CALENDAR.ACTIVE_INTERNAL')
                : t('JRC_CONTACT_CENTER.CALENDAR.INACTIVE_INTERNAL')
            }}
          </p>
          <p class="break-words">
            {{ t('JRC_CONTACT_CENTER.CALENDAR.LOCAL_ONLY') }}
          </p>
        </section>
      </div>
    </Dialog>
  </section>
</template>
