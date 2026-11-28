<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ContactSortMenu from './components/ContactSortMenu.vue';
import ContactMoreActions from './components/ContactMoreActions.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';

defineProps({
  directory: { type: Boolean, default: false },
  showSearch: { type: Boolean, default: true },
  searchValue: { type: String, default: '' },
  headerTitle: { type: String, required: true },
  buttonLabel: { type: String, default: '' },
  activeSort: { type: String, default: 'last_activity_at' },
  activeOrdering: { type: String, default: '' },
  isSegmentsView: { type: Boolean, default: false },
  hasActiveFilters: { type: Boolean, default: false },
  isLabelView: { type: Boolean, default: false },
  isActiveView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'search',
  'filter',
  'update:sort',
  'add',
  'import',
  'export',
  'createSegment',
  'deleteSegment',
]);

const { checkPermissions } = usePolicy();
const canManageContacts = computed(() =>
  checkPermissions(['administrator', 'contact_manage'])
);
</script>

<template>
  <div v-if="directory" class="flex flex-col gap-4">
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div class="flex min-w-0 items-center gap-3">
        <span
          class="grid size-11 shrink-0 place-items-center rounded-xl bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
        >
          <span class="i-lucide-users-round size-6" />
        </span>
        <div>
          <h1
            class="text-2xl font-bold tracking-tight text-n-slate-12 sm:text-3xl"
          >
            {{ headerTitle }}
          </h1>
          <p class="text-sm text-n-slate-11">
            {{ $t('CRM.DIRECTORY.CONTACTS_HELP') }}
          </p>
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <Button
          v-if="canManageContacts"
          color="slate"
          variant="outline"
          size="sm"
          icon="i-lucide-upload"
          :label="$t('CRM.DIRECTORY.IMPORT')"
          @click="emit('import')"
        />
        <Button
          v-if="canManageContacts"
          color="slate"
          variant="outline"
          size="sm"
          icon="i-lucide-download"
          :label="$t('CRM.DIRECTORY.EXPORT')"
          @click="emit('export')"
        />
        <Button
          color="blue"
          icon="i-lucide-plus"
          size="sm"
          :label="
            $t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT')
          "
          @click="emit('add')"
        />
      </div>
    </header>

    <slot name="metrics" />

    <div
      class="flex flex-wrap items-center gap-2 rounded-2xl border border-n-weak bg-n-solid-2 p-3 shadow-sm"
    >
      <label v-if="showSearch" class="relative min-w-[min(100%,14rem)] flex-1">
        <Icon
          icon="i-lucide-search"
          class="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-11"
          aria-hidden="true"
        />
        <input
          :value="searchValue"
          type="search"
          :aria-label="$t('CRM.DIRECTORY.SEARCH_CONTACTS')"
          :placeholder="$t('CRM.DIRECTORY.SEARCH_CONTACTS')"
          class="reset-base m-0 h-9 w-full rounded-lg border border-n-weak bg-n-solid-1 pe-3 ps-9 text-sm text-n-slate-12"
          @input="emit('search', $event.target.value)"
        />
      </label>
      <slot name="quick-filters" />
      <ContactSortMenu
        :active-sort="activeSort"
        :active-ordering="activeOrdering"
        @update:sort="emit('update:sort', $event)"
      />
      <div v-if="!isLabelView && !isActiveView" class="relative">
        <Button
          id="toggleContactsFilterButton"
          icon="i-lucide-list-filter"
          :label="$t('CRM.DIRECTORY.MORE_FILTERS')"
          color="blue"
          size="sm"
          :variant="hasActiveFilters ? 'faded' : 'outline'"
          @click="emit('filter')"
        />
        <slot name="filter" />
      </div>
      <Button
        v-if="
          hasActiveFilters && !isSegmentsView && !isLabelView && !isActiveView
        "
        :aria-label="
          $t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.CONFIRM')
        "
        icon="i-lucide-save"
        color="slate"
        size="sm"
        variant="ghost"
        @click="emit('createSegment')"
      />
      <Button
        v-if="isSegmentsView && !isLabelView && !isActiveView"
        :aria-label="
          $t('CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.DELETE_SEGMENT.CONFIRM')
        "
        icon="i-lucide-trash"
        color="ruby"
        size="sm"
        variant="ghost"
        @click="emit('deleteSegment')"
      />
    </div>
  </div>

  <header
    v-else
    class="sticky top-0 z-20 border-b border-n-weak bg-n-surface-1 px-6"
  >
    <div
      class="mx-auto flex w-full max-w-6xl flex-col gap-4 py-5 lg:flex-row lg:items-center lg:justify-between"
    >
      <span class="text-xl font-semibold tracking-tight text-n-slate-12">
        {{ headerTitle }}
      </span>
      <div
        class="flex w-full flex-col gap-3 lg:w-auto lg:flex-row lg:items-center"
      >
        <div v-if="showSearch" class="flex min-w-0 items-center gap-2 lg:w-72">
          <Input
            :model-value="searchValue"
            type="search"
            :placeholder="$t('CONTACTS_LAYOUT.HEADER.SEARCH_PLACEHOLDER')"
            :custom-input-class="[
              'h-8 [&:not(.focus)]:!border-transparent bg-n-alpha-2 dark:bg-n-solid-1 ltr:!pl-8 !py-1 rtl:!pr-8',
            ]"
            class="w-full"
            @input="emit('search', $event.target.value)"
          >
            <template #prefix>
              <Icon
                icon="i-lucide-search"
                class="absolute -translate-y-1/2 text-n-slate-11 size-4 top-1/2 ltr:left-2 rtl:right-2"
              />
            </template>
          </Input>
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <div
            class="flex items-center gap-1 rounded-xl border border-n-weak bg-n-solid-1 p-1 shadow-sm"
          >
            <div v-if="!isLabelView && !isActiveView" class="relative">
              <Button
                id="toggleContactsFilterButton"
                v-tooltip.top="$t('CONTACTS_LAYOUT.FILTER.TITLE')"
                :icon="
                  isSegmentsView ? 'i-lucide-pen-line' : 'i-lucide-list-filter'
                "
                color="slate"
                size="sm"
                class="relative w-8"
                :variant="hasActiveFilters ? 'faded' : 'ghost'"
                @click="emit('filter')"
              >
                <div
                  v-if="hasActiveFilters && !isSegmentsView"
                  class="absolute top-0 right-0 w-2 h-2 rounded-full bg-n-brand"
                />
              </Button>
              <slot name="filter" />
            </div>
            <Button
              v-if="
                hasActiveFilters &&
                !isSegmentsView &&
                !isLabelView &&
                !isActiveView
              "
              v-tooltip.top="
                $t(
                  'CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.CREATE_SEGMENT.CONFIRM'
                )
              "
              icon="i-lucide-save"
              color="slate"
              size="sm"
              variant="ghost"
              @click="emit('createSegment')"
            />
            <Button
              v-if="isSegmentsView && !isLabelView && !isActiveView"
              v-tooltip.top="
                $t(
                  'CONTACTS_LAYOUT.HEADER.ACTIONS.FILTERS.DELETE_SEGMENT.CONFIRM'
                )
              "
              icon="i-lucide-trash"
              color="slate"
              size="sm"
              variant="ghost"
              @click="emit('deleteSegment')"
            />
            <ContactSortMenu
              :active-sort="activeSort"
              :active-ordering="activeOrdering"
              @update:sort="emit('update:sort', $event)"
            />
            <ContactMoreActions
              @add="emit('add')"
              @import="emit('import')"
              @export="emit('export')"
            />
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <Button
              :label="
                $t(
                  'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT'
                )
              "
              icon="i-lucide-plus"
              color="teal"
              size="sm"
              class="shadow-sm"
              @click="emit('add')"
            />
            <Button
              v-if="canManageContacts"
              :label="
                $t(
                  'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.IMPORT_CONTACT'
                )
              "
              icon="i-lucide-download"
              color="blue"
              variant="faded"
              size="sm"
              @click="emit('import')"
            />
            <Button
              v-if="canManageContacts"
              :label="
                $t(
                  'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.EXPORT_CONTACT'
                )
              "
              icon="i-lucide-upload"
              color="slate"
              variant="outline"
              size="sm"
              @click="emit('export')"
            />
          </div>
          <ComposeConversation>
            <template #trigger>
              <Button
                :label="buttonLabel"
                icon="i-lucide-send"
                size="sm"
                class="shadow-sm"
              />
            </template>
          </ComposeConversation>
        </div>
      </div>
    </div>
  </header>
</template>
