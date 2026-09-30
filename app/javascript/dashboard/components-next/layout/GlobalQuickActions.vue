<script setup>
import { computed, ref, watch } from 'vue';
import {
  useRoute,
  useRouter,
  isNavigationFailure,
  NavigationFailureType,
} from 'vue-router';
import { useEventBus } from '@vueuse/core';
import { quickActionTarget } from './useQuickActionTarget';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';
import JrcCopilotLauncher from 'dashboard/components-next/jrcCopilot/JrcCopilotLauncher.vue';
import CreateNewContactDialog from 'dashboard/components-next/Contacts/ContactsForm/CreateNewContactDialog.vue';
import ConversationQuickActions from 'dashboard/components-next/Conversation/ConversationHome/ConversationQuickActions.vue';
import { useQuickActionAccess } from './useQuickActionAccess';

defineProps({ callActive: { type: Boolean, default: false } });
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const quickActionEvents = useEventBus(quickActionTarget);
const { actions, accountId, userId } = useQuickActionAccess();
const { openQuick } = useJrcCopilot();
const expanded = ref(false);
const toggle = ref(null);
const contactDialog = ref(null);
const canCreateContact = computed(() =>
  actions.value.some(action => action.key === 'CONTACT')
);
const contactDialogKey = computed(() => `${accountId.value}:${userId.value}`);
watch([() => route.fullPath, contactDialogKey], () => {
  expanded.value = false;
});
const openNico = () => {
  expanded.value = false;
  openQuick();
};
const collapse = () => {
  expanded.value = false;
  toggle.value?.focus({ preventScroll: true });
};
const activate = async key => {
  // Re-evaluate access at the instant of the click, including revocation/account changes.
  const action = actions.value.find(item => item.key === key);
  if (!action) return;
  expanded.value = false;
  if (action.command === 'contact') contactDialog.value?.dialogRef.open();
  else if (action.command === 'nico') openNico();
  else {
    const alreadyOnTarget = route.name === action.to.name;
    const identity = contactDialogKey.value;
    const failure = await router.push(action.to);
    if (
      alreadyOnTarget &&
      identity === contactDialogKey.value &&
      actions.value.some(item => item.key === key) &&
      (!failure ||
        isNavigationFailure(failure, NavigationFailureType.duplicated))
    ) {
      quickActionEvents.emit({
        name: action.to.name,
        accountId: accountId.value,
      });
    }
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
</script>

<template>
  <aside
    data-global-quick-actions
    :aria-label="t('JRC_HOME.QUICK_ACTIONS')"
    class="relative flex min-h-0 shrink-0 flex-col border-t border-n-weak bg-n-solid-2 lg:w-16 lg:border-s lg:border-t-0 xl:w-24"
    @keydown.esc.stop="collapse"
  >
    <ConversationQuickActions
      id="global-quick-actions-list"
      :actions="actions"
      :class="expanded ? 'grid lg:flex' : 'hidden lg:flex'"
      @select="activate"
    />
    <div
      class="flex shrink-0 items-center justify-between gap-2 px-3 py-2 lg:mt-auto lg:justify-center lg:px-1"
    >
      <button
        ref="toggle"
        type="button"
        class="flex min-h-11 items-center gap-2 rounded-xl border border-n-blue-6 bg-n-blue-2 px-3 text-sm font-semibold text-n-blue-11 hover:bg-n-blue-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand lg:hidden"
        :aria-expanded="expanded"
        aria-controls="global-quick-actions-list"
        @click="expanded = !expanded"
      >
        <span class="i-lucide-zap size-5" aria-hidden="true" />
        {{ t('JRC_HOME.QUICK_ACTIONS') }}
        <span
          :class="expanded ? 'i-lucide-chevron-down' : 'i-lucide-chevron-up'"
          class="size-4"
          aria-hidden="true"
        />
      </button>
      <JrcCopilotLauncher docked :call-active="callActive" />
    </div>
    <CreateNewContactDialog
      v-if="canCreateContact"
      :key="contactDialogKey"
      ref="contactDialog"
      @create="createContact"
    />
  </aside>
</template>
