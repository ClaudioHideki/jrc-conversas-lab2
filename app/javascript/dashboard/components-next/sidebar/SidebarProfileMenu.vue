<script setup>
import { computed } from 'vue';
import Auth from 'dashboard/api/auth';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import SidebarProfileMenuStatus from './SidebarProfileMenuStatus.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useImpersonation } from 'dashboard/composables/useImpersonation';

import {
  DropdownContainer,
  DropdownBody,
  DropdownSeparator,
  DropdownItem,
} from 'next/dropdown-menu/base';
import CustomBrandPolicyWrapper from '../../components/CustomBrandPolicyWrapper.vue';

defineProps({
  isCollapsed: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'openKeyShortcutModal']);

defineOptions({
  inheritAttrs: false,
});

const { t } = useI18n();

const currentUser = useMapGetter('getCurrentUser');
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const accountId = useMapGetter('getCurrentAccountId');
const globalConfig = useMapGetter('globalConfig/get');
const { isImpersonating, impersonationReturnTo } = useImpersonation();
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const showChatSupport = computed(() => {
  return (
    isFeatureEnabledonAccount.value(
      accountId.value,
      FEATURE_FLAGS.CONTACT_CHATWOOT_SUPPORT_TEAM
    ) && globalConfig.value.chatwootInboxToken
  );
});

const toggleChatSupport = () => {
  if (window.$chatwoot) {
    window.$chatwoot.toggle();
  }
};

const returnToSuperAdmin = () => {
  Auth.logoutAndRedirect(impersonationReturnTo.value);
};

const menuItems = computed(() => {
  return [
    {
      show: isImpersonating.value,
      showOnCustomBrandedInstance: true,
      label: 'Voltar ao Super Admin',
      icon: 'i-lucide-arrow-left-to-line',
      click: returnToSuperAdmin,
    },
    {
      show: showChatSupport.value,
      showOnCustomBrandedInstance: false,
      label: t('SIDEBAR_ITEMS.CONTACT_SUPPORT'),
      icon: 'i-lucide-life-buoy',
      click: toggleChatSupport,
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.KEYBOARD_SHORTCUTS'),
      icon: 'i-lucide-keyboard',
      click: () => {
        emit('openKeyShortcutModal');
      },
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.PROFILE_SETTINGS'),
      icon: 'i-lucide-user-pen',
      link: { name: 'profile_settings_index' },
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.APPEARANCE'),
      icon: 'i-lucide-palette',
      click: () => {
        const ninja = document.querySelector('ninja-keys');
        ninja.open({ parent: 'appearance_settings' });
      },
    },
    {
      show: currentUser.value.type === 'SuperAdmin',
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.SUPER_ADMIN_CONSOLE'),
      icon: 'i-lucide-castle',
      link: '/super_admin',
      nativeLink: true,
      target: '_blank',
    },
    {
      show: true,
      showOnCustomBrandedInstance: true,
      label: t('SIDEBAR_ITEMS.LOGOUT'),
      icon: 'i-lucide-power',
      click: Auth.logout,
    },
  ];
});

const allowedMenuItems = computed(() => {
  return menuItems.value.filter(item => item.show);
});
</script>

<template>
  <DropdownContainer
    class="relative min-w-0"
    :class="isCollapsed ? 'w-auto' : 'w-full'"
    @close="emit('close')"
  >
    <template #trigger="{ toggle, isOpen }">
      <button
        class="flex min-h-14 gap-3 items-center border border-white/15 bg-white/5 px-3 py-2.5 text-left rounded-xl cursor-pointer transition hover:bg-white/10 hover:border-white/25"
        :class="[
          { 'bg-white/10': isOpen },
          isCollapsed ? 'justify-center' : 'w-full',
        ]"
        :title="isCollapsed ? currentUser.available_name : undefined"
        @click="toggle"
      >
        <Avatar
          :size="32"
          :name="currentUser.available_name"
          :src="currentUser.avatar_url"
          :status="currentUserAvailability"
          class="flex-shrink-0"
        />
        <div v-if="!isCollapsed" class="min-w-0 flex-1">
          <div
            class="text-sm font-semibold leading-4 truncate !text-sidebar-foreground"
          >
            {{ currentUser.available_name }}
          </div>
          <div class="text-xs truncate !text-sidebar-secondary">
            {{ currentUser.email }}
          </div>
        </div>
        <span
          v-if="!isCollapsed"
          class="i-lucide-chevron-right size-4 flex-shrink-0 text-white/65 transition-transform"
          :class="{ 'rotate-90': isOpen }"
        />
      </button>
    </template>
    <DropdownBody
      class="bottom-[4.5rem] z-50 w-[276px] ltr:left-0 rtl:right-0 [&>ul]:!gap-1 [&>ul]:!rounded-2xl [&>ul]:!border-[#d8e4f0] [&>ul]:!bg-white [&>ul]:!p-2 [&>ul]:!text-[#173a5e] [&>ul]:!shadow-[0_24px_70px_rgba(2,31,62,0.28)] [&>ul]:!backdrop-blur-none [&_.n-dropdown-item>*]:!text-[#173a5e] [&_.n-dropdown-item_svg]:!text-[#526b85]"
    >
      <div class="mb-1 flex items-center gap-3 rounded-xl bg-[#f1f7fd] p-3">
        <Avatar
          :size="36"
          :name="currentUser.available_name"
          :src="currentUser.avatar_url"
          :status="currentUserAvailability"
          class="flex-shrink-0"
        />
        <div class="min-w-0 flex-1">
          <p class="truncate text-sm font-semibold text-[#082b52]">
            {{ currentUser.available_name }}
          </p>
          <p class="truncate text-xs text-n-slate-10">
            {{ currentUser.email }}
          </p>
        </div>
      </div>
      <SidebarProfileMenuStatus />
      <DropdownSeparator />
      <template v-for="item in allowedMenuItems" :key="item.label">
        <CustomBrandPolicyWrapper
          :show-on-custom-branded-instance="item.showOnCustomBrandedInstance"
        >
          <DropdownItem
            v-if="item.show"
            v-bind="item"
            class="!rounded-xl !px-3 !py-2.5 !text-[#173a5e] transition-colors hover:!bg-[#edf5fd] [&_svg]:!text-[#526b85]"
          />
        </CustomBrandPolicyWrapper>
      </template>
    </DropdownBody>
  </DropdownContainer>
</template>
