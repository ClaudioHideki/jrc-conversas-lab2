<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAudioInspections } from '../composables/useAudioInspections';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  assetId: { type: String, required: true },
  version: { type: Object, required: true },
  canManage: { type: Boolean, required: true },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.TITLE'),
  LIMITS: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.LIMITS'),
  INSPECT: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.INSPECT'),
  SCANNING: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.SCANNING'),
  LOADING: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.LOADING'),
  EMPTY: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.EMPTY'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.ERROR'),
  UNCERTAIN: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.UNCERTAIN'),
  VERIFIED: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.VERIFIED'),
  STATE_INFECTED: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.STATE_INFECTED'),
  STATE_UNAVAILABLE: t(
    'JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.STATE_UNAVAILABLE'
  ),
  STATE_CHECKSUM_MISMATCH: t(
    'JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.STATE_CHECKSUM_MISMATCH'
  ),
  PROBE_INVALID: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.PROBE_INVALID'),
  PROBE_UNAVAILABLE: t(
    'JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.PROBE_UNAVAILABLE'
  ),
  PROBE_NOT_RUN: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.PROBE_NOT_RUN'),
  ATTEMPT: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.ATTEMPT'),
  HASH: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.HASH'),
  NO_HASH: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.NO_HASH'),
  DURATION: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.DURATION'),
  FORMAT: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.FORMAT'),
  SAMPLE_RATE: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.SAMPLE_RATE'),
  CHANNELS: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.CHANNELS'),
  TOOLS: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.TOOLS'),
  PAGINATION: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.PAGINATION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.NEXT'),
  PAGE: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.PAGE'),
  TOTAL: t('JRC_CONTACT_CENTER.AUDIO_INSPECTIONS.TOTAL'),
}));
const label = key => labels.value[key];
const joined = values => values.join(' · ');
const attemptDescription = row =>
  joined([
    `${label('ATTEMPT')} ${row.attempt}`,
    row.created_by_name,
    row.observed_at,
  ]);
const { opened, items, meta, page, loading, saving, error, open, inspect } =
  useAudioInspections({
    accountId: computed(() => props.accountId),
    assetId: computed(() => props.assetId),
    version: computed(() => props.version),
    canManage: computed(() => props.canManage),
    onDenied: () => emit('denied'),
  });
const pageDescription = () =>
  joined([
    `${label('PAGE')} ${page.value}`,
    `${label('TOTAL')} ${meta.value.total}`,
  ]);
const stateLabel = row => {
  if (row.ready) return label('VERIFIED');
  if (row.state === 'clean')
    return label(`PROBE_${row.probe_state.toUpperCase()}`);
  return label(`STATE_${row.state.toUpperCase()}`);
};
</script>

<template>
  <section
    class="min-w-0 space-y-3 border-t border-n-weak pt-3"
    data-audio-inspection-history
  >
    <button
      type="button"
      :disabled="!canManage || loading || saving"
      :aria-expanded="opened"
      data-toggle-audio-inspections
      class="rounded-lg border border-n-blue-6 px-3 py-2 text-n-blue-11"
      @click="open"
    >
      {{ label('TITLE') }}
    </button>
    <div v-if="opened" class="min-w-0 space-y-3">
      <p class="break-words text-n-slate-11">{{ label('LIMITS') }}</p>
      <p v-if="error" role="alert" class="break-words text-n-ruby-11">
        {{ label(error) }}
      </p>
      <p v-if="loading || saving" role="status">
        {{ label(saving ? 'SCANNING' : 'LOADING') }}
      </p>
      <button
        type="button"
        :disabled="!canManage || loading || saving"
        data-inspect-audio-version
        class="rounded-lg bg-n-blue-9 px-3 py-2 text-white"
        @click="inspect"
      >
        {{ label('INSPECT') }}
      </button>
      <p v-if="!loading && !items.length">{{ label('EMPTY') }}</p>
      <article
        v-for="row in items"
        :key="row.id"
        :data-audio-inspection="row.id"
        class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
      >
        <p
          class="break-words font-semibold text-n-slate-12"
          :data-audio-inspection-state="row.ready ? 'verified' : row.state"
        >
          {{ stateLabel(row) }}
        </p>
        <p class="break-words">
          {{ attemptDescription(row) }}
        </p>
        <p class="break-all">
          {{ label('HASH') }} {{ row.observed_sha256 || label('NO_HASH') }}
        </p>
        <dl
          v-if="row.ready"
          class="grid min-w-0 grid-cols-1 gap-2 sm:grid-cols-2"
          data-audio-decoded-metadata
        >
          <div>
            <dt class="text-n-slate-11">{{ label('DURATION') }}</dt>
            <dd>{{ row.metadata.duration_ms }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-11">{{ label('FORMAT') }}</dt>
            <dd class="break-words">
              {{ joined([row.metadata.content_type, row.metadata.codec]) }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">{{ label('SAMPLE_RATE') }}</dt>
            <dd>{{ row.metadata.sample_rate }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-11">{{ label('CHANNELS') }}</dt>
            <dd>{{ row.metadata.channels }}</dd>
          </div>
          <div class="min-w-0 sm:col-span-2">
            <dt class="text-n-slate-11">{{ label('TOOLS') }}</dt>
            <dd class="break-all">
              {{
                joined([
                  row.scanner_adapter,
                  row.metadata.probe_version,
                  row.decoder_version,
                ])
              }}
            </dd>
          </div>
        </dl>
      </article>
      <nav
        v-if="meta.pages > 1"
        :aria-label="label('PAGINATION')"
        class="flex flex-wrap gap-3"
      >
        <button
          type="button"
          :disabled="loading || saving || page <= 1"
          @click="page -= 1"
        >
          {{ label('PREVIOUS') }}
        </button>
        <span>{{ pageDescription() }}</span>
        <button
          type="button"
          :disabled="loading || saving || page >= meta.pages"
          @click="page += 1"
        >
          {{ label('NEXT') }}
        </button>
      </nav>
    </div>
  </section>
</template>
