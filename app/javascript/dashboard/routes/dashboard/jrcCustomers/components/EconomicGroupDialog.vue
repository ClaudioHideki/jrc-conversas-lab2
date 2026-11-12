<script setup>
import {
  ref,
  reactive,
  computed,
  onMounted,
  onBeforeUnmount,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcCustomers';
import EconomicGroupMembers from './EconomicGroupMembers.vue';
import EconomicGroupHistory from './EconomicGroupHistory.vue';
import { useCustomerMaster } from '../useCustomerMaster';
import {
  T,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from '../copy';

const props = defineProps({
  groupId: { type: [Number, String], default: null },
});
const emit = defineEmits(['close', 'saved']);
const { t } = useI18n();
const { accountId, identity, canAdmin } = useCustomerMaster();
const dialog = ref(null);
const deleteDialog = ref(null);
const group = ref(null);
const form = reactive({ name: '', description: '' });
const tab = ref('summary');
const busy = ref(false);
const saving = ref(false);
const childBusy = ref(false);
const error = ref('');
const processing = computed(() => saving.value || childBusy.value);
const canManage = computed(
  () => canAdmin.value && (!group.value || group.value.can_manage)
);
const tabs = computed(() => [
  {
    key: 'summary',
    label: t('CRM.CORPORATE_SEGMENTS.SUMMARY'),
    tone: 'border-n-blue-7 bg-n-blue-3 text-n-blue-12',
  },
  {
    key: 'companies',
    label: T.companies,
    tone: 'border-n-teal-7 bg-n-teal-3 text-n-teal-12',
  },
  {
    key: 'history',
    label: t('CRM.CORPORATE_SEGMENTS.HISTORY'),
    tone: 'border-n-violet-7 bg-n-violet-3 text-n-violet-12',
  },
]);
let active = true;
let controller;
onMounted(async () => {
  dialog.value.open();
  if (!props.groupId) return;
  busy.value = true;
  controller = new AbortController();
  try {
    const { data } = await API.economicGroup(props.groupId, {
      accountId: accountId.value,
      signal: controller.signal,
    });
    if (!active) return;
    group.value = data.payload;
    form.name = data.payload.name;
    form.description = data.payload.description || '';
  } catch (failure) {
    if (active) error.value = errorMessage(failure);
  } finally {
    if (active) busy.value = false;
  }
});
watch(identity, () => emit('close'));
onBeforeUnmount(() => {
  active = false;
  controller?.abort();
});
const persist = async values => {
  if (
    !canManage.value ||
    processing.value ||
    busy.value ||
    (props.groupId && !group.value)
  )
    return;
  saving.value = true;
  error.value = '';
  try {
    const created = !group.value;
    const { data } = await API.saveEconomicGroup(
      { ...values, revision: group.value?.revision },
      group.value?.id || null,
      { accountId: accountId.value }
    );
    if (!active) return;
    group.value = data.payload;
    if (created) tab.value = 'companies';
    emit('saved');
  } catch (failure) {
    if (active) error.value = errorMessage(failure);
  } finally {
    if (active) saving.value = false;
  }
};
const savedMembership = value => {
  group.value = value;
  emit('saved');
};
const reloadGroup = async () => {
  try {
    const { data } = await API.economicGroup(group.value.id, {
      accountId: accountId.value,
    });
    if (!active) return;
    group.value = data.payload;
    emit('saved');
  } catch (failure) {
    if (active) error.value = errorMessage(failure);
  }
};
const remove = async () => {
  if (!canManage.value || !group.value || processing.value) return;
  saving.value = true;
  error.value = '';
  try {
    await API.deleteEconomicGroup(group.value.id, group.value.revision, {
      accountId: accountId.value,
    });
    if (!active) return;
    emit('saved');
    emit('close');
  } catch (failure) {
    if (active) error.value = errorMessage(failure);
  } finally {
    if (active) saving.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialog"
    :title="group?.name || t('CRM.ECONOMIC_GROUPS.NEW')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :dismissible="!processing"
    show-close-button
    contained
    width="5xl"
    @close="emit('close')"
  >
    <nav
      class="mb-4 flex flex-wrap gap-2"
      :aria-label="t('CRM.ECONOMIC_GROUPS.CORPORATE_TAB')"
    >
      <button
        v-for="item in tabs"
        :key="item.key"
        type="button"
        class="rounded-lg border px-4 py-2 font-medium"
        :class="[item.tone, tab === item.key ? 'ring-2 ring-n-brand' : '']"
        :aria-pressed="tab === item.key"
        :disabled="processing || busy || (item.key !== 'summary' && !group)"
        @click="tab = item.key"
      >
        {{ item.label }}
      </button>
    </nav>
    <p
      v-if="error"
      role="alert"
      class="mb-3 text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <template v-if="!busy && (!groupId || group)">
      <form
        v-if="tab === 'summary'"
        class="space-y-4"
        @submit.prevent="persist({ ...form })"
      >
        <label class="block">
          <span>{{ t('CRM.ECONOMIC_GROUPS.NAME') }}</span>
          <input
            v-model="form.name"
            :class="inputClass"
            maxlength="1000"
            required
            :disabled="!canManage || processing || !!group?.member_count"
        /></label>
        <p class="text-sm text-n-slate-10">
          {{ t('CRM.ECONOMIC_GROUPS.NAME_HELP') }}
        </p>
        <label class="block">
          <span>{{ t('CRM.ECONOMIC_GROUPS.DESCRIPTION') }}</span>
          <textarea
            v-model="form.description"
            :class="inputClass"
            maxlength="5000"
            rows="3"
            :disabled="!canManage || processing"
          />
        </label>
        <div class="rounded-xl border border-n-teal-6 bg-n-solid-2 p-4">
          <h4 class="font-semibold">
            {{ t('CRM.ECONOMIC_GROUPS.PRINCIPAL') }}
          </h4>
          <p>
            {{
              group?.principal_company?.name ||
              t('CRM.ECONOMIC_GROUPS.NO_PRINCIPAL')
            }}
          </p>
          <p class="text-sm text-n-slate-10">
            {{ t('CRM.ECONOMIC_GROUPS.PRINCIPAL_HELP') }}
          </p>
          <button
            v-if="canManage && group?.principal_company"
            type="button"
            :class="buttonClass"
            :disabled="processing"
            @click="persist({ principal_company_id: null })"
          >
            {{ t('CRM.ECONOMIC_GROUPS.CLEAR_PRINCIPAL') }}
          </button>
        </div>
        <p
          v-if="group && !canManage"
          class="text-sm text-n-slate-10"
        >
          {{ t('CRM.ECONOMIC_GROUPS.READ_ONLY') }}
        </p>
        <div
          v-if="canManage"
          class="flex flex-wrap justify-end gap-3"
        >
          <button
            v-if="group"
            type="button"
            :class="buttonClass"
            :disabled="processing"
            @click="
              error = '';
              deleteDialog.open();
            "
          >
            {{ t('CRM.ECONOMIC_GROUPS.DELETE') }}
          </button>
          <button
            type="submit"
            :class="primaryClass"
            :disabled="processing || !form.name.trim()"
          >
            {{ saving ? T.saving : T.save }}
          </button>
        </div>
      </form>
      <EconomicGroupMembers
        v-if="tab === 'companies' && group"
        :group="group"
        :disabled="processing"
        @busy="childBusy = $event"
        @changed="savedMembership"
        @refresh="reloadGroup"
        @principal="persist({ principal_company_id: $event })"
      />
      <EconomicGroupHistory
        v-if="tab === 'history' && group"
        :group-id="group.id"
      />
    </template>
    <Dialog
      ref="deleteDialog"
      type="alert"
      :title="t('CRM.ECONOMIC_GROUPS.DELETE')"
      :description="t('CRM.ECONOMIC_GROUPS.DELETE_HELP')"
      :confirm-button-label="t('CRM.ECONOMIC_GROUPS.DELETE')"
      :is-loading="saving"
      :dismissible="!saving"
      contained
      @confirm="remove"
    >
      <p
        v-if="error"
        role="alert"
        class="text-n-ruby-11"
      >
        {{ error }}
      </p>
    </Dialog>
  </Dialog>
</template>
