<script setup>
import { computed, ref, watch } from 'vue';
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
const query = ref('');
const category = ref('all');
const sort = ref('newest');
const page = ref(1);
const pageSize = 15;
const extension = file => file.name.split('.').pop().toLocaleLowerCase();
function fileCategory(file) {
  const type = extension(file);
  if (
    ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'heic', 'bmp'].includes(type)
  )
    return 'images';
  if (['xls', 'xlsx', 'csv', 'ods', 'tsv'].includes(type)) return 'sheets';
  if (['pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'ppt', 'pptx'].includes(type))
    return 'documents';
  return 'other';
}
const categories = computed(() =>
  [
    {
      key: 'all',
      label: projectText('ALL_FILES', 'Todos os arquivos'),
      icon: 'i-lucide-folder-open',
      color: 'text-n-blue-11 bg-n-blue-2',
    },
    {
      key: 'documents',
      label: projectText('DOCUMENTS', 'Documentos'),
      icon: 'i-lucide-file-text',
      color: 'text-n-iris-11 bg-n-iris-2',
    },
    {
      key: 'images',
      label: projectText('IMAGES', 'Imagens'),
      icon: 'i-lucide-image',
      color: 'text-n-teal-11 bg-n-teal-2',
    },
    {
      key: 'sheets',
      label: projectText('SPREADSHEETS', 'Planilhas'),
      icon: 'i-lucide-sheet',
      color: 'text-n-amber-11 bg-n-amber-2',
    },
    {
      key: 'other',
      label: projectText('OTHER_FILES', 'Outros arquivos'),
      icon: 'i-lucide-file',
      color: 'text-n-slate-11 bg-n-slate-3',
    },
  ].map(item => ({
    ...item,
    count:
      item.key === 'all'
        ? files.value.length
        : files.value.filter(file => fileCategory(file) === item.key).length,
  }))
);
const filtered = computed(() => {
  const term = query.value.trim().toLocaleLowerCase();
  const rows = files.value.filter(
    file =>
      (!term ||
        `${file.name} ${file.uploaded_by?.name || ''}`
          .toLocaleLowerCase()
          .includes(term)) &&
      (category.value === 'all' || fileCategory(file) === category.value)
  );
  return rows.sort((a, b) =>
    sort.value === 'name'
      ? a.name.localeCompare(b.name)
      : new Date(b.created_at) - new Date(a.created_at)
  );
});
const visible = computed(() =>
  filtered.value.slice((page.value - 1) * pageSize, page.value * pageSize)
);
const totalSize = computed(() =>
  files.value.reduce((sum, file) => sum + Number(file.byte_size || 0), 0)
);
const fileType = file =>
  categories.value.find(item => item.key === fileCategory(file));
const size = value => {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024)
    return `${(value / 1024).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} KB`;
  return `${(value / 1024 / 1024).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} MB`;
};
watch([query, category, sort], () => {
  page.value = 1;
});
let generation = 0;
async function load() {
  generation += 1;
  const n = generation;
  loading.value = true;
  error.value = '';
  try {
    const result = await request(accountId.value, props.endpoint);
    if (n === generation) {
      files.value = result.data;
      page.value = Math.min(
        page.value,
        Math.max(1, Math.ceil(filtered.value.length / pageSize))
      );
    }
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
    query.value = '';
    category.value = 'all';
    page.value = 1;
    load();
  },
  { immediate: true }
);
function selectFiles(event) {
  const values = Array.from(event.target.files || []);
  if (values.length > 10 || values.some(file => file.size > 20 * 1024 * 1024)) {
    error.value = projectText(
      'UPLOAD_LIMIT',
      'Até 10 arquivos de 20 MB por envio.'
    );
    selected.value = [];
    event.target.value = '';
    return;
  }
  error.value = '';
  selected.value = values;
}
async function submit() {
  if (busy.value || !props.canEdit || !selected.value.length) return;
  busy.value = true;
  error.value = '';
  try {
    const body = new FormData();
    selected.value.forEach(file => body.append('files[]', file));
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
  <section class="flex min-w-0 flex-col gap-4">
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="m-0 text-lg font-semibold">
          {{ projectText('FILES', 'Arquivos') }}
        </h2>
        <p class="mb-0 mt-1 text-sm text-n-slate-11">
          {{
            projectText(
              'FILES_SUBTITLE',
              'Documentos e anexos organizados em um só lugar.'
            )
          }}
        </p>
      </div>
      <button
        v-if="canEdit"
        class="flex items-center gap-2 rounded-lg bg-n-blue-9 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
        :disabled="busy"
        @click="upload?.click()"
      >
        <span class="i-lucide-upload size-4" />{{
          projectText('ADD_FILES', 'Adicionar arquivos')
        }}
      </button>
    </header>
    <div
      v-if="error"
      class="flex flex-wrap items-center gap-3 rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm"
      role="alert"
    >
      {{ error
      }}<button
        class="text-n-blue-11 underline"
        :disabled="busy || loading"
        @click="load"
      >
        {{ projectText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <div class="grid grid-cols-2 gap-3 xl:grid-cols-5">
      <button
        v-for="item in categories"
        :key="item.key"
        class="flex items-center gap-3 rounded-xl border bg-n-solid-1 p-4 text-left transition-colors"
        :class="
          category === item.key
            ? 'border-n-blue-8 ring-1 ring-n-blue-7'
            : 'border-n-weak hover:border-n-blue-6'
        "
        :aria-pressed="category === item.key"
        @click="category = item.key"
      >
        <span
          class="flex size-10 shrink-0 items-center justify-center rounded-lg"
          :class="item.color"
          ><span class="size-5" :class="item.icon" aria-hidden="true" /></span
        ><span class="min-w-0"
          ><strong class="block truncate text-sm">{{ item.label }}</strong
          ><span class="text-xs text-n-slate-11"
            >{{ item.count }}
            {{ projectText('FILES_COUNT_LABEL', 'arquivos') }}</span
          ></span
        >
      </button>
    </div>
    <form v-if="canEdit" class="flex flex-col gap-3" @submit.prevent="submit">
      <input
        ref="upload"
        type="file"
        multiple
        class="sr-only"
        :aria-label="projectText('UPLOAD_FILES', 'Enviar arquivos')"
        @change="selectFiles"
      />
      <div
        v-if="selected.length"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-4"
      >
        <div class="min-w-0">
          <p class="m-0 text-sm font-medium">
            {{ selected.map(file => file.name).join(', ') }}
          </p>
          <span class="text-xs text-n-slate-11">{{
            projectText('UPLOAD_LIMIT', 'Até 10 arquivos de 20 MB por envio.')
          }}</span>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm disabled:opacity-50"
            :disabled="busy"
            @click="selected = []"
          >
            {{ projectText('CANCEL', 'Cancelar') }}</button
          ><button
            class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm text-white disabled:opacity-50"
            :disabled="busy"
          >
            {{
              busy
                ? projectText('UPLOADING', 'Enviando...')
                : projectText('UPLOAD_FILES', 'Enviar arquivos')
            }}
          </button>
        </div>
      </div>
    </form>
    <div class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1">
      <div class="flex flex-wrap items-center gap-3 border-b border-n-weak p-3">
        <label
          class="flex min-w-44 flex-1 items-center gap-2 rounded-lg border border-n-weak px-3"
          ><span class="i-lucide-search size-4 text-n-slate-10" /><input
            v-model="query"
            class="min-w-0 flex-1 border-0 bg-transparent py-2 text-sm outline-none"
            :placeholder="
              projectText('SEARCH_FILES', 'Pesquisar por arquivo ou autor...')
            "
            :aria-label="
              projectText('SEARCH_FILES', 'Pesquisar por arquivo ou autor...')
            " /></label
        ><select
          v-model="sort"
          class="w-auto rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
          :aria-label="projectText('SORT_FILES', 'Ordenar arquivos')"
        >
          <option value="newest">
            {{ projectText('NEWEST_FILES', 'Mais recentes') }}
          </option>
          <option value="name">
            {{ projectText('FILE_NAME', 'Nome do arquivo') }}
          </option></select
        ><span class="text-xs text-n-slate-11"
          >{{ files.length }}
          {{ projectText('FILES_COUNT_LABEL', 'arquivos') }} ·
          {{ size(totalSize) }}</span
        >
      </div>
      <p v-if="loading" class="p-5 text-sm text-n-slate-11" role="status">
        {{ projectText('FILES_LOADING', 'Carregando arquivos...') }}
      </p>
      <div v-else class="overflow-x-auto">
        <table class="w-full min-w-[700px] text-left text-sm">
          <thead class="bg-n-slate-2 text-xs text-n-slate-11">
            <tr>
              <th class="px-4 py-3">
                {{ projectText('FILE_NAME', 'Nome do arquivo') }}
              </th>
              <th class="px-4 py-3">{{ projectText('SIZE', 'Tamanho') }}</th>
              <th class="px-4 py-3">{{ projectText('AUTHOR', 'Autor') }}</th>
              <th class="px-4 py-3">{{ projectText('DATE', 'Data') }}</th>
              <th class="px-4 py-3 text-right">
                {{ projectText('ACTIONS', 'Ações') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="file in visible"
              :key="file.id"
              class="border-t border-n-weak hover:bg-n-slate-2/50"
            >
              <td class="max-w-80 px-4 py-4">
                <div class="flex min-w-0 items-center gap-3">
                  <span
                    class="flex size-9 shrink-0 items-center justify-center rounded-lg"
                    :class="fileType(file).color"
                    ><span
                      class="size-4"
                      :class="fileType(file).icon"
                      aria-hidden="true"
                  /></span>
                  <div class="min-w-0">
                    <a
                      class="block truncate font-medium text-n-slate-12 hover:text-n-blue-11"
                      :href="file.url"
                      target="_blank"
                      rel="noopener noreferrer"
                      :title="file.name"
                      >{{ file.name }}</a
                    ><span class="text-xs uppercase text-n-slate-10">{{
                      extension(file)
                    }}</span>
                  </div>
                </div>
              </td>
              <td class="whitespace-nowrap px-4 py-4 text-n-slate-11">
                {{ size(file.byte_size) }}
              </td>
              <td class="px-4 py-4 text-n-slate-11">
                {{
                  file.uploaded_by?.name ||
                  projectText(
                    'UPLOADER_UNKNOWN',
                    'Não identificado no histórico'
                  )
                }}
              </td>
              <td class="whitespace-nowrap px-4 py-4 text-n-slate-11">
                {{ formatDate(file.created_at) }}
              </td>
              <td class="px-4 py-4">
                <div class="flex items-center justify-end gap-2">
                  <a
                    class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-blue-2 hover:text-n-blue-11"
                    :href="file.url"
                    target="_blank"
                    rel="noopener noreferrer"
                    :aria-label="`${projectText('VIEW_FILE', 'Visualizar')}: ${file.name}`"
                    :title="projectText('VIEW_FILE', 'Visualizar')"
                    ><span class="i-lucide-eye size-4" /></a
                  ><a
                    class="flex size-8 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-blue-2 hover:text-n-blue-11"
                    :href="file.download_url || file.url"
                    target="_blank"
                    rel="noopener noreferrer"
                    :aria-label="`${projectText('DOWNLOAD', 'Baixar')}: ${file.name}`"
                    :title="projectText('DOWNLOAD', 'Baixar')"
                    ><span class="i-lucide-download size-4" /></a
                  ><button
                    v-if="canEdit"
                    class="flex size-8 items-center justify-center rounded-lg text-n-ruby-11 hover:bg-n-ruby-2 disabled:opacity-50"
                    :disabled="busy"
                    :aria-label="`${projectText('REMOVE', 'Remover')}: ${file.name}`"
                    :title="projectText('REMOVE', 'Remover')"
                    @click="remove(file)"
                  >
                    <span class="i-lucide-trash-2 size-4" />
                  </button>
                </div>
              </td>
            </tr>
            <tr v-if="!error && !visible.length">
              <td colspan="5" class="p-10 text-center text-n-slate-11">
                <span
                  class="i-lucide-folder-open mx-auto mb-3 block size-8 text-n-slate-9"
                />{{
                  query || category !== 'all'
                    ? projectText(
                        'NO_FILE_RESULTS',
                        'Nenhum arquivo corresponde a estes filtros.'
                      )
                    : projectText('NO_FILES', 'Nenhum anexo.')
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <footer
        v-if="filtered.length > pageSize"
        class="flex items-center justify-end gap-3 border-t border-n-weak p-3 text-sm"
      >
        <button
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          :disabled="page <= 1"
          @click="page -= 1"
        >
          {{ projectText('PREVIOUS', 'Anterior') }}</button
        ><span>{{ page }} / {{ Math.ceil(filtered.length / pageSize) }}</span
        ><button
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          :disabled="page * pageSize >= filtered.length"
          @click="page += 1"
        >
          {{ projectText('NEXT', 'Próxima') }}
        </button>
      </footer>
    </div>
    <p class="m-0 flex items-center gap-2 text-xs text-n-slate-11">
      <span class="i-lucide-lock-keyhole size-3 shrink-0" />{{
        projectText(
          'FILES_ACCESS_HINT',
          'Arquivos internos: disponíveis a quem tem acesso ao projeto. O envio não compartilha documentos com o cliente.'
        )
      }}
    </p>
  </section>
</template>
