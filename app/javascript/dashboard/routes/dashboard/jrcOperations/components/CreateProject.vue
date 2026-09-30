<script setup>
import { reactive, ref, onMounted } from 'vue';
import OpsModal from './OpsModal.vue';
import ContactPicker from './ContactPicker.vue';
import { useProjects } from '../../jrcProjects/useProjects';
import { request, operationKey, errorMessage, priorities } from '../api';
const props = defineProps({
  ticketId: [String, Number],
  dealId: [String, Number],
  conversationId: [String, Number],
  contactId: [String, Number],
  initialTitle: String,
});
const emit = defineEmits(['close', 'created']);
const { accountId, projectText } = useProjects();
const options = ref({});
const busy = ref(false);
const error = ref('');
const templateId = ref('');
const key = operationKey();
const form = reactive({
  name: props.initialTitle || '',
  description: '',
  contact_id: props.contactId || null,
  visibility: 'members',
  priority: 'medium',
  starts_on: '',
  due_on: '',
});
onMounted(async () => {
  try {
    options.value = (await request(accountId.value, 'operations/options')).data;
  } catch (err) {
    error.value = errorMessage(err);
  }
});
async function submit() {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const result = await request(accountId.value, 'projects/projects', {
      method: 'post',
      key,
      data: {
        project: { ...form },
        template_id: templateId.value || null,
        ticket_id: props.ticketId || undefined,
        deal_id: props.dealId || undefined,
        conversation_display_id: props.conversationId || undefined,
      },
    });
    emit('created', result.data);
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <OpsModal title="Criar projeto" :busy="busy" @close="emit('close')">
    <form class="flex flex-col gap-4" @submit.prevent="submit">
      <p class="text-sm text-n-slate-11">
        {{
          dealId
            ? 'A entrega sera vinculada ao negocio ganho, preservando a venda no CRM.'
            : ticketId
              ? 'O chamado sera preservado. O projeto organizara a execucao e nao encerrara o atendimento automaticamente.'
              : 'Projetos internos nao precisam de uma venda ou chamado artificial.'
        }}
      </p>
      <div
        v-if="error"
        class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
        role="alert"
      >
        {{ error }}
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <label class="flex flex-col gap-1 min-w-0 col-span-full"><span>Nome do projeto *</span><input v-model="form.name"
required maxlength="240"/></label>
        <label class="flex flex-col gap-1 min-w-0 col-span-full"><span>Escopo e resultado esperado</span><textarea v-model="form.description" rows="4" />
        </label>
        <label class="flex flex-col gap-1 min-w-0"><span>{{ projectText('PRIORITY', 'Prioridade') }}</span><select v-model="form.priority">
            <option
              v-for="(label, value) in priorities"
              :key="value"
              :value="value"
            >
              {{ label }}
            </option>
          </select></label>
        <p class="text-sm text-n-slate-11">
          {{
            projectText(
              'OWNER_CREATOR',
              'Você será o responsável inicial. A transferência pode ser feita pelo Workspace.'
            )
          }}
        </p>
        <ContactPicker
          v-model="form.contact_id"
          :disabled="
            Boolean(contactId && (ticketId || dealId || conversationId))
          "
        />
        <label class="flex flex-col gap-1 min-w-0"><span>Modelo de entrega</span><select v-model="templateId">
            <option value="">Projeto sem tarefas predefinidas</option>
            <option
              v-for="template in options.templates || []"
              :key="template.id"
              :value="template.id"
            >
              {{ template.name }}
            </option>
          </select></label>
        <label class="flex flex-col gap-1 min-w-0"><span>Inicio previsto</span><input
v-model="form.starts_on" type="date"
        /></label>
        <label class="flex flex-col gap-1 min-w-0"><span>Prazo de entrega</span><input
            v-model="form.due_on"
            type="date"
            :min="form.starts_on || undefined"
        /></label>
        <label class="flex flex-col gap-1 min-w-0 col-span-full"><span>Visibilidade</span><select v-model="form.visibility">
            <option value="members">
              Somente participantes e administradores
            </option>
            <option value="private">
              {{ projectText('PRIVATE', 'Privado') }}
            </option>
            <option value="account">
              Toda a conta pode consultar; somente participantes podem executar
            </option></select><small>Custos continuam restritos ao proprietario e aos
            administradores.</small></label>
      </div>
      <footer class="flex justify-end gap-3 mt-4">
        <button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
          type="button"
          :disabled="busy"
          @click="emit('close')"
        >
          Cancelar</button><button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed bg-n-blue-9 text-white"
          :disabled="busy"
        >
          {{ busy ? 'Criando...' : 'Criar projeto' }}
        </button>
      </footer>
    </form>
  </OpsModal>
</template>
