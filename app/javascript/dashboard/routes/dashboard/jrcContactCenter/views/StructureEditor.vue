<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  units: { type: Array, required: true },
  queues: { type: Array, required: true },
  agents: { type: Array, required: true },
  memberships: { type: Array, required: true },
});
const emit = defineEmits(['saved']);
const { t } = useI18n();
const kindLabels = computed(() => ({
  sac: t('JRC_CONTACT_CENTER.SETTINGS.KINDS.sac'),
  finance: t('JRC_CONTACT_CENTER.SETTINGS.KINDS.finance'),
  coe: t('JRC_CONTACT_CENTER.SETTINGS.KINDS.coe'),
  administrative: t('JRC_CONTACT_CENTER.SETTINGS.KINDS.administrative'),
}));
const busy = ref(false);
const failed = ref(false);
const unitName = ref('');
const unitCode = ref('');
const unitKind = ref('sac');
const queueName = ref('');
const queueCode = ref('');
const unitId = ref('');
const queueId = ref('');
const memberId = ref('');
const strategy = ref('');

const recordIcon = kind => {
  if (kind === 'unit') return 'i-lucide-building-2';
  if (kind === 'queue') return 'i-lucide-layers-3';
  return 'i-lucide-user-round-check';
};
const existingRecords = computed(() => [
  ...props.units.map(record => ({
    kind: 'unit',
    record,
    name: record.name,
    active: record.status === 'active',
  })),
  ...props.queues.map(record => ({
    kind: 'queue',
    record,
    name: record.name,
    active: record.status === 'active',
  })),
  ...props.memberships.map(record => ({
    kind: 'membership',
    record,
    name: t('JRC_CONTACT_CENTER.COMMON.CODE_DETAIL', {
      code: record.user_name,
      detail: record.queue_name,
    }),
    active: record.active,
  })),
]);
const toggle = async item => {
  if (busy.value) return;
  busy.value = true;
  failed.value = false;
  try {
    if (item.kind === 'membership') {
      await JrcContactCenterAPI.saveQueueMembership(
        props.accountId,
        { active: !item.active },
        item.record.id
      );
    } else {
      const attributes = { status: item.active ? 'inactive' : 'active' };
      if (item.kind === 'unit')
        await JrcContactCenterAPI.saveUnit(
          props.accountId,
          attributes,
          item.record.id
        );
      else
        await JrcContactCenterAPI.saveQueue(
          props.accountId,
          attributes,
          item.record.id
        );
    }
    emit('saved');
  } catch {
    failed.value = true;
  } finally {
    busy.value = false;
  }
};

