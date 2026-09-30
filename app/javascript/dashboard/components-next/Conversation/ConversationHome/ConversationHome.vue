<script setup>
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';
import CreateNewContactDialog from 'dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue';
import ConversationQuickActions from './ConversationQuickActions.vue';
import { useConversationHome } from './useConversationHome';
import { homeMetrics, homeTones } from './presentation';

const { t, locale } = useI18n();
const avatarUrl = '/brand-assets/jrc-copilot-avatar.png';
const emit = defineEmits(['navigate']);
const router = useRouter();
const store = useStore();
const home = useConversationHome();
const { actions, user, summary, crmAllowed, failed, loading, generatedAt } =
  home;
const { openQuick, openWithPrompt } = useJrcCopilot();
const prompt = ref('');
const contactDialog = ref(null);
const canCreateContact = computed(() =>
  actions.value.some(action => action.key === 'CONTACT')
);
const contactDialogKey = computed(
  () => `${home.accountId.value}:${home.userId.value}`
);
watch(contactDialogKey, () => {
  prompt.value = '';
});
const firstName = computed(
  () => user.value?.name?.split(' ')[0] || t('JRC_HOME.USER')
);
const cards = computed(() => homeMetrics(summary.value, crmAllowed.value));
const formatCount = value =>
  value === null
    ? '—'
    : new Intl.NumberFormat(locale.value.replace('_', '-')).format(value);
const openNico = () => {
  emit('navigate');
  openQuick();
};
const activate = key => {
  // Re-evaluate access at the instant of the click, including revocation/account changes.
  const action = actions.value.find(item => item.key === key);
  if (!action) return;
  if (action.command === 'contact') contactDialog.value?.dialogRef.open();
  else if (action.command === 'nico') openNico();
  else {
    emit('navigate');
    router.push(action.to);
  }
};
const createContact = async contact => {
  if (!canCreateContact.value) return;
  const identity = contactDialogKey.value;
  try {
    await store.dispatch('contacts/create', contact);
    if (identity !== contactDialogKey.value) return;
    contactDialog.value?.onSuccess();
    useAlert(
      t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.SUCCESS_MESSAGE')
    );
  } catch {
    if (identity === contactDialogKey.value)
      useAlert(t('JRC_HOME.CONTACT_ERROR'));
  }
};
const ask = text => {
  if (!text.trim()) return;
  emit('navigate');
  openWithPrompt(text.trim());
  prompt.value = '';
};
const suggestedPrompts = computed(() => [
  t('JRC_HOME.PROMPT_SUMMARY'),
  t('JRC_HOME.PROMPT_GUIDE'),
]);
</script>

