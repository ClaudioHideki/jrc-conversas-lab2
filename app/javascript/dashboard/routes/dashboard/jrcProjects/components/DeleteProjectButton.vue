<script setup>
import { ref } from 'vue';
import { useProjects } from '../useProjects';
import { request, errorMessage } from '../../jrcOperations/api';

const props = defineProps({
  project: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['deleted', 'error']);
const { accountId, projectText } = useProjects();
const busy = ref(false);

async function remove() {
  if (busy.value || props.disabled) return;
  if (
    !window.confirm(
      `${projectText('DELETE_PROJECT_CONFIRM', 'Excluir este projeto e seus itens internos? Esta ação é definitiva. Vínculos externos e apontamentos de horas impedem a exclusão.')}\n\n${props.project.key} · ${props.project.name}`
    )
  )
    return;
  busy.value = true;
  try {
    await request(accountId.value, `projects/projects/${props.project.id}`, {
      method: 'delete',
      data: { lock_version: props.project.lock_version },
    });
    emit('deleted', props.project);
  } catch (error) {
    emit('error', errorMessage(error));
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <button
    v-if="project.capabilities?.includes('projects.project.delete')"
    type="button"
    class="inline-flex items-center justify-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-xs text-n-ruby-11 hover:bg-n-ruby-2 disabled:opacity-50"
    :disabled="busy || disabled"
    :aria-label="projectText('DELETE_PROJECT', 'Excluir projeto')"
    :title="projectText('DELETE_PROJECT', 'Excluir projeto')"
    @click="remove"
  >
    <span class="i-lucide-trash-2 size-3.5" aria-hidden="true" />
    <span v-if="!compact">{{
      projectText('DELETE_PROJECT', 'Excluir projeto')
    }}</span>
  </button>
</template>
