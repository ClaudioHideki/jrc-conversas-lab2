<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';
import TeamsAPI from 'dashboard/api/teams';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  card: { type: Object, required: true },
  context: { type: Object, required: true },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const key = computed(() => props.card.key);
const tab = ref('queues');
const q = ref('');
const status = ref('');
const items = ref([]);
const agents = ref([]);
const meta = ref({ page: 1, pages: 0, total: 0 });
const failed = ref(false);
const loading = ref(false);
const teamManage = ref(false);
const dialog = ref(null);
const draft = ref({});
const editing = ref(null);
const saving = ref(false);
const formError = ref('');
let generation = 0;
const resource = computed(() =>
  key.value === 'queues'
    ? tab.value
    : { general: 'units' }[key.value] || key.value
);
const pending = computed(() => props.card.state === 'pending_contract');
const local = computed(() =>
  ['units', 'queues', 'memberships', 'teams'].includes(resource.value)
);
const canEdit = computed(
  () =>
    props.context.capabilities.configure &&
    local.value &&
    (resource.value !== 'teams' || teamManage.value)
);
const label = name => t(`JRC_CONTACT_CENTER.ADMIN.${name}`);
const title = computed(() =>
  ['audit', 'events'].includes(key.value)
    ? label(key.value.toUpperCase())
    : t(`JRC_CONTACT_CENTER.ADMIN.CARDS.${key.value}.NAME`)
);
const queryValue = suffix => route.query[`${resource.value}_${suffix}`];
const page = computed(() => {
  const value = Number(queryValue('page') || 1);
  return Number.isSafeInteger(value) && value > 0 ? value : 1;
});
const tableRows = computed(() =>
  items.value.map(row => ({
    ...row,
    displayName:
      (resource.value === 'integrations'
        ? label(`CAPABILITIES.${row.name}`)
        : row.name) ||
      row.user_name ||
      row.event_type ||
      label('PABX_CONNECTION'),
    detail:
      row.code ||
      row.extension ||
      row.queue_name ||
      (row.state || row.status
        ? label(`STATES.${row.state || row.status}`)
        : ''),
  }))
);
const changePage = value =>
  router.replace({
    query: { ...route.query, [`${resource.value}_page`]: value },
  });
const search = () =>
  router.replace({
    query: {
      ...route.query,
      [`${resource.value}_q`]: q.value || undefined,
      [`${resource.value}_status`]: status.value || undefined,
      [`${resource.value}_page`]: 1,
    },
  });
