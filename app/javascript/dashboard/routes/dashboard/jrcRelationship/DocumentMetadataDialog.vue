<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  document: { type: Object, required: true },
  busy: Boolean,
  error: { type: String, default: '' },
});
const emit = defineEmits(['close', 'save']);
const { t } = useI18n();
const route = useRoute();
const dialog = ref(null);
const rows = ref([]);
const q = ref('');
const page = ref(1);
const meta = ref(null);
const loading = ref(false);
const optionsReady = ref(false);
const loadError = ref('');
const form = reactive({
  responsible_id: props.document.responsible?.id || '',
  status: props.document.status,
  revision: props.document.revision,
  reason: '',
});
let controller;
let turn = 0;
const load = async () => {
  turn += 1;
  const epoch = turn;
  controller?.abort();
  controller = new AbortController();
  loading.value = true;
  loadError.value = '';
  optionsReady.value = false;
  rows.value = [];
  try {
    const result = await API.documentResponsibles(
      route.params.accountId,
      props.document.id,
      { q: q.value, page: page.value },
      { signal: controller.signal }
    );
    if (turn !== epoch) return;
    rows.value = result.data.payload;
    meta.value = result.data.meta;
    optionsReady.value = true;
  } catch (error) {
    if (turn === epoch && error.code !== 'ERR_CANCELED')
      loadError.value =
        message(error) || t('RELATIONSHIP.V2.DOCS.OPTIONS_FAILED');
  } finally {
    if (turn === epoch) loading.value = false;
  }
};
const maySave = computed(
  () =>
    !props.busy && !loading.value && optionsReady.value && !!form.reason.trim()
);
const submit = () => {
  if (maySave.value) emit('save', { ...form });
};
const currentOutsidePage = computed(
  () =>
    props.document.responsible &&
    !rows.value.some(row => row.id === props.document.responsible.id)
);
const search = () => {
  if (page.value === 1) load();
  else page.value = 1;
};
watch(page, load);
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(() => {
  turn += 1;
  controller?.abort();
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    :title="t('RELATIONSHIP.V2.DOCS.METADATA')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!busy"
    @close="emit('close')"
  >
    <form
      class="space-y-4"
      @submit.prevent="submit"
    >
      <p class="text-sm text-n-slate-11">
        {{ t('RELATIONSHIP.V2.DOCS.RESPONSIBILITY_HELP') }}
      </p>
      <p
        v-if="error || loadError"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ error || loadError }}
      </p>
      <label class="grid gap-1 text-sm"
        >{{ t('RELATIONSHIP.V2.DOCS.RESPONSIBLE_SEARCH')
        }}<input
          v-model="q"
          :class="inputClass"
          maxlength="100"
          :disabled="busy || loading"
          @keydown.enter.prevent="search"
      /></label>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || loading"
        @click="search"
      >
        {{ t('RELATIONSHIP.V2.DOCS.SEARCH') }}
      </button>
      <label class="grid gap-1 text-sm"
        >{{ t('RELATIONSHIP.V2.DOCS.RESPONSIBLE')
        }}<select
          v-model="form.responsible_id"
          :class="inputClass"
          :disabled="busy || loading || !!loadError"
        >
          <option value="">
            {{ t('RELATIONSHIP.V2.DOCS.NO_DOCUMENT_RESPONSIBLE') }}
          </option>
          <option
            v-if="currentOutsidePage"
            :value="document.responsible.id"
          >
            {{ document.responsible.name }}
          </option>
          <option
            v-for="person in rows"
            :key="person.id"
            :value="person.id"
            :disabled="!person.eligible"
          >
            {{ person.name }}
          </option>
        </select></label
      >
      <nav
        v-if="meta"
        class="flex flex-wrap justify-between gap-2"
        :aria-label="t('RELATIONSHIP.V2.PAGINATION')"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || loading || page <= 1"
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
          :disabled="busy || loading || page * meta.per_page >= meta.total"
          @click="page += 1"
        >
          {{ t('RELATIONSHIP.V2.NEXT') }}
        </button>
      </nav>
      <label class="grid gap-1 text-sm"
        >{{ t('RELATIONSHIP.V2.DOCS.STATUS')
        }}<select
          v-model="form.status"
          :class="inputClass"
          :disabled="busy"
        >
          <option value="active">
            {{ t('RELATIONSHIP.V2.DOCS.STATUSES.active') }}
          </option>
          <option value="archived">
            {{ t('RELATIONSHIP.V2.DOCS.STATUSES.archived') }}
          </option>
        </select></label
      >
      <label class="grid gap-1 text-sm"
        >{{ t('RELATIONSHIP.V2.DOCS.METADATA_REASON')
        }}<textarea
          v-model="form.reason"
          required
          maxlength="500"
          rows="3"
          :class="inputClass"
          :disabled="busy"
        />
      </label>
      <div class="flex flex-wrap justify-end gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="dialog.close()"
        >
          {{ t('RELATIONSHIP.CLOSE') }}</button
        ><button
          type="submit"
          class="rounded-lg bg-n-violet-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
          :disabled="!maySave"
        >
          {{ t('RELATIONSHIP.SAVE') }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
