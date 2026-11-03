<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useOperationalContacts } from './useOperationalContacts';
import { useCustomerMaster } from './useCustomerMaster';
import CompanyDetailsDialog from './components/CompanyDetailsDialog.vue';
import ContactDetailsDialog from './components/ContactDetailsDialog.vue';
import SegmentFilterPicker from './components/SegmentFilterPicker.vue';
import OperationalContactActions from './components/OperationalContactActions.vue';
import { T, inputClass, buttonClass, primaryClass } from './copy';

const { t, tm } = useI18n();
const copy = computed(() => tm('CRM.OPERATIONAL_CONTACTS'));
const { date, accountScopedRoute } = useCustomerMaster();
const {
  identity,
  rows,
  meta,
  error,
  busy,
  filters,
  page,
  search,
  changePage,
  load,
} = useOperationalContacts();
const contactId = ref(null);
const companyId = ref(null);
const tones = {
  in_service: 'border-n-teal-6 bg-n-teal-3 text-n-teal-12',
  waiting: 'border-n-amber-6 bg-n-amber-3 text-n-amber-12',
  active: 'border-n-blue-6 bg-n-blue-3 text-n-blue-12',
};
const routeFor = record => {
  if (record.kind === 'conversation')
    return accountScopedRoute('inbox_conversation', {
      conversation_id: record.display_id,
    });
  if (record.kind === 'ticket')
    return accountScopedRoute('jrc_service_desk_detail', {
      ticketId: record.record_id,
    });
  if (record.kind === 'call')
    return accountScopedRoute('calls_dashboard_index');
  return accountScopedRoute(
    'crm_activities',
    {},
    {
      [record.kind === 'follow_up' ? 'followUpId' : 'activityId']:
        record.record_id,
    }
  );
};
watch(identity, () => {
  contactId.value = null;
  companyId.value = null;
});
</script>

