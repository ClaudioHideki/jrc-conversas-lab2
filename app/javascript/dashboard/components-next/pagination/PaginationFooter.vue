<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNumberFormatter } from 'shared/composables/useNumberFormatter';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  currentPage: {
    type: Number,
    required: true,
  },
  totalItems: {
    type: Number,
    required: true,
  },
  itemsPerPage: {
    type: Number,
    default: 16,
  },
  numbered: { type: Boolean, default: false },
  currentPageInfo: {
    type: String,
    default: '',
  },
});
const emit = defineEmits(['update:currentPage']);
const { t } = useI18n();
const { formatCompactNumber, formatFullNumber } = useNumberFormatter();

const totalPages = computed(() =>
  Math.ceil(props.totalItems / props.itemsPerPage)
);
const numberedPages = computed(() => {
  const last = totalPages.value;
  const current = props.currentPage;
  const start = Math.max(2, Math.min(current - 2, last - 5));
  const end = Math.min(last - 1, start + 4);
  const pages = [1];
  if (start > 2) pages.push('…');
  for (let page = start; page <= end; page += 1) pages.push(page);
  if (end < last - 1) pages.push('…');
  if (last > 1) pages.push(last);
  return pages;
});
const startItem = computed(
  () => (props.currentPage - 1) * props.itemsPerPage + 1
);
const endItem = computed(() =>
  Math.min(startItem.value + props.itemsPerPage - 1, props.totalItems)
);
const isFirstPage = computed(() => props.currentPage === 1);
const isLastPage = computed(() => props.currentPage === totalPages.value);
const changePage = newPage => {
  if (newPage >= 1 && newPage <= totalPages.value) {
    emit('update:currentPage', newPage);
  }
};

const currentPageInformation = computed(() => {
  const translationKey = props.currentPageInfo || 'PAGINATION_FOOTER.SHOWING';
  return t(
    translationKey,
    {
      startItem: formatFullNumber(startItem.value),
      endItem: formatFullNumber(endItem.value),
      totalItems: props.numbered
        ? formatFullNumber(props.totalItems)
        : formatCompactNumber(props.totalItems),
    },
    Number(props.totalItems)
  );
});

const pageInfo = computed(() => {
  return t(
    'PAGINATION_FOOTER.CURRENT_PAGE_INFO',
    {
      currentPage: '',
      totalPages: formatCompactNumber(totalPages.value),
    },
    Number(totalPages.value)
  );
});
</script>

<template>
  <div
    :class="
      numbered
        ? 'flex w-full flex-wrap items-center justify-between gap-2 border-t border-n-weak px-3 py-3 sm:px-4'
        : 'flex justify-between h-[3.375rem] w-full border-t border-n-weak mx-auto bg-n-surface-1 py-3 px-6 items-center before:absolute before:inset-x-0 before:-top-4 before:bg-gradient-to-t before:from-n-surface-1 before:from-0% before:to-transparent before:h-4 before:pointer-events-none'
    "
  >
    <div class="flex items-center gap-3">
      <span class="min-w-0 text-body-main line-clamp-1 text-n-slate-11">
        {{ currentPageInformation }}
      </span>
    </div>
    <div class="flex items-center gap-2">
      <Button
        icon="i-lucide-chevrons-left"
        variant="ghost"
        size="sm"
        color="slate"
        class="!w-8 !h-6"
        :aria-label="t('CRM.DIRECTORY.FIRST_PAGE')"
        :disabled="isFirstPage"
        @click="changePage(1)"
      />
      <Button
        icon="i-lucide-chevron-left"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-8 !h-6"
        :aria-label="t('CRM.CONTACT_LEAD.PREVIOUS')"
        :disabled="isFirstPage"
        @click="changePage(currentPage - 1)"
      />
      <div
        v-if="numbered"
        class="hidden items-center gap-1 sm:flex"
        :aria-label="t('CRM.DIRECTORY.PAGES')"
      >
        <template
          v-for="(page, index) in numberedPages"
          :key="`${page}:${index}`"
        >
          <button
            v-if="typeof page === 'number'"
            type="button"
            class="grid min-h-7 min-w-7 place-items-center rounded-lg px-1.5 text-xs font-semibold tabular-nums"
            :class="
              page === currentPage
                ? 'bg-n-brand text-white'
                : 'border border-n-weak text-n-slate-12 hover:bg-n-alpha-2'
            "
            :aria-current="page === currentPage ? 'page' : undefined"
            :aria-label="t('CRM.DIRECTORY.PAGE_NUMBER', { page })"
            @click="changePage(page)"
          >
            {{ formatFullNumber(page) }}
          </button>
          <span v-else class="px-0.5 text-xs" aria-hidden="true">{{
            page
          }}</span>
        </template>
      </div>
      <div
        class="inline-flex items-center gap-2 text-sm"
        :class="{ 'sm:hidden': numbered }"
      >
        <span
          class="px-3 tabular-nums py-0.5 font-420 bg-n-input-background text-body-main text-n-slate-12 rounded-md"
        >
          {{ formatFullNumber(currentPage) }}
        </span>
        <span class="truncate text-body-main text-n-slate-11">
          {{ pageInfo }}
        </span>
      </div>
      <Button
        icon="i-lucide-chevron-right"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-8 !h-6"
        :aria-label="t('CRM.CONTACT_LEAD.NEXT')"
        :disabled="isLastPage"
        @click="changePage(currentPage + 1)"
      />
      <Button
        icon="i-lucide-chevrons-right"
        variant="ghost"
        color="slate"
        size="sm"
        class="!w-8 !h-6"
        :aria-label="t('CRM.DIRECTORY.LAST_PAGE')"
        :disabled="isLastPage"
        @click="changePage(totalPages)"
      />
    </div>
  </div>
</template>
