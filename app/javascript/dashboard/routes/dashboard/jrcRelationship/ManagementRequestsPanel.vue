<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
const props = defineProps({
  metadata: { type: Object, required: true },
  assignmentId: { type: [Number, String], default: null },
});
const { t } = useI18n();
const route = useRoute();
const store = useStore();
const shown = ref(false);
const rows = ref([]);
const meta = ref({});
const page = ref(1);
const loading = ref(false);
const saving = ref(false);
const uncertain = ref(false);
const error = ref('');
const kind = ref('suspend');
const analyst = ref('');
const reason = ref('');
const selected = ref(null);
const options = ref([]);
const optionPage = ref(1);
const optionTotal = ref(0);
const receipt = ref('');
let sequence = 0;
let controller = null;
let attempt = null;
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
    props.metadata,
    props.assignmentId,
  ])
);
const permitted = computed(() =>
  props.assignmentId
    ? props.metadata.can_request_transfer
    : props.metadata.can_request_eligibility
);
const clear = (resetIntent = true) => {
  sequence += 1;
  controller?.abort();
  rows.value = [];
  meta.value = {};
  selected.value = null;
  options.value = [];
  receipt.value = '';
  loading.value = false;
  saving.value = false;
  uncertain.value = false;
  error.value = '';
  if (resetIntent) attempt = null;
};
watch(identity, () => {
  clear();
  shown.value = false;
  reason.value = '';
  analyst.value = '';
  page.value = 1;
});
onBeforeUnmount(clear);
const load = async () => {
  clear(false);
  shown.value = true;
  sequence += 1;
  const version = sequence;
  controller = new AbortController();
  loading.value = true;
  try {
    const { data } = await API.managementRequests(
      route.params.accountId,
      { page: page.value },
      { signal: controller.signal }
    );
    if (version !== sequence) return;
    rows.value = data.payload;
    meta.value = data.meta;
  } catch (e) {
    if (version === sequence)
      error.value =
        e.response?.data?.errors?.[0] ||
        t('RELATIONSHIP.MANAGEMENT_REQUESTS.error');
  } finally {
    if (version === sequence) loading.value = false;
  }
};
const submit = async () => {
  if (
    !permitted.value ||
    saving.value ||
    uncertain.value ||
    !reason.value.trim()
  )
    return;
  const requestKind = props.assignmentId ? 'transfer' : kind.value;
  const values = {
    kind: requestKind,
    reason: reason.value.trim(),
    ...(props.assignmentId
      ? { assignment_id: Number(props.assignmentId) }
      : { analyst_id: Number(analyst.value) }),
  };
  if (
    !Number.isSafeInteger(values.assignment_id || values.analyst_id) ||
    (values.assignment_id || values.analyst_id) <= 0
  )
    return;
  const fingerprint = JSON.stringify([identity.value, values]);
  if (attempt?.fingerprint !== fingerprint)
    attempt = { fingerprint, key: crypto.randomUUID() };
  const version = sequence;
  saving.value = true;
  error.value = '';
  try {
    await API.createManagementRequest(route.params.accountId, {
      ...values,
      idempotency_key: attempt.key,
    });
    if (version !== sequence) return;
    reason.value = '';
    attempt = null;
    await load();
  } catch (e) {
    if (version !== sequence) return;
    uncertain.value = !e.response || e.response.status >= 500;
    error.value =
      e.response?.data?.errors?.[0] ||
      t('RELATIONSHIP.MANAGEMENT_REQUESTS.error');
    if ([401, 403, 404].includes(e.response?.status)) {
      rows.value = [];
      selected.value = null;
    }
  } finally {
    if (version === sequence) saving.value = false;
  }
};
const choose = async (row, nextPage = 1) => {
  sequence += 1;
  const version = sequence;
  controller?.abort();
  controller = new AbortController();
  selected.value = row;
  options.value = [];
  receipt.value = '';
  optionPage.value = nextPage;
  loading.value = true;
  try {
    const { data } = await API.managementResolutionOptions(
      route.params.accountId,
      row.id,
      { page: nextPage },
      { signal: controller.signal }
    );
    if (version !== sequence) return;
    options.value = data.payload;
    optionTotal.value = data.meta.total;
  } catch (e) {
    if (version === sequence) {
      error.value =
        e.response?.data?.errors?.[0] ||
        t('RELATIONSHIP.MANAGEMENT_REQUESTS.error');
      if ([401, 403, 404].includes(e.response?.status)) {
        rows.value = [];
        selected.value = null;
      }
    }
  } finally {
    if (version === sequence) loading.value = false;
  }
};
const link = async () => {
  if (!selected.value || saving.value || uncertain.value || !receipt.value)
    return;
  const row = selected.value;
  const id = Number(receipt.value);
  if (!options.value.some(v => v.id === id)) return;
  const version = sequence;
  saving.value = true;
  try {
    await API.routeManagementRequest(route.params.accountId, row.id, {
      expected_version: row.lock_version,
      [row.kind === 'transfer' ? 'batch_review_id' : 'resolution_event_id']: id,
    });
    if (version === sequence) await load();
  } catch (e) {
    if (version !== sequence) return;
    uncertain.value = !e.response || e.response.status >= 500;
    error.value =
      e.response?.data?.errors?.[0] ||
      t('RELATIONSHIP.MANAGEMENT_REQUESTS.error');
    if ([401, 403, 404].includes(e.response?.status)) {
      rows.value = [];
      selected.value = null;
    }
  } finally {
    if (version === sequence) saving.value = false;
  }
};
</script>

