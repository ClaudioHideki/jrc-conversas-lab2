<script setup>
import { ref, watch } from 'vue';
import { request, errorMessage } from '../../jrcOperations/api';
import { templateResource } from '../../jrcOperations/resources';
import ResourceManager from '../../jrcOperations/components/ResourceManager.vue';
import { useProjects } from '../useProjects';
const { accountId, projectText } = useProjects();
const agents = ref([]);
const error = ref('');
const busy = ref(false);
async function load() {
  agents.value = [];
  error.value = '';
  try {
    agents.value = (
      await request(accountId.value, 'projects/settings')
    ).data.agent_access;
  } catch (e) {
    error.value = errorMessage(e);
  }
}
watch(accountId, load, { immediate: true });
async function save() {
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, 'projects/settings', {
      method: 'patch',
      data: {
        settings: {
          agent_access: agents.value.map(a => ({
            account_user_id: a.account_user_id,
            enabled: a.enabled,
          })),
        },
      },
    });
    await load();
  } catch (e) {
    error.value = errorMessage(e);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <section class="flex flex-col gap-4">
    <h2>{{ projectText('ACCESS_TITLE', 'Acesso a Projetos') }}</h2>
    <p>
      {{
        projectText(
          'ENTITLEMENT_HELP',
          'A ativação para a empresa é feita pelo Super Admin. Aqui você administra o acesso dos agentes; a equipe de cada projeto define sua participação.'
        )
      }}
    </p>
    <p v-if="error" role="alert">{{ error }}</p>
    <form class="flex flex-col gap-3" @submit.prevent="save">
      <label
        v-for="agent in agents"
        :key="agent.account_user_id"
        class="flex gap-2"
        :title="
          agent.role === 'administrator'
            ? projectText('ADMIN_ACCESS_HELP')
            : undefined
        "
      >
        <input
          v-model="agent.enabled"
          type="checkbox"
          :disabled="busy || agent.role === 'administrator'"
        />{{ agent.name }}
      </label>
      <button class="rounded bg-n-blue-9 p-2 text-white" :disabled="busy">
        {{ projectText('SAVE_ACCESS', 'Salvar acesso') }}
      </button>
    </form>
    <ResourceManager
      :schema="templateResource"
      endpoint="projects/project_templates"
    />
  </section>
</template>
