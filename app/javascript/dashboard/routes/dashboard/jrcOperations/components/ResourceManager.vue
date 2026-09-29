<script setup>
import { ref, reactive, computed, watch } from 'vue';
import { useProjects } from '../../jrcProjects/useProjects';
import { request, errorMessage, formatDate } from '../api';
import OpsModal from './OpsModal.vue';
import ContactPicker from './ContactPicker.vue';
const props = defineProps({
  schema: { type: Object, required: true },
  endpoint: { type: String, required: true },
  canEdit: { type: Boolean, default: true },
  payloadKey: { type: String, default: 'record' },
  extraOptions: { type: Object, default: () => ({}) },
  ownerId: { type: Number, default: null },
});
const emit = defineEmits(['changed']);
const { accountId, projectText } = useProjects();
const rows = ref([]);
const options = ref({});
const page = ref(1);
const total = ref(0);
const loading = ref(false);
const error = ref('');
const modal = ref(false);
const editing = ref(null);
const busy = ref(false);
const form = reactive({});
const week = reactive({});
const approvalReason = ref('');
const days = [
  'Domingo',
  'Segunda',
  'Terca',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sabado',
];
const visibleFields = computed(() =>
  props.schema.fields
    .filter(
      f =>
        ![
          'textarea',
          'tasks',
          'schedule',
          'lines',
          'number-lines',
          'multiselect',
          'contact',
          'json',
        ].includes(f.type)
    )
    .slice(0, 5)
);
const locked = record =>
  record?.role === 'owner' ||
  (props.schema.key === 'members' && record?.user_id === props.ownerId);