<template>
  <section class="space-y-3 rounded border p-3">
    <button
      type="button"
      :disabled="loading || saving"
      @click="load"
    >
      {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.title') }}</button
    ><template v-if="shown">
      <p>{{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.help') }}</p>
      <p
        v-if="error"
        role="alert"
      >
        {{ error }}
      </p>
      <p
        v-if="uncertain"
        role="alert"
      >
        {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.uncertain') }}
      </p>
      <form
        v-if="permitted"
        class="space-y-2"
        @submit.prevent="submit"
      >
        <fieldset :disabled="saving || loading || uncertain">
          <template v-if="!assignmentId">
            <label
              >{{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.kind')
              }}<select v-model="kind">
                <option value="suspend">
                  {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.suspend') }}
                </option>
                <option value="restore">
                  {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.restore') }}
                </option>
              </select></label
            ><label
              >{{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.analyst')
              }}<select
                v-model="analyst"
                required
              >
                <option value="">—</option>
                <option
                  v-for="row in metadata.owners || []"
                  :key="row[0]"
                  :value="row[0]"
                >
                  {{ row[1] }}
                </option>
              </select></label
            > </template
          ><label class="block"
            >{{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.reason')
            }}<textarea
              v-model="reason"
              maxlength="2000"
              required
              class="w-full rounded border p-2"
            /></label
          ><button type="submit">
            {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.submit') }}
          </button>
        </fieldset>
      </form>
      <ul>
        <li
          v-for="row in rows"
          :key="row.id"
          class="border-b py-2"
        >
          <strong
            >{{ t(`RELATIONSHIP.MANAGEMENT_REQUESTS.${row.kind}`) }} #{{
              row.id
            }}</strong
          >
          · {{ row.state }}
          <p v-if="!row.redacted">{{ row.reason }}</p>
          <p v-else>{{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.redacted') }}</p>
          <button
            v-if="meta.can_route && row.state === 'pending' && !row.redacted"
            type="button"
            :disabled="loading || saving || uncertain"
            @click="choose(row)"
          >
            {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.link') }}
          </button>
        </li>
      </ul>
      <button
        type="button"
        :disabled="page <= 1 || loading || saving"
        @click="
          page--;
          load();
        "
      >
        {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.previous') }}</button
      ><span>{{ page }}</span
      ><button
        type="button"
        :disabled="page * 25 >= meta.total || loading || saving"
        @click="
          page++;
          load();
        "
      >
        {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.next') }}
      </button>
      <form
        v-if="selected"
        @submit.prevent="link"
      >
        <p>{{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.nativeOnly') }}</p>
        <select
          v-model="receipt"
          :disabled="loading || saving || uncertain"
          required
        >
          <option value="">—</option>
          <option
            v-for="row in options"
            :key="row.id"
            :value="row.id"
          >
            #{{ row.id }} · {{ row.state }} · {{ row.created_at }}
          </option></select
        ><button
          type="button"
          :disabled="optionPage <= 1 || loading || saving"
          @click="choose(selected, optionPage - 1)"
        >
          {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.previous') }}</button
        ><button
          type="button"
          :disabled="optionPage * 25 >= optionTotal || loading || saving"
          @click="choose(selected, optionPage + 1)"
        >
          {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.next') }}</button
        ><button
          type="submit"
          :disabled="!receipt || loading || saving || uncertain"
        >
          {{ t('RELATIONSHIP.MANAGEMENT_REQUESTS.confirm') }}
        </button>
      </form>
    </template>
  </section>
</template>
