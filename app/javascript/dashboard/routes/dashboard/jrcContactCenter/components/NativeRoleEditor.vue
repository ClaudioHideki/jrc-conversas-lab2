<script setup>
import { useStore } from 'dashboard/composables/store';
import { watch } from 'vue';
import CustomRoleModal from 'dashboard/routes/dashboard/settings/customRoles/component/CustomRoleModal.vue';

const props = defineProps({
  roles: { type: Array, required: true },
  selectedRole: { type: Object, default: null },
});
const emit = defineEmits(['close', 'busy']);

// Hydrate the native module from the authenticated, current-Account response.
// The existing editor retains its validation, API, grant guard and persistence.
const store = useStore();
store.commit('customRole/SET_CUSTOM_ROLE', props.roles);
watch(
  () => store.getters['customRole/getUIFlags'],
  flags => emit('busy', Boolean(flags.creatingItem || flags.updatingItem)),
  { immediate: true, flush: 'sync', deep: true }
);
</script>

<template>
  <CustomRoleModal
    :mode="selectedRole ? 'edit' : 'add'"
    :selected-role="selectedRole || {}"
    @close="emit('close')"
  />
</template>
