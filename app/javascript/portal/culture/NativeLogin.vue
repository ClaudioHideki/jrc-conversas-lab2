<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { signIn } from './client';

const emit = defineEmits(['authenticated']);
const { t } = useI18n();
const email = ref('');
const password = ref('');
const code = ref('');
const challenge = ref('');
const sessions = ref([]);
const error = ref('');
const busy = ref(false);

async function submit(revokeId) {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const credentials = challenge.value
      ? {
          mfa_token: challenge.value,
          ...(/^\d{6}$/.test(code.value)
            ? { otp_code: code.value }
            : { backup_code: code.value }),
        }
      : {
          email: email.value,
          password: password.value,
          ...(revokeId ? { revoke_session_id: revokeId } : {}),
        };
    const response = await signIn(credentials);
    if (response.mfa_required) {
      challenge.value = response.mfa_token;
      password.value = '';
    } else if (response.sessions_limit_reached) {
      sessions.value = response.sessions;
    } else {
      password.value = '';
      emit('authenticated', response.accounts);
    }
  } catch (failure) {
    error.value =
      failure.status === 403 && failure.code !== 'login_failed'
        ? 'forbidden'
        : 'login_error';
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <form
    class="mx-auto mt-8 grid max-w-md gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-6"
    @submit.prevent="submit()"
  >
    <h2 class="text-xl font-semibold">{{ t('login') }}</h2>
    <template v-if="!challenge">
      <label class="grid gap-1.5">
        {{ t('email') }}
        <input
          v-model="email"
          class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
          required
          type="email"
          autocomplete="username"
        />
      </label>
      <label class="grid gap-1.5">
        {{ t('password') }}
        <input
          v-model="password"
          class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
          required
          type="password"
          autocomplete="current-password"
        />
      </label>
    </template>
    <label v-else class="grid gap-1.5">
      {{ t('verification') }}
      <input
        v-model="code"
        class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
        required
        autocomplete="one-time-code"
      />
    </label>
    <p v-if="error" class="text-n-ruby-11" role="alert">{{ t(error) }}</p>
    <div v-if="sessions.length" class="grid gap-2">
      <p>{{ t('sessions') }}</p>
      <button
        v-for="item in sessions"
        :key="item.id"
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2 text-left"
        :disabled="busy"
        @click="submit(item.id)"
      >
        {{ item.device || item.name || item.id }}
      </button>
    </div>
    <button
      class="rounded-lg bg-blue-700 px-4 py-2.5 font-semibold text-white disabled:opacity-50"
      :disabled="busy"
    >
      {{ t(busy ? 'loading' : 'login') }}
    </button>
    <a href="/app/auth/reset/password" class="w-fit text-n-blue-11 underline">{{
      t('recovery')
    }}</a>
  </form>
</template>
