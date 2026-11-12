<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRoute, RouterLink } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, date, message } from './definitions';
const props = defineProps({
  analystId: { type: Number, required: true },
  formatting: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['close']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const result = ref(null);
const busy = ref(false);
const error = ref('');
const kind = ref('project_tasks');
const page = ref(1);
const kinds = ['project_tasks', 'service_tickets', 'projects', 'activities'];
const pages = computed(() =>
  Math.max(1, Math.ceil((result.value?.meta.total || 0) / 10))
);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.analystId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentUser,
    store.getters.getCurrentRole,
  ])
);
let generation = 0;
let controller;
const clear = () => {
  generation += 1;
  controller?.abort();
  result.value = null;
  error.value = '';
};
const load = async (recoverPage = true) => {
  clear();
  const token = generation;
  controller = new AbortController();
  busy.value = true;
  try {
    const { data } = await API.analystNativeResponsibilities(
      route.params.accountId,
      props.analystId,
      { kind: kind.value, page: page.value },
      { signal: controller.signal }
    );
    if (token !== generation) return;
    const lastPage = Math.max(1, Math.ceil(data.meta.total / 10));
    if (recoverPage && page.value > lastPage) {
      page.value = lastPage;
      await load(false);
      return;
    }
    result.value = data;
  } catch (failure) {
    if (token === generation) error.value = message(failure);
  } finally {
    if (token === generation) busy.value = false;
  }
};
const select = value => {
  if (busy.value || kind.value === value) return;
  kind.value = value;
  page.value = 1;
  load();
};
const navigate = value => {
  if (busy.value) return;
  page.value = value;
  load();
};
watch(identity, () => {
  clear();
  emit('close');
});
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(clear);
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('RELATIONSHIP.NATIVE_RESPONSIBILITIES.TITLE')"
    :description="t('RELATIONSHIP.NATIVE_RESPONSIBILITIES.NOTE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    show-close-button
    width="2xl"
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-3">
      <div
        class="flex flex-wrap gap-2"
        role="group"
        :aria-label="t('RELATIONSHIP.NATIVE_RESPONSIBILITIES.TITLE')"
      >
        <button
          v-for="value in kinds"
          :key="value"
          type="button"
          :data-testid="`native-kind-${value}`"
          :aria-pressed="kind === value"
          :disabled="busy"
          class="rounded-lg border border-blue-300 px-3 py-2 text-sm font-semibold dark:border-blue-800"
          :class="
            kind === value
              ? 'bg-blue-600 text-white dark:bg-blue-700'
              : 'bg-blue-50 text-blue-900 dark:bg-blue-950 dark:text-blue-100'
          "
          @click="select(value)"
        >
          {{ t(`RELATIONSHIP.NATIVE_RESPONSIBILITIES.KINDS.${value}`) }}
        </button>
      </div>
      <p
        v-if="busy"
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
      <template v-if="result">
        <h3 class="break-words text-base font-semibold">
          {{ result.analyst.name }}
        </h3>
        <p class="text-sm">
          {{
            t('RELATIONSHIP.NATIVE_RESPONSIBILITIES.TOTAL', {
              count: result.meta.total,
            })
          }}
        </p>
        <p
          v-if="!result.payload.length"
          class="text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIP.EMPTY') }}
        </p>
        <ul class="space-y-3">
          <li
            v-for="row in result.payload"
            :key="row.id"
            data-testid="native-responsibility"
            class="min-w-0 space-y-2 rounded-xl border border-n-weak bg-n-solid-2 p-3 text-sm"
          >
            <p class="break-words font-semibold">{{ row.title }}</p>
            <p>
              {{
                t(`RELATIONSHIP.NATIVE_RESPONSIBILITIES.STATES.${row.status}`)
              }}
            </p>
            <p>
              {{ t('RELATIONSHIP.NATIVE_RESPONSIBILITIES.UPDATED') }}:
              {{ date(row.updated_at, formatting) }}
            </p>
            <RouterLink
              :to="row.source_route"
              class="inline-flex rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white dark:bg-blue-700"
              @click="emit('close')"
            >
              {{ t('RELATIONSHIP.NATIVE_RESPONSIBILITIES.OPEN_SOURCE') }}
            </RouterLink>
          </li>
        </ul>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy || page <= 1"
            data-testid="native-previous"
            @click="navigate(page - 1)"
          >
            {{ t('RELATIONSHIP.PREVIOUS') }}
          </button>
          <span class="text-sm">{{
            t('RELATIONSHIP.NATIVE_RESPONSIBILITIES.PAGE', { page, pages })
          }}</span>
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy || page >= pages"
            data-testid="native-next"
            @click="navigate(page + 1)"
          >
            {{ t('RELATIONSHIP.NEXT') }}
          </button>
        </div>
      </template>
      <button
        v-if="error"
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="() => load()"
      >
        {{ t('RELATIONSHIP.NATIVE_RESPONSIBILITIES.RETRY') }}
      </button>
    </div>
  </Dialog>
</template>
