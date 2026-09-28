<script setup>
import { computed } from 'vue';
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { provideServiceDesk } from './composables/useServiceDesk';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from './routeDefinitions';
import { screenAccessible, landingScreen } from './helpers/nativeIntegration';
import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import ServiceDeskState from './components/ServiceDeskState.vue';
import WriteFeedback from './components/WriteFeedback.vue';
import './serviceDesk.css';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const session = provideServiceDesk();
const { state, enabled, accountId, userId } = session;
const groups = ['operation', 'governance', 'management'];
const activeScreen = computed(() => route.meta.serviceDeskScreen || 'overview');
const entries = group => SERVICE_DESK_ROUTES.filter(item => item.group === group && screenAccessible(state.context, item));
const to = key => ({ name: serviceDeskRouteName(key), params: { accountId: accountId.value } });
const screenAllowed = computed(() => screenAccessible(state.context, SERVICE_DESK_ROUTES.find(item => item.key === activeScreen.value)));
const breadcrumbs = computed(() => {
  const landing = landingScreen(state.context);
  const items = [{ label: t('JRC_SERVICE_DESK.MODULE'), route: landing && to(landing) }];
  if (['detail', 'edit'].includes(activeScreen.value)) items.push({ label: t('JRC_SERVICE_DESK.SCREENS.tickets'), route: to('tickets') });
  items.push({ label: t(`JRC_SERVICE_DESK.SCREENS.${activeScreen.value}`) });
  return items;
});
const blocked = computed(() => ['denied', 'unauthenticated', 'invalid_contract', 'disabled'].includes(state.status));
</script>
<template>
  <div class="jrc-service-desk-root flex flex-1 min-w-0 min-h-0" data-testid="jrc-service-desk">
    <template v-if="enabled">
      <aside class="sd-module-nav" :aria-label="t('JRC_SERVICE_DESK.MODULE')">
        <div class="flex items-center gap-3 px-3 py-4 border-b border-n-weak">
          <Icon icon="i-lucide-headset" class="size-6 text-n-blue-11" />
          <div>
            <h1 class="text-base font-semibold m-0 text-n-slate-12">
              {{ t('JRC_SERVICE_DESK.MODULE') }}
            </h1>
            <span class="text-xs text-n-slate-11">
              {{ t('JRC_SERVICE_DESK.COMMON.structure') }}
            </span>
          </div>
        </div>
        <nav class="sd-module-nav-scroll">
          <section v-for="group in groups" :key="group" class="mb-4">
            <h2 class="text-[10px] font-semibold uppercase tracking-wider text-n-slate-10 px-3 mb-2">
              {{ t(`JRC_SERVICE_DESK.GROUPS.${group}`) }}
            </h2>
            <RouterLink
              v-for="item in entries(group)"
              :key="item.key"
              :to="to(item.key)"
              class="sd-nav-link"
              :class="{ 'sd-nav-active': activeScreen === item.key || (item.key === 'tickets' && ['detail', 'edit'].includes(activeScreen)) }"
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
      <main class="sd-main" :key="`${accountId}:${userId}`">
        <Breadcrumb v-if="state.status === 'ready'" :items="breadcrumbs" @click="item => item.route && router.push(item.route)" />
        <Banner color="amber" class="mb-4">
          <strong>
            {{ t('JRC_SERVICE_DESK.COMMON.structure') }}
          </strong>
          <span class="mx-2">
            {{ t('JRC_SERVICE_DESK.SCOPE.native_pending') }}
          </span>
        </Banner>
        <div v-if="state.status !== 'ready' && !blocked" class="sd-context-notice">
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
        <WriteFeedback v-if="session.operations.state.notice" :status="session.operations.state.notice" />
        <ServiceDeskState v-if="blocked" :status="state.status" retry @retry="session.retry()" />
        <ServiceDeskState v-else-if="state.status !== 'ready'" :status="state.status" retry @retry="session.retry()" />
        <ServiceDeskState v-else-if="!screenAllowed" status="denied" />
        <RouterView v-else :key="`${accountId}:${userId}:${activeScreen}`" />
      </main>
    </template>
    <ServiceDeskState v-else status="disabled" />
  </div>
</template>
