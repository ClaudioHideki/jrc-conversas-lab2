<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ImportPager from './ImportPager.vue';
import { inputClass, primaryClass, buttonClass } from '../copy';
defineProps({
  history: { type: Object, required: true },
  filters: { type: Object, required: true },
  kinds: { type: Array, required: true },
  date: { type: Function, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['filters', 'search', 'page', 'open']);
const { t, tm } = useI18n();
const copy = computed(() => tm('CRM.CUSTOMER_IMPORTS'));
</script>

<template>
  <section>
    <form
      class="mb-5 grid items-end gap-3 sm:grid-cols-2 lg:grid-cols-4"
      @submit.prevent="emit('search')"
    >
      <label class="text-sm">
        {{ t('CRM.CUSTOMER_IMPORTS.SEARCH') }}
        <input
          :value="filters.q"
          :class="inputClass"
          :disabled="disabled"
          maxlength="100"
          @input="emit('filters', { ...filters, q: $event.target.value })"
      /></label>
      <label class="text-sm">
        {{ t('CRM.CUSTOMER_IMPORTS.KIND') }}
        <select
          :value="filters.kind"
          :class="inputClass"
          :disabled="disabled"
          @change="emit('filters', { ...filters, kind: $event.target.value })"
        >
          <option value="">{{ t('CRM.CUSTOMER_IMPORTS.ALL') }}</option>
          <option
            v-for="key in kinds"
            :key="key"
            :value="key"
          >
            {{ copy.KINDS[key] }}
          </option>
        </select>
      </label>
      <label class="text-sm">
        {{ t('CRM.CUSTOMER_IMPORTS.STATUS') }}
        <select
          :value="filters.status"
          :class="inputClass"
          :disabled="disabled"
          @change="emit('filters', { ...filters, status: $event.target.value })"
        >
          <option value="">{{ t('CRM.CUSTOMER_IMPORTS.ALL') }}</option>
          <option
            v-for="key in ['pending', 'completed', 'failed']"
            :key="key"
            :value="key"
          >
            {{ copy.STATUSES[key] }}
          </option>
        </select>
      </label>
      <button
        type="submit"
        :class="primaryClass"
        :disabled="disabled"
      >
        {{ t('CRM.CUSTOMER_IMPORTS.SEARCH') }}
      </button>
    </form>
    <p class="mb-3 text-sm text-n-slate-11">
      {{ t('CRM.CUSTOMER_IMPORTS.HISTORY_HELP') }}
    </p>
    <div class="overflow-x-auto rounded-lg border border-n-weak">
      <table class="w-full min-w-[40rem] text-left text-sm">
        <thead class="bg-n-solid-3">
          <tr>
            <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.FILE') }}</th>
            <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.KIND') }}</th>
            <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.STATUS') }}</th>
            <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.DATE') }}</th>
            <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.OPEN') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="item in history.payload"
            :key="item.id"
            class="border-t border-n-weak"
          >
            <td class="break-words p-3">
              {{ item.filename }}
              <p class="text-xs text-n-slate-11">
                {{ item.initiated_by.name }}
                {{
                  t('CRM.CUSTOMER_IMPORTS.RECORD_COUNT', {
                    count: item.total_records,
                  })
                }}
              </p>
            </td>
            <td class="p-3">
              {{ copy.KINDS[item.kind] }}
            </td>
            <td class="p-3">
              {{ copy.STATUSES[item.status] }}
            </td>
            <td class="whitespace-nowrap p-3">{{ date(item.created_at) }}</td>
            <td class="p-3">
              <button
                type="button"
                :class="buttonClass"
                :disabled="disabled"
                @click="emit('open', item.id)"
              >
                {{
                  item.can_review
                    ? t('CRM.CUSTOMER_IMPORTS.RESUME')
                    : t('CRM.CUSTOMER_IMPORTS.OPEN_RESULT')
                }}
              </button>
            </td>
          </tr>
          <tr v-if="!history.payload.length">
            <td
              colspan="5"
              class="p-4 text-n-slate-11"
            >
              {{ t('CRM.CUSTOMER_IMPORTS.EMPTY') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <ImportPager
      :page="history.meta.page"
      :size="history.meta.per_page"
      :total="history.meta.total"
      :disabled="disabled"
      @page="emit('page', $event)"
    />
  </section>
</template>
