<script setup>
import { computed, nextTick, ref, useId, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import PauseCatalogEditor from './PauseCatalogEditor.vue';
import RoutingDraftWorkspace from './RoutingDraftWorkspace.vue';
import AgentStateHistory from './AgentStateHistory.vue';
import SupervisorPage from '../views/SupervisorPage.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const emit = defineEmits(['changed']);
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const id = useId();
const currentUser = useMapGetter('getCurrentUser');
const history = ref(null);
const tabs = computed(() => {
  const rights = props.context.capabilities || {};
  return [
    { key: 'motives', permission: rights.configure },
    { key: 'distribution', permission: rights.configure },
    { key: 'availability', permission: rights.supervise },
    { key: 'history', permission: rights.control },
  ].filter(tab => tab.permission === true);
});
const selected = computed(() => {
  const key = route.query.pauses_tab;
  return tabs.value.some(tab => tab.key === key) ? key : tabs.value[0]?.key;
});
const authorityKey = computed(() => {
  const member = currentUser.value?.accounts?.find(
    row => String(row.id) === String(props.accountId)
  );
  return JSON.stringify([
    String(props.accountId),
    currentUser.value?.id,
    currentUser.value?.type,
    accountMembershipAccess(member),
    props.context.capabilities,
    props.context.units,
  ]);
});
watch(
  [selected, authorityKey],
  async () => {
    const key = authorityKey.value;
    if (selected.value !== 'history') return;
    await nextTick();
    if (selected.value === 'history' && authorityKey.value === key)
      history.value?.open();
  },
  { immediate: true, flush: 'post' }
);
const select = key => {
  if (!tabs.value.some(tab => tab.key === key)) return;
  router.replace({
    query: {
      ...route.query,
      pauses_tab: key === 'motives' ? undefined : key,
    },
  });
};
const navigate = (event, index) => {
  const last = tabs.value.length - 1;
  const next = {
    ArrowRight: (index + 1) % tabs.value.length,
    ArrowLeft: (index + last) % tabs.value.length,
    Home: 0,
    End: last,
  }[event.key];
  if (next === undefined) return;
  event.preventDefault();
  select(tabs.value[next].key);
  event.currentTarget.parentElement
    .querySelectorAll('[role="tab"]')
    [next]?.focus();
};
const labels = computed(() => ({
  title: t('JRC_CONTACT_CENTER.PAUSE_WORKSPACE.TITLE'),
  motives: t('JRC_CONTACT_CENTER.PAUSE_WORKSPACE.MOTIVES'),
  distribution: t('JRC_CONTACT_CENTER.PAUSE_WORKSPACE.DISTRIBUTION'),
  availability: t('JRC_CONTACT_CENTER.PAUSE_WORKSPACE.AVAILABILITY'),
  history: t('JRC_CONTACT_CENTER.PAUSE_WORKSPACE.HISTORY'),
  denied: t('JRC_CONTACT_CENTER.PAUSE_WORKSPACE.DENIED'),
}));
</script>

<template>
  <section class="min-w-0 space-y-4" data-pause-workspace>
    <nav
      class="flex min-w-0 flex-wrap gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-2"
      role="tablist"
      :aria-label="labels.title"
    >
      <button
        v-for="(tab, index) in tabs"
        :id="`${id}-${tab.key}`"
        :key="tab.key"
        type="button"
        role="tab"
        :aria-selected="selected === tab.key"
        :tabindex="selected === tab.key ? 0 : -1"
        :aria-controls="`${id}-panel`"
        :data-pause-workspace-tab="tab.key"
        class="min-w-0 flex-1 basis-36 rounded-lg border border-n-blue-6 px-3 py-2 text-sm font-medium focus-visible:ring-2 focus-visible:ring-n-blue-7"
        :class="
          selected === tab.key
            ? 'bg-n-brand text-white'
            : 'bg-n-blue-2 text-n-blue-11'
        "
        @click="select(tab.key)"
        @keydown="navigate($event, index)"
      >
        {{ labels[tab.key] }}
      </button>
    </nav>
    <div
      v-if="selected"
      :id="`${id}-panel`"
      :key="`${authorityKey}:${selected}`"
      role="tabpanel"
      :aria-labelledby="`${id}-${selected}`"
      class="min-w-0"
      data-pause-workspace-panel
    >
      <PauseCatalogEditor
        v-if="selected === 'motives'"
        :account-id="accountId"
        :context="context"
        @changed="emit('changed')"
      />
      <RoutingDraftWorkspace
        v-else-if="selected === 'distribution'"
        :account-id="accountId"
        :context="context"
      />
      <SupervisorPage v-else-if="selected === 'availability'" />
      <AgentStateHistory
        v-else-if="selected === 'history'"
        ref="history"
        :account-id="accountId"
        :context="context"
      />
    </div>
    <p v-else role="alert" class="text-sm text-n-ruby-11">
      {{ labels.denied }}
    </p>
  </section>
</template>
