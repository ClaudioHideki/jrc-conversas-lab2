<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  assetId: { type: String, required: true },
  unitId: { type: String, required: true },
  canManage: { type: Boolean, required: true },
});
const emit = defineEmits(['denied']);
const { t } = useI18n();
const labels = computed(() => ({
  OPEN: t('JRC_CONTACT_CENTER.AUDIO_USAGES.OPEN'),
  TITLE: t('JRC_CONTACT_CENTER.AUDIO_USAGES.TITLE'),
  CLOSE: t('JRC_CONTACT_CENTER.AUDIO_USAGES.CLOSE'),
  LIMITS: t('JRC_CONTACT_CENTER.AUDIO_USAGES.LIMITS'),
  LOADING: t('JRC_CONTACT_CENTER.AUDIO_USAGES.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_USAGES.ERROR'),
  RETRY: t('JRC_CONTACT_CENTER.AUDIO_USAGES.RETRY'),
  EMPTY: t('JRC_CONTACT_CENTER.AUDIO_USAGES.EMPTY'),
  DRAFT: t('JRC_CONTACT_CENTER.AUDIO_USAGES.DRAFT'),
  REVISION: t('JRC_CONTACT_CENTER.AUDIO_USAGES.REVISION'),
  ARCHIVED: t('JRC_CONTACT_CENTER.AUDIO_USAGES.ARCHIVED'),
  LOCAL: t('JRC_CONTACT_CENTER.AUDIO_USAGES.LOCAL'),
  MENU: t('JRC_CONTACT_CENTER.AUDIO_USAGES.MENU'),
  VERSION_ID: t('JRC_CONTACT_CENTER.AUDIO_USAGES.VERSION_ID'),
  PAGINATION: t('JRC_CONTACT_CENTER.AUDIO_USAGES.PAGINATION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.AUDIO_USAGES.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.AUDIO_USAGES.NEXT'),
  TOTAL: t('JRC_CONTACT_CENTER.AUDIO_USAGES.TOTAL'),
  PAGE: t('JRC_CONTACT_CENTER.AUDIO_USAGES.PAGE'),
  CHECKSUM: t('JRC_CONTACT_CENTER.AUDIO_USAGES.CHECKSUM'),
}));
const label = key => labels.value[key];
const draftDescription = item =>
  [
    `${label('DRAFT')} ${item.draft_id}`,
    `${label('REVISION')} ${item.draft_revision}`,
  ].join(' · ');
const referenceDescription = item =>
  [
    `${label('MENU')} ${item.node_id}`,
    `${label('VERSION_ID')} ${item.audio_version_id}`,
  ].join(' · ');
const dialog = ref(null);
const opened = ref(false);
const items = ref([]);
const meta = ref({ page: 1, pages: 0, total: 0 });
const page = ref(1);
const pageDescription = () =>
  [
    `${label('TOTAL')} ${meta.value.total}`,
    `${label('PAGE')} ${page.value}`,
  ].join(' · ');
const checksumDescription = value => [label('CHECKSUM'), value].join(': ');
const loading = ref(false);
const error = ref(false);
let generation = 0;
const clear = () => {
  generation += 1;
  items.value = [];
  meta.value = { page: 1, pages: 0, total: 0 };
  page.value = 1;
  opened.value = false;
  loading.value = false;
  error.value = false;
};
const load = async target => {
  if (!opened.value || !props.canManage || loading.value) return;
  generation += 1;
  const current = generation;
  items.value = [];
  error.value = false;
  loading.value = true;
  try {
    const { data } = await API.audioUsages(props.accountId, props.assetId, {
      page: target,
      per_page: 10,
    });
    if (current !== generation || !props.canManage) return;
    if (
      String(data.account_id) !== String(props.accountId) ||
      data.audio_asset_id !== props.assetId ||
      data.unit_id !== props.unitId ||
      data.coverage !== 'current_local_ivr_drafts_only' ||
      data.provider_configuration_verified !== false
    )
      throw new Error('Invalid authorized local audio reference context');
    items.value = data.items;
    meta.value = data.meta;
    page.value = data.meta.page;
  } catch (failure) {
    if (current !== generation) return;
    if ([401, 403, 404].includes(failure?.response?.status)) {
      dialog.value?.close();
      clear();
      emit('denied');
    } else error.value = true;
  } finally {
    if (current === generation) loading.value = false;
  }
};
const open = () => {
  if (!props.canManage) return;
  clear();
  opened.value = true;
  dialog.value.open();
  load(1);
};
watch(
  [
    () => props.accountId,
    () => props.assetId,
    () => props.unitId,
    () => props.canManage,
  ],
  () => {
    dialog.value?.close();
    clear();
  }
);
onBeforeUnmount(clear);
</script>

<template>
  <button
    type="button"
    :disabled="!canManage"
    class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
    data-audio-usages-open
    @click="open"
  >
    {{ label('OPEN') }}
  </button>
  <Dialog
    ref="dialog"
    contained
    :title="label('TITLE')"
    :show-confirm-button="false"
    :cancel-button-label="label('CLOSE')"
    @close="clear"
  >
    <div class="min-w-0 space-y-3 text-sm text-n-slate-12" data-audio-usages>
      <p
        class="break-words rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-n-amber-11"
      >
        {{ label('LIMITS') }}
      </p>
      <p v-if="loading" role="status">{{ label('LOADING') }}</p>
      <div v-else-if="error" role="alert" class="space-y-2 text-n-ruby-11">
        <p>{{ label('ERROR') }}</p>
        <button
          type="button"
          class="text-n-blue-11"
          data-audio-usages-retry
          @click="load(page)"
        >
          {{ label('RETRY') }}
        </button>
      </div>
      <p v-else-if="!items.length">{{ label('EMPTY') }}</p>
      <article
        v-for="item in items"
        :key="item.draft_id"
        class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        :data-audio-usage-draft="item.draft_id"
      >
        <h4 class="break-words font-semibold">{{ item.name }}</h4>
        <p>
          {{ draftDescription(item) }}
        </p>
        <p>{{ label(item.status === 'archived' ? 'ARCHIVED' : 'LOCAL') }}</p>
        <ul class="min-w-0 space-y-2">
          <li
            v-for="reference in item.references"
            :key="reference.node_id"
            class="break-words"
          >
            {{ referenceDescription(reference) }}
            <span class="block break-all">{{
              checksumDescription(reference.sha256)
            }}</span>
          </li>
        </ul>
      </article>
      <nav
        v-if="meta.pages > 1 && !error"
        :aria-label="label('PAGINATION')"
        class="flex flex-wrap items-center gap-3"
      >
        <button
          type="button"
          :disabled="loading || page <= 1"
          @click="load(page - 1)"
        >
          {{ label('PREVIOUS') }}
        </button>
        <span>{{ pageDescription() }}</span>
        <button
          type="button"
          :disabled="loading || page >= meta.pages"
          @click="load(page + 1)"
        >
          {{ label('NEXT') }}
        </button>
      </nav>
    </div>
  </Dialog>
</template>
