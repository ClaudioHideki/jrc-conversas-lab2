<script setup>
/* global axios */
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ accountId: { type: String, required: true } });
const { t } = useI18n();
const units = ref([]);
const grants = ref([]);
const establishments = ref([]);
const busy = ref(false);
const error = ref(false);
const saved = ref(false);
let generation = 0;
const base = () =>
  `/api/v1/accounts/${props.accountId}/jrc_service_desk/requester_portal`;
async function load() {
  generation += 1;
  const current = generation;
  units.value = [];
  grants.value = [];
  establishments.value = [];
  error.value = false;
  try {
    const [routing, access, stores] = await Promise.all([
      axios.get(`${base()}/routing`),
      axios.get(base()),
      axios.get(`${base()}/establishments`),
    ]);
    if (current !== generation) return;
    units.value = routing.data.units;
    grants.value = access.data.grants;
    establishments.value = stores.data.establishments;
  } catch {
    if (current === generation) error.value = true;
  }
}
watch(() => props.accountId, load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
});
async function saveUnit(unit, remove = false) {
  if (busy.value) return;
  const account = props.accountId;
  const current = generation;
  busy.value = true;
  error.value = false;
  saved.value = false;
  try {
    const configuration = remove
      ? {
          stores_enabled: unit.configuration.stores_enabled === true,
          company_routes: unit.configuration.company_routes || [],
        }
      : unit.configuration;
    await axios.patch(`${base()}/routing`, {
      unit_id: unit.id,
      revision: unit.revision,
      configuration,
    });
    if (account !== props.accountId || current !== generation) return;
    await load();
    if (account === props.accountId) saved.value = true;
  } catch {
    if (account === props.accountId) error.value = true;
  } finally {
    busy.value = false;
  }
}
async function saveGrant(grant) {
  if (busy.value) return;
  const account = props.accountId;
  const current = generation;
  busy.value = true;
  error.value = false;
  saved.value = false;
  try {
    await axios.patch(`${base()}/grants/${grant.id}`, {
      establishment_ids: grant.establishment_ids,
      expected_revision: grant.revision,
    });
    if (account !== props.accountId || current !== generation) return;
    await load();
    if (account === props.accountId) saved.value = true;
  } catch {
    if (account === props.accountId && current === generation)
      error.value = true;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <section
    class="mt-6 space-y-4 rounded-xl border border-n-weak bg-n-solid-1 p-4"
  >
    <h3 class="font-semibold">{{ t('PORTAL.ROUTING_TITLE') }}</h3>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ t('PORTAL.ERROR') }}
    </p>
    <p v-if="saved" role="status" class="text-sm">{{ t('PORTAL.SAVED') }}</p>
    <form
      v-for="unit in units"
      :key="unit.id"
      class="space-y-3 rounded-lg border border-n-weak p-4"
      @submit.prevent="saveUnit(unit)"
    >
      <h4 class="font-medium">{{ unit.name }}</h4>
      <div class="grid gap-3 md:grid-cols-2">
        <label class="text-sm"
          >{{ t('PORTAL.DEFAULT_QUEUE') }}
          <select
            v-model="unit.configuration.queue_id"
            class="mt-1 w-full rounded border border-n-weak bg-n-background p-2"
            :disabled="busy"
            @change="unit.configuration.assignee_account_user_id = null"
          >
            <option :value="null">{{ t('PORTAL.SELECT') }}</option>
            <option
              v-for="queue in unit.queues"
              :key="queue.id"
              :value="queue.id"
            >
              {{ queue.name }}
            </option>
          </select>
        </label>
        <label class="text-sm"
          >{{ t('PORTAL.DEFAULT_ASSIGNEE') }}
          <select
            v-model="unit.configuration.assignee_account_user_id"
            class="mt-1 w-full rounded border border-n-weak bg-n-background p-2"
            :disabled="busy || !unit.configuration.queue_id"
          >
            <option :value="null">{{ t('PORTAL.SELECT') }}</option>
            <option
              v-for="member in unit.assignees"
              :key="member.id"
              :value="member.id"
            >
              {{ member.name }}
            </option>
          </select>
        </label>
      </div>
      <label class="flex items-center gap-2 text-sm"
        ><input
          v-model="unit.configuration.stores_enabled"
          type="checkbox"
          :disabled="busy"
        />{{ t('PORTAL.STORES_ENABLED') }}</label
      >
      <div class="flex flex-wrap gap-2">
        <Button type="submit" :label="t('PORTAL.SAVE')" :disabled="busy" />
        <Button
          type="button"
          variant="outline"
          :label="t('PORTAL.REMOVE_ROUTING')"
          :disabled="busy"
          @click="saveUnit(unit, true)"
        />
      </div>
    </form>
    <details
      v-for="grant in grants"
      :key="grant.id"
      class="rounded-lg border border-n-weak p-3"
    >
      <summary class="cursor-pointer text-sm font-medium">
        {{ t('PORTAL.AUTHORIZED_STORES') }} — {{ grant.contact_name }} ({{
          grant.user_name
        }})
      </summary>
      <form class="mt-3 space-y-3" @submit.prevent="saveGrant(grant)">
        <label
          v-for="store in establishments"
          :key="store.id"
          class="flex items-center gap-2 text-sm"
        >
          <input
            v-model="grant.establishment_ids"
            type="checkbox"
            :value="Number(store.id)"
            :disabled="busy"
          />
          {{ store.store_code }} — {{ store.name }} — {{ store.cnpj }}
        </label>
        <p v-if="!establishments.length" class="text-sm">
          {{ t('PORTAL.NO_STORES') }}
        </p>
        <Button type="submit" :label="t('PORTAL.SAVE')" :disabled="busy" />
      </form>
    </details>
  </section>
</template>
