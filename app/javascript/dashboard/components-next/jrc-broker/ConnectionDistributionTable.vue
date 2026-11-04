<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  inboxes: { type: Array, required: true },
});
const emit = defineEmits(['configure']);
const { t } = useI18n();
const rows = ref({});
let controller;
let generation = 0;
const stop = () => {
  generation += 1;
  controller?.abort();
  rows.value = {};
};
const load = async () => {
  stop();
  controller = new AbortController();
  const current = generation;
  const pending = [...props.inboxes];
  const api = createJrcBrokerApi(props.accountId);
  const read = async () => {
    const inbox = pending.shift();
    if (!inbox || current !== generation) return;
    try {
      const result = await api.connectionDistribution(
        inbox.id,
        controller.signal
      );
      if (current === generation) rows.value[inbox.id] = result;
    } catch {
      if (current === generation) rows.value[inbox.id] = { error: true };
    }
    if (current === generation) await read();
  };
  await Promise.all(Array.from({ length: Math.min(4, pending.length) }, read));
};
const modeLabel = mode =>
  t(
    `JRC_BROKER.DISTRIBUTION.MODES.${{ round_robin: 'ROUND_ROBIN', priority: 'PRIORITY', direct: 'DIRECT' }[mode] || 'UNKNOWN'}`
  );
const selectedTeams = id => {
  const row = rows.value[id];
  return (row?.policy?.team_ids || []).map(
    teamId =>
      row.teams.find(team => team.id === teamId) || {
        id: teamId,
        name: t('JRC_BROKER.DISTRIBUTION.TEAM_UNAVAILABLE'),
      }
  );
};
watch(() => [props.accountId, props.inboxes], load, { immediate: true });
onBeforeUnmount(stop);
</script>

<template>
  <section
    data-testid="distribution-table"
    class="rounded-xl border border-n-weak bg-n-solid-1 shadow-sm"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-5 py-4"
    >
      <h2 class="text-base font-semibold">
        {{ t('JRC_BROKER.DISTRIBUTION.TITLE') }}
      </h2>
      <details class="relative">
        <summary
          class="cursor-pointer rounded-lg bg-n-brand px-3 py-2 text-sm font-medium text-white focus-visible:ring-2 focus-visible:ring-n-brand"
        >
          {{ t('JRC_BROKER.WORKSPACE.NEW_DISTRIBUTION') }}
        </summary>
        <div
          class="absolute right-0 z-20 min-w-60 rounded-xl border border-n-weak bg-n-solid-1 p-2 shadow-lg"
        >
          <p class="px-3 py-2 text-xs text-n-slate-11">
            {{ t('JRC_BROKER.WORKSPACE.SELECT_CONNECTION') }}
          </p>
          <button
            v-for="inbox in inboxes"
            :key="inbox.id"
            type="button"
            class="block w-full rounded-lg px-3 py-2 text-left text-sm hover:bg-n-alpha-2"
            @click="emit('configure', inbox.id)"
          >
            {{ inbox.name }}
          </button>
        </div>
      </details>
    </header>
    <div class="overflow-x-auto">
      <table class="w-full text-left text-sm">
        <thead
          class="border-b border-n-weak bg-n-alpha-1 text-xs text-n-slate-11"
        >
          <tr>
            <th class="px-5 py-3">{{ t('JRC_BROKER.WORKSPACE.NUMBER') }}</th>
            <th class="px-4 py-3">{{ t('JRC_BROKER.WORKSPACE.QUEUES') }}</th>
            <th class="px-4 py-3">{{ t('JRC_BROKER.WORKSPACE.MODE') }}</th>
            <th class="px-4 py-3">{{ t('JRC_BROKER.WORKSPACE.STATE') }}</th>
            <th class="relative px-4 py-3">
              <span class="sr-only">{{
                t('JRC_BROKER.WORKSPACE.CONFIGURE_DISTRIBUTION')
              }}</span>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="inbox in inboxes"
            :key="inbox.id"
            class="border-b border-n-weak last:border-b-0"
          >
            <th scope="row" class="px-5 py-4 font-medium">{{ inbox.name }}</th>
            <template v-if="rows[inbox.id] && !rows[inbox.id].error">
              <td class="px-4 py-4">
                <div class="flex flex-wrap gap-1">
                  <span
                    v-for="team in selectedTeams(inbox.id)"
                    :key="team.id"
                    class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-blue-11"
                    >{{ team.name }}</span
                  ><span
                    v-if="!rows[inbox.id].policy"
                    class="text-n-slate-11"
                    >{{ t('JRC_BROKER.WORKSPACE.UNCONFIGURED') }}</span
                  >
                </div>
              </td>
              <td class="px-4 py-4">
                {{
                  rows[inbox.id].policy
                    ? modeLabel(rows[inbox.id].policy.mode)
                    : '—'
                }}
              </td>
              <td class="px-4 py-4">
                <span
                  v-if="rows[inbox.id].policy"
                  class="rounded-full bg-n-alpha-2 px-2 py-1 text-xs"
                  :class="
                    rows[inbox.id].policy.enabled
                      ? 'text-n-teal-11'
                      : 'text-n-slate-11'
                  "
                  >{{
                    t(
                      `JRC_BROKER.DISTRIBUTION.${rows[inbox.id].policy.enabled ? 'ACTIVE' : 'INACTIVE'}`
                    )
                  }}</span
                ><span v-else>—</span>
              </td>
            </template>
            <td v-else colspan="3" class="px-4 py-4 text-xs text-n-slate-11">
              {{
                t(
                  rows[inbox.id]?.error
                    ? 'JRC_BROKER.ERROR.UNAVAILABLE'
                    : 'JRC_BROKER.CONNECTIONS.CHECKING'
                )
              }}
            </td>
            <td class="px-4 py-4">
              <Button
                :data-testid="`configure-distribution-${inbox.id}`"
                variant="outline"
                icon="i-lucide-settings-2"
                :label="t('JRC_BROKER.WORKSPACE.CONFIGURE_DISTRIBUTION')"
                @click="emit('configure', inbox.id)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p class="border-t border-n-weak px-5 py-4 text-xs text-n-slate-11">
      {{ t('JRC_BROKER.DISTRIBUTION.HELP') }}
    </p>
  </section>
</template>
