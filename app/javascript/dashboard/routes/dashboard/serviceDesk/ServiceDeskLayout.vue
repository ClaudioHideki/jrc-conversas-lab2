<script setup>
import { computed, ref } from 'vue';
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
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const session = provideServiceDesk();
const { state, enabled, accountId, userId } = session;
const groups = ['operation', 'governance', 'management'];
const groupLabels = computed(() => ({
  operation: t('JRC_SERVICE_DESK.GROUPS.operation'),
  governance: t('JRC_SERVICE_DESK.GROUPS.governance'),
  management: t('JRC_SERVICE_DESK.GROUPS.management'),
}));
const activeScreen = computed(() => route.meta.serviceDeskScreen || 'overview');
const navigationExpanded = ref(true);
const mobileNavigationOpen = ref(false);
const entries = group =>
  SERVICE_DESK_ROUTES.filter(
    item => item.group === group && screenAccessible(state.context, item)
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
  items.push({ label: t(`JRC_SERVICE_DESK.SCREENS.${activeScreen.value}`) });
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
      <header
        class="flex shrink-0 items-center gap-3 border-b border-n-weak bg-n-solid-1 px-4 py-2.5"
      >
        <Button
          class="hidden lg:inline-flex"
          variant="ghost"
          size="sm"
          icon="i-lucide-panel-left"
          :aria-label="
            t(
              navigationExpanded
                ? 'JRC_SERVICE_DESK.REDESIGN_LIST.collapse_navigation'
                : 'JRC_SERVICE_DESK.REDESIGN_LIST.expand_navigation'
            )
          "
          :aria-expanded="navigationExpanded"
          aria-controls="service-desk-navigation"
          @click="navigationExpanded = !navigationExpanded"
        />
        <Button
          class="lg:hidden"
          variant="ghost"
          size="sm"
          icon="i-lucide-menu"
          :aria-label="t('JRC_SERVICE_DESK.REDESIGN_LIST.navigation')"
          :aria-expanded="mobileNavigationOpen"
          aria-controls="service-desk-navigation"
          @click="mobileNavigationOpen = !mobileNavigationOpen"
        />
        <Icon icon="i-lucide-headset" class="size-5 text-n-blue-11" />
        <h1 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t('JRC_SERVICE_DESK.MODULE') }}
        </h1>
        <span class="ml-auto hidden text-xs text-n-slate-11 md:block">{{
          t('JRC_SERVICE_DESK.REDESIGN_LIST.workspace')
        }}</span>
      </header>
      <div class="flex flex-1 min-h-0 min-w-0 flex-col lg:flex-row">
        <aside
          id="service-desk-navigation"
          class="w-full shrink-0 flex-col border-b border-n-weak bg-n-solid-1 lg:w-44 lg:border-b-0 lg:border-r"
          :class="[
            mobileNavigationOpen ? 'flex' : 'hidden',
            navigationExpanded ? 'lg:flex' : 'lg:hidden',
          ]"
          :aria-label="t('JRC_SERVICE_DESK.REDESIGN_LIST.navigation')"
        >
          <nav class="max-h-64 overflow-y-auto p-2 lg:max-h-none">
            <section
              v-for="group in groups.filter(value => entries(value).length)"
              :key="group"
              class="mb-3"
            >
              <h2
                class="mb-1 px-2 pt-2 text-[10px] font-semibold uppercase tracking-wider text-n-slate-11"
              >
                {{ groupLabels[group] }}
              </h2>
              <RouterLink
                v-for="item in entries(group)"
                :key="item.key"
                :to="to(item.key)"
                class="mb-0.5 flex items-center gap-2 rounded-lg px-2 py-2 text-xs focus-visible:ring-2 focus-visible:ring-n-blue-9"
                :class="
                  activeScreen === item.key ||
                  (item.key === 'tickets' &&
                    ['detail', 'edit'].includes(activeScreen))
                    ? 'bg-n-blue-3 font-semibold text-n-blue-11'
                    : 'text-n-slate-11 hover:bg-n-slate-3'
                "
                :aria-current="activeScreen === item.key ? 'page' : undefined"
                @click="mobileNavigationOpen = false"
              >
                <Icon :icon="item.icon" class="size-4 shrink-0" />
                <span>{{ t(`JRC_SERVICE_DESK.SCREENS.${item.key}`) }}</span>
              </RouterLink>
            </section>
          </nav>
        </aside>
        <main :key="`${accountId}:${userId}`" class="sd-main">
          <Breadcrumb
            v-if="state.status === 'ready'"
            :items="breadcrumbs"
            @click="item => item.route && router.push(item.route)"
          />
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
      </div>
    </template>
    <ServiceDeskState v-else status="disabled" />
  </div>
</template>
