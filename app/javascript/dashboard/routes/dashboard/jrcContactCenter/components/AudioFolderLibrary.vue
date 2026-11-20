<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';
import { useMapGetter } from 'dashboard/composables/store';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import AudioAssetLibrary from './AudioAssetLibrary.vue';
import AudioFolderBranch from './AudioFolderBranch.vue';
import { useConfigurationRevision } from '../composables/useConfigurationRevision';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const currentUser = useMapGetter('getCurrentUser');
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.TITLE'),
  LIMITS: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.LIMITS'),
  UNIT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.UNIT'),
  SEARCH: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.SEARCH'),
  FILTER: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.FILTER'),
  CLEAR: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.CLEAR'),
  NEW: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.NEW'),
  NO_UNIT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.NO_UNIT'),
  PATH: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PATH'),
  ROOT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.ROOT'),
  UP: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.UP'),
  LOADING: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.LOADING'),
  ERROR: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.ERROR'),
  EMPTY: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.EMPTY'),
  EDIT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.EDIT'),
  PAGINATION: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PAGINATION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.NEXT'),
  TOTAL: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.TOTAL'),
  PAGE: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PAGE'),
  EDITOR: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.EDITOR'),
  SAVE: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.SAVE'),
  CANCEL: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.CANCEL'),
  SAVE_ERROR: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.SAVE_ERROR'),
  NAME: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.NAME'),
  DESCRIPTION: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.DESCRIPTION'),
  SEARCH_PARENT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.SEARCH_PARENT'),
  PARENT_ERROR: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PARENT_ERROR'),
  PARENT: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.PARENT'),
  REVIEW: t('JRC_CONTACT_CENTER.AUDIO_FOLDERS.REVIEW'),
}));
const label = key => labels.value[key];
const parentOptionLabel = row =>
  `${row.parent_name || label('ROOT')} / ${row.name} (#${row.id})`;
const units = computed(() => props.context.units || []);
const unitId = computed(() =>
  String(route.query.audio_unit || units.value[0]?.id || '')
);
const unitAllowed = computed(() =>
  units.value.some(row => String(row.id) === unitId.value)
);
const parentId = computed(() => String(route.query.audio_parent || ''));
const page = computed(() =>
  Math.min(
    1_000_000,
    Math.max(1, Math.floor(Number(route.query.audio_page)) || 1)
  )
);
const q = ref('');
const items = ref([]);
const currentFolder = ref(null);
const meta = ref({ page: 1, pages: 0, total: 0 });
const paginationLabel = computed(
  () =>
    `${label('TOTAL')} ${meta.value.total} ${label('PAGE')} ${meta.value.page}`
);
const loading = ref(false);
const error = ref(false);
const opening = ref(false);
const saving = ref(false);
const saveError = ref(false);
const dialog = ref(null);
const editing = ref(null);
const draft = ref({
  name: '',
  description: '',
  parent_id: null,
  parent_name: '',
});
const reviewedDraft = ref('');
const parentSearch = ref('');
const parentPage = ref(1);
const parentOptions = ref([]);
const parentMeta = ref({ pages: 0 });
const parentLoading = ref(false);
const parentError = ref(false);
const editorOpen = ref(false);
let generation = 0;
let parentGeneration = 0;
const fingerprint = () =>
  JSON.stringify([props.accountId, unitId.value, draft.value]);
const reviewed = computed(() => reviewedDraft.value === fingerprint());
let clearDeniedContext;
const revision = useConfigurationRevision({
  accountId: computed(() => props.accountId),
  resource: computed(() => 'audio_folders'),
  draft,
  onDenied: () => clearDeniedContext(),
});
const canManage = computed(
  () => props.context.capabilities?.configure === true && unitAllowed.value
);
const canSave = computed(
  () =>
    canManage.value &&
    !opening.value &&
    !saving.value &&
    !parentError.value &&
    reviewed.value &&
    draft.value.name.trim().length > 0 &&
    revision.canSave.value &&
    (!editing.value ||
      (revision.state.required &&
        String(revision.state.id) === String(editing.value.id)))
);
const query = values =>
  router.replace({ query: { ...route.query, ...values } });
const navigate = id =>
  query({
    audio_parent: id || undefined,
    audio_q: undefined,
    audio_page: 1,
    audio_file_page: 1,
    audio_file_q: undefined,
  });
