<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text, no-alert */
import { computed, onMounted, reactive, ref } from 'vue';
import { contractTemplatesAPI } from 'dashboard/api/crm/commercialCycle';
import { useAlert } from 'dashboard/composables';

const rows = ref([]);
const query = ref('');
const loading = ref(false);
const saving = ref(false);
const showForm = ref(false);
const editingId = ref(null);

const form = reactive({
  name: '',
  category: '',
  description: '',
  body: '',
  variables: '',
  active: true,
});

const filtered = computed(() => {
  const search = query.value.trim().toLowerCase();

  if (!search) return rows.value;

  return rows.value.filter(row =>
    [row.name, row.category, row.description]
      .filter(Boolean)
      .some(value => value.toLowerCase().includes(search))
  );
});

const stats = computed(() => ({
  total: rows.value.length,
  active: rows.value.filter(row => row.active).length,
  inactive: rows.value.filter(row => !row.active).length,
  variables: rows.value.reduce(
    (total, row) => total + (row.variables?.length || 0),
    0
  ),
}));

const load = async () => {
  loading.value = true;

  try {
    rows.value = (await contractTemplatesAPI.list()).data || [];
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        'Não foi possível carregar os modelos.'
    );
  } finally {
    loading.value = false;
  }
};

const openForm = template => {
  editingId.value = template?.id || null;

  Object.assign(form, {
    name: template?.name || '',
    category: template?.category || '',
    description: template?.description || '',
    body: template?.body || '',
    variables: (template?.variables || []).join(', '),
    active: template?.active ?? true,
  });

  showForm.value = true;
};

const closeForm = () => {
  showForm.value = false;
};

const save = async () => {
  saving.value = true;

  const payload = {
    contract_template: {
      name: form.name,
      category: form.category,
      description: form.description,
      body: form.body,
      active: form.active,
      variables: form.variables
        .split(',')
        .map(value => value.trim())
        .filter(Boolean),
    },
  };

  try {
    if (editingId.value) {
      await contractTemplatesAPI.update(editingId.value, payload);
    } else {
      await contractTemplatesAPI.create(payload);
    }

    showForm.value = false;
    await load();

    useAlert(
      editingId.value
        ? 'Modelo atualizado com sucesso.'
        : 'Modelo criado com sucesso.'
    );
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível salvar o modelo.'
    );
  } finally {
    saving.value = false;
  }
};

const remove = async template => {
  if (!window.confirm(`Excluir o modelo "${template.name}"?`)) return;

  try {
    await contractTemplatesAPI.delete(template.id);
    await load();
    useAlert('Modelo excluído.');
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        'Não foi possível excluir o modelo.'
    );
  }
};

onMounted(load);
</script>

