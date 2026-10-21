<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { inbox360Labels } from './inboxPresentation';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import CannedResponseAPI from 'dashboard/api/cannedResponse';
import LabelsAPI from 'dashboard/api/labels';
import ConversationAPI from 'dashboard/api/conversations';

const props = defineProps({
  accountId: { type: Number, required: true },
  conversationId: { type: Number, default: null },
  callId: { type: Number, default: null },
  categories: { type: Array, default: () => [] },
});
const emit = defineEmits(['insert', 'qualify', 'labelsUpdated']);
const { t } = useI18n();
const labels = computed(() => inbox360Labels(t));
const dialog = ref(null);
const mode = ref('REPLIES');
const items = ref([]);
const search = ref('');
const busy = ref(false);
const failed = ref(false);
const currentLabels = ref([]);
let generation = 0;
const visibleItems = computed(() =>
  items.value.filter(item =>
    `${item.title} ${item.content || ''}`
      .toLocaleLowerCase()
      .includes(search.value.toLocaleLowerCase())
  )
);
const invalidate = () => {
  generation += 1;
  items.value = [];
  search.value = '';
  busy.value = false;
  failed.value = false;
};
const close = () => {
  invalidate();
  dialog.value?.close();
};
const open = async kind => {
  invalidate();
  const version = generation;
  mode.value = kind;
  dialog.value.open();
  busy.value = true;
  try {
    if (kind === 'REPLIES') {
      const response = await CannedResponseAPI.get({ searchKey: '' });
      if (version === generation)
        items.value = response.data.map(item => ({
          id: item.id,
          title: item.short_code,
          content: item.content,
        }));
    } else if (props.conversationId) {
      const [accountLabels, selected] = await Promise.all([
        LabelsAPI.get(),
        ConversationAPI.getLabels(props.conversationId),
      ]);
      if (version === generation) {
        items.value = accountLabels.data.payload.map(item => ({
          id: item.id,
          title: item.title,
        }));
        currentLabels.value = selected.data.payload;
      }
    } else {
      items.value = props.categories.map(title => ({ id: title, title }));
    }
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) busy.value = false;
  }
};
const choose = async item => {
  if (busy.value) return;
  if (mode.value === 'REPLIES') {
    emit('insert', item.content);
    close();
    return;
  }
  const version = generation;
  busy.value = true;
  try {
    let updatedLabels;
    if (props.conversationId) {
      const response = await ConversationAPI.updateLabels(
        props.conversationId,
        [...new Set([...currentLabels.value, item.title])]
      );
      updatedLabels = response.data.payload;
    }
    if (version !== generation) return;
    if (props.conversationId)
      emit('labelsUpdated', { id: props.conversationId, data: updatedLabels });
    emit('qualify', item.title);
    close();
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) busy.value = false;
  }
};
watch(() => [props.accountId, props.conversationId, props.callId], close);
onBeforeUnmount(invalidate);
defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="labels[mode]"
    :show-confirm-button="false"
    show-close-button
    width="lg"
    @close="invalidate"
  >
    <div class="space-y-3">
      <p class="m-0 text-xs leading-5 text-n-slate-10">
        {{
          labels[mode === 'REPLIES' ? 'REPLIES_HINT' : 'QUALIFICATIONS_HINT']
        }}
      </p>
      <input
        v-model="search"
        type="search"
        :aria-label="t('JRC_CONTACT_CENTER.INBOX_360.SEARCH_OPTIONS')"
        :placeholder="t('JRC_CONTACT_CENTER.INBOX_360.SEARCH_OPTIONS')"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
      />
      <p v-if="failed" role="alert" class="text-sm text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </p>
      <div v-if="busy" class="h-24 animate-pulse rounded-lg bg-n-alpha-2" />
      <div v-else class="max-h-80 space-y-2 overflow-y-auto">
        <button
          v-for="item in visibleItems"
          :key="item.id"
          type="button"
          class="block w-full rounded-lg border border-n-weak bg-n-solid-1 p-3 text-left hover:border-n-blue-7 hover:bg-n-blue-2"
          @click="choose(item)"
        >
          <span class="block text-sm font-semibold text-n-slate-12">
            {{ item.title }}
          </span>
          <span
            v-if="item.content"
            class="mt-1 block whitespace-pre-wrap text-xs leading-5 text-n-slate-11"
          >
            {{ item.content }}
          </span>
        </button>
        <p
          v-if="!visibleItems.length"
          class="p-4 text-center text-sm text-n-slate-10"
        >
          {{ t('JRC_CONTACT_CENTER.INBOX_360.OPTIONS_EMPTY') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
