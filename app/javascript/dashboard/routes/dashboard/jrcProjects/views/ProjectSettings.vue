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
const capabilities = [
  'project.view',
  'project.update',
  'task.create',
  'task.update',
  'task.assign',
  'task.move',
  'member.manage',
  'member.view',
  'planning.view',
  'time_entry.view',
  'time_entry.create',
  'report.view',
  'attachment.view',
];
const setPermission = (agent, capability, event) => {
  const key = 'projects.' + capability;
  if (event.target.value === 'inherit') delete agent.permissions[key];
  else agent.permissions[key] = event.target.value === 'allow';
};
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
            permissions: a.permissions,
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
      <fieldset
        v-for="agent in agents"
        :key="agent.account_user_id"
        class="space-y-3 rounded-lg border border-n-weak p-3"
        :disabled="busy || agent.administrator === true"
      >
        <legend class="px-1 font-medium">{{ agent.name }}</legend>
        <label class="flex items-center gap-2"
          ><input v-model="agent.enabled" type="checkbox" />{{
            projectText('ACCESS_TITLE')
          }}</label
        >
        <label class="flex items-center gap-2"
          ><input
            v-model="agent.permissions['projects.project.create']"
            type="checkbox"
          />{{ projectText('CREATE_PERMISSION') }}</label
        >
        <details>
          <summary class="cursor-pointer text-sm">
            {{ projectText('INDIVIDUAL_PERMISSIONS') }}
          </summary>
          <div class="mt-3 grid gap-3 md:grid-cols-2">
            <label
              v-for="capability in capabilities"
              :key="capability"
              class="text-sm"
            >
              {{
                projectText(
                  'CAPABILITY_LABELS.projects_' +
                    capability.replaceAll('.', '_')
                )
              }}
              <select
                class="mt-1 w-full rounded border border-n-weak bg-n-background p-2"
                :value="
                  agent.permissions['projects.' + capability] === undefined
                    ? 'inherit'
                    : agent.permissions['projects.' + capability]
                      ? 'allow'
                      : 'deny'
                "
                @change="setPermission(agent, capability, $event)"
              >
                <option value="inherit">
                  {{ projectText('PERMISSION_INHERIT') }}
                </option>
                <option value="allow">
                  {{ projectText('PERMISSION_ALLOW') }}
                </option>
                <option value="deny">
                  {{ projectText('PERMISSION_DENY') }}
                </option>
              </select>
            </label>
          </div>
        </details>
      </fieldset>
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
