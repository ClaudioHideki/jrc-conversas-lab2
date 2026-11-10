<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ImportPager from './ImportPager.vue';
import { buttonClass, primaryClass } from '../copy';
const props = defineProps({
  preview: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['confirm', 'errors', 'back']);
const { t, tm } = useI18n();
const copy = computed(() => tm('CRM.CUSTOMER_IMPORTS'));
const view = ref('summary');
const page = ref(1);
const stats = computed(() => props.preview.payload.stats);
const items = computed(() =>
  view.value === 'errors'
    ? props.preview.errors
    : props.preview.rows.filter(row => row.entity === view.value)
);
const rows = computed(() =>
  items.value.slice((page.value - 1) * 12, page.value * 12)
);
watch(view, () => {
  page.value = 1;
});
const countKeys = [
  'total_rows',
  'valid_rows',
  'invalid_rows',
  'ignored_rows',
  'company_create',
  'company_update',
  'company_skip',
  'company_reference',
  'contact_create',
  'contact_update',
  'contact_skip',
];
</script>

<template>
  <section class="space-y-4">
    <p class="text-sm text-n-slate-11">
      {{ t('CRM.CUSTOMER_IMPORTS.PREVIEW_HELP') }}
    </p>
    <nav
      class="flex flex-wrap gap-2"
      :aria-label="t('CRM.CUSTOMER_IMPORTS.PREVIEW')"
    >
      <button
        v-for="key in ['summary', 'company', 'contact', 'errors']"
        :key="key"
        type="button"
        class="rounded-lg border px-3 py-2 text-sm"
        :class="
          view === key
            ? 'border-n-blue-8 bg-n-blue-4 text-n-blue-12'
            : 'border-n-weak bg-n-solid-1 text-n-slate-12'
        "
        :aria-pressed="view === key"
        :disabled="disabled"
        @click="view = key"
      >
        {{ copy.VIEWS[key] }}
      </button>
    </nav>
    <div
      v-if="view === 'summary'"
      class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4"
    >
      <div
        v-for="key in countKeys"
        :key="key"
        class="rounded-xl border border-n-teal-6 bg-n-teal-3 p-4 text-n-teal-12"
      >
        <p class="text-xs">{{ copy.COUNTS[key] }}</p>
        <p class="mt-1 text-2xl font-bold">{{ stats[key] || 0 }}</p>
      </div>
    </div>
    <template v-else>
      <div class="overflow-x-auto rounded-lg border border-n-weak">
        <table class="w-full text-left text-sm">
          <thead class="bg-n-solid-3">
            <tr>
              <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.LINE') }}</th>
              <th class="p-3">
                {{
                  view === 'errors'
                    ? t('CRM.CUSTOMER_IMPORTS.FIELD')
                    : t('CRM.CUSTOMER_IMPORTS.ACTION')
                }}
              </th>
              <th class="p-3">{{ t('CRM.CUSTOMER_IMPORTS.DETAILS') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows"
              :key="`${row.line}:${row.entity}:${row.field || ''}`"
              class="border-t border-n-weak"
            >
              <td class="p-3">{{ row.line }}</td>
              <td class="p-3">
                {{
                  view === 'errors'
                    ? `${row.entity}.${row.field}`
                    : copy.ACTIONS[row.action]
                }}
              </td>
              <td class="p-3">
                <template v-if="view === 'errors'">{{ row.message }}</template>
                <template v-else>
                  <p>
                    {{
                      row.attributes.name ||
                      row.attributes.email ||
                      row.record_id
                    }}
                  </p>
                  <p
                    v-if="row.reference_line"
                    class="text-xs text-n-slate-11"
                  >
                    {{
                      t('CRM.CUSTOMER_IMPORTS.REFERENCE_ROW', {
                        line: row.reference_line,
                      })
                    }}
                  </p>
                  <p
                    v-if="row.attributes.tax_id"
                    class="text-xs text-n-slate-11"
                  >
                    {{ row.attributes.tax_id }}
                  </p>
                  <p
                    v-for="warning in row.warnings"
                    :key="warning"
                    class="text-xs text-n-amber-11"
                  >
                    {{ copy.WARNINGS[warning] }}
                  </p>
                </template>
              </td>
            </tr>
            <tr v-if="!rows.length">
              <td
                colspan="3"
                class="p-4 text-n-slate-11"
              >
                {{ t('CRM.CUSTOMER_IMPORTS.EMPTY') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <ImportPager
        :page="page"
        :size="12"
        :total="items.length"
        :disabled="disabled"
        @page="page = $event"
      />
    </template>
    <p
      v-if="preview.errors.length"
      role="alert"
      class="rounded-lg border border-n-ruby-7 bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
    >
      {{ t('CRM.CUSTOMER_IMPORTS.CORRECT_ERRORS') }}
    </p>
    <div class="flex flex-wrap gap-3">
      <button
        type="button"
        :class="buttonClass"
        :disabled="disabled"
        @click="emit('back')"
      >
        {{ t('CRM.CUSTOMER_IMPORTS.EDIT_MAPPING') }}
      </button>
      <button
        v-if="preview.errors.length"
        type="button"
        :class="buttonClass"
        :disabled="disabled"
        @click="emit('errors')"
      >
        {{ t('CRM.CUSTOMER_IMPORTS.DOWNLOAD_ERRORS') }}
      </button>
      <button
        type="button"
        :class="primaryClass"
        :disabled="disabled || !preview.token"
        @click="emit('confirm')"
      >
        {{ t('CRM.CUSTOMER_IMPORTS.APPLY') }}
      </button>
    </div>
  </section>
</template>
