<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useOperations } from '../useOperations';
import { request, errorMessage } from '../api';
const props = defineProps({ modelValue: [Number, String], disabled: Boolean });
const emit = defineEmits(['update:modelValue']);
const { accountId } = useOperations();
const query = ref('');
const selected = ref(null);
const options = ref([]);
const error = ref('');
const searching = ref(false);
let timer;
let generation = 0;
async function search() {
  const version = ++generation;
  searching.value = true;
  try {
    const result = await request(accountId.value, 'operations/contacts', {
      params: { q: query.value },
    });
    if (version === generation) options.value = result.data;
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    if (version === generation) searching.value = false;
  }
}
watch(query, () => {
  clearTimeout(timer);
  timer = setTimeout(search, 300);
});
watch(
  () => [props.modelValue, accountId.value],
  async () => {
    if (!props.modelValue) {
      selected.value = null;
      return;
    }
    try {
      selected.value = (
        await request(accountId.value, 'operations/contacts', {
          params: { id: props.modelValue },
        })
      ).data[0];
    } catch (err) {
      error.value = errorMessage(err);
    }
  },
  { immediate: true }
);
function choose(contact) {
  selected.value = contact;
  emit('update:modelValue', contact.id);
  options.value = [];
  query.value = '';
}
onBeforeUnmount(() => {
  clearTimeout(timer);
  generation += 1;
});
</script>

<template>
  <div class="flex flex-col gap-1 min-w-0">
    <span>Cliente / contato existente</span>
    <div v-if="selected" class="flex flex-wrap items-center gap-3">
      <strong>{{ selected.name }}</strong><span class="text-n-slate-11 text-sm">{{
        selected.email || selected.phone_number
      }}</span><button
        v-if="!disabled"
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
        type="button"
        @click="emit('update:modelValue', null)"
      >
        Trocar
      </button>
    </div>
    <template v-else>
      <input
        v-model="query"
        type="search"
        :disabled="disabled"
        placeholder="Pesquise por nome, e-mail ou telefone"
        aria-label="Pesquisar cliente existente"
        @focus="search"
      />
      <small v-if="searching">Buscando contatos...</small>
      <div
        v-if="options.length && !disabled"
        class="max-h-56 overflow-auto border border-n-weak rounded-md bg-n-solid-1 [&_button]:block [&_button]:p-2 [&_button]:w-full [&_button]:text-left [&_button:hover]:bg-n-alpha-2"
      >
        <button
          v-for="contact in options"
          :key="contact.id"
          type="button"
          @click="choose(contact)"
        >
          {{ contact.name }}
          <small>{{ contact.email || contact.phone_number }}</small>
        </button>
      </div>
      <small v-if="!selected">Nenhum contato selecionado. Nenhum cadastro novo sera criado.</small>
    </template>
    <span
      v-if="error"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
      role="alert"
      >{{ error }}</span>
  </div>
</template>
