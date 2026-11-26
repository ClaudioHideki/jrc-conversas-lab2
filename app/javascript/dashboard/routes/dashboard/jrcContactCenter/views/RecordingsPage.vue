<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import RecordingDetailsDialog from '../components/RecordingDetailsDialog.vue';
import AcwRuleTarget from '../components/AcwRuleTarget.vue';
import { useScopedRecordings } from '../composables/useScopedRecordings';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const accountId = computed(() => route.params.accountId);
const user = useMapGetter('getCurrentUser');
const actorScope = computed(() => {
  const member = user.value?.accounts?.find(
    row => String(row.id) === String(accountId.value)
  );
  return JSON.stringify([
    user.value?.id,
    member?.role,
    member?.custom_role_id,
    member?.contact_center_eligible,
    [...(member?.permissions || [])].sort(),
  ]);
});
const state = useScopedRecordings({
  accountId,
  actorScope,
  routeQuery: computed(() => route.query),
  replaceQuery: query => router.replace({ query }),
});
const {
  items,
  meta,
  period,
  filters,
  page,
  capabilities,
  loading,
  mediaLoading,
  error,
  mediaError,
  selected,
  url,
} = state;
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.RECORDINGS.TITLE'),
  INTRO: t('JRC_CONTACT_CENTER.RECORDINGS.INTRO'),
  SCOPE: t('JRC_CONTACT_CENTER.RECORDINGS.SCOPE'),
  FROM: t('JRC_CONTACT_CENTER.RECORDINGS.FROM'),
  TO: t('JRC_CONTACT_CENTER.RECORDINGS.TO'),
  SEARCH: t('JRC_CONTACT_CENTER.RECORDINGS.SEARCH'),
  UNIT: t('JRC_CONTACT_CENTER.RECORDINGS.UNIT'),
  QUEUE: t('JRC_CONTACT_CENTER.RECORDINGS.QUEUE'),
  APPLY: t('JRC_CONTACT_CENTER.RECORDINGS.APPLY'),
  CLEAR: t('JRC_CONTACT_CENTER.RECORDINGS.CLEAR'),
  REFRESH: t('JRC_CONTACT_CENTER.RECORDINGS.REFRESH'),
  CALL: t('JRC_CONTACT_CENTER.RECORDINGS.CALL'),
  NUMBER: t('JRC_CONTACT_CENTER.RECORDINGS.NUMBER'),
  STARTED: t('JRC_CONTACT_CENTER.RECORDINGS.STARTED'),
  DURATION: t('JRC_CONTACT_CENTER.RECORDINGS.DURATION'),
  DETAILS: t('JRC_CONTACT_CENTER.RECORDINGS.DETAILS'),
  LISTEN: t('JRC_CONTACT_CENTER.RECORDINGS.LISTEN'),
  DOWNLOAD: t('JRC_CONTACT_CENTER.RECORDINGS.DOWNLOAD'),
  CLOSE: t('JRC_CONTACT_CENTER.RECORDINGS.CLOSE'),
  EMPTY: t('JRC_CONTACT_CENTER.RECORDINGS.EMPTY'),
  LOADING: t('JRC_CONTACT_CENTER.RECORDINGS.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.ERROR'),
  INVALID_RANGE: t('JRC_CONTACT_CENTER.RECORDINGS.INVALID_RANGE'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDINGS.DENIED'),
  MEDIA_ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.MEDIA_ERROR'),
  MEDIA_AUDIT_ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.MEDIA_AUDIT_ERROR'),
  PENDING: t('JRC_CONTACT_CENTER.RECORDINGS.PENDING'),
  AVAILABLE: t('JRC_CONTACT_CENTER.RECORDINGS.AVAILABLE'),
  PREVIOUS: t('JRC_CONTACT_CENTER.RECORDINGS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.RECORDINGS.NEXT'),
  NO_MEASUREMENT: t('JRC_CONTACT_CENTER.RECORDINGS.NO_MEASUREMENT'),
}));
const copy = key => labels.value[key];
const duration = value =>
  Number.isFinite(value) && value >= 0
    ? `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`
    : copy('NO_MEASUREMENT');
</script>