<template>
  <main
    class="h-full min-w-0 w-full overflow-auto bg-n-solid-1 p-4 text-n-slate-12 md:p-6"
  >
    <header
      class="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-teal-6 bg-n-teal-3 p-5"
    >
      <div>
        <h1 class="text-xl font-bold">{{ copy.TITLE }}</h1>
        <p class="mt-2 max-w-3xl text-sm">{{ copy.HELP }}</p>
      </div>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="load"
      >
        {{ copy.REFRESH }}
      </button>
    </header>
    <form
      class="mb-5 grid gap-3 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4 sm:grid-cols-2 xl:grid-cols-3"
      @submit.prevent="search"
    >
      <label class="text-xs">
        {{ T.search }}
        <input
          v-model.trim="filters.q"
          :class="inputClass"
          :placeholder="copy.SEARCH"
        />
      </label>
      <label class="text-xs">
        {{ copy.STATUS }}
        <select
          v-model="filters.status"
          :class="inputClass"
        >
          <option value="">{{ T.all }}</option>
          <option
            v-for="(label, key) in copy.STATES"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select>
      </label>
      <label class="text-xs">
        {{ copy.SOURCE }}
        <select
          v-model="filters.kind"
          :class="inputClass"
        >
          <option value="">{{ T.all }}</option>
          <option
            v-for="(label, key) in copy.KINDS"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select>
      </label>
      <label class="text-xs">
        {{ copy.DAYS }}
        <input
          v-model="filters.days"
          type="number"
          min="1"
          max="365"
          required
          :class="inputClass"
        />
      </label>
      <div class="min-w-0 text-xs">
        <p>{{ t('CRM.CORPORATE_SEGMENTS.FILTER_LABEL') }}</p>
        <SegmentFilterPicker v-model="filters.taxonomy_id" />
      </div>
      <button
        type="submit"
        :class="primaryClass"
        class="self-end"
        :disabled="busy"
      >
        {{ copy.APPLY }}
      </button>
    </form>
    <p class="mb-4 text-sm text-n-slate-10">
      {{
        t('CRM.OPERATIONAL_CONTACTS.TOTAL', {
          total: meta.total,
          days: meta.days,
        })
      }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-3 text-n-ruby-12"
    >
      {{ error }}
    </p>
    <p
      v-if="!busy && !error && !rows.length"
      class="rounded-xl border border-n-weak p-6 text-sm"
    >
      {{ copy.EMPTY }}
    </p>
    <section
      class="space-y-4"
      :aria-label="copy.TITLE"
    >
      <article
        v-for="row in rows"
        :key="row.id"
        class="space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0">
            <button
              type="button"
              class="break-words text-left text-lg font-bold text-n-blue-11 underline"
              @click="contactId = row.id"
            >
              {{ row.name }}
            </button>
            <p
              v-if="row.company_id"
              class="mt-1"
            >
              <button
                type="button"
                class="break-words text-left text-sm font-medium text-n-teal-11 underline"
                @click="companyId = row.company_id"
              >
                {{ row.company_name }}
              </button>
            </p>
            <p
              v-else
              class="mt-1 text-sm text-n-slate-10"
            >
              {{ T.noCompany }}
            </p>
          </div>
          <span
            class="rounded-lg border px-3 py-1 text-sm font-semibold"
            :class="tones[row.operational_status]"
          >
            {{ copy.STATES[row.operational_status] }}
          </span>
        </div>
        <dl class="grid gap-4 text-sm md:grid-cols-3">
          <div>
            <dt class="text-n-slate-10">{{ copy.CONTEXT }}</dt>
            <dd
              v-if="row.context"
              class="mt-1 space-y-1"
            >
              <RouterLink
                :to="routeFor(row.context)"
                class="font-semibold text-n-blue-11 underline"
              >
                {{
                  row.context.title ||
                  `${copy.KINDS[row.context.kind]} #${row.context.display_id || row.context.record_id}`
                }}
              </RouterLink>
              <p>
                {{
                  row.context.channel_name ||
                  row.context.channel_type ||
                  copy.NO_CHANNEL
                }}
              </p>
              <p>{{ row.context.responsible?.name || copy.NO_OWNER }}</p>
            </dd>
            <dd v-else>{{ copy.NO_CONTEXT }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-10">{{ T.lastInteraction }}</dt>
            <dd class="mt-1">
              {{
                row.last_interaction_at
                  ? date(row.last_interaction_at)
                  : copy.NO_INTERACTION
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-10">{{ T.nextActivity }}</dt>
            <dd
              v-if="row.next_action"
              class="mt-1 space-y-1"
            >
              <RouterLink
                :to="routeFor(row.next_action)"
                class="font-semibold text-n-violet-11 underline"
              >
                {{ row.next_action.title }}
              </RouterLink>
              <p>{{ date(row.next_action.due_at) }}</p>
              <p>{{ row.next_action.responsible?.name || copy.NO_OWNER }}</p>
            </dd>
            <dd v-else>{{ T.noNextActivity }}</dd>
          </div>
        </dl>
        <OperationalContactActions :contact="row" />
      </article>
    </section>
    <nav
      class="my-5 flex flex-wrap items-center gap-3 pb-16"
      :aria-label="copy.PAGINATION"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page <= 1"
        @click="changePage(page - 1)"
      >
        {{ T.previous }}
      </button>
      <span class="text-sm">{{
        t('CRM.OPERATIONAL_CONTACTS.PAGE', { page })
      }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page * meta.per_page >= meta.total"
        @click="changePage(page + 1)"
      >
        {{ T.next }}
      </button>
    </nav>
    <ContactDetailsDialog
      v-if="contactId"
      :key="`${identity}:contact:${contactId}`"
      :contact-id="contactId"
      @close="contactId = null"
      @updated="load"
    />
    <CompanyDetailsDialog
      v-if="companyId"
      :key="`${identity}:company:${companyId}`"
      :company-id="companyId"
      @close="companyId = null"
      @updated="load"
    />
  </main>
</template>
