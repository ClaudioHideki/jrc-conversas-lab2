<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/jrcContactCenter';
import AcwFormSchemaEditor from './AcwFormSchemaEditor.vue';
import AcwFormFields from './AcwFormFields.vue';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import { useAcwFormEditor } from '../composables/useAcwFormEditor';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
const separator = ' · ';
const dialog = ref(null);
const editor = useAcwFormEditor({ accountId: computed(() => props.accountId) });
const { draft, recordId, state, revision, dirty, busy, locked, canSave } =
  editor;
const labels = computed(() => ({
  title: t('JRC_CONTACT_CENTER.ACW_FORMS.TITLE'),
  hint: t('JRC_CONTACT_CENTER.ACW_FORMS.LIBRARY_HINT'),
  new: t('JRC_CONTACT_CENTER.ACW_FORMS.NEW'),
  list: t('JRC_CONTACT_CENTER.ACW_FORMS.BACK_TO_LIST'),
  description: t('JRC_CONTACT_CENTER.ACW_FORMS.DESCRIPTION'),
  preview: t('JRC_CONTACT_CENTER.ACW_FORMS.PREVIEW'),
  previewHint: t('JRC_CONTACT_CENTER.ACW_FORMS.PREVIEW_HINT'),
  history: t('JRC_CONTACT_CENTER.ACW_FORMS.HISTORY'),
  save: t('JRC_CONTACT_CENTER.ACW_FORMS.SAVE'),
  saved: t('JRC_CONTACT_CENTER.ACW_FORMS.SAVED'),
  active: t('JRC_CONTACT_CENTER.ACW_FORMS.ACTIVE'),
  archived: t('JRC_CONTACT_CENTER.ACW_FORMS.ARCHIVED'),
  archive: t('JRC_CONTACT_CENTER.ACW_FORMS.ARCHIVE'),
  restore: t('JRC_CONTACT_CENTER.ACW_FORMS.RESTORE'),
  confirmArchive: t('JRC_CONTACT_CENTER.ACW_FORMS.CONFIRM_ARCHIVE'),
  discard: t('JRC_CONTACT_CENTER.ACW_FORMS.CONFIRM_DISCARD'),
  cancel: t('JRC_CONTACT_CENTER.LOCAL_IVR.CANCEL'),
  close: t('JRC_CONTACT_CENTER.LOCAL_IVR.CLOSE'),
  retry: t('JRC_CONTACT_CENTER.LOCAL_IVR.RETRY_SAVE'),
  name: t('JRC_CONTACT_CENTER.ADMIN.NAME'),
  status: t('JRC_CONTACT_CENTER.ADMIN.STATUS'),
  open: t('JRC_CONTACT_CENTER.ACW_FORMS.OPEN'),
  loading: t('JRC_CONTACT_CENTER.COMMON.LOADING'),
  refresh: t('JRC_CONTACT_CENTER.COMMON.REFRESH'),
  failed: t('JRC_CONTACT_CENTER.COMMON.ERROR'),
  empty: t('JRC_CONTACT_CENTER.COMMON.EMPTY'),
  revision: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.REVISION'),
  previous: t('JRC_CONTACT_CENTER.LOCAL_IVR.PREVIOUS'),
  next: t('JRC_CONTACT_CENTER.LOCAL_IVR.NEXT'),
  filter: t('JRC_CONTACT_CENTER.ADMIN.FILTER'),
  clear: t('JRC_CONTACT_CENTER.ADMIN.CLEAR'),
}));
const errorText = computed(
  () =>
    ({
      DENIED: t('JRC_CONTACT_CENTER.ACW_FORMS.DENIED'),
      LOAD_FAILED: t('JRC_CONTACT_CENTER.ACW_FORMS.LOAD_FAILED'),
      SAVE_FAILED: t('JRC_CONTACT_CENTER.ACW_FORMS.SAVE_FAILED'),
      UNCERTAIN: t('JRC_CONTACT_CENTER.ACW_FORMS.UNCERTAIN'),
    })[state.error] || ''
);
const list = reactive({
  items: [],
  page: 1,
  pages: 0,
  total: 0,
  loading: false,
  loaded: false,
  failed: false,
});
const history = reactive({
  items: [],
  page: 1,
  pages: 0,
  loading: false,
  failed: false,
});
const filters = reactive({ q: '', status: 'active' });
const mode = ref('list');
const tab = ref('edit');
const confirm = ref('');
const preview = ref({});
const selectedVersion = ref(null);
const secondaryBusy = ref(false);
const controlsLocked = computed(
  () => busy.value || secondaryBusy.value || list.loading
);
let generation = 0;
let alive = true;

