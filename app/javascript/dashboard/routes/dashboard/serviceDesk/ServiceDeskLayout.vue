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
import { tones, screenTones } from './helpers/visualTheme';
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
const activeGroup = computed(
  () =>
    SERVICE_DESK_ROUTES.find(item => item.key === activeScreen.value)?.group ||
    (['detail', 'edit'].includes(activeScreen.value)
      ? 'operation'
      : 'management')
);
const groupTone = group =>
  ({ operation: 'blue', governance: 'amber', management: 'iris' })[group];
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
      <header class="shrink-0 border-b border-n-weak bg-n-solid-2 p-4">
        <div class="mb-3 flex items-center gap-3">
          <span
            class="grid size-11 place-content-center rounded-2xl bg-blue-700 text-white shadow-sm"
          >
            <Icon icon="i-lucide-headset" class="size-6" />
          </span>
          <div>
            <h1 class="m-0 text-xl font-bold text-n-slate-12">
              {{ t('JRC_SERVICE_DESK.MODULE') }}
            </h1>
            <p class="m-0 text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.SUBTITLE') }}
            </p>
          </div>
          <Button
            v-if="entries('operation').some(item => item.key === 'new')"
            class="ml-auto"
            icon="i-lucide-plus"
            :label="t('JRC_SERVICE_DESK.SCREENS.new')"
            @click="router.push(to('new'))"
          />
        </div>
        <nav
          class="flex gap-2 overflow-x-auto"
          :aria-label="t('JRC_SERVICE_DESK.MODULE')"
        >
          <RouterLink
            v-for="group in groups.filter(value => entries(value).length)"
            :key="group"
            :to="to(entries(group)[0].key)"
            class="flex shrink-0 items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold focus-visible:ring-2 focus-visible:ring-n-blue-9"
            :class="
              activeGroup === group
                ? tones[groupTone(group)].solid
                : tones[groupTone(group)].soft
            "
            :aria-current="activeGroup === group ? 'page' : undefined"
          >
            <Icon
              :icon="
                {
                  operation: 'i-lucide-headset',
                  governance: 'i-lucide-shield-check',
                  management: 'i-lucide-chart-no-axes-combined',
                }[group]
              "
              class="size-4"
            />{{ groupLabels[group] }}
          </RouterLink>
        </nav>
      </header>
      <div class="flex flex-1 min-h-0 min-w-0 flex-col lg:flex-row">
        <aside
          class="sd-module-nav !w-full lg:!w-52 !max-h-none"
          :aria-label="t('JRC_SERVICE_DESK.MODULE')"
        >
          <div class="flex items-center gap-3 px-3 py-4 border-b border-n-weak">
            <Icon icon="i-lucide-headset" class="size-6 text-n-blue-11" />
            <div>
              <h2 class="text-base font-semibold m-0 text-n-slate-12">
                {{ t('JRC_SERVICE_DESK.MODULE') }}
              </h2>
              <span class="text-xs text-n-slate-11">
                {{ t('JRC_SERVICE_DESK.COMMON.structure') }}
              </span>
            </div>
          </div>
          <nav
            class="sd-module-nav-scroll !flex !flex-row lg:!flex-col !gap-2 overflow-x-auto"
          >
            <section v-for="group in groups" :key="group" class="mb-4 shrink-0">
              <h2
                class="text-[10px] font-semibold uppercase tracking-wider text-n-slate-11 px-3 mb-2"
              >
                {{ groupLabels[group] }}
              </h2>
              <RouterLink
                v-for="item in entries(group)"
                :key="item.key"
                :to="to(item.key)"
                class="sd-nav-link !rounded-xl focus-visible:ring-2 focus-visible:ring-n-blue-9"
                :class="
                  activeScreen === item.key ||
                  (item.key === 'tickets' &&
                    ['detail', 'edit'].includes(activeScreen))
                    ? ['sd-nav-active', '!bg-blue-700 !text-white shadow-sm']
                    : tones[screenTones[item.key] || 'blue'].soft
                "
                :aria-current="activeScreen === item.key ? 'page' : undefined"
              >
                <Icon :icon="item.icon" class="size-4 flex-shrink-0" />
                <span>
                  {{ t(`JRC_SERVICE_DESK.SCREENS.${item.key}`) }}
                </span>
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
            <ScreenGuidance :screen="activeScreen" />
            <RouterView :key="`${accountId}:${userId}:${activeScreen}`" />
          </template>
        </main>
      </div>
    </template>
    <ServiceDeskState v-else status="disabled" />
  </div>
</template>
