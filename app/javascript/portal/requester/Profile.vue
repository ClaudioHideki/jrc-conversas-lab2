<script setup>
import { inject } from 'vue';
import { useI18n } from 'vue-i18n';
import PortalIcon from './PortalIcon.vue';
import PortalHeading from './PortalHeading.vue';
const { t } = useI18n();
const context = inject('portalContext');
</script>

<template>
  <section class="space-y-6">
    <PortalHeading
      icon="user"
      :title="t('PORTAL.PROFILE')"
      :subtitle="t('PORTAL.TITLE')"
    />
    <div
      class="space-y-6 rounded-2xl border border-blue-200/80 bg-white/90 p-6 shadow-[0_3px_12px_#0754a414] sm:p-8"
    >
      <div class="flex flex-wrap items-center gap-6">
        <span
          class="flex h-28 w-28 items-center justify-center rounded-full border-4 border-white bg-gradient-to-b from-sky-400 via-blue-600 to-blue-900 text-white shadow-md"
        >
          <PortalIcon
            name="user"
            class="h-16 w-16"
          />
        </span>
        <div class="min-w-0 border-l-4 border-blue-600 pl-6">
          <div class="flex flex-wrap items-center gap-3">
            <h2 class="break-words text-2xl font-bold sm:text-3xl">
              {{ context.contact.name }}
            </h2>
            <span
              class="rounded-full bg-blue-100 px-4 py-1 text-sm text-blue-900"
            >
              {{ t(`PORTAL.ROLES.${context.role}`) }}
            </span>
          </div>
          <p class="mt-3 flex items-center gap-2 text-base">
            <PortalIcon name="building" />
            {{ context.organization }}
          </p>
        </div>
      </div>
      <dl
        class="grid gap-5 rounded-2xl border border-blue-100 bg-blue-50/70 p-5 md:grid-cols-3 md:divide-x md:divide-blue-200"
      >
        <div
          v-for="field in [
            { key: 'EMAIL', value: context.contact.email, icon: 'mail' },
            {
              key: 'PHONE',
              value: context.contact.phone_number,
              icon: 'phone',
            },
            {
              key: 'ROLE',
              value: t(`PORTAL.ROLES.${context.role}`),
              icon: 'user',
            },
          ]"
          :key="field.key"
          class="flex min-w-0 items-start gap-3 md:px-3"
        >
          <span class="rounded-xl bg-blue-100 p-3 text-blue-700">
            <PortalIcon :name="field.icon" />
          </span>
          <div class="min-w-0">
            <dt class="text-sm text-slate-600">
              {{ t(`PORTAL.${field.key}`) }}
            </dt>
            <dd class="mt-1 break-words font-bold">{{ field.value }}</dd>
          </div>
        </div>
      </dl>
      <p
        class="flex items-start gap-3 rounded-xl border border-blue-200 bg-blue-50/60 p-4 text-sm leading-relaxed text-slate-600"
      >
        <PortalIcon
          name="info"
          class="text-blue-700"
        />
        {{ t('PORTAL.PROFILE_HELP') }}
      </p>
    </div>
    <div
      class="grid gap-4 rounded-2xl border border-blue-200/80 bg-white/90 p-5 shadow-sm sm:grid-cols-2"
    >
      <RouterLink
        to="/chamados"
        class="flex items-center gap-4 rounded-xl border border-blue-200 bg-blue-50/50 p-5 font-semibold text-blue-900 hover:bg-blue-100"
      >
        <PortalIcon name="headset" />
        {{ t('PORTAL.TICKETS') }}
      </RouterLink>
      <RouterLink
        to="/login"
        class="flex items-center gap-4 rounded-xl border border-blue-200 bg-blue-50/50 p-5 font-semibold text-blue-900 hover:bg-blue-100"
      >
        <PortalIcon name="user" />
        {{ t('PORTAL.RECOVER') }}
      </RouterLink>
    </div>
  </section>
</template>
