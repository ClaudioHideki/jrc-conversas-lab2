<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed } from 'vue';
import { useStore } from 'vuex';

const props = defineProps({
  filters: { type: Object, required: true },
});

const emit = defineEmits(['update:filters', 'change']);

const store = useStore();

const pipelines = computed(
  () => store.getters['jrcCrm/pipelines/allPipelines'] || []
);
const agents = computed(() => store.state.agents?.records || []);

const localFilters = computed({
  get: () => props.filters,
  set: val => emit('update:filters', val),
});

const onFilterChange = () => {
  emit('change');
};

const clearFilters = () => {
  localFilters.value = {
    pipeline_id: pipelines.value[0]?.id || null,
    owner_id: null,
    search: '',
    status: 'open',
    overdueOnly: false,
    noNextActivity: false,
  };
  emit('change');
};
</script>

<template>
  <div class="bg-n-solid-2 p-3">
    <div class="flex flex-wrap items-center gap-3">
      <div class="flex-1 min-w-[200px]">
        <div class="relative">
          <i
            class="i-lucide-search absolute left-3 top-1/2 transform -translate-y-1/2 text-n-slate-10"
          />
          <input
            v-model="localFilters.search"
            type="text"
            placeholder="Buscar negócios..."
            class="h-10 w-full rounded-xl border border-n-weak bg-n-solid-2 py-2 pl-9 pr-3 text-sm focus:border-n-brand"
            @input="onFilterChange"
          />
        </div>
      </div>

      <div class="w-48">
        <select
          v-model="localFilters.pipeline_id"
          class="h-10 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 text-sm"
          @change="onFilterChange"
        >
          <option :value="null">Todos os Funis</option>
          <option v-for="p in pipelines" :key="p.id" :value="p.id">
            {{ p.name }}
          </option>
        </select>
      </div>

      <div class="w-48">
        <select
          v-model="localFilters.owner_id"
          class="h-10 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 text-sm"
          @change="onFilterChange"
        >
          <option :value="null">Todos os Responsáveis</option>
          <option v-for="a in agents" :key="a.id" :value="a.id">
            {{ a.name }}
          </option>
        </select>
      </div>

      <div class="flex items-center gap-2">
        <label
          class="flex h-10 cursor-pointer items-center gap-2 rounded-xl border border-n-ruby-6 bg-n-ruby-3 px-3 text-sm font-medium text-n-ruby-11"
        >
          <input
            v-model="localFilters.overdueOnly"
            type="checkbox"
            class="rounded border-n-weak text-n-blue-11 focus:ring-blue-500"
            @change="onFilterChange"
          />
          Atrasados
        </label>
      </div>

      <div class="flex items-center gap-2">
        <label
          class="flex h-10 cursor-pointer items-center gap-2 rounded-xl border border-n-amber-6 bg-n-amber-3 px-3 text-sm font-medium text-n-amber-11"
        >
          <input
            v-model="localFilters.noNextActivity"
            type="checkbox"
            class="rounded border-n-weak text-n-blue-11 focus:ring-blue-500"
            @change="onFilterChange"
          />
          Sem próx. atividade
        </label>
      </div>

      <button
        class="ml-auto h-10 rounded-xl border border-n-weak px-3 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2"
        @click="clearFilters"
      >
        Limpar Filtros
      </button>
    </div>
  </div>
</template>