const load = async (page = 1) => {
  if (list.loading || !alive) return;
  generation += 1;
  const current = generation;
  list.loading = true;
  list.failed = false;
  list.loaded = false;
  list.items = [];
  try {
    const response = await API.acwForms(props.accountId, {
      ...filters,
      page,
      per_page: 20,
    });
    if (current !== generation || !alive) return;
    Object.assign(list, response.data.meta, {
      items: response.data.items,
      loaded: true,
    });
  } catch {
    if (current === generation && alive) list.failed = true;
  } finally {
    if (current === generation && alive) list.loading = false;
  }
};
const close = () => {
  if (controlsLocked.value) return;
  if (confirm.value !== 'close' && (dirty.value || state.uncertain)) {
    confirm.value = 'close';
    return;
  }
  dialog.value.close();
};
const back = () => {
  if (controlsLocked.value) return;
  if (confirm.value !== 'back' && (dirty.value || state.uncertain)) {
    confirm.value = 'back';
    return;
  }
  editor.reset();
  selectedVersion.value = null;
  preview.value = {};
  confirm.value = '';
  mode.value = 'list';
  load(list.page);
};
const open = async id => {
  if (controlsLocked.value || !list.loaded) return;
  mode.value = 'editor';
  tab.value = 'edit';
  preview.value = {};
  selectedVersion.value = null;
  await editor.open(id);
};
const save = async (status = 'active', retry = false) => {
  if (secondaryBusy.value) return;
  confirm.value = '';
  if (await editor.save(status, retry)) {
    preview.value = {};
    selectedVersion.value = null;
  }
};
const loadHistory = async (page = 1) => {
  if (!recordId.value || controlsLocked.value) return;
  secondaryBusy.value = true;
  history.loading = true;
  history.failed = false;
  history.items = [];
  selectedVersion.value = null;
  try {
    const response = await API.acwFormHistory(
      props.accountId,
      recordId.value,
      page
    );
    if (alive)
      Object.assign(history, response.data.meta, {
        items: response.data.items,
      });
  } catch {
    if (alive) history.failed = true;
  } finally {
    if (alive) {
      history.loading = false;
      secondaryBusy.value = false;
    }
  }
};
const viewVersion = async row => {
  if (controlsLocked.value) return;
  secondaryBusy.value = true;
  history.failed = false;
  selectedVersion.value = null;
  try {
    const response = await API.acwFormVersion(
      props.accountId,
      recordId.value,
      row.revision
    );
    if (alive) {
      selectedVersion.value = response.data.item;
      preview.value = {};
    }
  } catch {
    if (alive) history.failed = true;
  } finally {
    if (alive) secondaryBusy.value = false;
  }
};
const chooseTab = value => {
  if (controlsLocked.value) return;
  tab.value = value;
  preview.value = {};
  if (value === 'history') loadHistory();
};
const confirmAction = () => {
  if (confirm.value === 'close') close();
  else if (confirm.value === 'back') back();
  else if (confirm.value === 'archive') save('archived');
};
const beforeUnload = event => {
  if (!dirty.value && !state.uncertain && !state.saving) return;
  event.preventDefault();
  event.returnValue = '';
};
onMounted(() => {
  dialog.value.open();
  window.addEventListener('beforeunload', beforeUnload);
  load();
});
onBeforeUnmount(() => {
  alive = false;
  generation += 1;
  window.removeEventListener('beforeunload', beforeUnload);
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="labels.title"
    :description="labels.hint"
    width="5xl"
    :show-confirm-button="false"
    :show-cancel-button="false"
    contained
    :use-form="false"
    :dismissible="!controlsLocked && !dirty && !state.uncertain"
    :close-on-click-outside="false"
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-4 text-n-slate-12" data-acw-form-library>
      <p v-if="list.loading || state.loading || history.loading" role="status">
        {{ labels.loading }}
      </p>
      <p
        v-if="errorText"
        role="alert"
        class="rounded-lg bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
      >
        {{ errorText }}
      </p>
      <p
        v-if="state.saved"
        role="status"
        data-acw-form-saved
        class="rounded-lg bg-n-teal-2 p-3 text-sm text-n-teal-11"
      >
        {{ labels.saved }}
      </p>
      <template v-if="mode === 'list'">
        <form
          class="grid min-w-0 gap-3 sm:grid-cols-2"
          @submit.prevent="load(1)"
        >
          <label class="block min-w-0 text-sm"
            ><span class="block">{{ labels.name }}</span
            ><input
              v-model="filters.q"
              type="search"
              maxlength="100"
              :disabled="list.loading"
              class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-acw-form-search
          /></label>
          <label class="block min-w-0 text-sm"
            ><span class="block">{{ labels.status }}</span
            ><select
              v-model="filters.status"
              :disabled="list.loading"
              class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-acw-form-status
            >
              <option value="active">{{ labels.active }}</option>
              <option value="archived">{{ labels.archived }}</option>
              <option value="">{{ t('JRC_CONTACT_CENTER.ADMIN.ALL') }}</option>
            </select></label
          >
          <div class="flex flex-wrap gap-2 sm:col-span-2">
            <Button
              type="submit"
              :label="labels.filter"
              :disabled="list.loading"
            /><Button
              type="button"
              :label="labels.clear"
              :disabled="list.loading"
              faded
              slate
              @click="
                filters.q = '';
                filters.status = '';
                load(1);
              "
            /><Button
              type="button"
              :label="labels.new"
              :disabled="!list.loaded || list.loading"
              data-acw-form-new
              @click="open(null)"
            />
          </div>
        </form>
        <p v-if="list.failed" role="alert" class="text-sm text-n-ruby-11">
          {{ labels.failed
          }}<Button
            type="button"
            :label="labels.refresh"
            size="sm"
            faded
            @click="load(list.page)"
          />
        </p>
        <p
          v-if="list.loaded && !list.items.length"
          class="text-sm text-n-slate-11"
        >
          {{ labels.empty }}
        </p>
        <ul class="min-w-0 space-y-2">
          <li
            v-for="row in list.items"
            :key="row.id"
            class="flex min-w-0 flex-wrap items-center justify-between gap-3 rounded-lg border border-n-weak p-3"
            data-acw-form-row
          >
            <div class="min-w-0">
              <p class="break-words font-medium">{{ row.name }}</p>
              <p class="text-sm text-n-slate-11">
                {{ row.status === 'active' ? labels.active : labels.archived
                }}<span aria-hidden="true">{{ separator }}</span
                >{{ labels.revision }}<span> {{ row.revision }}</span>
              </p>
            </div>
            <Button
              type="button"
              :label="labels.open"
              :disabled="controlsLocked"
              size="sm"
              faded
              data-acw-form-open
              @click="open(row.id)"
            />
          </li>
        </ul>
        <div class="flex flex-wrap items-center gap-2">
          <Button
            type="button"
            :label="labels.previous"
            :disabled="list.loading || list.page <= 1"
            size="sm"
            faded
            @click="load(list.page - 1)"
          /><span class="text-sm">{{
            t('JRC_CONTACT_CENTER.LOCAL_IVR.PAGE', {
              page: list.page,
              pages: list.pages,
            })
          }}</span
          ><Button
            type="button"
            :label="labels.next"
            :disabled="list.loading || list.page >= list.pages"
            size="sm"
            faded
            @click="load(list.page + 1)"
          />
        </div>
      </template>
      <Button
        v-if="mode === 'editor' && !draft && !busy"
        type="button"
        :label="labels.list"
        faded
        @click="back"
      />
      <template v-else-if="draft && !state.denied">
        <nav class="flex flex-wrap gap-2">
          <Button
            type="button"
            :label="labels.list"
            :disabled="controlsLocked"
            size="sm"
            faded
            @click="back"
          /><Button
            type="button"
            :label="labels.title"
            :disabled="controlsLocked"
            size="sm"
            :faded="tab !== 'edit'"
            @click="chooseTab('edit')"
          /><Button
            type="button"
            :label="labels.preview"
            :disabled="controlsLocked"
            size="sm"
            :faded="tab !== 'preview'"
            data-acw-form-preview
            @click="chooseTab('preview')"
          /><Button
            v-if="recordId"
            type="button"
            :label="labels.history"
            :disabled="controlsLocked"
            size="sm"
            :faded="tab !== 'history'"
            data-acw-form-history
            @click="chooseTab('history')"
          />
        </nav>
        <fieldset
          v-if="tab === 'edit'"
          :disabled="locked || secondaryBusy"
          class="min-w-0 space-y-4"
        >
          <label class="block min-w-0 text-sm"
            ><span class="block">{{ labels.name }}</span
            ><input
              v-model="draft.name"
              maxlength="160"
              required
              class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-acw-form-name
          /></label>
          <label class="block min-w-0 text-sm"
            ><span class="block">{{ labels.description }}</span
            ><textarea
              v-model="draft.description"
              maxlength="1000"
              rows="3"
              class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
              data-acw-form-description
            />
          </label>
          <AcwFormSchemaEditor
            v-model="draft.definition"
            :disabled="locked || secondaryBusy"
          />
        </fieldset>
        <section v-if="tab === 'preview'" class="min-w-0 space-y-3">
          <p class="text-sm text-n-slate-11">{{ labels.previewHint }}</p>
          <AcwFormFields v-model="preview" :definition="draft.definition" />
        </section>
        <section v-if="tab === 'history'" class="min-w-0 space-y-3">
          <p v-if="history.failed" role="alert" class="text-sm text-n-ruby-11">
            {{ labels.failed }}
          </p>
          <ul class="space-y-2">
            <li
              v-for="row in history.items"
              :key="row.revision"
              class="flex min-w-0 flex-wrap items-center justify-between gap-2 rounded-lg border border-n-weak p-3"
            >
              <span class="break-words"
                >{{ labels.revision }} {{ row.revision
                }}<span aria-hidden="true">{{ separator }}</span
                >{{ row.name }}</span
              ><Button
                type="button"
                :label="labels.open"
                size="sm"
                faded
                :disabled="controlsLocked"
                @click="viewVersion(row)"
              />
            </li>
          </ul>
          <div class="flex flex-wrap items-center gap-2">
            <Button
              type="button"
              :label="labels.previous"
              size="sm"
              faded
              :disabled="controlsLocked || history.page <= 1"
              @click="loadHistory(history.page - 1)"
            /><Button
              type="button"
              :label="labels.next"
              size="sm"
              faded
              :disabled="controlsLocked || history.page >= history.pages"
              @click="loadHistory(history.page + 1)"
            /><Button
              v-if="history.failed"
              type="button"
              :label="labels.refresh"
              size="sm"
              faded
              :disabled="controlsLocked"
              @click="loadHistory(history.page)"
            />
          </div>
          <section
            v-if="selectedVersion"
            class="min-w-0 rounded-lg border border-n-weak p-3"
          >
            <h3 class="mb-3 break-words font-medium">
              {{ selectedVersion.name
              }}<span aria-hidden="true">{{ separator }}</span
              >{{ labels.revision }} {{ selectedVersion.revision }}
            </h3>
            <AcwFormFields
              v-model="preview"
              :definition="selectedVersion.definition"
              disabled
            />
          </section>
        </section>
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="draft"
          resource="acw_forms"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="revision.review"
        />
      </template>
      <section
        v-if="confirm"
        class="space-y-3 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3 text-sm"
        data-acw-form-confirmation
      >
        <p>
          {{ confirm === 'archive' ? labels.confirmArchive : labels.discard }}
        </p>
        <div class="flex flex-wrap gap-2">
          <Button
            type="button"
            :label="confirm === 'archive' ? labels.archive : labels.discard"
            :disabled="controlsLocked"
            data-acw-form-confirm
            @click="confirmAction"
          /><Button
            type="button"
            :label="labels.cancel"
            :disabled="controlsLocked"
            faded
            slate
            @click="confirm = ''"
          />
        </div>
      </section>
    </div>
    <template #footer>
      <div class="flex w-full flex-wrap justify-between gap-2">
        <Button
          type="button"
          :label="labels.close"
          :disabled="controlsLocked"
          faded
          slate
          @click="close"
        /><template v-if="mode === 'editor' && draft && !state.denied">
          <Button
            v-if="recordId && draft.status === 'active'"
            type="button"
            :label="labels.archive"
            :disabled="!canSave || dirty || secondaryBusy"
            faded
            ruby
            @click="confirm = 'archive'"
          /><Button
            v-if="state.uncertain"
            type="button"
            :label="labels.retry"
            :disabled="controlsLocked"
            data-acw-form-retry
            @click="save('active', true)"
          /><Button
            v-else
            type="button"
            :label="draft.status === 'archived' ? labels.restore : labels.save"
            :disabled="!canSave || secondaryBusy"
            data-acw-form-save
            @click="save()"
          />
        </template>
      </div>
    </template>
  </Dialog>
</template>
