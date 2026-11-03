<script setup>
import {
  defineAsyncComponent,
  reactive,
  ref,
  watch,
  onBeforeUnmount,
} from 'vue';
import API from 'dashboard/api/jrcCustomers';
import MasterContactPanel from './MasterContactPanel.vue';
import { useCustomerMaster } from '../useCustomerMaster';
import {
  T,
  FIELD_LABELS,
  inputClass,
  buttonClass,
  primaryClass,
  errorMessage,
} from '../copy';
const props = defineProps({
  companyId: { type: [Number, String], required: true },
});
const emit = defineEmits(['changed', 'denied']);
const ContactDetailsDialog = defineAsyncComponent(
  () => import('./ContactDetailsDialog.vue')
);
const selection = ref(null);
const { accountId, identity } = useCustomerMaster();
const contacts = ref([]);
const candidates = ref([]);
const query = ref('');
const meta = ref({ total: 0 });
const page = ref(1);
const mode = ref('');
const detailId = ref(null);
const error = ref('');
const busy = ref(false);
let generation = 0;
let searchGeneration = 0;
let controller;
let searchController;
let active = true;
const subjectKey = () => `${identity.value}:${props.companyId}`;
const current = context => active && context === subjectKey();
const fail = (failure, context) => {
  if (!current(context)) return;
  if ([401, 403, 404].includes(failure.response?.status)) {
    contacts.value = [];
    candidates.value = [];
    selection.value = null;
    mode.value = '';
    emit('denied');
  }
  error.value = errorMessage(failure);
};
const form = reactive({
  name: '',
  email: '',
  phone_number: '',
  job_title: '',
  department: '',
});
const load = async () => {
  generation += 1;
  const version = generation;
  const context = subjectKey();
  controller?.abort();
  controller = new AbortController();
  busy.value = true;
  error.value = '';
  contacts.value = [];
  meta.value = { total: 0 };
  try {
    const { data } = await API.contacts(
      { company_id: props.companyId, page: page.value },
      { accountId: accountId.value, signal: controller.signal }
    );
    if (version === generation) {
      contacts.value = data.payload;
      meta.value = data.meta;
      return true;
    }
    return false;
  } catch (err) {
    if (version === generation) fail(err, context);
    return false;
  } finally {
    if (version === generation) busy.value = false;
  }
};
const changed = async () => {
  const context = subjectKey();
  if ((await load()) && current(context)) emit('changed');
};
const search = async () => {
  const context = subjectKey();
  searchGeneration += 1;
  const version = searchGeneration;
  searchController?.abort();
  searchController = new AbortController();
  error.value = '';
  candidates.value = [];
  try {
    const { data } = await API.contacts(
      { q: query.value },
      { accountId: accountId.value, signal: searchController.signal }
    );
    if (version === searchGeneration && current(context))
      candidates.value = data.payload;
  } catch (err) {
    if (version === searchGeneration) fail(err, context);
  }
};
const link = async item => {
  const context = subjectKey();
  const options = { accountId: accountId.value };
  const reassign =
    item.company_id && String(item.company_id) !== String(props.companyId);
  if (reassign && !window.confirm(T.confirmReassignment)) return;
  busy.value = true;
  error.value = '';
  try {
    await API.saveContact(
      { company_id: Number(props.companyId) },
      item.id,
      {
        confirm_reassignment: Boolean(reassign),
      },
      options
    );
    if (!current(context)) return;
    mode.value = '';
    candidates.value = [];
    await changed();
  } catch (err) {
    fail(err, context);
  } finally {
    if (current(context)) busy.value = false;
  }
};
const create = async () => {
  const context = subjectKey();
  const options = { accountId: accountId.value };
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.saveContact(
      {
        ...form,
        company_id: Number(props.companyId),
      },
      null,
      {},
      options
    );
    if (!current(context)) return;
    selection.value = data.payload.id;
    detailId.value = null;
    mode.value = '';
    Object.keys(form).forEach(key => {
      form[key] = '';
    });
    await changed();
  } catch (err) {
    fail(err, context);
    if (current(context) && err.response?.data?.candidates)
      candidates.value = err.response.data.candidates;
  } finally {
    if (current(context)) busy.value = false;
  }
};
const detach = async item => {
  const context = subjectKey();
  const options = { accountId: accountId.value };
  if (!window.confirm(T.confirmReassignment)) return;
  busy.value = true;
  try {
    await API.saveContact(
      { company_id: null },
      item.id,
      {
        confirm_reassignment: true,
      },
      options
    );
    if (!current(context)) return;
    await changed();
  } catch (err) {
    fail(err, context);
  } finally {
    if (current(context)) busy.value = false;
  }
};
watch(
  [identity, () => props.companyId],
  () => {
    generation += 1;
    searchGeneration += 1;
    controller?.abort();
    searchController?.abort();
    query.value = '';
    Object.keys(form).forEach(key => {
      form[key] = '';
    });
    candidates.value = [];
    mode.value = '';
    detailId.value = null;
    selection.value = null;
    if (page.value === 1) load();
    else page.value = 1;
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  active = false;
  controller?.abort();
  searchController?.abort();
  searchGeneration += 1;
  generation += 1;
});
</script>

