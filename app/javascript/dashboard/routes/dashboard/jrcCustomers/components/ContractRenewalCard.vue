<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCustomerMaster } from '../useCustomerMaster';
const props = defineProps({ value: { type: Object, default: null } });
const { t } = useI18n();
const { accountScopedRoute } = useCustomerMaster();
const next = computed(() => props.value?.next);
const label = key => t(`CRM.CONTRACT_RENEWAL.${key}`);
// Contract terms are calendar dates; never shift them through the browser timezone.
const date = value => (value ? value.split('-').reverse().join('/') : '—');
</script>

<template>
  <section
    class="my-4 min-w-0 space-y-3 rounded-xl border border-n-amber-6 bg-n-amber-2 p-4"
  >
    <h3 class="font-semibold text-n-amber-11">{{ label('HEADING') }}</h3>
    <p
      v-if="!value"
      class="text-sm"
    >
      {{ label('UNAVAILABLE') }}
    </p>
    <template v-else>
      <div
        v-if="next"
        class="flex flex-wrap items-center justify-between gap-3"
      >
        <dl class="grid min-w-0 gap-3 text-sm sm:grid-cols-3">
          <div>
            <dt>{{ label('CONTRACT') }}</dt>
            <dd class="break-words font-semibold">
              {{ next.contract_number }}
            </dd>
          </div>
          <div>
            <dt>{{ label('ENDS_ON') }}</dt>
            <dd>
              <time :datetime="next.ends_on">{{ date(next.ends_on) }}</time>
            </dd>
          </div>
          <div>
            <dt>{{ label('NOTICE_ON') }}</dt>
            <dd>
              <time :datetime="next.notice_on">{{ date(next.notice_on) }}</time>
            </dd>
          </div>
        </dl>
        <RouterLink
          :to="accountScopedRoute('crm_contracts', {}, { contractId: next.id })"
          class="inline-flex rounded-lg bg-n-amber-9 px-3 py-2 text-sm font-semibold text-white"
        >
          {{ label('OPEN_CONTRACT') }}
        </RouterLink>
      </div>
      <p
        v-else
        class="text-sm"
      >
        {{ label('NO_UPCOMING') }}
      </p>
      <p
        v-if="next?.within_notice_window"
        class="text-sm font-semibold text-n-amber-11"
      >
        {{ label('IN_NOTICE_WINDOW') }}
      </p>
      <p
        v-if="value.overdue"
        class="text-sm text-n-ruby-11"
      >
        {{ t('CRM.CONTRACT_RENEWAL.OVERDUE', { count: value.overdue }) }}
      </p>
      <p
        v-if="value.undated"
        class="text-sm text-n-slate-11"
      >
        {{ t('CRM.CONTRACT_RENEWAL.UNDATED', { count: value.undated }) }}
      </p>
      <p class="text-xs text-n-slate-11">{{ label('HELP') }}</p>
    </template>
  </section>
</template>
