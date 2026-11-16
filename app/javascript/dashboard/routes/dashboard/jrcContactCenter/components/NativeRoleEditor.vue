<script setup>
import { useStore } from 'dashboard/composables/store';
import { watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CustomRoleModal from 'dashboard/routes/dashboard/settings/customRoles/component/CustomRoleModal.vue';

const props = defineProps({
  roles: { type: Array, required: true },
  selectedRole: { type: Object, default: null },
});
const emit = defineEmits(['close', 'busy']);

// Hydrate the native module from the authenticated, current-Account response.
// The existing editor retains its validation, API, grant guard and persistence.
const store = useStore();
const { t } = useI18n();
const reviewLabels = {
  title: t('JRC_CONTACT_CENTER.ADMIN.ROLE_REVIEW_TITLE'),
  added: t('JRC_CONTACT_CENTER.ADMIN.ROLE_REVIEW_ADDED'),
  removed: t('JRC_CONTACT_CENTER.ADMIN.ROLE_REVIEW_REMOVED'),
  unchanged: t('JRC_CONTACT_CENTER.ADMIN.ROLE_REVIEW_UNCHANGED'),
  review: t('JRC_CONTACT_CENTER.ADMIN.ROLE_REVIEW'),
  confirm: t('JRC_CONTACT_CENTER.ADMIN.ROLE_CONFIRM'),
};
store.commit('customRole/SET_CUSTOM_ROLE', props.roles);
watch(
  () => store.getters['customRole/getUIFlags'],
  flags => emit('busy', Boolean(flags.creatingItem || flags.updatingItem)),
  { immediate: true, flush: 'sync', deep: true }
);
</script>

<template>
  <p class="mb-4 rounded-lg bg-n-blue-2 p-3 text-sm text-n-blue-11">
    {{ t('JRC_CONTACT_CENTER.ADMIN.ROLE_SCOPE') }}
  </p>
  <CustomRoleModal
    :mode="selectedRole ? 'edit' : 'add'"
    :review-labels="reviewLabels"
    :selected-role="selectedRole || {}"
    :save-error-message="t('JRC_CONTACT_CENTER.ADMIN.SAVE_ERROR')"
    @close="emit('close')"
  />
</template>
