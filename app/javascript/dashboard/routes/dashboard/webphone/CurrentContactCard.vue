<script setup>
import { computed } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  contact: { type: Object, default: null },
  phoneNumber: { type: String, default: '' },
  loading: { type: Boolean, default: false },
  accountId: { type: [Number, String], required: true },
  companyName: { type: String, default: '' },
  searchQuery: { type: String, default: '' },
  searchResults: { type: Array, default: () => [] },
  searching: { type: Boolean, default: false },
  loadingMore: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:searchQuery',
  'selectContact',
  'dialContact',
  'loadMore',
]);

const isDesktop = Boolean(window.jrcSoftphoneDesktop);
const openInJrc = () =>
  window.jrcSoftphoneDesktop
    .openContact({
      accountId: String(props.accountId),
      contactId: String(props.contact.id),
    })
    .catch(() => {});

const TEXT = Object.freeze({
  title: 'CONTATO ATUAL',
  identifying: 'Identificando contato...',
  unknown: 'Contato não cadastrado',
  empty: 'Nenhum contato selecionado',
  viewContact: 'Ver contato',
  searchPlaceholder: 'Buscar nome ou telefone',
  contactsTitle: 'Contatos próximos',
  searching: 'Buscando contatos...',
  emptyResults: 'Nenhum contato com telefone encontrado',
  call: 'Ligar',
  loadMore: 'Carregar mais',
});

const contactName = computed(() => {
  if (props.contact?.name) return props.contact.name;
  return props.phoneNumber ? TEXT.unknown : TEXT.empty;
});
const contactPhone = computed(
  () =>
    props.contact?.phone_number ||
    props.contact?.phoneNumber ||
    props.phoneNumber
);
const contactEmail = computed(() => props.contact?.email || '');
const contactThumbnail = computed(() => props.contact?.thumbnail || '');
const companyName = computed(
  () =>
    props.companyName ||
    props.contact?.company?.name ||
    props.contact?.company_name ||
    props.contact?.companyName ||
    props.contact?.additional_attributes?.company_name ||
    props.contact?.additionalAttributes?.companyName ||
    ''
);
const contactId = computed(() => props.contact?.id);

const resultName = contact => contact?.name || 'Contato sem nome';
const resultPhone = contact =>
  contact?.phone_number || contact?.phoneNumber || '';
const resultEmail = contact => contact?.email || '';
const resultThumbnail = contact => contact?.thumbnail || '';
const selectContact = contact => emit('selectContact', contact);
</script>

<template>
  <section
    class="flex flex-col rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
  >
    <div class="shrink-0">
      <p class="text-xs font-bold tracking-[0.12em] text-n-teal-11">
        {{ TEXT.title }}
      </p>
      <div
        v-if="loading"
        class="mt-3 flex items-center gap-3 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-5 animate-spin" />
        {{ TEXT.identifying }}
      </div>
      <div v-else class="mt-3 flex items-start gap-3">
        <Avatar
          :name="contactName"
          :src="contactThumbnail"
          :size="44"
          rounded-full
          class="shrink-0"
        />
        <div class="min-w-0 flex-1">
          <p class="truncate font-semibold text-n-slate-12">
            {{ contactName }}
          </p>
          <p
            v-if="contactPhone"
            class="mt-1 flex items-center gap-1.5 truncate text-sm text-n-slate-11"
          >
            <span class="i-lucide-phone size-3.5 shrink-0" />
            {{ contactPhone }}
          </p>
          <a
            v-if="contactEmail"
            :href="`mailto:${contactEmail}`"
            class="mt-1 flex items-center gap-1.5 truncate text-sm text-n-brand hover:underline"
          >
            <span class="i-lucide-mail size-3.5 shrink-0" />
            {{ contactEmail }}
          </a>
          <p
            v-if="companyName"
            class="mt-1 flex items-center gap-1.5 truncate text-sm text-n-slate-10"
          >
            <span class="i-lucide-building-2 size-3.5 shrink-0" />
            {{ companyName }}
          </p>
        </div>
        <button
          v-if="contactId && isDesktop"
          type="button"
          class="shrink-0 text-xs font-semibold text-n-brand hover:underline"
          @click="openInJrc"
        >
          {{ $t('SOFTPHONE.OPEN_IN_JRC') }}
        </button>
        <RouterLink
          v-else-if="contactId"
          :to="{
            name: 'contacts_edit',
            params: { accountId, contactId },
          }"
          class="shrink-0 text-xs font-semibold text-n-brand hover:underline"
        >
          {{ TEXT.viewContact }}
        </RouterLink>
      </div>
    </div>

    <div class="mt-5 flex min-h-0 flex-1 flex-col border-t border-n-weak pt-4">
      <label class="text-sm font-medium text-n-slate-12">
        {{ TEXT.contactsTitle }}
      </label>
      <div class="relative mt-2">
        <span
          class="i-lucide-search pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
        />
        <input
          :value="searchQuery"
          type="search"
          :placeholder="TEXT.searchPlaceholder"
          class="h-9 w-full rounded-lg border border-n-weak bg-n-alpha-1 pl-9 pr-3 text-sm text-n-slate-12 outline-none transition focus:border-n-brand"
          @input="emit('update:searchQuery', $event.target.value)"
        />
      </div>

      <div
        v-if="searching"
        class="mt-4 flex items-center gap-2 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-4 animate-spin" />
        {{ TEXT.searching }}
      </div>
      <div
        v-else-if="!searchResults.length && !hasMore"
        class="mt-4 text-sm text-n-slate-10"
      >
        {{ TEXT.emptyResults }}
      </div>
      <div v-else class="mt-3 min-h-0 flex-1 space-y-2 overflow-y-auto pr-1">
        <div
          v-for="result in searchResults"
          :key="result.id"
          class="flex w-full items-center gap-2 rounded-lg border border-n-weak bg-n-alpha-1 p-2 transition hover:bg-n-alpha-2"
        >
          <button
            type="button"
            class="flex min-w-0 flex-1 items-center gap-3 p-1 text-left"
            @click="selectContact(result)"
          >
            <Avatar
              :name="resultName(result)"
              :src="resultThumbnail(result)"
              :size="32"
              rounded-full
              class="shrink-0"
            />
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm font-medium text-n-slate-12">
                {{ resultName(result) }}
              </span>
              <span class="block truncate text-xs text-n-slate-11">
                {{ resultPhone(result) }}
              </span>
              <span
                v-if="resultEmail(result)"
                class="block truncate text-xs text-n-slate-10"
              >
                {{ resultEmail(result) }}
              </span>
            </span>
          </button>
          <button
            type="button"
            class="inline-flex size-9 shrink-0 items-center justify-center rounded-lg bg-n-teal-3 text-n-teal-11 transition hover:bg-n-teal-4"
            :title="`${TEXT.call}: ${resultName(result)}`"
            @click="emit('dialContact', result)"
          >
            <span class="i-lucide-phone size-4" />
          </button>
        </div>
        <button
          v-if="hasMore"
          type="button"
          class="flex min-h-10 w-full items-center justify-center gap-2 rounded-lg border border-n-brand px-3 text-sm font-semibold text-n-brand transition hover:bg-n-alpha-2 disabled:opacity-60"
          :disabled="loadingMore"
          @click="emit('loadMore')"
        >
          <span
            v-if="loadingMore"
            class="i-lucide-loader-2 size-4 animate-spin"
          />
          {{ TEXT.loadMore }}
        </button>
      </div>
    </div>
  </section>
</template>
