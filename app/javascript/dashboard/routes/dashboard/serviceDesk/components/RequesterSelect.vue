<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import API from 'dashboard/api/serviceDeskRequesters';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canonicalId } from '../helpers/access';
import { newRequestKey } from '../helpers/drafts';
import LookupSelect from './LookupSelect.vue';
import ServiceDeskDialog from './ServiceDeskDialog.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  companyId: { type: [String, Number], default: null },
  unitId: { type: String, default: '' },
  disabled: Boolean,
  currentName: { type: String, default: '' },
  currentPhone: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue', 'selected', 'busy']);
const { t } = useI18n();
const session = useServiceDesk();
const { canAccess } = useCustomerMaster();
const copy = key => t(`JRC_SERVICE_DESK.REQUESTERS.${key}`);
const mode = ref('');
const query = ref('');
const page = ref(1);
const total = ref(0);
const rows = ref([]);
const candidate = ref(null);
const saving = ref(false);
const searching = ref(false);
const checking = ref(false);
const error = ref('');
const message = ref('');
const refresh = ref(0);
const canCreate = ref(false);
const distinctAllowed = ref(false);
const confirmDistinct = ref(false);
const companyName = ref('');
const person = reactive({ name: '', email: '', phone_number: '' });
let epoch = 0;
let searchTurn = 0;
let timer;
let requestKey = null;
const permitted = computed(
  () =>
    canAccess.value &&
    !!props.companyId &&
    !!props.unitId &&
    session.state.context?.effective_permissions?.includes(
      'jrc_service_desk_customers_view'
    ) &&
    session.state.context?.units?.some(
      unit => unit.id === props.unitId && unit.permissions.create_ticket
    )
);
const busy = computed(() => saving.value || checking.value);
watch(busy, value => emit('busy', value));
const params = () => ({ unit_id: props.unitId, company_id: props.companyId });
const current = turn => turn === epoch;
const choose = row => {
  const id = canonicalId(row?.id);
  if (
    !id ||
    String(row.company_id) !== String(props.companyId) ||
    row.requester_eligible === false
  )
    throw new TypeError('Invalid requester response');
  emit('update:modelValue', id);
  emit('selected', { ...row, id, company_id: String(row.company_id) });
  refresh.value += 1;
  mode.value = '';
  candidate.value = null;
  message.value = copy('selected');
};
const search = async () => {
  if (!permitted.value || props.disabled) return;
  const turn = epoch;
  searchTurn += 1;
  const version = searchTurn;
  searching.value = true;
  error.value = '';
  distinctAllowed.value = false;
  confirmDistinct.value = false;
  try {
    const { data } = await API.search({
      ...params(),
      q: query.value,
      page: page.value,
      per_page: 10,
    });
    if (!current(turn) || version !== searchTurn) return;
    if (mode.value === 'search') rows.value = data.items;
    total.value = data.meta.total;
    canCreate.value = data.can_create === true;
    companyName.value = data.company?.name || '';
  } catch {
    if (current(turn) && version === searchTurn)
      error.value = copy('load_failed');
  } finally {
    if (current(turn) && version === searchTurn) searching.value = false;
  }
};
const open = async value => {
  if (!permitted.value || props.disabled || busy.value) return;
  mode.value = value;
  rows.value = [];
  candidate.value = null;
  error.value = '';
  query.value = '';
  page.value = 1;
  await search();
};
watch(query, () => {
  clearTimeout(timer);
  searchTurn += 1;
  rows.value = [];
  page.value = 1;
  timer = setTimeout(search, 300);
});
watch(page, search);
const selectCandidate = row => {
  if (!row.requester_eligible || !row.can_link || saving.value) return;
  if (String(row.company_id) === String(props.companyId)) choose(row);
  else if (!row.company_id) candidate.value = row;
};
const link = async () => {
  if (!candidate.value || saving.value || !permitted.value || props.disabled)
    return;
  const turn = epoch;
  saving.value = true;
  error.value = '';
  try {
    const { data } = await API.link(candidate.value.id, {
      ...params(),
      confirm: true,
    });
    if (current(turn)) choose(data.person);
  } catch {
    if (current(turn)) error.value = copy('link_failed');
  } finally {
    if (current(turn)) saving.value = false;
  }
};
watch(person, () => {
  requestKey = null;
  distinctAllowed.value = false;
  confirmDistinct.value = false;
  error.value = '';
  rows.value = [];
});
const create = async () => {
  if (
    !person.name.trim() ||
    !permitted.value ||
    !canCreate.value ||
    props.disabled ||
    saving.value
  )
    return;
  const turn = epoch;
  saving.value = true;
  error.value = '';
  requestKey ||= newRequestKey();
  try {
    const { data } = await API.register({
      ...params(),
      contact: { ...person },
      request_key: requestKey,
      confirm_distinct: confirmDistinct.value,
    });
    if (!current(turn)) return;
    choose(data.person);
    Object.assign(person, { name: '', email: '', phone_number: '' });
  } catch (err) {
    if (!current(turn)) return;
    error.value = copy(
      err.response?.data?.code === 'POSSIBLE_DUPLICATE'
        ? 'duplicate'
        : 'create_failed'
    );
    if (Array.isArray(err.response?.data?.candidates))
      rows.value = err.response.data.candidates;
    distinctAllowed.value = err.response?.data?.allow_distinct === true;
  } finally {
    if (current(turn)) saving.value = false;
  }
};
watch(
  [() => props.companyId, () => props.unitId, () => session.state.context],
  async () => {
    epoch += 1;
    const turn = epoch;
    clearTimeout(timer);
    searchTurn += 1;
    mode.value = '';
    rows.value = [];
    candidate.value = null;
    message.value = '';
    error.value = '';
    saving.value = false;
    searching.value = false;
    checking.value = false;
    requestKey = null;
    canCreate.value = false;
    companyName.value = '';
    Object.assign(person, { name: '', email: '', phone_number: '' });
    if (!props.modelValue) return;
    // Revalidate the actual relationship. Changing a company never writes a Contact.
    const id = props.modelValue;
    checking.value = true;
    try {
      const { data } = await API.validate(id, params());
      if (current(turn) && props.modelValue === id) choose(data.person);
    } catch {
      if (current(turn) && props.modelValue === id) {
        emit('update:modelValue', '');
        emit('selected', null);
        message.value = copy('company_changed');
      }
    } finally {
      if (current(turn)) checking.value = false;
    }
  }
);
watch(permitted, value => {
  if (value) return;
  mode.value = '';
  rows.value = [];
  candidate.value = null;
  searchTurn += 1;
});
onBeforeUnmount(() => {
  epoch += 1;
  searchTurn += 1;
  clearTimeout(timer);
  emit('busy', false);
});
</script>