const clear = () => {
  q.value = '';
  status.value = '';
  search();
};
const load = async () => {
  generation += 1;
  const version = generation;
  items.value = [];
  meta.value = { page: page.value, pages: 0, total: 0 };
  failed.value = false;
  if (
    pending.value ||
    ['closures', 'permissions', 'approvals'].includes(key.value)
  )
    return;
  loading.value = true;
  const params = {
    page: page.value,
    per_page: 20,
    q: queryValue('q') || '',
    status: queryValue('status') || '',
  };
  try {
    let response;
    if (resource.value === 'units')
      response = await API.units(props.accountId, params);
    else if (resource.value === 'queues')
      response = await API.queues(props.accountId, params);
    else if (resource.value === 'memberships')
      response = await API.queueMemberships(props.accountId, params);
    else
      response = await API.administrativeList(
        props.accountId,
        resource.value,
        params
      );
    if (version !== generation) return;
    items.value = response.data.items || [];
    meta.value = response.data.meta || {
      page: 1,
      pages: 1,
      total: items.value.length,
    };
    agents.value = response.data.agents || [];
    teamManage.value = response.data.can_manage === true;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
const reprocess = async row => {
  if (saving.value) return;
  saving.value = true;
  try {
    await API.reprocessEvent(props.accountId, row.id);
    await load();
  } catch {
    failed.value = true;
  } finally {
    saving.value = false;
  }
};
const open = async row => {
  editing.value = row || null;
  formError.value = '';
  draft.value = row
    ? JSON.parse(JSON.stringify(row))
    : {
        name: '',
        code: '',
        kind: 'sac',
        timezone: 'America/Sao_Paulo',
        status: 'active',
        strategy: 'provider',
        unit_id: '',
        queue_id: '',
        account_user_id: '',
        role: 'agent',
        priority: 100,
        active: true,
        settings: {},
        description: '',
        participates: true,
        supervises: false,
      };
  if (key.value === 'closures') {
    const version = generation;
    try {
      const response = await API.acwPolicy(props.accountId);
      if (version !== generation) return;
      const policy = response.data.item;
      const format = seconds =>
        seconds % 60
          ? ''
          : `${String(Math.floor(seconds / 3600)).padStart(2, '0')}:${String((seconds / 60) % 60).padStart(2, '0')}`;
      draft.value = {
        voice: format(policy.limits.voice),
        whatsapp: format(policy.limits.whatsapp),
        voice_required: policy.voice_required,
      };
    } catch {
      failed.value = true;
      return;
    }
  }
  await nextTick();
  dialog.value.open();
};
const save = async () => {
  if (saving.value) return;
  saving.value = true;
  formError.value = '';
  const version = generation;
  const account = props.accountId;
  try {
    const row = draft.value;
    const id = editing.value?.id;
    if (key.value === 'closures') {
      const seconds = value => {
        if (!/^\d{2}:[0-5]\d$/.test(value))
          throw new Error(label('TIME_INVALID'));
        const [hours, minutes] = value.split(':').map(Number);
        const result = (hours * 60 + minutes) * 60;
        if (result < 60 || result > 3600)
          throw new Error(label('TIME_INVALID'));
        return result;
      };
      await API.updateAcwPolicy(
        account,
        { voice: seconds(row.voice), whatsapp: seconds(row.whatsapp) },
        { voice_required: row.voice_required }
      );
    } else if (resource.value === 'units')
      await API.saveUnit(
        account,
        {
          name: row.name,
          code: row.code,
          kind: row.kind,
          timezone: row.timezone,
          status: row.status,
          settings: row.settings || {},
        },
        id
      );
    else if (resource.value === 'queues')
      await API.saveQueue(
        account,
        {
          name: row.name,
          code: row.code,
          unit_id: row.unit_id,
          status: row.status,
          strategy: row.strategy,
          service_kind: 'voice',
        },
        id
      );
    else if (resource.value === 'memberships')
      await API.saveQueueMembership(
        account,
        {
          queue_id: row.queue_id,
          account_user_id: row.account_user_id,
          participates: row.participates,
          supervises: row.supervises,
          active: row.active,
          priority: row.priority,
        },
        id
      );
    else if (resource.value === 'teams') {
      const attributes = { name: row.name, description: row.description };
      if (id) await TeamsAPI.update(id, attributes);
      else await TeamsAPI.create(attributes);
    }
    if (version !== generation) return;
    dialog.value.close();
    await load();
    emit('changed');
  } catch (error) {
    if (version === generation)
      formError.value =
        error.response?.data?.message ||
        error.response?.data?.error ||
        error.message ||
        label('SAVE_ERROR');
  } finally {
    saving.value = false;
  }
};
watch(
  [
    () => props.accountId,
    resource,
    page,
    () => queryValue('q'),
    () => queryValue('status'),
  ],
  () => {
    q.value = queryValue('q') || '';
    status.value = queryValue('status') || '';
    dialog.value?.close();
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-2xl border border-n-weak bg-n-solid-2 p-4 sm:p-5"
    data-administration-section
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2 class="text-xl font-semibold text-n-slate-12">{{ title }}</h2>
      <button
        v-if="canEdit || key === 'closures'"
        type="button"
        class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white"
        data-create
        @click="open()"
      >
        {{ label(key === 'closures' ? 'CONFIGURE' : 'CREATE') }}
      </button>
    </div>
    <p class="text-sm text-n-slate-11">{{ label('LOCAL_ONLY') }}</p>
    <p
      v-if="pending"
      role="status"
      class="rounded-xl border border-n-amber-6 bg-n-amber-2 p-4 text-sm text-n-amber-11"
    >
      {{ label('PENDING') }}
    </p>
    <p v-if="key === 'closures'" class="text-sm text-n-slate-11">
      {{ label('ACW_SCOPE') }}
    </p>
    <p
      v-if="key === 'permissions' || key === 'approvals'"
      class="text-sm text-n-slate-11"
    >
      {{ label('NATIVE_INTEGRATION') }}
    </p>
    <p
      v-if="
        ['permissions', 'approvals'].includes(key) &&
        !context.native_links?.[key]
      "
      class="text-sm text-n-amber-11"
    >
      {{ label('NATIVE_DENIED') }}
    </p>
    <p
      v-if="key === 'closures' && failed"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <RouterLink
      v-if="key === 'permissions' && context.native_links?.permissions"
      :to="{ name: 'custom_roles_list', params: { accountId } }"
      class="inline-block text-sm text-n-blue-11"
    >
      {{ label('NATIVE_PERMISSIONS') }}
    </RouterLink>
    <RouterLink
      v-if="key === 'approvals' && context.native_links?.approvals"
      :to="{ name: 'jrc_approvals', params: { accountId } }"
      class="inline-block text-sm text-n-blue-11"
    >
      {{ label('NATIVE_APPROVALS') }}
    </RouterLink>
    <nav
      v-if="key === 'queues'"
      class="flex flex-wrap gap-2"
      :aria-label="title"
    >
      <button
        v-for="name in ['queues', 'teams', 'memberships']"
        :key="name"
        type="button"
        :aria-pressed="tab === name"
        class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
        :class="{ 'bg-n-blue-3': tab === name }"
        @click="tab = name"
      >
        {{ label(`RESOURCES.${name}`) }}
      </button>
    </nav>
    <template
      v-if="!pending && !['closures', 'permissions', 'approvals'].includes(key)"
    >
      <form
        v-if="resource !== 'pabx'"
        class="flex flex-wrap items-end gap-3"
        @submit.prevent="search"
      >
        <label class="min-w-0 flex-1 text-sm text-n-slate-11"
          >{{ label('SEARCH')
          }}<input
            v-model="q"
            type="search"
            maxlength="100"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        /></label>
        <label
          v-if="local && resource !== 'teams'"
          class="text-sm text-n-slate-11"
          >{{ label('STATUS')
          }}<select
            v-model="status"
            class="ml-2 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">{{ label('ALL') }}</option>
            <option value="active">{{ label('ACTIVE') }}</option>
            <option value="inactive">{{ label('INACTIVE') }}</option>
          </select></label
        >
        <button
          type="submit"
          class="rounded-lg border border-n-blue-7 px-3 py-2 text-sm text-n-blue-11"
        >
          {{ label('FILTER') }}
        </button>
        <button
          type="button"
          class="px-3 py-2 text-sm text-n-slate-11"
          @click="clear"
        >
          {{ label('CLEAR') }}
        </button>
      </form>
      <p v-if="loading" role="status">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <p v-else-if="failed" role="alert" class="text-n-ruby-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </p>
      <p v-else-if="!items.length" class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
      </p>
      <div v-else class="divide-y divide-n-weak">
        <article
          v-for="row in tableRows"
          :key="row.id || row.name"
          class="flex min-w-0 flex-wrap items-center justify-between gap-3 py-3"
          data-resource-row
        >
          <div class="min-w-0">
            <p class="break-words font-semibold text-n-slate-12">
              {{ row.displayName }}
            </p>
            <p class="break-words text-sm text-n-slate-11">{{ row.detail }}</p>
          </div>
          <button
            v-if="canEdit"
            type="button"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
            data-edit
            @click="open(row)"
          >
            {{ label('EDIT') }}
          </button>
          <button
            v-if="
              key === 'events' &&
              row.status === 'failed' &&
              row.signature_verified &&
              context.capabilities.control
            "
            type="button"
            :disabled="saving"
            class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
            @click="reprocess(row)"
          >
            {{ label('REPROCESS') }}
          </button>
        </article>
      </div>
      <nav
        v-if="meta.pages > 1"
        class="flex flex-wrap items-center gap-3"
        :aria-label="label('PAGINATION')"
      >
        <button
          type="button"
          :disabled="page <= 1 || loading"
          class="rounded-lg border border-n-weak p-2 disabled:opacity-40"
          @click="changePage(page - 1)"
        >
          {{ label('PREVIOUS') }}
        </button>
        <span class="text-sm"
          >{{ label('TOTAL') }} {{ meta.total }} · {{ label('PAGE') }}
          {{ page }} / {{ meta.pages }}</span
        >
        <button
          type="button"
          :disabled="page >= meta.pages || loading"
          class="rounded-lg border border-n-weak p-2 disabled:opacity-40"
          @click="changePage(page + 1)"
        >
          {{ label('NEXT') }}
        </button>
      </nav>
    </template>
    <Dialog
      ref="dialog"
      contained
      overflow-y-auto
      :title="`${title} — ${label(editing ? 'EDIT' : 'CREATE')}`"
      :confirm-button-label="label('SAVE')"
      :cancel-button-label="label('CANCEL')"
      :disable-confirm-button="saving"
      :is-loading="saving"
      :dismissible="!saving"
      :close-on-click-outside="false"
      width="2xl"
      @confirm="save"
    >
      <div class="grid min-w-0 gap-4 sm:grid-cols-2">
        <p
          v-if="formError"
          role="alert"
          class="break-words text-sm text-n-ruby-11 sm:col-span-2"
        >
          {{ formError }}
        </p>
        <template v-if="key === 'closures'">
          <label
            v-for="channel in ['voice', 'whatsapp']"
            :key="channel"
            class="text-sm"
            >{{ label(channel.toUpperCase())
            }}<input
              v-model="draft[channel]"
              required
              pattern="[0-9]{2}:[0-5][0-9]"
              :placeholder="label('TIME_FORMAT')"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
          <label class="flex items-center gap-2 text-sm sm:col-span-2"
            ><input v-model="draft.voice_required" type="checkbox" />{{
              label('VOICE_REQUIRED')
            }}</label
          >
        </template>
        <template v-else-if="resource === 'memberships'">
          <label class="text-sm"
            >{{ label('QUEUE')
            }}<select
              v-model="draft.queue_id"
              required
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="">{{ label('SELECT') }}</option>
              <option
                v-for="row in context.queues"
                :key="row.id"
                :value="row.id"
              >
                {{ row.name }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >{{ label('AGENT')
            }}<select
              v-model="draft.account_user_id"
              required
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="">{{ label('SELECT') }}</option>
              <option
                v-for="row in agents"
                :key="row.account_user_id"
                :value="row.account_user_id"
              >
                {{ row.name }}
              </option>
            </select></label
          >
          <label class="flex items-center gap-2 text-sm"
            ><input v-model="draft.participates" type="checkbox" />{{
              label('PARTICIPATES')
            }}</label
          >
          <label class="flex items-center gap-2 text-sm"
            ><input v-model="draft.supervises" type="checkbox" />{{
              label('SUPERVISES')
            }}</label
          >
          <label class="flex items-center gap-2 text-sm"
            ><input v-model="draft.active" type="checkbox" />{{
              label('ACTIVE')
            }}</label
          >
        </template>
        <template v-else>
          <label class="text-sm"
            >{{ label('NAME')
            }}<input
              v-model="draft.name"
              required
              maxlength="120"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
          <template v-if="resource !== 'teams'">
            <label class="text-sm"
              >{{ label('CODE')
              }}<input
                v-model="draft.code"
                required
                maxlength="80"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            /></label>
          </template>
          <template v-if="resource === 'teams'">
            <label class="text-sm sm:col-span-2"
              >{{ label('DESCRIPTION_FIELD')
              }}<textarea
                v-model="draft.description"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              />
            </label>
          </template>
          <template v-if="resource === 'queues'">
            <label class="text-sm"
              >{{ label('UNIT')
              }}<select
                v-model="draft.unit_id"
                required
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">{{ label('SELECT') }}</option>
                <option
                  v-for="row in context.units"
                  :key="row.id"
                  :value="row.id"
                >
                  {{ row.name }}
                </option>
              </select></label
            >
          </template>
          <template v-if="resource === 'units'">
            <label class="text-sm"
              >{{ label('KIND')
              }}<select
                v-model="draft.kind"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option
                  v-for="kind in ['sac', 'finance', 'coe', 'administrative']"
                  :key="kind"
                  :value="kind"
                >
                  {{ t(`JRC_CONTACT_CENTER.SETTINGS.KINDS.${kind}`) }}
                </option>
              </select></label
            >
            <label class="text-sm"
              >{{ label('TIMEZONE')
              }}<input
                v-model="draft.timezone"
                required
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            /></label>
            <label class="text-sm"
              >{{ label('COMPANY')
              }}<select
                v-model="draft.settings.issuer_company_id"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">{{ label('SELECT') }}</option>
                <option
                  v-for="row in context.corporate.companies"
                  :key="row.id"
                  :value="row.id"
                >
                  {{ row.name }}
                </option>
              </select></label
            >
            <label class="text-sm"
              >{{ label('BUSINESS_UNIT')
              }}<select
                v-model="draft.settings.business_unit_id"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="">{{ label('SELECT') }}</option>
                <option
                  v-for="row in context.corporate.units.filter(
                    unit =>
                      String(unit.company_id) ===
                      String(draft.settings.issuer_company_id)
                  )"
                  :key="row.id"
                  :value="row.id"
                >
                  {{ row.name }}
                </option>
              </select></label
            >
          </template>
          <template v-if="resource !== 'teams'">
            <label class="text-sm"
              >{{ label('STATUS')
              }}<select
                v-model="draft.status"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
              >
                <option value="active">{{ label('ACTIVE') }}</option>
                <option value="inactive">{{ label('INACTIVE') }}</option>
              </select></label
            >
          </template>
        </template>
      </div>
    </Dialog>
  </section>
</template>
