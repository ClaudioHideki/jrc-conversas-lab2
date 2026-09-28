<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import SoftphoneDownload from './SoftphoneDownload.vue';

import Avatar from 'next/avatar/Avatar.vue';
import SidebarNotificationBell from 'dashboard/components-next/sidebar/SidebarNotificationBell.vue';
import SidebarProfileMenuStatus from 'dashboard/components-next/sidebar/SidebarProfileMenuStatus.vue';
import { DropdownContainer, DropdownBody } from 'next/dropdown-menu/base';

const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const searchShortcut = useKbd([`$mod`, 'k']);
const SEARCH_PLACEHOLDER = 'Pesquisar conversas, contatos ou mensagens...';

const currentUser = useMapGetter('getCurrentUser');
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');

const availability = computed(() => {
  const statuses = {
    online: { label: 'Disponível', color: 'bg-n-teal-9' },
    offline: { label: 'Indisponível', color: 'bg-n-slate-9' },
    meeting: { label: 'Reunião', color: 'bg-n-blue-9' },
    feedback: { label: 'Feedback', color: 'bg-n-violet-9' },
    end_shift: { label: 'Fim do turno', color: 'bg-n-gray-9' },
    training: { label: 'Treinamento', color: 'bg-n-purple-9' },
    bathroom_break: { label: 'Pausa banheiro', color: 'bg-n-cyan-9' },
    lunch_break: { label: 'Pausa almoço', color: 'bg-n-amber-9' },
    manual_call: { label: 'Chamada Manual', color: 'bg-n-rose-9' },
  };

  return statuses[currentUserAvailability.value] || statuses.offline;
});
</script>

<template>
  <header
    class="hidden md:flex h-[78px] flex-shrink-0 items-center justify-between gap-8 border-b border-n-weak bg-n-solid-1 px-7"
  >
    <RouterLink
      :to="{ name: 'search' }"
      class="group flex h-12 w-full max-w-3xl items-center gap-3 rounded-xl border border-n-weak bg-n-surface-1 px-4 shadow-sm transition hover:border-n-blue-7 hover:shadow"
    >
      <span
        class="i-lucide-search size-5 flex-shrink-0 text-n-slate-10 group-hover:text-n-brand"
      />
      <span class="flex-1 truncate text-sm text-n-slate-10">
        {{ SEARCH_PLACEHOLDER }}
      </span>
      <kbd
        class="rounded-md border border-n-weak bg-n-solid-2 px-2 py-0.5 text-xs text-n-slate-10"
      >
        {{ searchShortcut }}
      </kbd>
    </RouterLink>

    <div class="flex flex-shrink-0 items-center gap-3">
      <DropdownContainer>
        <template #trigger="{ toggle, isOpen }">
          <button
            type="button"
            class="flex h-10 items-center gap-2 rounded-full border border-n-weak bg-n-surface-1 px-4 text-sm font-medium text-n-slate-12 transition hover:bg-n-alpha-1"
            :class="{ 'bg-n-alpha-1': isOpen }"
            @click="toggle"
          >
            <span class="size-2.5 rounded-full" :class="availability.color" />
            <span>{{ availability.label }}</span>
            <span class="i-lucide-chevron-down size-4 text-n-slate-10" />
          </button>
        </template>
        <DropdownBody class="z-50 mt-2 min-w-80 ltr:right-0 rtl:left-0">
          <SidebarProfileMenuStatus />
        </DropdownBody>
      </DropdownContainer>

      <SoftphoneDownload />

      <SidebarNotificationBell
        class="!size-10 !rounded-full !border !border-n-weak hover:!bg-n-alpha-1"
        @open-notification-panel="
          $router.push(accountScopedRoute('notifications_index'))
        "
      />

      <RouterLink
        :to="
          accountScopedRoute('portals_index', {
            navigationPath: 'portals_articles_index',
          })
        "
        class="grid size-10 place-items-center rounded-full text-n-slate-11 transition hover:bg-n-alpha-1 hover:text-n-brand"
        :title="t('SIDEBAR.HELP_CENTER.TITLE')"
      >
        <span class="i-lucide-circle-help size-5" />
      </RouterLink>

      <RouterLink
        :to="accountScopedRoute('profile_settings_index')"
        class="rounded-full outline outline-2 outline-transparent transition hover:outline-n-brand/30"
        :title="t('SIDEBAR.PROFILE_SETTINGS')"
      >
        <Avatar
          :size="40"
          :name="currentUser.available_name"
          :src="currentUser.avatar_url"
        />
      </RouterLink>
    </div>
  </header>
</template>
