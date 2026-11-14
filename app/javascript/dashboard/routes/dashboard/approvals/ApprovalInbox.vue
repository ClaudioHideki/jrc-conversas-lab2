<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import ApprovalStatus from './ApprovalStatus.vue';
import { scopeLabel } from './model';
defineProps({
  rows: { type: Array, required: true },
  request: { type: Object, default: null },
  context: { type: Object, default: null },
  loading: Boolean,
  showDetail: Boolean,
});
const emit = defineEmits(['select', 'back']);
const { t, te, locale } = useI18n();
const moduleLabel = key => {
  const label = `JRC_APPROVALS.workspace.modules.${key}`;
  return te(label) ? t(label) : t('JRC_APPROVALS.workspace.modules.other');
};
const dateOptions = computed(() => ({
  dateStyle: 'short',
  timeStyle: 'short',
}));
const date = value =>
  value
    ? new Intl.DateTimeFormat(
        locale.value.replaceAll('_', '-'),
        dateOptions.value
      ).format(new Date(value))
    : '—';
</script>

<template>
  <div
    class="grid min-w-0 items-start gap-4 lg:grid-cols-[minmax(18rem,0.95fr)_minmax(0,1.05fr)]"
    data-approval-workspace
  >
    <section
      class="min-w-0 rounded-2xl border border-n-weak bg-n-solid-2 p-3 sm:p-4"
      :class="showDetail ? 'hidden lg:block' : ''"
      :aria-label="t('JRC_APPROVALS.workspace.queue')"
    >
      <div
        class="mb-3 flex items-center gap-2 text-sm font-semibold text-n-slate-12"
      >
        <Icon
          icon="i-lucide-list-checks"
          class="size-4 text-n-blue-10"
        />{{ t('JRC_APPROVALS.workspace.queue') }}
      </div>
      <p
        v-if="!rows.length && !loading"
        class="rounded-xl bg-n-alpha-2 px-4 py-10 text-center text-sm text-n-slate-11"
      >
        {{ t('JRC_APPROVALS.empty') }}
      </p>
      <ul class="grid min-w-0 gap-2">
        <li
          v-for="row in rows"
          :key="row.id"
          class="min-w-0"
        >
          <button
            type="button"
            class="flex w-full min-w-0 gap-3 rounded-xl border p-3 text-left transition-colors focus-visible:outline-blue-500"
            :class="
              request?.id === row.id
                ? 'border-n-blue-7 bg-n-blue-2'
                : 'border-n-weak bg-n-solid-2 hover:bg-n-alpha-2'
            "
            :aria-pressed="request?.id === row.id"
            :disabled="loading"
            :data-approval-request="row.id"
            @click="emit('select', row.id)"
          >
            <span
              class="mt-1 flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
              ><Icon
                icon="i-lucide-file-check-2"
                class="size-5"
            /></span>
            <span class="grid min-w-0 flex-1 gap-2">
              <span class="break-words text-sm font-semibold text-n-slate-12"
                >{{ row.policy_name || t('JRC_APPROVALS.request') }} · #{{
                  row.id
                }}</span
              >
              <span class="break-words text-xs text-n-slate-11"
                >{{ row.requester_name }} ·
                {{ moduleLabel(row.module_key) }}</span
              >
              <span class="break-words text-xs text-n-slate-11">{{
                scopeLabel(context, row) || t('JRC_APPROVALS.groupScope')
              }}</span>
              <span class="flex flex-wrap items-center justify-between gap-2"
                ><ApprovalStatus :state="row.state" /><span
                  class="text-xs text-n-slate-11"
                  >{{ date(row.created_at) }}</span
                ></span
              >
            </span>
            <Icon
              icon="i-lucide-chevron-right"
              class="mt-1 size-4 shrink-0 text-n-slate-10"
            />
          </button>
        </li>
      </ul>
    </section>
    <section
      class="min-w-0 rounded-2xl border border-n-weak bg-n-solid-2 p-4 sm:p-5"
      :class="!showDetail ? 'hidden lg:block' : ''"
      :aria-label="t('JRC_APPROVALS.workspace.detail')"
    >
      <button
        v-if="showDetail"
        type="button"
        class="mb-4 inline-flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 lg:hidden"
        @click="emit('back')"
      >
        <Icon
          icon="i-lucide-arrow-left"
          class="size-4"
        />{{ t('JRC_APPROVALS.workspace.backToQueue') }}
      </button>
      <slot
        v-if="request"
        name="detail"
      />
      <div
        v-else
        class="flex min-h-64 flex-col items-center justify-center gap-3 text-center text-n-slate-11"
      >
        <Icon
          icon="i-lucide-file-check-2"
          class="size-10 text-n-blue-9"
        />
        <p class="font-semibold">
          {{ t('JRC_APPROVALS.workspace.selectRequest') }}
        </p>
        <p class="max-w-xs text-sm">
          {{ t('JRC_APPROVALS.workspace.selectRequestHelp') }}
        </p>
      </div>
    </section>
  </div>
</template>
