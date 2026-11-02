<script setup>
import { inject } from 'vue';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();
const context = inject('portalContext');
</script>

<template>
  <section class="space-y-6">
    <h1 class="text-2xl font-semibold text-slate-900">
      {{ t('PORTAL.PROFILE') }}
    </h1>
    <div class="rounded-2xl border border-slate-200 bg-white p-6 sm:p-8">
      <dl class="grid gap-6 text-sm sm:grid-cols-2">
        <div
          v-for="(value, key) in {
            NAME: context.contact.name,
            EMAIL: context.contact.email,
            PHONE: context.contact.phone_number,
            ORGANIZATION: context.organization,
            ROLE: t(`PORTAL.ROLES.${context.role}`),
          }"
          :key="key"
        >
          <dt class="text-xs text-slate-500">{{ t(`PORTAL.${key}`) }}</dt>
          <dd class="mt-2 break-words font-semibold">{{ value }}</dd>
        </div>
      </dl>
      <p class="mt-8 text-sm leading-relaxed text-slate-500">
        {{ t('PORTAL.PROFILE_HELP') }}
      </p>
    </div>
  </section>
</template>
