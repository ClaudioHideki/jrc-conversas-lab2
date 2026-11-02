<script setup>
import { inject, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { login, request, errorKey } from './client';

const { t } = useI18n();
const samlEnabled = inject('portalSamlEnabled', false);
const email = ref('');
const password = ref('');
const verification = ref('');
const mfaToken = ref('');
const sessions = ref([]);
const busy = ref(false);
const feedback = ref('');
const submit = async revokeId => {
  if (busy.value) return;
  busy.value = true;
  feedback.value = '';
  try {
    const fields = mfaToken.value
      ? {
          mfa_token: mfaToken.value,
          ...(/^\d{6}$/.test(verification.value)
            ? { otp_code: verification.value }
            : { backup_code: verification.value }),
        }
      : {
          email: email.value,
          password: password.value,
          ...(revokeId ? { revoke_session_id: revokeId } : {}),
        };
    const result = await login(fields);
    if (result.mfa_required) {
      mfaToken.value = result.mfa_token;
      password.value = '';
    } else if (result.sessions_limit_reached) sessions.value = result.sessions;
    else {
      password.value = '';
      window.location.assign('/portal');
    }
  } catch (failure) {
    feedback.value = errorKey(failure);
  } finally {
    busy.value = false;
  }
};
const recover = async () => {
  if (!email.value || busy.value) return;
  busy.value = true;
  try {
    await request('/auth/password', {
      method: 'POST',
      body: { email: email.value },
    });
    feedback.value = 'PORTAL.RECOVERY_SENT';
  } catch (failure) {
    feedback.value = errorKey(failure);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <main
    class="flex min-h-screen items-center justify-center bg-slate-50 px-5 py-10 text-slate-800"
  >
    <div
      class="grid w-full max-w-4xl overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm md:grid-cols-2"
    >
      <section
        class="flex flex-col justify-between bg-slate-900 p-8 text-white md:p-12"
      >
        <div>
          <div class="mb-12 text-xl font-bold">{{ t('PORTAL.BRAND') }}</div>
          <p class="mb-3 text-sm text-blue-200">{{ t('PORTAL.TITLE') }}</p>
          <h1 class="text-3xl font-semibold leading-tight">
            {{ t('PORTAL.LOGIN_TITLE') }}
          </h1>
          <p class="mt-5 text-sm leading-relaxed text-slate-300">
            {{ t('PORTAL.LOGIN_DESCRIPTION') }}
          </p>
        </div>
      </section>
      <form
        class="space-y-5 p-8 md:p-12"
        @submit.prevent="submit()"
      >
        <h2 class="text-xl font-semibold">{{ t('PORTAL.SIGN_IN') }}</h2>
        <p
          v-if="feedback"
          role="alert"
          class="rounded-xl bg-slate-100 p-3 text-sm"
        >
          {{ t(feedback) }}
        </p>
        <template v-if="!mfaToken">
          <label class="block text-sm font-medium">
            {{ t('PORTAL.EMAIL') }}
            <input
              v-model="email"
              type="email"
              autocomplete="username"
              required
              class="mt-2 w-full rounded-xl border border-slate-300 px-3 py-3"
            />
          </label>
          <label class="block text-sm font-medium">
            {{ t('PORTAL.PASSWORD') }}
            <input
              v-model="password"
              type="password"
              autocomplete="current-password"
              required
              class="mt-2 w-full rounded-xl border border-slate-300 px-3 py-3"
            />
          </label>
        </template>
        <template v-else>
          <p class="text-sm text-slate-500">{{ t('PORTAL.MFA_HELP') }}</p>
          <label class="block text-sm font-medium">
            {{ t('PORTAL.MFA') }}
            <input
              v-model="verification"
              autocomplete="one-time-code"
              required
              class="mt-2 w-full rounded-xl border border-slate-300 px-3 py-3"
            />
          </label>
        </template>
        <template v-if="sessions.length">
          <p class="text-sm">{{ t('PORTAL.SESSION_LIMIT') }}</p>
          <button
            v-for="session in sessions"
            :key="session.id"
            type="button"
            :disabled="busy"
            class="block w-full rounded-xl border border-slate-200 p-3 text-left text-sm"
            @click="submit(session.id)"
          >
            {{ session.browser_name }} · {{ session.device_name }} ·
            {{ session.platform_name }}
          </button>
        </template>
        <button
          :disabled="busy"
          class="w-full rounded-xl bg-slate-900 px-4 py-3 font-semibold text-white disabled:opacity-50"
        >
          {{ t(busy ? 'PORTAL.LOADING' : 'PORTAL.SIGN_IN') }}
        </button>
        <button
          v-if="!mfaToken"
          type="button"
          :disabled="busy"
          class="w-full py-2 text-sm text-slate-600 underline"
          @click="recover"
        >
          {{ t('PORTAL.RECOVER') }}
        </button>
        <a
          v-if="samlEnabled && !mfaToken"
          href="/app/login/sso"
          class="block text-center text-sm text-slate-600 underline"
        >
          {{ t('PORTAL.SSO') }}
        </a>
      </form>
    </div>
  </main>
</template>
