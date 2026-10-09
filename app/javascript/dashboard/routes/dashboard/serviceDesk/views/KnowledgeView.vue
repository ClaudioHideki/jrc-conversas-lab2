<script setup>
/* global axios */
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import State from '../components/ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canonicalId } from '../helpers/access';
import { errorStatus } from '../helpers/session';

const { t } = useI18n();
const route = useRoute();
const session = useServiceDesk();
const routeQuery = () =>
  typeof route.query.query === 'string' ? route.query.query.slice(0, 200) : '';
const query = ref(routeQuery());
const page = ref(1);
const total = ref(0);
const items = ref([]);
const status = ref('idle');
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const epoch = generation;
  controller?.abort();
  controller = new AbortController();
  items.value = [];
  total.value = 0;
  if (session.state.status !== 'ready') {
    status.value = session.state.status;
    return;
  }
  status.value = 'loading';
  const accountId = session.accountId.value;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId}/jrc_service_desk/knowledge`,
      {
        params: { query: query.value, page: page.value },
        signal: controller.signal,
      }
    );
    if (epoch !== generation) return;
    if (
      canonicalId(data.account_id) !== accountId ||
      data.contract_version !== 1 ||
      !Array.isArray(data.items)
    ) {
      throw new TypeError('Invalid knowledge response');
    }
    if (
      data.items.some(
        item =>
          item.visibility !== 'published_public' ||
          item.source !== 'native_help_center' ||
          !item.path?.startsWith('/hc/')
      )
    ) {
      throw new TypeError('Invalid knowledge source');
    }
    items.value = data.items;
    total.value = data.meta.total;
    status.value = items.value.length ? 'ready' : 'empty';
  } catch (error) {
    if (epoch === generation) status.value = errorStatus(error);
  }
};
const search = () => {
  page.value = 1;
  load();
};
watch(
  () => route.query.query,
  () => {
    query.value = routeQuery();
    search();
  }
);
watch(
  [
    () => session.state.status,
    () => session.accountId.value,
    () => session.userId.value,
  ],
  load,
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section>
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t('JRC_SERVICE_DESK.SCREENS.knowledge') }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.KNOWLEDGE.source') }}
        </p>
      </div>
    </header>
    <form class="flex items-end gap-3 mb-5" @submit.prevent="search">
      <Input
        v-model="query"
        class="flex-1"
        :label="t('JRC_SERVICE_DESK.COMMON.search')"
        :maxlength="200"
      />
      <Button
        type="submit"
        :label="t('JRC_SERVICE_DESK.COMMON.search')"
        :disabled="status === 'loading'"
      />
    </form>
    <div v-if="status === 'ready'" class="grid gap-3">
      <article
        v-for="item in items"
        :key="item.id"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ item.title }}
            </h3>
            <p class="text-sm text-n-slate-11">{{ item.description }}</p>
            <span class="text-xs text-n-slate-10"
              >{{ item.locale }} ·
              {{ t('JRC_SERVICE_DESK.KNOWLEDGE.public') }}</span
            >
          </div>
          <a
            :href="item.path"
            target="_blank"
            rel="noopener noreferrer"
            class="text-n-blue-11 font-medium text-sm whitespace-nowrap"
          >
            {{ t('JRC_SERVICE_DESK.COMMON.open') }}
          </a>
        </div>
      </article>
    </div>
    <State v-else :status="status" retry @retry="load" />
    <div class="flex justify-end gap-3 mt-4">
      <Button
        :label="t('JRC_SERVICE_DESK.COMMON.previous')"
        size="sm"
        variant="outline"
        :disabled="page === 1 || status === 'loading'"
        @click="
          page -= 1;
          load();
        "
      />
      <Button
        :label="t('JRC_SERVICE_DESK.COMMON.next')"
        size="sm"
        variant="outline"
        :disabled="page * 25 >= total || status === 'loading'"
        @click="
          page += 1;
          load();
        "
      />
    </div>
  </section>
</template>
