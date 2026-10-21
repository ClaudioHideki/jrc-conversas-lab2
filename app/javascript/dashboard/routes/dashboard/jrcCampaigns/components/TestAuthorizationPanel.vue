<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import api from 'dashboard/api/jrcCampaigns';
import { useAlert } from 'dashboard/composables';

const props = defineProps({ inboxes: { type: Array, default: () => [] } });
const { t } = useI18n();
const entries = ref([]);
const loadedInboxes = ref([]);
const saving = ref(false);
const form = reactive({
  inbox_id: '',
  phone_number: '',
  evidence: '',
  operator_confirmed: false,
});
const evolutionInboxes = computed(() =>
  (props.inboxes.length ? props.inboxes : loadedInboxes.value).filter(
    inbox => inbox.connector === 'evolution'
  )
);
const showError = error => {
  useAlert(
    error?.response?.data?.errors?.join(', ') ||
      t('JRC_CAMPAIGNS.ALERTS.ACTION_FAILED')
  );
};
const load = async () => {
  try {
    const { data } = await api.testAuthorizations();
    entries.value = data;
  } catch (error) {
    showError(error);
  }
};
const add = async () => {
  if (saving.value || !form.operator_confirmed) return;
  saving.value = true;
  try {
    await api.createTestAuthorization({ ...form });
    form.phone_number = '';
    form.evidence = '';
    form.operator_confirmed = false;
    useAlert(t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.RECORDED'));
  } catch (error) {
    showError(error);
  } finally {
    await load();
    saving.value = false;
  }
};
const revoke = async id => {
  try {
    await api.revokeTestAuthorization(id);
    await load();
  } catch (error) {
    showError(error);
  }
};
const status = entry => {
  if (entry.consumed_at) return t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.CONSUMED');
  if (entry.revoked_at) return t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.REVOKED');
  return t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.AVAILABLE');
};
onMounted(async () => {
  await load();
  if (!props.inboxes.length) {
    try {
      const { data } = await api.metadata();
      loadedInboxes.value = data.whatsapp_inboxes || [];
    } catch (error) {
      showError(error);
    }
  }
});
</script>

<template>
  <section class="mt-8 space-y-4 rounded-xl border border-n-weak p-5">
    <h2 class="text-xl font-semibold text-n-slate-12">
      {{ t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.TITLE') }}
    </h2>
    <p class="text-sm text-n-slate-11">
      {{ t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.HELP') }}
    </p>
    <form class="flex flex-col gap-3" @submit.prevent="add">
      <select
        v-model="form.inbox_id"
        required
        class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
        :aria-label="t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.SENDER')"
      >
        <option disabled value="">
          {{ t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.SENDER') }}
        </option>
        <option
          v-for="inbox in evolutionInboxes"
          :key="inbox.id"
          :value="inbox.id"
        >
          {{ `${inbox.name} — ${inbox.phone_number}` }}
        </option>
      </select>
      <input
        v-model="form.phone_number"
        required
        class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
        :aria-label="t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.DESTINATION')"
        :placeholder="t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.DESTINATION')"
      />
      <textarea
        v-model="form.evidence"
        required
        class="rounded-lg border border-n-weak bg-n-background px-3 py-2"
        :aria-label="t('JRC_CAMPAIGNS.GOVERNANCE.EVIDENCE')"
        :placeholder="t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.EVIDENCE')"
      />
      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <input v-model="form.operator_confirmed" type="checkbox" required />
        {{ t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.CONFIRM') }}
      </label>
      <button
        type="submit"
        class="rounded-lg bg-n-brand px-4 py-2 text-white disabled:opacity-40"
        :disabled="
          saving ||
          !form.inbox_id ||
          !form.phone_number.trim() ||
          !form.evidence.trim() ||
          !form.operator_confirmed
        "
      >
        {{ t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.RECORD') }}
      </button>
    </form>
    <p v-if="!entries.length" class="text-sm text-n-slate-11">
      {{ t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.EMPTY') }}
    </p>
    <div
      v-for="entry in entries"
      :key="entry.id"
      class="space-y-2 border-t border-n-weak py-3 text-sm text-n-slate-12"
    >
      <p class="font-medium">
        {{
          t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.ROUTE', {
            sender: entry.sender_number,
            destination: entry.phone_number,
          })
        }}
      </p>
      <p>{{ entry.evidence }}</p>
      <p>{{ entry.granted_at }}</p>
      <p>{{ status(entry) }}</p>
      <p v-if="entry.consumed_at">
        {{ entry.consumed_at }}
        {{
          t('JRC_CAMPAIGNS.TEST_AUTHORIZATION.REQUEST', {
            id: entry.test_delivery_id,
          })
        }}
      </p>
      <button
        v-if="!entry.consumed_at && !entry.revoked_at"
        type="button"
        class="rounded-lg px-3 py-2 text-n-ruby-11 hover:bg-n-ruby-3"
        @click="revoke(entry.id)"
      >
        {{ t('JRC_CAMPAIGNS.GOVERNANCE.REVOKE') }}
      </button>
    </div>
  </section>
</template>
