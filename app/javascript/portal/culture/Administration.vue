<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { request } from './client';
import Reports from './Reports.vue';
import Publications from './Publications.vue';
import Collaborators from './Collaborators.vue';
import Imports from './Imports.vue';

const props = defineProps({ base: { type: String, required: true } });
const emit = defineEmits(['expired']);
const { t } = useI18n();
const section = ref('overview');
const setup = ref(null);
const error = ref('');
const sections = [
  'overview',
  'people',
  'confirmations',
  'pendings',
  'publications',
  'materials',
  'imports',
];

async function loadSetup() {
  error.value = '';
  try {
    setup.value = await request(`${props.base}/admin/setup`);
  } catch (failure) {
    if (failure.status === 401) emit('expired');
    else error.value = 'forbidden';
  }
}
onMounted(loadSetup);
</script>

<template>
  <section class="grid gap-4">
    <h2 class="text-xl font-semibold">{{ t('admin') }}</h2>
    <p v-if="error" class="text-n-ruby-11" role="alert">{{ t(error) }}</p>
    <p v-else-if="!setup" role="status">{{ t('loading') }}</p>
    <template v-else>
      <nav class="flex flex-wrap gap-2" :aria-label="t('admin')">
        <button
          v-for="item in sections"
          :key="item"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm font-medium"
          :class="
            section === item ? 'bg-n-blue-3 text-n-blue-11' : 'bg-n-solid-1'
          "
          :aria-current="section === item ? 'page' : undefined"
          @click="section = item"
        >
          {{ t(item) }}
        </button>
      </nav>
      <Reports
        v-if="['overview', 'confirmations', 'pendings'].includes(section)"
        :key="section"
        :base="base"
        :setup="setup"
        :section="section"
        @expired="emit('expired')"
      />
      <Collaborators
        v-else-if="section === 'people'"
        :base="base"
        :units="setup.units"
        @expired="emit('expired')"
      />
      <Publications
        v-else-if="['publications', 'materials'].includes(section)"
        :base="base"
        :setup="setup"
        :materials="section === 'materials'"
        @changed="loadSetup"
        @expired="emit('expired')"
      />
      <Imports v-else :base="base" :setup="setup" @expired="emit('expired')" />
    </template>
  </section>
</template>
