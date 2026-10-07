<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CannedResponseAPI from 'dashboard/api/cannedResponse';
import { useQuickActionAccess } from 'dashboard/components-next/layout/useQuickActionAccess';
import { homeTones } from 'dashboard/components-next/Conversation/ConversationHome/presentation';

defineProps({ canInsert: { type: Boolean, default: false } });
defineEmits(['action', 'insertResponse']);
const { t } = useI18n();
const { actions } = useQuickActionAccess();
const responses = ref([]);
const search = ref('');
const loading = ref(true);
const failed = ref(false);
const filteredResponses = computed(() =>
  responses.value.filter(response =>
    `${response.short_code} ${response.content}`
      .toLowerCase()
      .includes(search.value.toLowerCase())
  )
);
onMounted(async () => {
  try {
    const { data } = await CannedResponseAPI.get({});
    responses.value = data;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <aside
    class="flex shrink-0 min-w-0 flex-col xl:overflow-y-auto gap-4 border-t border-n-weak bg-n-slate-2 p-4 xl:w-80 xl:border-s xl:border-t-0"
  >
    <section class="rounded-xl border border-n-weak bg-n-solid-2 p-4">
      <h3 class="mb-3 text-sm font-semibold text-n-slate-12">
        {{ t('JRC_HOME.QUICK_ACTIONS') }}
      </h3>
      <div class="grid grid-cols-3 gap-2">
        <button
          v-for="action in actions"
          :key="action.key"
          type="button"
          class="flex min-h-20 flex-col items-center justify-center gap-2 rounded-xl p-2 text-center text-xs text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="$emit('action', action.key)"
        >
          <div
            :class="homeTones[action.tone]"
            class="grid size-10 place-content-center rounded-xl border"
          >
            <span :class="action.icon" class="size-5" aria-hidden="true" />
          </div>
          {{ t(`JRC_HOME.ACTIONS.${action.key}`) }}
        </button>
      </div>
    </section>
    <section class="rounded-xl border border-n-weak bg-n-solid-2 p-4">
      <h3 class="mb-3 text-sm font-semibold text-n-slate-12">
        {{ t('JRC_HOME.COMPOSE.SAVED') }}
      </h3>
      <input
        v-model="search"
        type="search"
        :aria-label="t('JRC_HOME.COMPOSE.SEARCH_SAVED')"
        :placeholder="t('JRC_HOME.COMPOSE.SEARCH_SAVED')"
        class="mb-3 w-full rounded-lg border border-n-weak bg-n-slate-2 px-3 py-2 text-sm text-n-slate-12"
      />
      <p v-if="loading" class="mb-0 text-sm text-n-slate-11">
        {{ t('JRC_HOME.LOADING') }}
      </p>
      <p v-else-if="failed" role="alert" class="mb-0 text-sm text-n-ruby-11">
        {{ t('JRC_HOME.COMPOSE.SAVED_ERROR') }}
      </p>
      <p
        v-else-if="!filteredResponses.length"
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ t('JRC_HOME.COMPOSE.NO_SAVED') }}
      </p>
      <div v-else class="max-h-60 space-y-2 overflow-y-auto">
        <button
          v-for="response in filteredResponses"
          :key="response.id"
          type="button"
          :disabled="!canInsert"
          class="flex w-full items-start gap-2 rounded-lg p-2 text-left hover:bg-n-blue-2 disabled:cursor-not-allowed disabled:opacity-50"
          @click="$emit('insertResponse', response.content)"
        >
          <span
            class="i-lucide-file-text mt-1 size-5 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />
          <span class="min-w-0"
            ><strong class="block truncate text-sm text-n-slate-12">{{
              response.short_code
            }}</strong
            ><span class="line-clamp-2 text-xs text-n-slate-11">{{
              response.content
            }}</span></span
          >
        </button>
      </div>
      <p class="mb-0 mt-3 text-xs text-n-slate-11">
        {{ t('JRC_HOME.COMPOSE.TEMPLATE_HINT') }}
      </p>
    </section>
    <section class="rounded-xl border border-n-weak bg-n-solid-2 p-4">
      <h3 class="mb-2 text-sm font-semibold text-n-slate-12">
        {{
          t(
            'COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_OPTIONS.TEMPLATE_PARSER.VARIABLES'
          )
        }}
      </h3>
      <p class="mb-0 text-xs leading-5 text-n-slate-11">
        {{ t('JRC_HOME.COMPOSE.VARIABLE_HINT') }}
      </p>
    </section>
  </aside>
</template>
