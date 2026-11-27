<script setup>
import { computed, onBeforeUnmount, ref, shallowRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  call: { type: Object, default: null },
  customer: { type: Object, default: null },
  enabled: { type: Boolean, default: false },
  showHistory: { type: Boolean, default: false },
});
const emit = defineEmits(['updated', 'closed']);
const { t } = useI18n();
const visible = ref(false);
const initialTab = ref('overview');
const opening = ref(false);
const failed = ref(false);
const dialogComponent = shallowRef(null);
let generation = 0;
const contactId = computed(() => {
  const id = props.call?.contact_id;
  const customer = props.customer;
  if (
    !props.enabled ||
    !id ||
    customer?.status !== 'identified' ||
    customer.ambiguous
  )
    return '';
  if (
    customer.contacts?.length !== 1 ||
    String(customer.contacts[0].id) !== String(id)
  )
    return '';
  return String(customer.directory?.contact_id || '') === String(id)
    ? String(id)
    : '';
});
const identity = computed(() =>
  JSON.stringify([props.accountId, props.call?.id, contactId.value])
);
const close = () => {
  generation += 1;
  visible.value = false;
  opening.value = false;
  failed.value = false;
  dialogComponent.value = null;
};
const closeDialog = () => {
  close();
  emit('closed');
};
const open = async (requestedTab = 'overview') => {
  if (!contactId.value || opening.value || visible.value) return;
  generation += 1;
  const version = generation;
  const source = identity.value;
  opening.value = true;
  failed.value = false;
  try {
    const module = await import(
      'dashboard/routes/dashboard/jrcCustomers/components/ContactDetailsDialog.vue'
    );
    if (version !== generation || source !== identity.value || !contactId.value)
      return;
    initialTab.value = requestedTab === 'history' ? 'history' : 'overview';
    dialogComponent.value = module.default;
    visible.value = true;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) opening.value = false;
  }
};
watch(identity, close);
onBeforeUnmount(close);
</script>

<template>
  <div class="space-y-2" data-linked-master>
    <Button
      v-if="contactId"
      class="mb-3"
      data-open-linked-master
      :label="
        opening
          ? t('JRC_CONTACT_CENTER.COMMON.LOADING')
          : t('CRM.CONTACT_MASTER_360.TITLE')
      "
      :disabled="opening"
      @click="open('overview')"
    />
    <Button
      v-if="contactId && showHistory"
      data-open-linked-history
      :label="t('JRC_CONTACT_CENTER.RECORDINGS.CONTEXT.FULL_HISTORY')"
      :disabled="opening || visible"
      @click="open('history')"
    />
    <p v-if="failed" role="alert" class="text-sm text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <component
      :is="dialogComponent"
      v-if="visible && dialogComponent && contactId"
      :key="identity"
      :contact-id="contactId"
      :initial-tab="initialTab"
      open-full-page-in-new-tab
      @close="closeDialog"
      @updated="emit('updated')"
    />
  </div>
</template>