const search = () => query({ audio_q: q.value || undefined, audio_page: 1 });
const closeEditor = () => {
  editorOpen.value = false;
  parentGeneration += 1;
  editing.value = null;
  draft.value = { name: '', description: '', parent_id: null, parent_name: '' };
  reviewedDraft.value = '';
  parentOptions.value = [];
  revision.capture(null);
};
const forgetPrivateRecords = () => {
  items.value = [];
  currentFolder.value = null;
  meta.value = { page: page.value, pages: 0, total: 0 };
};
clearDeniedContext = () => {
  generation += 1;
  dialog.value.close();
  closeEditor();
  forgetPrivateRecords();
  opening.value = false;
  loading.value = false;
  saving.value = false;
  parentLoading.value = false;
  error.value = true;
};
const load = async () => {
  generation += 1;
  const version = generation;
  forgetPrivateRecords();
  error.value = false;
  loading.value = false;
  if (!canManage.value) return;
  loading.value = true;
  try {
    const response = await API.audioFolders(props.accountId, {
      unit_id: unitId.value,
      parent_id: route.query.audio_q ? undefined : parentId.value,
      q: route.query.audio_q || '',
      page: page.value,
      per_page: 20,
    });
    if (version !== generation) return;
    const lastPage = Math.max(1, response.data.meta.pages);
    if (page.value > lastPage) {
      await router.replace({ query: { ...route.query, audio_page: lastPage } });
      return;
    }
    const parent = parentId.value
      ? await API.audioFolder(props.accountId, parentId.value)
      : null;
    if (version !== generation) return;
    items.value = response.data.items;
    meta.value = response.data.meta;
    currentFolder.value = parent?.data.item || null;
  } catch {
    if (version === generation) error.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
const loadParents = async () => {
  parentGeneration += 1;
  const version = parentGeneration;
  parentOptions.value = [];
  parentError.value = false;
  if (!editorOpen.value || !canManage.value) return;
  parentLoading.value = true;
  try {
    const response = await API.audioFolders(props.accountId, {
      unit_id: unitId.value,
      q: parentSearch.value,
      page: parentPage.value,
      per_page: 20,
    });
    if (version !== parentGeneration) return;
    parentOptions.value = response.data.items.filter(
      row => String(row.id) !== String(editing.value?.id)
    );
    parentMeta.value = response.data.meta;
  } catch (failure) {
    if (version === parentGeneration) {
      if ([401, 403, 404].includes(failure?.response?.status))
        clearDeniedContext();
      else parentError.value = true;
    }
  } finally {
    if (version === parentGeneration) parentLoading.value = false;
  }
};
const selectParent = event => {
  const id = event.target.value || null;
  const option = parentOptions.value.find(row => String(row.id) === String(id));
  draft.value.parent_id = id;
  draft.value.parent_name = option?.name || '';
};
const open = async row => {
  if (!canManage.value || loading.value || opening.value || saving.value)
    return;
  const version = generation;
  opening.value = true;
  saveError.value = false;
  try {
    const source = row
      ? (await API.audioFolder(props.accountId, row.id)).data.item
      : null;
    if (version !== generation) return;
    editing.value = source;
    draft.value = source
      ? {
          name: source.name,
          description: source.description || '',
          parent_id: source.parent_id,
          parent_name: source.parent_name || '',
        }
      : {
          name: '',
          description: '',
          parent_id: currentFolder.value?.id || null,
          parent_name: currentFolder.value?.name || '',
        };
    reviewedDraft.value = '';
    parentSearch.value = '';
    parentPage.value = 1;
    revision.capture(source);
    editorOpen.value = true;
    dialog.value.open();
    await loadParents();
  } catch (failure) {
    if (version === generation) {
      if ([401, 403, 404].includes(failure?.response?.status)) {
        clearDeniedContext();
      }
      error.value = true;
    }
  } finally {
    if (version === generation) opening.value = false;
  }
};
const save = async () => {
  if (!canSave.value) return;
  const version = generation;
  saving.value = true;
  saveError.value = false;
  const values = {
    name: draft.value.name,
    description: draft.value.description,
    parent_id: draft.value.parent_id,
  };
  if (!editing.value) values.unit_id = unitId.value;
  try {
    await API.saveAudioFolder(
      props.accountId,
      editing.value?.id,
      values,
      revision.options()
    );
    if (version !== generation) return;
    dialog.value.close();
    closeEditor();
    saving.value = false;
    await load();
  } catch (failure) {
    if (version !== generation) return;
    if ([401, 403, 404].includes(failure?.response?.status)) {
      clearDeniedContext();
    } else saveError.value = !revision.handleError(failure);
    reviewedDraft.value = '';
  } finally {
    if (version === generation || !editorOpen.value) saving.value = false;
  }
};
watch([parentSearch, parentPage], loadParents);
watch(
  [
    () => props.accountId,
    unitId,
    parentId,
    page,
    () => route.query.audio_q,
    () => {
      const user = currentUser.value;
      const member = user?.accounts?.find(
        row => String(row.id) === String(props.accountId)
      );
      return JSON.stringify([
        user?.id,
        member?.role,
        member?.custom_role_id,
        member?.contact_center_eligible,
        [...(member?.permissions || [])].sort(),
        props.context.capabilities?.configure,
        units.value.map(row => String(row.id)).sort(),
      ]);
    },
  ],
  () => {
    dialog.value?.close();
    closeEditor();
    opening.value = false;
    saving.value = false;
    q.value = route.query.audio_q || '';
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  parentGeneration += 1;
});
</script>

<template>
  <section class="min-w-0 space-y-4" data-audio-folder-library>
    <h3 class="text-lg font-semibold text-n-slate-12">{{ label('TITLE') }}</h3>
    <p
      role="status"
      data-audio-library-limits
      class="rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
    >
      {{ label('LIMITS') }}
    </p>
    <div
      class="grid min-w-0 grid-cols-1 items-start gap-4 xl:grid-cols-[minmax(0,16rem)_minmax(0,1fr)]"
      data-audio-library-layout
    >
      <aside
        class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
        data-audio-folder-navigation
      >
        <form class="flex flex-wrap items-end gap-3" @submit.prevent="search">
          <label
            class="w-full min-w-0 text-sm text-n-slate-12 sm:min-w-48 sm:flex-1"
            >{{ label('UNIT') }}
            <select
              :value="unitId"
              data-audio-unit
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              @change="
                query({
                  audio_unit: $event.target.value,
                  audio_parent: undefined,
                  audio_page: 1,
                  audio_q: undefined,
                  audio_file_page: 1,
                  audio_file_q: undefined,
                })
              "
            >
              <option
                v-for="unit in units"
                :key="unit.id"
                :value="String(unit.id)"
              >
                {{ unit.name }}
              </option>
            </select>
          </label>
          <label
            class="w-full min-w-0 text-sm text-n-slate-12 sm:min-w-48 sm:flex-1"
            >{{ label('SEARCH') }}
            <input
              v-model="q"
              type="search"
              maxlength="100"
              data-audio-search
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
          <button
            type="submit"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
          >
            {{ label('FILTER') }}
          </button>
          <button
            type="button"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
            @click="
              q = '';
              search();
            "
          >
            {{ label('CLEAR') }}
          </button>
          <button
            type="button"
            :disabled="!canManage || loading || opening || saving"
            data-new-audio-folder
            class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white disabled:opacity-40"
            @click="open(null)"
          >
            {{ label('NEW') }}
          </button>
        </form>
        <p v-if="!canManage" role="status" class="text-sm text-n-amber-11">
          {{ label('NO_UNIT') }}
        </p>
        <nav
          v-else
          class="flex min-w-0 flex-wrap items-center gap-2 text-sm"
          :aria-label="label('PATH')"
        >
          <button type="button" class="text-n-blue-11" @click="navigate(null)">
            {{ label('ROOT') }}
          </button>
          <template v-if="currentFolder">
            <button
              v-for="ancestor in currentFolder.path"
              :key="ancestor.id"
              type="button"
              :disabled="ancestor.id === currentFolder.id"
              :aria-current="
                ancestor.id === currentFolder.id ? 'page' : undefined
              "
              :data-audio-folder-path="ancestor.id"
              class="min-w-0 max-w-full break-words text-left text-n-blue-11 disabled:text-n-slate-12"
              @click="navigate(ancestor.id)"
            >
              {{ ancestor.name }}
            </button>
            <button
              type="button"
              class="text-n-blue-11"
              @click="navigate(currentFolder.parent_id)"
            >
              {{ label('UP') }}
            </button>
          </template>
        </nav>
        <p
          v-if="loading || opening"
          role="status"
          class="text-sm text-n-slate-11"
        >
          {{ label('LOADING') }}
        </p>
        <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
          {{ label('ERROR') }}
        </p>
        <p
          v-else-if="canManage && !items.length"
          class="text-sm text-n-slate-11"
        >
          {{ label('EMPTY') }}
        </p>
        <ul
          v-else
          data-audio-folder-scroll
          class="max-h-80 space-y-2 overflow-y-auto overscroll-contain pr-1"
        >
          <AudioFolderBranch
            v-for="row in items"
            :key="row.id"
            :account-id="accountId"
            :unit-id="unitId"
            :folder="row"
            :can-manage="canManage"
            :busy="opening || saving"
            @navigate="navigate"
            @edit="open"
            @denied="clearDeniedContext"
          />
        </ul>
        <nav
          v-if="meta.pages > 1"
          class="flex flex-wrap items-center gap-3 text-sm text-n-slate-12"
          :aria-label="label('PAGINATION')"
        >
          <button
            type="button"
            :disabled="loading || page <= 1"
            @click="query({ audio_page: page - 1 })"
          >
            {{ label('PREVIOUS') }}
          </button>
          <p
            data-audio-folder-pagination-total
            class="inline-flex flex-wrap gap-1"
          >
            {{ paginationLabel }}
          </p>
          <button
            type="button"
            :disabled="loading || page >= meta.pages"
            @click="query({ audio_page: page + 1 })"
          >
            {{ label('NEXT') }}
          </button>
        </nav>
      </aside>
      <AudioAssetLibrary
        v-if="canManage && !error && !loading"
        :account-id="accountId"
        :context="context"
        :unit-id="unitId"
        :folder-id="parentId"
        @denied="clearDeniedContext"
      />
    </div>
    <Dialog
      ref="dialog"
      contained
      use-form
      :title="label('EDITOR')"
      :confirm-button-label="label('SAVE')"
      :cancel-button-label="label('CANCEL')"
      :disable-confirm-button="!canSave"
      :is-loading="saving"
      :dismissible="!saving"
      @confirm="save"
      @close="closeEditor"
    >
      <div class="min-w-0 space-y-4 text-n-slate-12" data-audio-folder-editor>
        <p v-if="saveError" role="alert" class="text-sm text-n-ruby-11">
          {{ label('SAVE_ERROR') }}
        </p>
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="draft"
          resource="audio_folders"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="revision.review"
        />
        <label
          data-audio-folder-field-label
          class="block min-w-0 text-sm text-n-slate-12"
          >{{ label('NAME')
          }}<input
            v-model="draft.name"
            maxlength="120"
            required
            data-audio-folder-name
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label
          data-audio-folder-field-label
          class="block min-w-0 text-sm text-n-slate-12"
          >{{ label('DESCRIPTION')
          }}<textarea
            v-model="draft.description"
            maxlength="1000"
            rows="3"
            data-audio-folder-description
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          />
        </label>
        <label
          data-audio-folder-field-label
          class="block min-w-0 text-sm text-n-slate-12"
          >{{ label('SEARCH_PARENT')
          }}<input
            v-model="parentSearch"
            maxlength="100"
            data-audio-parent-search
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            @input="parentPage = 1"
        /></label>
        <p v-if="parentError" role="alert" class="text-sm text-n-ruby-11">
          {{ label('PARENT_ERROR') }}
        </p>
        <label
          data-audio-folder-field-label
          class="block min-w-0 text-sm text-n-slate-12"
          >{{ label('PARENT') }}
          <select
            :value="draft.parent_id || ''"
            :disabled="parentLoading"
            data-audio-folder-parent
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            @change="selectParent"
          >
            <option value="">{{ label('ROOT') }}</option>
            <option
              v-if="
                draft.parent_id &&
                !parentOptions.some(
                  row => String(row.id) === String(draft.parent_id)
                )
              "
              :value="draft.parent_id"
            >
              {{ draft.parent_name }}
            </option>
            <option v-for="row in parentOptions" :key="row.id" :value="row.id">
              {{ parentOptionLabel(row) }}
            </option>
          </select>
        </label>
        <div v-if="parentMeta.pages > 1" class="flex flex-wrap gap-3 text-sm">
          <button
            type="button"
            :disabled="parentLoading || parentPage <= 1"
            @click="parentPage -= 1"
          >
            {{ label('PREVIOUS') }}
          </button>
          <button
            type="button"
            :disabled="parentLoading || parentPage >= parentMeta.pages"
            @click="parentPage += 1"
          >
            {{ label('NEXT') }}
          </button>
        </div>
        <label
          class="flex items-start gap-2 rounded-lg border border-n-blue-6 p-3 text-sm"
        >
          <input
            type="checkbox"
            :checked="reviewed"
            data-review-audio-folder
            @change="reviewedDraft = $event.target.checked ? fingerprint() : ''"
          />
          <span>{{ label('REVIEW') }}</span>
        </label>
      </div>
    </Dialog>
  </section>
</template>