<template>
  <section
    :key="`${accountId}-${actorScope}`"
    class="min-w-0 space-y-4 p-4 text-n-slate-12 sm:p-6"
    data-scoped-recordings
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h1 class="flex items-center gap-2 text-xl font-semibold">
          <Icon icon="i-lucide-mic" class="size-6 text-n-violet-11" />{{
            copy('TITLE')
          }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">{{ copy('INTRO') }}</p>
      </div>
      <button
        type="button"
        :disabled="loading"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
        @click="state.load"
      >
        {{ copy('REFRESH') }}
      </button>
    </header>
    <p
      class="rounded-lg border border-n-blue-6 bg-n-blue-2 p-3 text-sm text-n-blue-11"
    >
      {{ copy('SCOPE') }}
    </p>
    <form
      class="grid min-w-0 grid-cols-1 gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-2 xl:grid-cols-3"
      @submit.prevent="state.apply"
    >
      <label class="min-w-0 text-sm">
        {{ copy('FROM') }}
        <input
          v-model="filters.from"
          type="date"
          data-recordings-from
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <label class="min-w-0 text-sm">
        {{ copy('TO') }}
        <input
          v-model="filters.to"
          type="date"
          data-recordings-to
          class="mt-1 block w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <label class="min-w-0 text-sm">
        {{ copy('SEARCH') }}
        <input
          v-model="filters.q"
          type="search"
          maxlength="100"
          data-recordings-search
          class="mt-1 block w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
        />
      </label>
      <div class="min-w-0 text-sm">
        {{ copy('UNIT') }}
        <AcwRuleTarget
          v-model="filters.unit_id"
          :account-id="accountId"
          scope="unit"
          :required="false"
        />
      </div>
      <div class="min-w-0 text-sm">
        {{ copy('QUEUE') }}
        <AcwRuleTarget
          v-model="filters.queue_id"
          :account-id="accountId"
          scope="queue"
          :required="false"
        />
      </div>
      <div class="flex flex-wrap items-end gap-2">
        <button
          type="submit"
          :disabled="loading"
          class="rounded-lg bg-n-brand px-4 py-2 text-white"
        >
          {{ copy('APPLY') }}
        </button>
        <button
          type="button"
          :disabled="loading"
          class="rounded-lg border border-n-weak px-4 py-2"
          @click="state.clearFilters"
        >
          {{ copy('CLEAR') }}
        </button>
      </div>
    </form>
    <p v-if="loading" role="status">{{ copy('LOADING') }}</p>
    <p v-else-if="error" role="alert" class="text-n-ruby-11">
      {{ copy(error) }}
    </p>
    <template v-else>
      <p
        v-if="period"
        class="break-words text-sm text-n-slate-11"
        data-recordings-period
      >
        {{
          t('JRC_CONTACT_CENTER.RECORDINGS.PERIOD', {
            from: period.from,
            to: period.to,
            timezone: period.timezone,
            count: meta.total,
          })
        }}
      </p>
      <p v-if="!items.length" class="rounded-lg border border-n-weak p-4">
        {{ copy('EMPTY') }}
      </p>
      <table
        v-else
        class="block w-full border-separate border-spacing-y-2 text-left md:table md:table-fixed md:border-spacing-y-0"
        data-recordings-table
      >
        <caption class="sr-only">
          {{
            copy('TITLE')
          }}
        </caption>
        <thead class="hidden text-xs text-n-slate-11 md:table-header-group">
          <tr>
            <th
              v-for="key in [
                'CALL',
                'NUMBER',
                'STARTED',
                'DURATION',
                'UNIT',
                'QUEUE',
                'DETAILS',
              ]"
              :key="key"
              scope="col"
              class="p-3"
            >
              {{ copy(key) }}
            </th>
          </tr>
        </thead>
        <tbody class="block space-y-3 md:table-row-group md:space-y-0">
          <tr
            v-for="row in items"
            :key="row.id"
            class="block min-w-0 rounded-xl border border-n-weak bg-n-solid-1 p-3 md:table-row md:rounded-none md:p-0"
            :data-recording-row="row.id"
          >
            <td
              v-for="[key, value] in [
                ['CALL', row.unique_id],
                ['NUMBER', row.external_number],
                ['STARTED', row.started_at],
                ['DURATION', duration(row.talk_duration_seconds)],
                ['UNIT', row.unit_name],
                ['QUEUE', row.queue_name],
              ]"
              :key="key"
              class="grid min-w-0 grid-cols-[6rem_minmax(0,1fr)] gap-2 py-2 text-sm md:table-cell md:p-3"
            >
              <span class="text-n-slate-11 md:hidden">{{ copy(key) }}</span>
              <span class="break-all">{{
                value || copy('NO_MEASUREMENT')
              }}</span>
            </td>
            <td class="py-2 md:p-3">
              <button
                type="button"
                :disabled="mediaLoading"
                class="rounded-lg border border-n-violet-6 px-3 py-2 text-n-violet-11"
                :data-recording-details="row.id"
                @click="state.select(row)"
              >
                {{ copy('DETAILS') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
      <nav
        v-if="meta.pages > 1 || page > 1"
        class="flex flex-wrap items-center justify-between gap-3"
        :aria-label="copy('TITLE')"
      >
        <button
          type="button"
          :disabled="page <= 1 || loading"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="state.changePage(page - 1)"
        >
          {{ copy('PREVIOUS') }}
        </button>
        <span>
          {{
            t('JRC_CONTACT_CENTER.RECORDINGS.PAGE', { page, pages: meta.pages })
          }}
        </span>
        <button
          type="button"
          :disabled="page >= meta.pages || loading"
          class="rounded-lg border border-n-weak px-3 py-2"
          @click="state.changePage(page + 1)"
        >
          {{ copy('NEXT') }}
        </button>
      </nav>
    </template>
    <p
      v-if="mediaError && !selected"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ copy(mediaError) }}
    </p>
    <RecordingDetailsDialog
      v-if="selected"
      :key="`${accountId}-${actorScope}-${selected.id}`"
      :item="selected"
      :formatted-duration="duration(selected.talk_duration_seconds)"
      :capabilities="capabilities"
      :url="url"
      :loading="mediaLoading"
      :error="mediaError"
      :authorize-playback="state.authorizePlayback"
      @close="state.close"
      @playback="state.bytes('playback')"
      @download="state.bytes('download')"
      @playback-error="state.playbackFailed"
    />
  </section>
</template>
