<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import API from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: String, required: true },
  folder: { type: Object, required: true },
  canManage: { type: Boolean, required: true },
  busy: { type: Boolean, default: false },
  depth: { type: Number, default: 1 },
});
const emit = defineEmits(['navigate', 'edit', 'denied']);
const { t } = useI18n();
const labels = computed(() => ({
  EXPAND: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.EXPAND'),
  COLLAPSE: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.COLLAPSE'),
  EDIT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.EDIT'),
  LOADING: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.LOADING'),
  EMPTY_CHILDREN: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.EMPTY_CHILDREN'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.ERROR'),
  RETRY: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.RETRY'),
  PREVIOUS: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.NEXT'),
  PAGINATION: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PAGINATION'),
}));
const opened = ref(false);
const loading = ref(false);
const error = ref(false);
const items = ref([]);
const page = ref(1);
const meta = ref({ total: 0, pages: 0 });
const { uid } = getCurrentInstance();
const childrenId = `cc-audio-children-${uid}`;
const nameId = `cc-audio-folder-name-${uid}`;
let generation = 0;
const scope = () =>
  JSON.stringify([props.accountId, props.unitId, props.folder.id]);
const clear = () => {
  generation += 1;
  opened.value = false;
  loading.value = false;
  error.value = false;
  items.value = [];
  page.value = 1;
  meta.value = { total: 0, pages: 0 };
};
const denied = () => {
  clear();
  emit('denied');
};
const validResponse = data =>
  String(data?.account_id) === String(props.accountId) &&
  Array.isArray(data.items) &&
  data.items.every(
    row =>
      typeof row.id === 'string' &&
      row.id !== props.folder.id &&
      row.unit_id === props.unitId &&
      row.parent_id === props.folder.id
  ) &&
  Number.isSafeInteger(data.meta?.pages) &&
  data.meta.pages >= 0 &&
  Number.isSafeInteger(data.meta?.total) &&
  data.meta.total >= 0;
const load = async (nextPage, redirected = false) => {
  if (!props.canManage || !opened.value) return;
  generation += 1;
  const current = generation;
  const origin = scope();
  loading.value = true;
  error.value = false;
  items.value = [];
  meta.value = { total: 0, pages: 0 };
  try {
    const response = await API.audioFolders(props.accountId, {
      unit_id: props.unitId,
      parent_id: props.folder.id,
      page: nextPage,
      per_page: 20,
    });
    if (current !== generation || origin !== scope() || !props.canManage)
      return;
    if (!validResponse(response.data))
      throw new Error('Invalid scoped folder children');
    const last = Math.max(1, response.data.meta.pages);
    if (nextPage > last) {
      if (redirected) throw new Error('Folder pagination changed again');
      await load(last, true);
      return;
    }
    items.value = response.data.items;
    meta.value = response.data.meta;
    page.value = nextPage;
  } catch (failure) {
    if (current !== generation) return;
    if ([401, 403, 404].includes(failure?.response?.status)) denied();
    else error.value = true;
  } finally {
    if (current === generation) loading.value = false;
  }
};
const toggle = () => {
  if (!props.canManage || props.busy) return;
  if (opened.value) clear();
  else {
    opened.value = true;
    load(1);
  }
};
watch(
  [
    () => props.accountId,
    () => props.unitId,
    () => props.folder.id,
    () => props.folder.parent_id,
    () => props.canManage,
  ],
  clear
);
onBeforeUnmount(clear);
</script>

<template>
  <li class="min-w-0 space-y-2" :data-audio-folder="folder.id">
    <div
      class="flex min-w-0 flex-wrap items-center gap-2 rounded-xl border border-n-weak bg-n-solid-1 p-3"
    >
      <button
        type="button"
        :disabled="!canManage || busy"
        :aria-expanded="opened"
        :aria-controls="childrenId"
        :aria-describedby="nameId"
        :aria-label="opened ? labels.COLLAPSE : labels.EXPAND"
        :data-expand-audio-folder="folder.id"
        class="flex size-7 shrink-0 items-center justify-center rounded-lg border border-n-weak text-n-blue-11 disabled:opacity-40"
        @click="toggle"
      >
        <Icon
          icon="i-lucide-chevron-right"
          class="size-4"
          :class="opened ? 'rotate-90' : ''"
          aria-hidden="true"
        />
      </button>
      <button
        :id="nameId"
        type="button"
        :disabled="!canManage || busy"
        :data-open-audio-folder="folder.id"
        class="flex min-w-0 flex-1 items-start gap-2 break-words text-left text-n-blue-11"
        @click="emit('navigate', folder.id)"
      >
        <Icon
          icon="i-lucide-folder"
          class="mt-0.5 size-4 shrink-0"
          aria-hidden="true"
        />
        <span class="min-w-0 break-words">{{ folder.name }}</span>
      </button>
      <button
        type="button"
        :disabled="!canManage || busy"
        :data-edit-audio-folder="folder.id"
        class="max-w-full break-words rounded-lg border border-n-blue-6 px-2 py-2 text-sm text-n-blue-11 disabled:opacity-40"
        @click="emit('edit', folder)"
      >
        {{ labels.EDIT }}
      </button>
    </div>
    <div
      v-if="opened"
      :id="childrenId"
      class="min-w-0 space-y-2"
      :class="depth < 4 ? 'pl-3' : ''"
      :data-audio-folder-children="folder.id"
    >
      <p v-if="loading" role="status" class="text-sm text-n-slate-11">
        {{ labels.LOADING }}
      </p>
      <div v-else-if="error" class="min-w-0 space-y-2">
        <p role="alert" class="break-words text-sm text-n-ruby-11">
          {{ labels.ERROR }}
        </p>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-2 py-2 text-sm text-n-blue-11"
          @click="load(1)"
        >
          {{ labels.RETRY }}
        </button>
      </div>
      <p v-else-if="!items.length" class="break-words text-sm text-n-slate-11">
        {{ labels.EMPTY_CHILDREN }}
      </p>
      <ul v-else class="min-w-0 space-y-2">
        <AudioFolderBranch
          v-for="row in items"
          :key="row.id"
          :account-id="accountId"
          :unit-id="unitId"
          :folder="row"
          :can-manage="canManage"
          :busy="busy"
          :depth="depth + 1"
          @navigate="emit('navigate', $event)"
          @edit="emit('edit', $event)"
          @denied="denied"
        />
      </ul>
      <nav
        v-if="!loading && !error && meta.pages > 1"
        class="flex min-w-0 flex-wrap gap-3 text-sm text-n-blue-11"
        :aria-label="labels.PAGINATION"
      >
        <button type="button" :disabled="page <= 1" @click="load(page - 1)">
          {{ labels.PREVIOUS }}
        </button>
        <button
          type="button"
          :disabled="page >= meta.pages"
          @click="load(page + 1)"
        >
          {{ labels.NEXT }}
        </button>
      </nav>
    </div>
  </li>
</template>