<template>
  <div class="grid min-w-0 gap-2" data-testid="requester-select">
    <LookupSelect
      :model-value="modelValue"
      resource="requesters"
      :company-id="companyId"
      :unit-id="unitId"
      :label="t('JRC_SERVICE_DESK.FIELDS.requester')"
      :current-name="currentName"
      :current-phone="currentPhone"
      :disabled="disabled || busy"
      :refresh-key="refresh"
      :empty-text="companyId ? copy('empty') : ''"
      @update:model-value="emit('update:modelValue', $event)"
      @selected="emit('selected', $event)"
    />
    <p class="m-0 text-xs text-n-slate-11">{{ copy('separation') }}</p>
    <p v-if="message" role="status" class="m-0 text-sm text-n-teal-11">
      {{ message }}
    </p>
    <div v-if="permitted" class="flex flex-wrap gap-2">
      <Button
        type="button"
        size="sm"
        variant="ghost"
        :label="copy('search')"
        :disabled="disabled || busy"
        @click="open('search')"
      />
      <Button
        type="button"
        size="sm"
        variant="ghost"
        :label="copy('new')"
        :disabled="disabled || busy"
        @click="open('create')"
      />
    </div>
    <ServiceDeskDialog
      :open="!!mode"
      :title="copy(mode === 'create' ? 'new' : 'search')"
      :busy="saving"
      @close="mode = ''"
    >
      <div class="grid gap-4">
        <p class="m-0 text-sm text-n-slate-11">
          {{ copy('company') }}: {{ companyName }} #{{ companyId }}
        </p>
        <template v-if="mode === 'create'">
          <Input
            v-model="person.name"
            :label="copy('name')"
            :disabled="saving"
            maxlength="255"
          />
          <div class="grid gap-3 sm:grid-cols-2">
            <Input
              v-model="person.email"
              type="email"
              :label="copy('email')"
              :disabled="saving"
              maxlength="255"
            />
            <Input
              v-model="person.phone_number"
              :label="copy('phone')"
              :disabled="saving"
              maxlength="50"
            />
          </div>
          <p class="m-0 text-xs text-n-slate-11">{{ copy('save_help') }}</p>
          <label v-if="distinctAllowed" class="flex items-start gap-2 text-sm">
            <input
              v-model="confirmDistinct"
              type="checkbox"
              :disabled="saving"
            />
            <span>{{ copy('confirm_distinct') }}</span>
          </label>
          <Button
            type="button"
            :label="copy('save')"
            :disabled="saving || searching || !person.name.trim() || !canCreate"
            @click="create"
          />
        </template>
        <template v-else>
          <Input
            v-model="query"
            :label="copy('search_label')"
            :disabled="saving"
            maxlength="200"
          />
          <Button
            type="button"
            :label="t('JRC_SERVICE_DESK.COMMON.search')"
            :disabled="saving || searching"
            @click="search"
          />
        </template>
        <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
          {{ error }}
        </p>
        <p v-if="searching" role="status">
          {{ t('JRC_SERVICE_DESK.STATES.loading') }}
        </p>
        <p
          v-if="!searching && !rows.length && mode === 'search'"
          class="text-sm text-n-slate-11"
        >
          {{ copy('no_results') }}
        </p>
        <div v-if="rows.length" class="grid max-h-80 gap-2 overflow-y-auto">
          <article
            v-for="row in rows"
            :key="row.id"
            class="grid gap-2 rounded-xl border border-n-weak p-3 text-sm sm:grid-cols-[1fr_auto]"
          >
            <div class="min-w-0 break-words">
              <strong>{{ row.name }}</strong> #{{ row.id }}
              <p class="m-0 text-xs text-n-slate-11">
                {{ row.email }} {{ row.phone_number }} {{ row.identifier }}
              </p>
              <p class="m-0 text-xs text-n-slate-11">
                {{ row.company_name || copy('unlinked') }}
              </p>
              <p
                v-if="!row.requester_eligible"
                class="m-0 text-xs text-n-amber-11"
              >
                {{ copy(row.review_reason || 'import_review') }}
              </p>
              <p
                v-else-if="
                  row.company_id && String(row.company_id) !== String(companyId)
                "
                class="m-0 text-xs text-n-amber-11"
              >
                {{ copy('other_company') }}
              </p>
            </div>
            <Button
              type="button"
              size="sm"
              :label="
                copy(
                  String(row.company_id) === String(companyId) ? 'use' : 'link'
                )
              "
              :disabled="
                saving ||
                !row.requester_eligible ||
                !row.can_link ||
                (!!row.company_id &&
                  String(row.company_id) !== String(companyId))
              "
              @click="selectCandidate(row)"
            />
          </article>
        </div>
        <div
          v-if="mode === 'search' && total > 10"
          class="flex flex-wrap items-center justify-between gap-2"
        >
          <Button
            type="button"
            variant="ghost"
            :label="t('JRC_SERVICE_DESK.COMMON.previous')"
            :disabled="saving || searching || page <= 1"
            @click="page--"
          />
          <span class="text-xs">{{ page }} / {{ Math.ceil(total / 10) }}</span>
          <Button
            type="button"
            variant="ghost"
            :label="t('JRC_SERVICE_DESK.COMMON.next')"
            :disabled="saving || searching || page * 10 >= total"
            @click="page++"
          />
        </div>
        <div
          v-if="candidate"
          class="grid gap-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-4"
        >
          <p class="m-0 text-sm">
            {{ copy('confirm_help') }} <strong>{{ candidate.name }}</strong>
            {{ '→' }} {{ companyName }} #{{ companyId }}
          </p>
          <Button
            type="button"
            :label="copy('confirm_link')"
            :disabled="saving"
            @click="link"
          />
          <Button
            type="button"
            variant="ghost"
            :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
            :disabled="saving"
            @click="candidate = null"
          />
        </div>
      </div>
    </ServiceDeskDialog>
  </div>
</template>
