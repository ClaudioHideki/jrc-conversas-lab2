<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, message } from './definitions';
const props = defineProps({
  book: { type: Object, required: true },
  allowed: Boolean,
  disabled: Boolean,
});
const emit = defineEmits(['restore']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const opened = ref(false);
const rows = ref([]);
const loading = ref(false);
const error = ref('');
const pagination = ref({ page: 1, per_page: 25, total: 0 });
const pages = computed(() =>
  Math.max(1, Math.ceil(pagination.value.total / pagination.value.per_page))
);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.book.id,
    props.book.version,
    props.allowed,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
  ])
);
let generation = 0;
let controller;
const reset = () => {
  generation += 1;
  controller?.abort();
  opened.value = false;
  rows.value = [];
  error.value = '';
  loading.value = false;
  pagination.value = { page: 1, per_page: 25, total: 0 };
};
const load = async (page = 1) => {
  if (!props.allowed || props.disabled || !opened.value) return;
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  const { signal } = controller;
  rows.value = [];
  loading.value = true;
  error.value = '';
  try {
    const { data } = await API.playbookHistory(
      route.params.accountId,
      props.book.id,
      { page, per_page: 25 },
      { signal }
    );
    if (signal.aborted || token !== generation) return;
    if (
      data.current?.id !== props.book.id ||
      data.current.version !== props.book.version
    )
      throw new Error(t('RELATIONSHIP.PLAYBOOK_RESTORE.UNCONFIRMED'));
    rows.value = data.payload;
    pagination.value = data.meta;
  } catch (err) {
    if (!signal.aborted && token === generation) error.value = message(err);
  } finally {
    if (!signal.aborted && token === generation) loading.value = false;
  }
};
const toggle = event => {
  if (event.target.open) {
    if (opened.value) return;
    opened.value = true;
    load();
  } else reset();
};
watch(identity, reset);
onBeforeUnmount(reset);
</script>

<template>
  <details
    v-if="allowed"
    :open="opened"
    class="min-w-0 rounded-lg border border-n-weak p-3"
    @toggle="toggle"
  >
    <summary class="cursor-pointer text-sm font-semibold">
      {{ t('RELATIONSHIP.PLAYBOOK_RESTORE.HISTORY') }}
    </summary>
    <section
      v-if="opened"
      class="mt-3 min-w-0 space-y-3"
    >
      <p
        v-if="loading"
        role="status"
      >
        {{ t('RELATIONSHIP.LOADING') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ error }}
      </p>
      <button
        v-if="error"
        type="button"
        :class="buttonClass"
        :disabled="loading || disabled"
        @click="load(pagination.page)"
      >
        {{ t('RELATIONSHIP.PLAYBOOK_RESTORE.RETRY') }}
      </button>
      <ul class="space-y-2">
        <li
          v-for="version in rows"
          :key="version.version"
          class="flex min-w-0 flex-wrap items-center justify-between gap-3 text-sm"
        >
          <span>{{
            t('RELATIONSHIP.VERSION', { version: version.version })
          }}</span>
          <button
            v-if="version.version < book.version"
            type="button"
            :class="buttonClass"
            :disabled="loading || disabled"
            @click="emit('restore', book.id, version.version)"
          >
            {{ t('RELATIONSHIP.PLAYBOOK_RESTORE.OPEN') }}
          </button>
        </li>
      </ul>
      <p
        v-if="!loading && !error && !rows.length"
        class="text-sm text-n-slate-11"
      >
        {{ t('RELATIONSHIP.CONFIG_HISTORY_EMPTY') }}
      </p>
      <footer class="flex flex-wrap items-center justify-end gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="loading || disabled || pagination.page <= 1"
          @click="load(pagination.page - 1)"
        >
          {{ t('RELATIONSHIP.PREVIOUS') }}
        </button>
        <span class="text-sm">{{
          t('RELATIONSHIP.PAGE', {
            page: pagination.page,
            total: pagination.total,
          })
        }}</span>
        <button
          type="button"
          :class="buttonClass"
          :disabled="loading || disabled || pagination.page >= pages"
          @click="load(pagination.page + 1)"
        >
          {{ t('RELATIONSHIP.NEXT') }}
        </button>
      </footer>
    </section>
  </details>
  <p
    v-else
    role="status"
  >
    {{ t('RELATIONSHIP.RESTRICTED') }}
  </p>
</template>
