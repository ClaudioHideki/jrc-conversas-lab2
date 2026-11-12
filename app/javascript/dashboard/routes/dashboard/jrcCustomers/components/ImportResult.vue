<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ImportPager from './ImportPager.vue';
import { buttonClass } from '../copy';
defineProps({
  run: { type: Object, required: true },
  records: { type: Object, required: true },
  view: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['view', 'page', 'open', 'errors']);
const { t, tm } = useI18n();
const copy = computed(() => tm('CRM.CUSTOMER_IMPORTS'));
</script>

<template>
  <section class="space-y-4">
    <div
      class="rounded-lg border border-n-teal-7 bg-n-teal-3 p-4 text-n-teal-12"
    >
      <h2 class="font-semibold">
        {{ t('CRM.CUSTOMER_IMPORTS.STATUSES.completed') }}
      </h2>
      <p class="text-sm">
        {{
          t('CRM.CUSTOMER_IMPORTS.RESULT_HELP', {
            count: run.stats.applied_entities || 0,
          })
        }}
      </p>
    </div>
    <nav
      class="flex gap-2"
      :aria-label="t('CRM.CUSTOMER_IMPORTS.RESULT')"
    >
      <button
        v-for="key in ['rows', 'errors']"
        :key="key"
        type="button"
        class="rounded-lg border px-4 py-2 text-sm"
        :class="
          view === key
            ? 'border-n-blue-8 bg-n-blue-4 text-n-blue-12'
            : 'border-n-weak bg-n-solid-1 text-n-slate-12'
        "
        :disabled="disabled"
        :aria-pressed="view === key"
        @click="emit('view', key)"
      >
        {{ copy.VIEWS[key] }}
      </button>
    </nav>
    <div class="overflow-x-auto rounded-lg border border-n-weak">
      <table class="w-full min-w-[36rem] text-left text-sm">
        <thead class="bg-n-solid-3">
          <tr>
            <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.LINE') }}</th>
            <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.KIND') }}</th>
            <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.DETAILS') }}</th>
            <th
              v-if="view === 'rows'"
              class="p-3"
            >
              {{ t('CRM.CUSTOMER_IMPORTS.ACTION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="item in records.payload"
            :key="item.id"
            class="border-t border-n-weak"
          >
            <td class="p-3">{{ item.line }}</td>
            <td class="p-3">
              {{ copy.VIEWS[item.entity] }}
            </td>
            <td class="p-3">
              <template v-if="view === 'errors'">
                {{
                  t('CRM.CUSTOMER_IMPORTS.ERROR_DETAIL', {
                    field: item.field,
                    message: item.message,
                  })
                }}
              </template>
              <button
                v-else-if="item.record_id"
                type="button"
                class="text-n-blue-11 underline"
                :disabled="disabled"
                @click="emit('open', item)"
              >
                {{ item.name || item.record_id }}
              </button>
              <span v-else>{{ t('CRM.CUSTOMER_IMPORTS.UNAVAILABLE') }}</span>
            </td>
            <td
              v-if="view === 'rows'"
              class="p-3"
            >
              {{ copy.ACTIONS[item.action] }}
            </td>
          </tr>
          <tr v-if="!records.payload.length">
            <td
              :colspan="view === 'rows' ? 4 : 3"
              class="p-4 text-n-slate-11"
            >
              {{ t('CRM.CUSTOMER_IMPORTS.EMPTY') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <ImportPager
      :page="records.meta.page"
      :size="records.meta.per_page"
      :total="records.meta.total"
      :disabled="disabled"
      @page="emit('page', $event)"
    />
    <button
      v-if="view === 'errors' && records.meta.total"
      type="button"
      :class="buttonClass"
      :disabled="disabled"
      @click="emit('errors')"
    >
      {{ t('CRM.CUSTOMER_IMPORTS.DOWNLOAD_ERRORS') }}
    </button>
  </section>
</template>