let generation = 0;
async function load() {
  const n = ++generation;
  loading.value = true;
  error.value = '';
  try {
    const [list, selectors] = await Promise.all([
      request(accountId.value, props.endpoint, {
        params: { page: page.value, per_page: 25 },
      }),
      request(accountId.value, 'operations/options'),
    ]);
    if (n === generation) {
      rows.value = list.data;
      total.value = list.meta?.total || rows.value.length;
      options.value = selectors.data;
    }
  } catch (err) {
    if (n === generation) error.value = errorMessage(err);
  } finally {
    if (n === generation) loading.value = false;
  }
}
watch(
  () => [props.endpoint, accountId.value],
  () => {
    page.value = 1;
    modal.value = false;
    rows.value = [];
    load();
  },
  { immediate: true }
);
function choices(field) {
  return field.type === 'option'
    ? (
        props.extraOptions[field.source] ||
        options.value[field.source] ||
        []
      ).map(x => ({ value: x.id, label: x.name }))
    : Object.entries(field.choices || {}).map(([value, label]) => ({
        value,
        label,
      }));
}
function open(record = null) {
  error.value = '';
  approvalReason.value = '';
  editing.value = record;
  for (const key of Object.keys(form)) delete form[key];
  for (const field of props.schema.fields) {
    let value =
      record?.[field.key] ??
      field.default ??
      (field.type === 'checkbox'
        ? false
        : field.type === 'select' && field.required
          ? Object.keys(field.choices)[0]
          : '');
    if (field.type === 'lines')
      value = Array.isArray(value) ? value.join('\n') : '';
    if (field.type === 'number-lines')
      value = Array.isArray(value) ? value.join('\n') : '';
    if (field.type === 'multiselect') value = Array.isArray(value) ? value : [];
    if (field.type === 'datetime-local' && value) {
      const date = new Date(value);
      if (!Number.isNaN(date.getTime())) {
        const offset = date.getTimezoneOffset() * 60000;
        value = new Date(date.getTime() - offset).toISOString().slice(0, 16);
      }
    }
    if (field.type === 'json') value = JSON.stringify(value || {}, null, 2);
    if (field.type === 'tasks')
      value = (value.tasks || []).map(x => x.title).join('\n');
    if (field.type === 'schedule')
      for (let day = 0; day < 7; day += 1)
        week[day] = (value?.[day] || [])
          .map(x => `${x.from}-${x.to}`)
          .join(', ');
    form[field.key] = value;
  }
  modal.value = true;
}
function payload() {
  const record = {};
  for (const field of props.schema.fields) {
    let value = form[field.key];
    if (
      field.type === 'option' ||
      field.type === 'contact' ||
      field.type === 'date'
    )
      value = value || null;
    if (field.type === 'number') value = value === '' ? null : Number(value);
    if (field.type === 'lines')
      value = value
        .split('\n')
        .map(x => x.trim())
        .filter(Boolean);
    if (field.type === 'number-lines')
      value = value
        .split('\n')
        .map(x => x.trim())
        .filter(Boolean)
        .map(x => Number(x));
    if (field.type === 'multiselect') value = Array.isArray(value) ? value : [];
    if (field.type === 'json') {
      try {
        value = JSON.parse(value || '{}');
      } catch {
        throw new Error(`${field.label}: JSON invalido.`);
      }
    }
    if (field.type === 'tasks') {
      const previous = editing.value?.definition || {};
      value = {
        ...previous,
        tasks: value
          .split('\n')
          .map(x => x.trim())
          .filter(Boolean)
          .map(title => ({
            ...(previous.tasks || []).find(x => x.title === title),
            title,
          })),
      };
    }
    if (field.type === 'schedule') {
      value = {};
      for (let day = 0; day < 7; day += 1) {
        value[day] = week[day].trim()
          ? week[day].split(',').map(interval => {
              const match = interval
                .trim()
                .match(/^(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})$/);
              if (!match)
                throw new Error(
                  `Horario de ${days[day]} invalido. Use 09:00-12:00, 13:00-18:00.`
                );
              return { from: match[1], to: match[2] };
            })
          : [];
      }
    }
    record[field.key] = value;
  }
  if (
    props.schema.key === 'changes' &&
    ['approved', 'rejected'].includes(record.status) &&
    record.status !== editing.value?.status
  )
    throw new Error('Use a decisao de aprovacao abaixo.');
  return record;
}
async function save() {
  if (busy.value || !props.canEdit || locked(editing.value)) return;
  busy.value = true;
  error.value = '';
  try {
    await request(
      accountId.value,
      editing.value ? `${props.endpoint}/${editing.value.id}` : props.endpoint,
      {
        method: editing.value ? 'patch' : 'post',
        data: { [props.payloadKey]: payload() },
      }
    );
    modal.value = false;
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function remove(record) {
  if (busy.value || !props.canEdit || locked(record)) return;
  if (
    !window.confirm(
      'Excluir este registro? Registros em uso podem impedir a exclusao.'
    )
  )
    return;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${props.endpoint}/${record.id}`, {
      method: 'delete',
    });
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function complete(record) {
  if (
    busy.value ||
    !props.canEdit ||
    props.schema.key !== 'milestones' ||
    record.status !== 'open'
  )
    return;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${props.endpoint}/${record.id}`, {
      method: 'patch',
      data: { [props.payloadKey]: { status: 'completed' } },
    });
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function approve(decision) {
  if (
    !approvalReason.value.trim() ||
    !window.confirm('Registrar esta decisao de mudanca?')
  )
    return;
  busy.value = true;
  try {
    await request(
      accountId.value,
      `${props.endpoint}/${editing.value.id}/approvals`,
      { method: 'post', data: { decision, reason: approvalReason.value } }
    );
    modal.value = false;
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
function display(record, field) {
  const value = record[field.key];
  if (field.type === 'checkbox') return value ? 'Sim' : 'Nao';
  if (['select', 'option'].includes(field.type))
    return (
      choices(field).find(x => String(x.value) === String(value))?.label ||
      (value === 'owner' ? 'Proprietario' : value || '-')
    );
  return ['date', 'datetime-local'].includes(field.type)
    ? formatDate(value)
    : value || '-';
}
function navigatePage(delta) {
  page.value += delta;
  load();
}
</script>

<template>
  <section class="flex flex-col gap-4">
    <header class="flex flex-wrap items-center gap-3 justify-between">
      <div>
        <h3>{{ schema.title }}</h3>
        <p v-if="schema.help" class="text-n-slate-11 text-sm">
          {{ schema.help }}
        </p>
      </div>
      <button
        v-if="canEdit"
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 bg-n-blue-9 text-white"
        :disabled="busy"
        @click="open()"
      >
        Adicionar
      </button>
    </header>
    <div
      v-if="error && !modal"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
      role="alert"
    >
      {{ error }}
    </div>
    <p v-if="loading" class="text-n-slate-11 text-sm" role="status">
      Carregando...
    </p>
    <div v-if="rows.length" class="overflow-x-auto">
      <table
        class="w-full text-sm text-left [&_th]:p-3 [&_td]:p-3 [&_td]:border-t [&_td]:border-n-weak"
      >
        <thead>
          <tr>
            <th v-for="field in visibleFields" :key="field.key">
              {{ field.label }}
            </th>
            <th>Acoes</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="record in rows" :key="record.id">
            <td v-for="field in visibleFields" :key="field.key">
              {{ display(record, field) }}
            </td>
            <td>
              <button
                class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
                @click="open(record)"
              >
                {{ canEdit && !locked(record) ? 'Editar' : 'Consultar' }}
              </button>
              <button
                v-if="canEdit && !locked(record)"
                class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs text-n-ruby-11"
                :disabled="busy"
                @click="remove(record)"
              >
                Excluir
              </button>
              <button
                v-if="
                  canEdit &&
                  schema.key === 'milestones' &&
                  record.status === 'open'
                "
                class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
                :disabled="busy"
                @click="complete(record)"
              >
                {{ projectText('COMPLETE_MILESTONE', 'Concluir marco') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-else-if="!loading" class="p-6 text-center text-n-slate-11">
      Nenhum registro.
    </p>
    <footer v-if="total > 25" class="flex justify-end items-center gap-3 pt-4">
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
        :disabled="page <= 1 || loading"
        @click="navigatePage(-1)"
      >
        Anterior</button><span>{{ page }} · {{ total }} registros</span><button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
        :disabled="page * 25 >= total || loading"
        @click="navigatePage(1)"
      >
        Proxima
      </button>
    </footer>
    <OpsModal
      v-if="modal"
      :title="`${editing ? 'Registro' : 'Adicionar'} · ${schema.title}`"
      :busy="busy"
      wide
      @close="modal = false"
    >
      <form class="flex flex-col gap-4" @submit.prevent="save">
        <div
          v-if="error"
          class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
          role="alert"
        >
          {{ error }}
        </div>
        <fieldset
          class="grid grid-cols-1 md:grid-cols-2 gap-4"
          :disabled="!canEdit || busy || locked(editing)"
        >
          <template v-for="field in schema.fields" :key="field.key">
            <ContactPicker
              v-if="field.type === 'contact'"
              v-model="form[field.key]"
            />
            <div
              v-else-if="field.type === 'schedule'"
              class="flex flex-col gap-1 min-w-0 col-span-full"
            >
              <span>{{ field.label }}</span><small>Deixe vazio para folga. Separe os turnos por virgula:
                09:00-12:00, 13:00-18:00.</small><label
                v-for="(day, index) in days"
                :key="index"
                class="flex flex-wrap items-center gap-3"
                ><span class="w-20">{{ day }}</span><input
                  v-model="week[index]"
                  class="flex-1"
                  :aria-label="`Expediente de ${day}`"
                  placeholder="Sem expediente"
              /></label>
            </div>
            <label
              v-else-if="field.type === 'checkbox'"
              class="flex gap-2 items-center"
              ><input v-model="form[field.key]" type="checkbox" />{{
                field.label
              }}</label>
            <label
              v-else
              class="flex flex-col gap-1 min-w-0"
              :class="{
                'col-span-full': [
                  'textarea',
                  'lines',
                  'number-lines',
                  'tasks',
                  'json',
                  'multiselect',
                ].includes(field.type),
              }"
              ><span>{{ field.label }}{{ field.required ? ' *' : '' }}</span><textarea
                v-if="
                  [
                    'textarea',
                    'lines',
                    'number-lines',
                    'tasks',
                    'json',
                  ].includes(field.type)
                "
                v-model="form[field.key]"
                :required="field.required"
                rows="4" /><select
                v-else-if="field.type === 'multiselect'"
                v-model="form[field.key]"
                multiple
              >
                <option
                  v-for="choice in choices(field)"
                  :key="choice.value"
                  :value="choice.value"
                >
                  {{ choice.label }}
                </option></select><select
                v-else-if="['select', 'option'].includes(field.type)"
                v-model="form[field.key]"
                :required="field.required"
                :disabled="Boolean(editing && field.readOnlyOnEdit)"
              >
                <option value="">Selecionar</option>
                <option
                  v-for="choice in choices(field)"
                  :key="choice.value"
                  :value="choice.value"
                >
                  {{ choice.label }}
                </option></select><input
                v-else
                v-model="form[field.key]"
                :type="field.type"
                :required="field.required"
                :min="field.min"
                :max="field.max"
                :step="field.type === 'number' ? 1 : undefined"
            /></label>
          </template>
        </fieldset>
        <footer class="flex justify-end gap-3 mt-4">
          <button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            type="button"
            :disabled="busy"
            @click="modal = false"
          >
            Fechar</button><button
            v-if="canEdit && !locked(editing)"
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 bg-n-blue-9 text-white"
            :disabled="busy"
          >
            Salvar
          </button>
        </footer>
      </form>
      <section
        v-if="schema.key === 'changes' && editing && canEdit"
        class="flex flex-col gap-4"
      >
        <h3>Decisao de aprovacao</h3>
        <label class="flex flex-col gap-1 min-w-0"><span>Justificativa</span><textarea v-model="approvalReason" />
        </label>
        <div class="flex flex-wrap items-center gap-3">
          <button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            :disabled="busy || !approvalReason.trim()"
            @click="approve('approved')"
          >
            Aprovar</button><button
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 danger"
            :disabled="busy || !approvalReason.trim()"
            @click="approve('rejected')"
          >
            Rejeitar
          </button>
        </div>
      </section>
    </OpsModal>
  </section>
</template>
