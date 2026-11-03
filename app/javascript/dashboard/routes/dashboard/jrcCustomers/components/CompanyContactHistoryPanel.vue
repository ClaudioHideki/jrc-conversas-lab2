<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, buttonClass, errorMessage } from '../copy';
import { companyContactRoleLabels } from './companyContactRoles';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const roleLabels = computed(() => companyContactRoleLabels(t));
const { accountId, identity, date } = useCustomerMaster();
const rows = ref([]);
const page = ref(1);
const meta = ref({ total: 0, per_page: 25 });
const busy = ref(false);
const error = ref('');
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  meta.value = { total: 0, per_page: 25 };
  error.value = '';
  busy.value = true;
  try {
    const { data } = await API.contactCompanyHistory(
      props.contactId,
      { page: page.value },
      { accountId: accountId.value, signal: controller.signal }
    );
    if (version !== generation) return;
    rows.value = data.payload;
    meta.value = data.meta;
  } catch (failure) {
    if (version === generation) error.value = errorMessage(failure);
  } finally {
    if (version === generation) busy.value = false;
  }
};
watch(
  [identity, () => props.contactId],
  () => {
    if (page.value !== 1) page.value = 1;
    else load();
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4">
    <h3 class="text-base font-semibold">
      {{ t('CRM.COMPANY_CONTACT_CONTEXT.HISTORY') }}
    </h3>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <p
      v-else-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-else-if="!rows.length"
      class="text-sm text-n-slate-10"
    >
      {{ T.noResults }}
    </p>
    <article
      v-for="row in rows"
      :key="row.id"
      class="rounded-lg border border-n-weak p-3 text-sm"
    >
      <p class="font-semibold">
        {{
          row.kind === 'customer_contact_primary_changed'
            ? t('CRM.COMPANY_CONTACT_CONTEXT.PRIMARY_CHANGED')
            : t('CRM.COMPANY_CONTACT_CONTEXT.CHANGED')
        }}
      </p>
      <p class="text-xs text-n-slate-10">
        {{ [date(row.at), row.actor_name].filter(Boolean).join(' · ') }}
      </p>
      <dl class="mt-3 grid gap-3 sm:grid-cols-2">
        <div
          v-for="side in ['from', 'to']"
          :key="side"
        >
          <dt class="font-medium">
            {{
              side === 'from'
                ? t('CRM.COMPANY_CONTACT_CONTEXT.FROM')
                : t('CRM.COMPANY_CONTACT_CONTEXT.TO')
            }}
          </dt>
          <dd
            v-if="row[side]?.restricted"
            class="text-n-slate-10"
          >
            {{ t('CRM.COMPANY_CONTACT_CONTEXT.RESTRICTED') }}
          </dd>
          <dd
            v-else-if="row[side]"
            class="space-y-1 break-words"
          >
            <p>
              {{
                row[side].company_name ||
                t('CRM.COMPANY_CONTACT_CONTEXT.NO_COMPANY')
              }}
            </p>
            <p>{{ row[side].job_title }} {{ row[side].department }}</p>
            <p v-if="row[side].company_role">
              {{ roleLabels[row[side].company_role] }}
            </p>
            <p
              v-if="row[side].company_primary"
              class="font-semibold text-n-teal-11"
            >
              {{ t('CRM.COMPANY_CONTACT_CONTEXT.PRIMARY') }}
            </p>
            <p v-if="row[side].company_contact_status">
              {{
                row[side].company_contact_status === 'inactive'
                  ? t('CRM.COMPANY_CONTACT_CONTEXT.INACTIVE')
                  : t('CRM.COMPANY_CONTACT_CONTEXT.ACTIVE')
              }}
            </p>
          </dd>
          <dd v-else>{{ t('CRM.COMPANY_CONTACT_CONTEXT.NO_CONTEXT') }}</dd>
        </div>
      </dl>
    </article>
    <div
      v-if="!error"
      class="flex flex-wrap items-center gap-3"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page <= 1"
        @click="page--"
      >
        {{ T.previous }}
      </button>
      <span class="text-sm">
        {{
          t('CRM.COMPANY_CONTACT_CONTEXT.PAGE', {
            page,
            total: Math.max(1, Math.ceil(meta.total / meta.per_page)),
          })
        }}
      </span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page * meta.per_page >= meta.total"
        @click="page++"
      >
        {{ T.next }}
      </button>
    </div>
  </section>
</template>