<template>
  <section>
    <div class="flex flex-wrap gap-3">
      <button
        type="button"
        :class="primaryClass"
        @click="
          mode = 'create';
          candidates = [];
        "
      >
        {{ T.newContact }}</button
      ><button
        type="button"
        :class="buttonClass"
        @click="
          mode = 'link';
          candidates = [];
        "
      >
        {{ T.linkContact }}
      </button>
    </div>
    <p
      v-if="error"
      class="my-3 text-sm text-n-ruby-11"
      role="alert"
    >
      {{ error }}
    </p>
    <form
      v-if="mode === 'create'"
      class="my-4 rounded-xl border border-n-weak p-4"
      @submit.prevent="create"
    >
      <fieldset
        :disabled="busy"
        class="grid gap-3 md:grid-cols-2"
      >
        <label
          v-for="field in Object.keys(form)"
          :key="field"
          class="text-sm"
          >{{ field === 'name' ? T.contactName : FIELD_LABELS[field]
          }}<input
            v-model.trim="form[field]"
            :type="field === 'email' ? 'email' : 'text'"
            :required="field === 'name'"
            maxlength="255"
            :class="inputClass"
        /></label>
      </fieldset>
      <div class="mt-4 flex gap-2">
        <button
          :class="primaryClass"
          :disabled="busy"
        >
          {{ T.save }}</button
        ><button
          type="button"
          :class="buttonClass"
          @click="
            mode = '';
            candidates = [];
          "
        >
          {{ T.cancel }}
        </button>
      </div>
    </form>
    <form
      v-if="mode === 'link'"
      class="my-4 flex items-end gap-3"
      @submit.prevent="search"
    >
      <input
        v-model="query"
        :aria-label="T.searchContact"
        :placeholder="T.searchContact"
        :class="inputClass"
      /><button
        :class="buttonClass"
        :disabled="busy"
      >
        {{ T.search }}
      </button>
    </form>
    <div
      v-if="candidates.length"
      class="my-3 rounded-xl border border-n-weak p-3"
    >
      <h3 class="font-semibold">{{ T.useExisting }}</h3>
      <article
        v-for="item in candidates"
        :key="item.id"
        class="flex items-center justify-between gap-3 border-b border-n-weak py-2 text-sm"
      >
        <div>
          {{ item.name }} #{{ item.id }}
          <p class="text-xs text-n-slate-10">
            {{ item.company_name }} {{ item.email }} {{ item.phone_number }}
          </p>
        </div>
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="link(item)"
        >
          {{ T.useExisting }}
        </button>
      </article>
    </div>
    <p
      v-if="busy"
      class="py-3"
      role="status"
    >
      {{ T.loading }}
    </p>
    <p
      v-if="!busy && !error && !contacts.length"
      class="py-6 text-n-slate-10"
    >
      {{ T.noResults }}
    </p>
    <div class="mt-4 divide-y divide-n-weak">
      <article
        v-for="item in contacts"
        :key="item.id"
        class="py-4"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <button
              type="button"
              class="font-semibold text-n-brand"
              @click="selection = item.id"
            >
              {{ item.name }}
            </button>
            <p class="text-sm text-n-slate-10">
              {{ item.job_title }} / {{ item.department }}
            </p>
            <p class="text-sm">{{ item.email }} {{ item.phone_number }}</p>
          </div>
          <div class="flex gap-2">
            <button
              type="button"
              :class="buttonClass"
              @click="detailId = detailId === item.id ? null : item.id"
            >
              {{ T.edit }}</button
            ><button
              type="button"
              :class="buttonClass"
              :disabled="busy"
              @click="detach(item)"
            >
              {{ T.detach }}
            </button>
          </div>
        </div>
        <MasterContactPanel
          v-if="detailId === item.id"
          :contact-id="item.id"
          @updated="changed"
        />
      </article>
    </div>
    <div class="mt-4 flex items-center gap-3">
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page <= 1"
        @click="page--"
      >
        {{ T.previous }}</button
      ><span>{{ page }} / {{ Math.max(1, Math.ceil(meta.total / 25)) }}</span
      ><button
        type="button"
        :class="buttonClass"
        :disabled="busy || page * 25 >= meta.total"
        @click="page++"
      >
        {{ T.next }}
      </button>
    </div>
    <ContactDetailsDialog
      v-if="selection"
      :key="identity"
      :contact-id="selection"
      @close="selection = null"
      @updated="changed"
    />
  </section>
</template>