const save = async kind => {
  if (busy.value) return;
  busy.value = true;
  failed.value = false;
  try {
    if (kind === 'unit') {
      await JrcContactCenterAPI.saveUnit(props.accountId, {
        name: unitName.value.trim(),
        code: unitCode.value.trim(),
        kind: unitKind.value,
      });
    } else if (kind === 'queue') {
      await JrcContactCenterAPI.saveQueue(props.accountId, {
        name: queueName.value.trim(),
        code: queueCode.value.trim(),
        unit_id: unitId.value,
        service_kind: 'voice',
        strategy: strategy.value.trim(),
      });
    } else {
      await JrcContactCenterAPI.saveQueueMembership(props.accountId, {
        queue_id: queueId.value,
        account_user_id: memberId.value,
        role: 'agent',
        active: true,
      });
    }
    emit('saved');
  } catch {
    failed.value = true;
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <div class="space-y-5">
    <p
      class="flex gap-2 rounded-2xl border border-n-amber-5 bg-n-amber-2 p-4 text-sm leading-6 text-n-amber-11"
    >
      <Icon icon="i-lucide-circle-help" class="mt-1 size-4 shrink-0" />
      {{ t('JRC_CONTACT_CENTER.SETTINGS.LOCAL_STRUCTURE') }}
    </p>
    <p
      v-if="failed"
      role="alert"
      class="rounded-2xl border border-n-ruby-5 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>

    <div class="grid gap-4 xl:grid-cols-3">
      <form
        class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
        @submit.prevent="save('unit')"
      >
        <div class="mb-4 flex items-center gap-3">
          <span
            class="grid size-10 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11"
          >
            <Icon icon="i-lucide-building-2" class="size-5" />
          </span>
          <div>
            <h4 class="text-sm font-semibold text-n-slate-12">
              {{ t('JRC_CONTACT_CENTER.CARDS.UNITS') }}
            </h4>
            <p class="mt-0.5 text-xs text-n-slate-10">
              {{ t('JRC_CONTACT_CENTER.SETTINGS.CREATE_UNIT') }}
            </p>
          </div>
        </div>
        <div class="space-y-3">
          <input
            v-model="unitName"
            required
            :aria-label="t('JRC_CONTACT_CENTER.SETTINGS.UNIT_NAME')"
            :placeholder="t('JRC_CONTACT_CENTER.SETTINGS.UNIT_NAME')"
            class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
          />
          <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-1 2xl:grid-cols-2">
            <input
              v-model="unitCode"
              required
              :aria-label="t('JRC_CONTACT_CENTER.COMMON.CODE')"
              :placeholder="t('JRC_CONTACT_CENTER.COMMON.CODE')"
              class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
            />
            <select
              v-model="unitKind"
              :aria-label="t('JRC_CONTACT_CENTER.COMMON.TYPE')"
              class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
            >
              <option
                v-for="kind in ['sac', 'finance', 'coe', 'administrative']"
                :key="kind"
                :value="kind"
              >
                {{ kindLabels[kind] }}
              </option>
            </select>
          </div>
          <button
            :disabled="busy"
            type="submit"
            class="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Icon icon="i-lucide-plus" class="size-4" />
            {{ t('JRC_CONTACT_CENTER.SETTINGS.CREATE_UNIT') }}
          </button>
        </div>
      </form>

      <form
        class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
        @submit.prevent="save('queue')"
      >
        <div class="mb-4 flex items-center gap-3">
          <span
            class="grid size-10 place-content-center rounded-xl bg-n-teal-2 text-n-teal-11"
          >
            <Icon icon="i-lucide-layers-3" class="size-5" />
          </span>
          <div>
            <h4 class="text-sm font-semibold text-n-slate-12">
              {{ t('JRC_CONTACT_CENTER.CARDS.QUEUES') }}
            </h4>
            <p class="mt-0.5 text-xs text-n-slate-10">
              {{ t('JRC_CONTACT_CENTER.SETTINGS.CREATE_QUEUE') }}
            </p>
          </div>
        </div>
        <div class="space-y-3">
          <input
            v-model="queueName"
            required
            :aria-label="t('JRC_CONTACT_CENTER.SETTINGS.QUEUE_NAME')"
            :placeholder="t('JRC_CONTACT_CENTER.SETTINGS.QUEUE_NAME')"
            class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
          />
          <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-1 2xl:grid-cols-2">
            <input
              v-model="queueCode"
              required
              :aria-label="t('JRC_CONTACT_CENTER.COMMON.CODE')"
              :placeholder="t('JRC_CONTACT_CENTER.COMMON.CODE')"
              class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
            />
            <select
              v-model="unitId"
              required
              :aria-label="t('JRC_CONTACT_CENTER.CARDS.UNITS')"
              class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
            >
              <option value="" disabled>
                {{ t('JRC_CONTACT_CENTER.CARDS.UNITS') }}
              </option>
              <option v-for="unit in units" :key="unit.id" :value="unit.id">
                {{ unit.name }}
              </option>
            </select>
          </div>
          <input
            v-model="strategy"
            required
            :aria-label="t('JRC_CONTACT_CENTER.SETTINGS.STRATEGY')"
            :placeholder="t('JRC_CONTACT_CENTER.SETTINGS.STRATEGY')"
            class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
          />
          <button
            :disabled="busy"
            type="submit"
            class="inline-flex w-full items-center justify-center gap-2 rounded-xl border border-n-teal-6 bg-n-teal-2 px-4 py-2.5 text-sm font-semibold text-n-teal-11 shadow-sm transition hover:bg-n-teal-3 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Icon icon="i-lucide-plus" class="size-4" />
            {{ t('JRC_CONTACT_CENTER.SETTINGS.CREATE_QUEUE') }}
          </button>
        </div>
      </form>

      <form
        class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
        @submit.prevent="save('membership')"
      >
        <div class="mb-4 flex items-center gap-3">
          <span
            class="grid size-10 place-content-center rounded-xl bg-n-iris-2 text-n-iris-11"
          >
            <Icon icon="i-lucide-users-round" class="size-5" />
          </span>
          <div>
            <h4 class="text-sm font-semibold text-n-slate-12">
              {{ t('JRC_CONTACT_CENTER.SETTINGS.MEMBERSHIPS') }}
            </h4>
            <p class="mt-0.5 text-xs text-n-slate-10">
              {{ t('JRC_CONTACT_CENTER.SETTINGS.CREATE_MEMBERSHIP') }}
            </p>
          </div>
        </div>
        <div class="space-y-3">
          <select
            v-model="queueId"
            required
            :aria-label="t('JRC_CONTACT_CENTER.CARDS.QUEUES')"
            class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
          >
            <option value="" disabled>
              {{ t('JRC_CONTACT_CENTER.CARDS.QUEUES') }}
            </option>
            <option v-for="queue in queues" :key="queue.id" :value="queue.id">
              {{ queue.name }}
            </option>
          </select>
          <select
            v-model="memberId"
            required
            :aria-label="t('JRC_CONTACT_CENTER.SETTINGS.MEMBERSHIPS')"
            class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
          >
            <option value="" disabled>
              {{ t('JRC_CONTACT_CENTER.SETTINGS.MEMBERSHIPS') }}
            </option>
            <option
              v-for="agent in agents"
              :key="agent.account_user_id"
              :value="agent.account_user_id"
            >
              {{ agent.name }}
            </option>
          </select>
          <button
            :disabled="busy"
            type="submit"
            class="inline-flex w-full items-center justify-center gap-2 rounded-xl border border-n-iris-6 bg-n-iris-2 px-4 py-2.5 text-sm font-semibold text-n-iris-11 shadow-sm transition hover:bg-n-iris-3 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <Icon icon="i-lucide-user-round-plus" class="size-4" />
            {{ t('JRC_CONTACT_CENTER.SETTINGS.CREATE_MEMBERSHIP') }}
          </button>
        </div>
      </form>
    </div>

    <section
      class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2"
    >
      <header
        class="flex items-center justify-between gap-3 border-b border-n-weak px-4 py-3.5"
      >
        <div class="flex items-center gap-3">
          <span
            class="grid size-9 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11"
          >
            <Icon icon="i-lucide-network" class="size-4" />
          </span>
          <div>
            <h4 class="text-sm font-semibold text-n-slate-12">
              {{ t('JRC_CONTACT_CENTER.SETTINGS.TITLE') }}
            </h4>
            <p class="mt-0.5 text-xs text-n-slate-10">
              {{ existingRecords.length }}
            </p>
          </div>
        </div>
      </header>
      <div
        v-if="existingRecords.length"
        class="grid gap-3 p-4 md:grid-cols-2 xl:grid-cols-3"
      >
        <article
          v-for="item in existingRecords"
          :key="`${item.kind}-${item.record.id}`"
          class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-3.5"
        >
          <span
            class="grid size-10 shrink-0 place-content-center rounded-xl bg-n-solid-2 text-n-blue-11 shadow-sm"
          >
            <Icon :icon="recordIcon(item.kind)" class="size-4" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold text-n-slate-12">
              {{ item.name }}
            </p>
            <VisualStatusBadge
              class="mt-2"
              :label="
                item.active
                  ? t('JRC_CONTACT_CENTER.COMMON.ACTIVE')
                  : t('JRC_CONTACT_CENTER.COMMON.INACTIVE')
              "
              :tone="item.active ? 'emerald' : 'slate'"
            />
          </div>
          <button
            type="button"
            :disabled="busy"
            class="grid size-9 shrink-0 place-content-center rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-10 transition hover:bg-n-alpha-2 hover:text-n-slate-12 disabled:opacity-50"
            :aria-label="
              item.active
                ? t('JRC_CONTACT_CENTER.SETTINGS.DEACTIVATE')
                : t('JRC_CONTACT_CENTER.SETTINGS.ACTIVATE')
            "
            @click="toggle(item)"
          >
            <Icon
              :icon="
                item.active ? 'i-lucide-toggle-right' : 'i-lucide-toggle-left'
              "
              class="size-5"
            />
          </button>
        </article>
      </div>
      <p v-else class="p-5 text-sm text-n-slate-10">
        {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
      </p>
    </section>
  </div>
</template>
