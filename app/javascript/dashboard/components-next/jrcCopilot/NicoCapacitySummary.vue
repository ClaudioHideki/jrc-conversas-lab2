<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ capacity: { type: Object, default: null } });
const { t, locale } = useI18n();
const number = value =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(value);
</script>

<template>
  <details
    v-if="capacity"
    class="rounded-lg border border-n-weak px-3 py-2 text-xs text-n-slate-11"
  >
    <summary class="cursor-pointer text-n-slate-12">
      {{
        t('JRC_NICO.CAPACITY.SUMMARY', {
          remaining: number(capacity.remaining_tokens),
          limit: number(capacity.token_limit),
        })
      }}
    </summary>
    <dl class="mt-2 grid grid-cols-2 gap-1">
      <dt>{{ t('JRC_NICO.CAPACITY.USED') }}</dt>
      <dd>{{ number(capacity.used_tokens) }}</dd>
      <dt>{{ t('JRC_NICO.CAPACITY.RESERVED') }}</dt>
      <dd>{{ number(capacity.reserved_tokens) }}</dd>
      <dt>{{ t('JRC_NICO.CAPACITY.UNCERTAIN') }}</dt>
      <dd>{{ number(capacity.uncertain_tokens) }}</dd>
      <dt>{{ t('JRC_NICO.CAPACITY.EXECUTIONS') }}</dt>
      <dd>
        {{
          t('JRC_NICO.CAPACITY.RATIO', {
            value: number(capacity.executions),
            limit: number(capacity.execution_limit),
          })
        }}
      </dd>
      <dt>{{ t('JRC_NICO.CAPACITY.CONCURRENCY') }}</dt>
      <dd>
        {{
          t('JRC_NICO.CAPACITY.RATIO', {
            value: number(capacity.active_operations),
            limit: number(capacity.concurrency_limit),
          })
        }}
      </dd>
    </dl>
  </details>
  <template v-else />
</template>
