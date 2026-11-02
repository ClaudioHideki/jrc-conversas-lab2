<script setup>
import { computed } from 'vue';
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { provideServiceDesk } from './composables/useServiceDesk';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from './routeDefinitions';
import { screenAccessible, landingScreen } from './helpers/nativeIntegration';
import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import ServiceDeskState from './components/ServiceDeskState.vue';
import ScreenGuidance from './components/ScreenGuidance.vue';
import WriteFeedback from './components/WriteFeedback.vue';
import './serviceDesk.css';
import { crmControlClasses } from '../crm/crmControlClasses';
const { t, tm } = useI18n();
const route = useRoute();
const router = useRouter();
const session = provideServiceDesk();
const { state, enabled, accountId, userId } = session;
const groups = ['operation', 'governance', 'management'];
const screenLabels = computed(() => ({
  ...tm('JRC_SERVICE_DESK.SCREENS'),
  policies: t('JRC_SERVICE_DESK.EXPERIENCE.manage_policies'),
}));
const primaryKeys = [
  'overview',
  'tickets',
  'mine',
  'sla',
  'assignees',
  'reports',
];
const primaryEntries = computed(() =>
  primaryKeys
    .map(key => SERVICE_DESK_ROUTES.find(item => item.key === key))
    .filter(item => screenAccessible(state.context, item))
    .map(item => ({
      ...item,
      label: screenLabels.value[item.key],
    }))
);
const groupLabels = computed(() => ({
  operation: t('JRC_SERVICE_DESK.GROUPS.operation'),
  governance: t('JRC_SERVICE_DESK.GROUPS.governance'),
  management: t('JRC_SERVICE_DESK.GROUPS.management'),
}));
const activeScreen = computed(() => route.meta.serviceDeskScreen || 'overview');
const entries = group =>
  SERVICE_DESK_ROUTES.filter(
    item =>
      item.group === group &&
      !primaryKeys.includes(item.key) &&
      screenAccessible(state.context, item)
  );
const to = key => ({
  name: serviceDeskRouteName(key),
  params: { accountId: accountId.value },
});
const screenAllowed = computed(() =>
  screenAccessible(
    state.context,
    SERVICE_DESK_ROUTES.find(item => item.key === activeScreen.value)
  )
);
const breadcrumbs = computed(() => {
  const landing = landingScreen(state.context);
  const items = [
    { label: t('JRC_SERVICE_DESK.MODULE'), route: landing && to(landing) },
  ];
  if (['detail', 'edit'].includes(activeScreen.value))
    items.push({
      label: t('JRC_SERVICE_DESK.SCREENS.tickets'),
      route: to('tickets'),
    });
  items.push({ label: screenLabels.value[activeScreen.value] });
  return items;
});
const blocked = computed(() =>
  ['denied', 'unauthenticated', 'invalid_contract', 'disabled'].includes(
    state.status
  )
);
</script>

<template>
  <div
    class="jrc-service-desk-root flex flex-1 min-w-0 min-h-0 !flex-col"
    :class="crmControlClasses"
    data-testid="jrc-service-desk"
  >
    <template v-if="enabled">
      <main
        :key="`${accountId}:${userId}`"
        class="flex-1 min-h-0 min-w-0 overflow-auto p-4 xl:p-5"
      >
        <Breadcrumb
          v-if="state.status === 'ready'"
          :items="breadcrumbs"
          @click="item => item.route && router.push(item.route)"
        />
        <nav
          v-if="
            state.status === 'ready' &&
            !['detail', 'edit', 'new'].includes(activeScreen)
          "
          class="relative z-20 mb-4 flex flex-wrap items-center gap-1 rounded-xl border border-n-weak bg-n-solid-1 p-1.5"
          :aria-label="t('JRC_SERVICE_DESK.REDESIGN_LIST.navigation')"
        >
          <RouterLink
            v-for="item in primaryEntries"
            :key="item.key"
            :to="to(item.key)"
            class="flex items-center gap-2 rounded-lg border-b-2 px-3 py-2.5 text-xs font-medium focus-visible:ring-2 focus-visible:ring-n-blue-9"
            :class="
              activeScreen === item.key
                ? 'border-n-blue-9 bg-n-blue-3 text-n-blue-11'
                : 'border-transparent text-n-slate-11 hover:bg-n-slate-2'
            "
            :aria-current="activeScreen === item.key ? 'page' : undefined"
          >
            <Icon :icon="item.icon" class="size-4 shrink-0" />
            {{ item.label }}
          </RouterLink>
          <details
            v-for="group in groups.filter(value => entries(value).length)"
            :key="group"
            class="static xl:relative"
          >
            <summary
              class="cursor-pointer rounded-lg px-3 py-2.5 text-xs font-medium text-n-slate-11 focus-visible:ring-2 focus-visible:ring-n-blue-9"
            >
              {{ groupLabels[group] }}
            </summary>
            <div
              class="absolute inset-x-0 top-full z-30 mt-1 grid max-h-80 gap-1 overflow-y-auto rounded-xl border border-n-weak bg-n-solid-1 p-2 shadow-lg xl:left-auto xl:right-0 xl:min-w-52"
            >
              <RouterLink
                v-for="item in entries(group)"
                :key="item.key"
                :to="to(item.key)"
                class="flex items-center gap-2 rounded-lg px-3 py-2 text-xs hover:bg-n-blue-2"
                :class="
                  activeScreen === item.key
                    ? 'bg-n-blue-3 font-semibold text-n-blue-11'
                    : 'text-n-slate-11'
                "
                :aria-current="activeScreen === item.key ? 'page' : undefined"
                @click="
                  $event.currentTarget
                    .closest('details')
                    .removeAttribute('open')
                "
              >
                <Icon :icon="item.icon" class="size-4 shrink-0" />{{
                  screenLabels[item.key]
                }}
              </RouterLink>
            </div>
          </details>
        </nav>
        <div
          v-if="state.status !== 'ready' && !blocked"
          class="sd-context-notice"
        >
          <span>
            {{ t('JRC_SERVICE_DESK.SCOPE.contract_pending') }}
          </span>
          <Button
            :label="t('JRC_SERVICE_DESK.COMMON.retry')"
            size="xs"
            variant="ghost"
            :disabled="state.status === 'loading'"
            @click="session.retry()"
          />
        </div>
        <WriteFeedback
          v-if="session.operations.state.notice"
          :status="session.operations.state.notice"
        />
        <ServiceDeskState
          v-if="blocked"
          :status="state.status"
          retry
          @retry="session.retry()"
        />
        <ServiceDeskState
          v-else-if="state.status !== 'ready'"
          :status="state.status"
          retry
          @retry="session.retry()"
        />
        <ServiceDeskState v-else-if="!screenAllowed" status="denied" />
        <template v-else>
          <RouterView :key="`${accountId}:${userId}:${activeScreen}`" />
          <ScreenGuidance
            v-if="!['detail', 'edit', 'new'].includes(activeScreen)"
            :screen="activeScreen"
            class="mt-4"
          />
        </template>
      </main>
    </template>
    <ServiceDeskState v-else status="disabled" />
  </div>
</template>
