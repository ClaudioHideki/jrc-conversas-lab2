<script setup>
import { onMounted, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { buttonClass, date as formatDate, message } from './definitions';
const props = defineProps({
  document: { type: Object, required: true },
  formatting: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['close', 'denied', 'versions']);
const route = useRoute();
const { t } = useI18n();
const dialog = ref(null);
const kind = ref('');
const page = ref(1);
const rows = ref([]);
const meta = ref(null);
const busy = ref(false);
const error = ref('');
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const epoch = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  meta.value = null;
  error.value = '';
  busy.value = true;
  try {
    const { data } = await API.documentHistory(
      route.params.accountId,
      props.document.id,
      { kind: kind.value || undefined, page: page.value, per_page: 20 },
      { signal: controller.signal }
    );
    if (epoch !== generation) return;
    rows.value = data.payload;
    meta.value = data.meta;
  } catch (err) {
    if (epoch !== generation || err.code === 'ERR_CANCELED') return;
    error.value = message(err) || t('RELATIONSHIP.V2.DOCS.HISTORY_FAILED');
    if ([403, 404].includes(err.response?.status)) emit('denied', err);
  } finally {
    if (epoch === generation) busy.value = false;
  }
};
const choose = value => {
  kind.value = value;
  page.value = 1;
};
const name = user =>
  user?.state === 'unassigned'
    ? t('RELATIONSHIP.V2.DOCS.NO_DOCUMENT_RESPONSIBLE')
    : user?.name || t('RELATIONSHIP.V2.DOCS.UNAVAILABLE');
const date = value => formatDate(value, props.formatting);
watch([kind, page], load);
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="2xl"
    :title="t('RELATIONSHIP.V2.DOCS.HISTORY')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    @close="emit('close')"
  >
    <section class="min-w-0 space-y-4">
      <p class="break-words font-semibold">{{ document.title }}</p>
      <nav
        class="flex flex-wrap gap-2"
        :aria-label="t('RELATIONSHIP.V2.DOCS.HISTORY_FILTER')"
      >
        <button
          v-for="option in ['', 'metadata', 'version']"
          :key="option"
          type="button"
          :class="
            kind === option
              ? 'rounded-lg border border-n-violet-9 bg-n-violet-9 px-3 py-2 text-sm font-semibold text-white'
              : buttonClass
          "
          :aria-pressed="kind === option"
          @click="choose(option)"
        >
          {{ t(`RELATIONSHIP.V2.DOCS.HISTORY_FILTERS.${option || 'all'}`) }}
        </button>
      </nav>
      <p
        v-if="error"
        role="alert"
        class="text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p
        v-if="busy"
        role="status"
      >
        {{ t('RELATIONSHIP.LOADING') }}
      </p>
      <p v-else-if="!error && !rows.length">
        {{ t('RELATIONSHIP.V2.DOCS.HISTORY_EMPTY') }}
      </p>
      <article
        v-for="event in rows"
        :key="event.id"
        class="min-w-0 space-y-3 rounded-xl border border-n-violet-6 bg-n-solid-2 p-4 text-sm"
      >
        <h4 class="font-semibold">
          {{ t(`RELATIONSHIP.V2.DOCS.HISTORY_ACTIONS.${event.action}`) }}
        </h4>
        <p>{{ date(event.at) }} · {{ name(event.actor) }}</p>
        <p
          v-if="event.reason"
          class="whitespace-pre-wrap break-words"
        >
          {{ event.reason }}
        </p>
        <div
          v-if="event.action === 'document_metadata_updated'"
          class="grid min-w-0 gap-3 sm:grid-cols-2"
        >
          <section
            v-for="side in ['before', 'after']"
            :key="side"
            class="min-w-0 rounded-lg border border-n-weak p-3"
          >
            <h5 class="font-semibold">
              {{ t(`RELATIONSHIP.V2.DOCS.HISTORY_SIDES.${side}`) }}
            </h5>
            <dl class="space-y-1 break-words">
              <dt>{{ t('RELATIONSHIP.V2.DOCS.RESPONSIBLE') }}</dt>
              <dd>{{ name(event[side].responsible) }}</dd>
              <dt>{{ t('RELATIONSHIP.V2.DOCS.STATUS') }}</dt>
              <dd>
                {{
                  event[side].status
                    ? t(`RELATIONSHIP.V2.DOCS.STATUSES.${event[side].status}`)
                    : t('RELATIONSHIP.V2.DOCS.UNAVAILABLE')
                }}
              </dd>
              <dt>{{ t('RELATIONSHIP.V2.DOCS.REQUIREMENT_LINK') }}</dt>
              <dd>
                {{
                  event[side].requirement_key ||
                  t('RELATIONSHIP.V2.DOCS.NO_REQUIREMENT_LINK')
                }}
              </dd>
            </dl>
          </section>
        </div>
        <p v-if="event.version">
          {{ t('RELATIONSHIP.VERSION', { version: event.version.number }) }} ·
          {{ t('RELATIONSHIP.V2.DOCS.VALID_UNTIL') }}:
          {{ date(event.version.valid_until) }}
        </p>
      </article>
      <nav
        v-if="meta"
        class="flex flex-wrap items-center justify-between gap-2"
        :aria-label="t('RELATIONSHIP.V2.PAGINATION')"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page <= 1"
          @click="page -= 1"
        >
          {{ t('RELATIONSHIP.V2.PREVIOUS') }}
        </button>
        <span>{{
          t('RELATIONSHIP.V2.PAGE', { page, total: meta.total })
        }}</span>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || page * meta.per_page >= meta.total"
          @click="page += 1"
        >
          {{ t('RELATIONSHIP.V2.NEXT') }}
        </button>
      </nav>
      <footer class="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="load"
        >
          {{ t('RELATIONSHIP.REFRESH') }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="emit('versions', document)"
        >
          {{ t('RELATIONSHIP.V2.DOCS.VERSIONS') }}
        </button>
        <button
          type="button"
          :class="buttonClass"
          @click="dialog.close()"
        >
          {{ t('RELATIONSHIP.CLOSE') }}
        </button>
      </footer>
    </section>
  </Dialog>
</template>
