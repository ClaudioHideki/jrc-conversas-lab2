<script setup>
import { ref, watch } from 'vue';
import { useProjects } from '../../jrcProjects/useProjects';
import { request, errorMessage, formatDate } from '../api';
const props = defineProps({
  endpoint: { type: String, required: true },
  canEdit: Boolean,
});
const emit = defineEmits(['changed']);
const { accountId, projectText } = useProjects();
const files = ref([]);
const error = ref('');
const busy = ref(false);
const loading = ref(false);
const selected = ref([]);
const upload = ref(null);
let generation = 0;
async function load() {
  const n = ++generation;
  loading.value = true;
  error.value = '';
  try {
    const result = await request(accountId.value, props.endpoint);
    if (n === generation) files.value = result.data;
  } catch (err) {
    if (n === generation) error.value = errorMessage(err);
  } finally {
    if (n === generation) loading.value = false;
  }
}
watch(
  () => [props.endpoint, accountId.value],
  () => {
    files.value = [];
    selected.value = [];
    load();
  },
  { immediate: true }
);
async function submit() {
  if (busy.value || !props.canEdit || !selected.value.length) return;
  busy.value = true;
  error.value = '';
  try {
    const body = new FormData();
    for (const file of selected.value) body.append('files[]', file);
    await request(accountId.value, props.endpoint, {
      method: 'post',
      data: body,
    });
    selected.value = [];
    if (upload.value) upload.value.value = '';
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function remove(file) {
  if (
    busy.value ||
    !props.canEdit ||
    !window.confirm(
      `${projectText('REMOVE_ATTACHMENT', 'Remover anexo')}: ${file.name}?`
    )
  )
    return;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${props.endpoint}/${file.id}`, {
      method: 'delete',
    });
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <section class="flex flex-col gap-4">
    <h3>{{ projectText('INTERNAL_FILES', 'Arquivos internos') }}</h3>
    <p class="text-n-slate-11 text-sm">
      {{
        projectText(
          'INTERNAL_FILES_HELP',
          'Anexos do projeto não são enviados ao cliente. Compartilhe pelo atendimento quando necessário.'
        )
      }}
    </p>
    <div
      v-if="error"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
      role="alert"
    >
      {{ error }}
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
        @click="load"
      >
        {{ projectText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <p v-if="loading" role="status">
      {{ projectText('FILES_LOADING', 'Carregando arquivos...') }}
    </p>
    <div
      v-for="file in files"
      :key="file.id"
      class="flex flex-wrap items-center gap-3 justify-between"
    >
      <div>
        <a
          class="text-n-blue-11 underline"
          :href="file.url"
          target="_blank"
          rel="noopener noreferrer"
          >{{ file.name }}</a>
        <p class="text-n-slate-11 text-sm">
          {{ projectText('UPLOADED_BY', 'Enviado por') }}:
          {{
            file.uploaded_by?.name ||
            projectText('UPLOADER_UNKNOWN', 'Não identificado no histórico')
          }}
          · {{ formatDate(file.created_at) }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-3">
        <a
          class="text-n-blue-11 underline"
          :href="file.download_url || file.url"
          target="_blank"
          rel="noopener noreferrer"
          >{{ projectText('DOWNLOAD', 'Baixar') }}</a><button
          v-if="canEdit"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs text-n-ruby-11"
          :disabled="busy"
          @click="remove(file)"
        >
          {{ projectText('REMOVE', 'Remover') }}
        </button>
      </div>
    </div>
    <p
      v-if="!loading && !error && !files.length"
      class="text-n-slate-11 text-sm"
    >
      {{ projectText('NO_FILES', 'Nenhum anexo.') }}
    </p>
    <form
      v-if="canEdit"
      class="flex flex-wrap items-center gap-3"
      @submit.prevent="submit"
    >
      <input
        ref="upload"
        type="file"
        multiple
        :aria-label="projectText('INTERNAL_FILES', 'Arquivos internos')"
        @change="selected = Array.from($event.target.files || [])"
      /><button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
        :disabled="busy || !selected.length"
      >
        {{ projectText('UPLOAD_FILES', 'Enviar arquivos') }}</button><small class="text-n-slate-11 text-sm">{{
        projectText('UPLOAD_LIMIT', 'Até 10 arquivos de 20 MB por envio.')
      }}</small>
    </form>
  </section>
</template>