<template>
  <section
    class="flex h-full min-h-0 w-full min-w-0 flex-col-reverse overflow-hidden bg-n-surface-1 xl:flex-row"
    :aria-label="t('JRC_HOME.TITLE')"
  >
    <main
      class="min-h-0 min-w-0 flex-1 overflow-y-auto overscroll-contain p-4 pb-24 sm:p-6 sm:pb-24"
    >
      <header
        class="flex flex-wrap items-center justify-between gap-4 rounded-2xl bg-gradient-to-br from-n-blue-2 via-n-solid-2 to-n-violet-2 p-5 sm:p-6"
      >
        <div class="min-w-0 flex-1 basis-64">
          <p
            class="text-xs font-semibold uppercase tracking-widest text-n-slate-11"
          >
            {{ t('JRC_HOME.GREETING', { name: firstName }) }}
          </p>
          <h1
            class="mt-3 text-2xl font-bold leading-tight text-n-slate-12 2xl:text-3xl"
          >
            <span class="text-n-blue-11">NICO</span>
            {{ t('JRC_HOME.HEADLINE') }}
          </h1>
          <p class="mt-3 text-sm text-n-slate-11">{{ t('JRC_HOME.INTRO') }}</p>
        </div>
        <button
          type="button"
          class="mx-auto flex shrink-0 flex-col items-center rounded-2xl p-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="t('JRC_HOME.ACTIONS.NICO')"
          @click="openNico"
        >
          <img
            :src="avatarUrl"
            alt=""
            class="size-24 object-contain 2xl:size-32"
          />
          <span class="font-bold text-n-blue-11">NICO</span>
        </button>
      </header>

      <div class="mb-3 mt-5 flex flex-wrap items-center justify-between gap-2">
        <p class="m-0 text-xs text-n-slate-11">
          {{ t('JRC_HOME.METRIC_SCOPE') }}
        </p>
        <button
          type="button"
          :disabled="loading"
          class="flex min-h-9 items-center gap-1 rounded-lg px-2 text-xs font-semibold text-n-blue-11 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-wait disabled:text-n-slate-11"
          @click="home.refresh"
        >
          <span class="i-lucide-refresh-cw size-3.5" aria-hidden="true" />{{
            t(loading ? 'JRC_HOME.LOADING' : 'JRC_HOME.REFRESH')
          }}
        </button>
      </div>
      <p
        v-if="failed"
        role="status"
        class="rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
      >
        {{ t('JRC_HOME.METRIC_ERROR') }}
      </p>
      <div
        class="grid grid-cols-1 gap-3 min-[480px]:grid-cols-2 2xl:grid-cols-4"
        :aria-busy="loading"
      >
        <article
          v-for="card in cards"
          :key="card.key"
          class="rounded-2xl border bg-n-solid-2 p-4 shadow-sm"
          :class="
            card.value === null
              ? 'border-n-weak'
              : homeTones[card.tone].split(' ')[0]
          "
        >
          <div class="flex items-center gap-3">
            <span
              class="grid size-10 shrink-0 place-content-center rounded-xl border"
              :class="homeTones[card.value === null ? 'neutral' : card.tone]"
              ><span :class="card.icon" class="size-5" aria-hidden="true"
            /></span>
            <strong
              class="text-3xl font-bold"
              :class="
                homeTones[card.value === null ? 'neutral' : card.tone].split(
                  ' '
                )[2]
              "
              >{{ formatCount(card.value) }}</strong
            >
          </div>
          <p class="mb-3 mt-3 text-sm font-medium text-n-slate-12">
            {{ t(`JRC_HOME.METRICS.${card.key}`) }}
          </p>
          <span
            class="inline-block rounded-full border px-2 py-1 text-xs font-medium"
            :class="homeTones[card.value === null ? 'neutral' : card.tone]"
            >{{
              t(
                card.value === null
                  ? 'JRC_HOME.UNAVAILABLE'
                  : 'JRC_HOME.AUTHORIZED_DATA'
              )
            }}</span
          >
        </article>
      </div>
      <p v-if="generatedAt" class="mt-2 text-xs text-n-slate-11">
        {{ t('JRC_HOME.SNAPSHOT') }}
      </p>

      <section class="mt-6 border-t border-n-weak pt-5">
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{ t('JRC_HOME.NEXT_ACTION') }}
        </h2>
        <div class="my-4 grid gap-3 sm:grid-cols-2">
          <button
            v-for="suggestion in suggestedPrompts"
            :key="suggestion"
            type="button"
            class="flex items-center gap-3 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4 text-left text-sm text-n-slate-12 transition hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="ask(suggestion)"
          >
            <span
              class="i-lucide-sparkles size-5 shrink-0 text-n-blue-11"
              aria-hidden="true"
            />{{ suggestion }}
          </button>
        </div>
        <form
          class="flex items-center gap-2 rounded-2xl border border-n-blue-6 bg-n-solid-2 p-2 focus-within:ring-2 focus-within:ring-n-blue-7"
          @submit.stop.prevent="ask(prompt)"
        >
          <label class="sr-only" for="jrc-home-prompt">{{
            t('JRC_HOME.PROMPT_LABEL')
          }}</label>
          <input
            id="jrc-home-prompt"
            v-model="prompt"
            class="min-w-0 flex-1 !border-0 !bg-transparent !shadow-none !ring-0 text-n-slate-12"
            :placeholder="t('JRC_HOME.PROMPT_PLACEHOLDER')"
          />
          <button
            type="submit"
            :disabled="!prompt.trim()"
            :aria-label="t('JRC_HOME.SEND')"
            class="grid size-11 shrink-0 place-content-center rounded-xl bg-n-brand text-white hover:enabled:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:bg-n-slate-3 disabled:text-n-slate-11"
          >
            <span class="i-lucide-send size-5" aria-hidden="true" />
          </button>
        </form>
        <p class="mt-2 text-xs text-n-slate-11">
          {{ t('JRC_HOME.NICO_HELP') }}
        </p>
      </section>
    </main>
    <ConversationQuickActions :actions="actions" @select="activate" />
    <CreateNewContactDialog
      v-if="canCreateContact"
      :key="contactDialogKey"
      ref="contactDialog"
      @create="createContact"
    />
  </section>
</template>