<template>
  <div class="h-full overflow-auto bg-[#f7faff] p-5 sm:p-6">
    <!-- CABEÇALHO -->
    <header
      class="mb-6 flex flex-wrap items-center justify-between gap-4"
    >
      <div class="flex items-center gap-4">
        <span
          class="grid size-12 place-content-center rounded-2xl bg-violet-600 text-white shadow-lg shadow-violet-100"
        >
          <i class="i-lucide-layout-template size-6" />
        </span>

        <div>
          <p class="mb-1 text-xs font-semibold uppercase tracking-wide text-violet-600">
            CRM / Contratos
          </p>

          <h2 class="text-2xl font-bold text-slate-900">
            Modelos de contrato
          </h2>

          <p class="text-sm text-slate-500">
            Crie e gerencie modelos reutilizáveis para geração de contratos.
          </p>
        </div>
      </div>

      <button
        class="flex items-center gap-2 rounded-xl bg-violet-600 px-5 py-3 font-semibold text-white shadow-lg shadow-violet-100 transition hover:bg-violet-700"
        @click="openForm()"
      >
        <i class="i-lucide-plus size-5" />
        Novo modelo
      </button>
    </header>

    <!-- INDICADORES -->
    <section class="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <article
        class="flex items-center gap-4 rounded-2xl border border-blue-100 bg-white p-5 shadow-sm"
      >
        <span
          class="grid size-12 place-content-center rounded-2xl bg-blue-50 text-blue-600"
        >
          <i class="i-lucide-files size-6" />
        </span>

        <div>
          <p class="text-sm text-slate-500">Total de modelos</p>
          <strong class="text-3xl font-bold text-slate-900">
            {{ stats.total }}
          </strong>
        </div>
      </article>

      <article
        class="flex items-center gap-4 rounded-2xl border border-emerald-100 bg-white p-5 shadow-sm"
      >
        <span
          class="grid size-12 place-content-center rounded-2xl bg-emerald-50 text-emerald-600"
        >
          <i class="i-lucide-circle-check size-6" />
        </span>

        <div>
          <p class="text-sm text-slate-500">Modelos ativos</p>
          <strong class="text-3xl font-bold text-emerald-600">
            {{ stats.active }}
          </strong>
        </div>
      </article>

      <article
        class="flex items-center gap-4 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm"
      >
        <span
          class="grid size-12 place-content-center rounded-2xl bg-slate-100 text-slate-600"
        >
          <i class="i-lucide-circle-pause size-6" />
        </span>

        <div>
          <p class="text-sm text-slate-500">Modelos inativos</p>
          <strong class="text-3xl font-bold text-slate-700">
            {{ stats.inactive }}
          </strong>
        </div>
      </article>

      <article
        class="flex items-center gap-4 rounded-2xl border border-amber-100 bg-white p-5 shadow-sm"
      >
        <span
          class="grid size-12 place-content-center rounded-2xl bg-amber-50 text-amber-600"
        >
          <i class="i-lucide-braces size-6" />
        </span>

        <div>
          <p class="text-sm text-slate-500">Variáveis cadastradas</p>
          <strong class="text-3xl font-bold text-amber-600">
            {{ stats.variables }}
          </strong>
        </div>
      </article>
    </section>

    <!-- CONTEÚDO -->
    <section
      class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
    >
      <!-- BUSCA -->
      <div
        class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 p-4"
      >
        <div class="relative w-full max-w-md">
          <i
            class="i-lucide-search absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400"
          />

          <input
            v-model="query"
            class="w-full rounded-xl border border-slate-200 bg-slate-50 py-2.5 pl-10 pr-4 outline-none transition focus:border-violet-400 focus:bg-white"
            placeholder="Buscar por nome, categoria ou descrição..."
          />
        </div>

        <div class="text-sm text-slate-500">
          {{ filtered.length }}
          {{ filtered.length === 1 ? 'modelo encontrado' : 'modelos encontrados' }}
        </div>
      </div>

      <!-- LOADING -->
      <div
        v-if="loading"
        class="flex min-h-64 flex-col items-center justify-center gap-3 text-slate-500"
      >
        <i class="i-lucide-loader-circle size-8 animate-spin text-violet-600" />
        <span>Carregando modelos...</span>
      </div>

      <!-- VAZIO -->
      <div
        v-else-if="!filtered.length"
        class="flex min-h-64 flex-col items-center justify-center p-8 text-center"
      >
        <span
          class="mb-4 grid size-16 place-content-center rounded-2xl bg-violet-50 text-violet-600"
        >
          <i class="i-lucide-layout-template size-8" />
        </span>

        <h3 class="text-lg font-bold text-slate-900">
          Nenhum modelo encontrado
        </h3>

        <p class="mt-1 max-w-md text-sm text-slate-500">
          Crie modelos de contrato para padronizar e agilizar o processo
          comercial.
        </p>

        <button
          class="mt-5 rounded-xl bg-violet-600 px-5 py-2.5 font-semibold text-white"
          @click="openForm()"
        >
          Criar primeiro modelo
        </button>
      </div>

      <!-- CARDS -->
      <div
        v-else
        class="grid gap-4 p-5 md:grid-cols-2 xl:grid-cols-3"
      >
        <article
          v-for="template in filtered"
          :key="template.id"
          class="group flex min-h-64 flex-col rounded-2xl border border-slate-200 bg-white p-5 transition hover:-translate-y-0.5 hover:border-violet-200 hover:shadow-lg"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex min-w-0 items-start gap-3">
              <span
                class="grid size-11 shrink-0 place-content-center rounded-xl bg-violet-50 text-violet-600"
              >
                <i class="i-lucide-file-text size-5" />
              </span>

              <div class="min-w-0">
                <h3
                  class="truncate text-base font-bold text-slate-900"
                  :title="template.name"
                >
                  {{ template.name }}
                </h3>

                <p class="mt-1 text-xs font-medium text-violet-600">
                  {{ template.category || 'Sem categoria' }}
                </p>
              </div>
            </div>

            <span
              class="shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold"
              :class="
                template.active
                  ? 'bg-emerald-50 text-emerald-700'
                  : 'bg-slate-100 text-slate-600'
              "
            >
              {{ template.active ? 'Ativo' : 'Inativo' }}
            </span>
          </div>

          <p class="mt-4 min-h-10 text-sm leading-5 text-slate-600">
            {{ template.description || 'Sem descrição cadastrada.' }}
          </p>

          <div class="mt-4">
            <div class="mb-2 flex items-center justify-between">
              <span class="text-xs font-semibold uppercase text-slate-400">
                Variáveis
              </span>

              <span class="text-xs text-slate-400">
                {{ template.variables?.length || 0 }}
              </span>
            </div>

            <div
              v-if="template.variables?.length"
              class="flex max-h-20 flex-wrap gap-1.5 overflow-auto"
            >
              <code
                v-for="variable in template.variables"
                :key="variable"
                class="rounded-lg bg-violet-50 px-2 py-1 text-xs text-violet-700"
              >
                {{ variable }}
              </code>
            </div>

            <p v-else class="text-xs text-slate-400">
              Nenhuma variável cadastrada.
            </p>
          </div>

          <div
            class="mt-auto flex items-center justify-end gap-2 border-t border-slate-100 pt-4"
          >
            <button
              class="flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium text-red-600 transition hover:bg-red-50"
              @click="remove(template)"
            >
              <i class="i-lucide-trash-2 size-4" />
              Excluir
            </button>

            <button
              class="flex items-center gap-1.5 rounded-lg bg-violet-50 px-3 py-2 text-sm font-semibold text-violet-700 transition hover:bg-violet-100"
              @click="openForm(template)"
            >
              <i class="i-lucide-pencil size-4" />
              Editar
            </button>
          </div>
        </article>
      </div>
    </section>

    <!-- MODAL -->
    <div
      v-if="showForm"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm"
      @click.self="closeForm"
    >
      <form
        class="flex max-h-[92vh] w-full max-w-3xl flex-col overflow-hidden rounded-3xl bg-white shadow-2xl"
        @submit.prevent="save"
      >
        <!-- MODAL HEADER -->
        <header
          class="flex items-center justify-between border-b border-slate-200 px-6 py-5"
        >
          <div class="flex items-center gap-3">
            <span
              class="grid size-11 place-content-center rounded-xl bg-violet-600 text-white"
            >
              <i
                :class="
                  editingId
                    ? 'i-lucide-pencil'
                    : 'i-lucide-file-plus-2'
                "
                class="size-5"
              />
            </span>

            <div>
              <h3 class="text-xl font-bold text-slate-900">
                {{ editingId ? 'Editar modelo' : 'Novo modelo de contrato' }}
              </h3>

              <p class="text-sm text-slate-500">
                Configure o conteúdo e as variáveis disponíveis no contrato.
              </p>
            </div>
          </div>

          <button
            type="button"
            class="grid size-9 place-content-center rounded-lg text-slate-400 transition hover:bg-slate-100 hover:text-slate-700"
            title="Fechar"
            @click="closeForm"
          >
            <i class="i-lucide-x size-5" />
          </button>
        </header>

        <!-- MODAL BODY -->
        <div class="overflow-y-auto p-6">
          <div class="grid gap-5 sm:grid-cols-2">
            <label class="text-sm font-medium text-slate-700">
              Nome do modelo
              <input
                v-model="form.name"
                required
                class="mt-1.5 w-full rounded-xl border border-slate-200 px-3 py-2.5 outline-none transition focus:border-violet-400"
                placeholder="Ex.: Contrato de prestação de serviços"
              />
            </label>

            <label class="text-sm font-medium text-slate-700">
              Categoria
              <input
                v-model="form.category"
                class="mt-1.5 w-full rounded-xl border border-slate-200 px-3 py-2.5 outline-none transition focus:border-violet-400"
                placeholder="Ex.: Serviços, Licenciamento..."
              />
            </label>

            <label class="sm:col-span-2 text-sm font-medium text-slate-700">
              Descrição
              <input
                v-model="form.description"
                class="mt-1.5 w-full rounded-xl border border-slate-200 px-3 py-2.5 outline-none transition focus:border-violet-400"
                placeholder="Descrição rápida sobre quando utilizar este modelo"
              />
            </label>

            <label class="sm:col-span-2 text-sm font-medium text-slate-700">
              Variáveis disponíveis
              <input
                v-model="form.variables"
                class="mt-1.5 w-full rounded-xl border border-slate-200 px-3 py-2.5 font-mono text-sm outline-none transition focus:border-violet-400"
                placeholder="cliente.nome, contrato.numero, contrato.valor"
              />

              <span class="mt-1.5 block text-xs text-slate-400">
                Separe as variáveis por vírgula.
              </span>
            </label>

            <label class="sm:col-span-2 text-sm font-medium text-slate-700">
              Conteúdo do contrato
              <textarea
                v-model="form.body"
                required
                rows="14"
                class="mt-1.5 w-full resize-y rounded-xl border border-slate-200 bg-slate-50 p-4 font-mono text-sm leading-6 outline-none transition focus:border-violet-400 focus:bg-white"
                placeholder="Digite aqui o conteúdo do contrato..."
              />
            </label>

            <label
              class="sm:col-span-2 flex cursor-pointer items-center justify-between rounded-xl border border-slate-200 bg-slate-50 p-4"
            >
              <div>
                <p class="font-semibold text-slate-800">
                  Modelo ativo
                </p>
                <p class="text-xs text-slate-500">
                  Modelos ativos ficam disponíveis durante a geração de contratos.
                </p>
              </div>

              <input
                v-model="form.active"
                type="checkbox"
                class="size-5 accent-violet-600"
              />
            </label>
          </div>
        </div>

        <!-- MODAL FOOTER -->
        <footer
          class="flex justify-end gap-3 border-t border-slate-200 bg-slate-50 px-6 py-4"
        >
          <button
            type="button"
            class="rounded-xl border border-slate-200 bg-white px-5 py-2.5 font-semibold text-slate-700 transition hover:bg-slate-50"
            @click="closeForm"
          >
            Cancelar
          </button>

          <button
            class="flex items-center gap-2 rounded-xl bg-violet-600 px-5 py-2.5 font-semibold text-white shadow-sm transition hover:bg-violet-700 disabled:cursor-not-allowed disabled:opacity-50"
            :disabled="saving"
          >
            <i
              :class="
                saving
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-save'
              "
              class="size-4"
            />

            {{
              saving
                ? 'Salvando...'
                : editingId
                  ? 'Salvar alterações'
                  : 'Criar modelo'
            }}
          </button>
        </footer>
      </form>
    </div>
  </div>
</template>
