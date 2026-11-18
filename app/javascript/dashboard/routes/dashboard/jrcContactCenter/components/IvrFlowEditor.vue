<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import IvrReferencePicker from './IvrReferencePicker.vue';
import IvrFlowOverview from './IvrFlowOverview.vue';
import {
  addIvrNode,
  removeIvrNode,
  IVR_NODES_LIMIT,
} from '../helpers/ivrDraft';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  unitId: { type: [String, Number], required: true },
  modelValue: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const change = operation => {
  const graph = JSON.parse(JSON.stringify(props.modelValue));
  operation(graph);
  emit('update:modelValue', graph);
};
const set = (index, field, value) =>
  change(graph => {
    graph.nodes[index][field] = value;
  });
const option = (index, choice, field, value) =>
  change(graph => {
    graph.nodes[index].options[choice][field] = value;
  });
const nodeIcons = {
  menu: 'i-lucide-network',
  queue: 'i-lucide-layers',
  end: 'i-lucide-flag',
};
const typeLabel = type => t(`JRC_CONTACT_CENTER.LOCAL_IVR.TYPES.${type}`);
</script>

<template>
  <fieldset :disabled="disabled" class="min-w-0 space-y-4" data-ivr-flow-editor>
    <IvrFlowOverview :model-value="modelValue" />
    <label class="block text-sm text-n-slate-12" for="ivr-start">
      {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.START') }}
    </label>
    <select
      id="ivr-start"
      :value="modelValue.start"
      class="h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
      @change="
        change(graph => {
          graph.start = $event.target.value;
        })
      "
    >
      <option value="" disabled>
        {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.CHOOSE_NODE') }}
      </option>
      <option v-for="node in modelValue.nodes" :key="node.id" :value="node.id">
        {{ node.id }} · {{ typeLabel(node.type) }}
      </option>
    </select>
    <div class="flex flex-wrap gap-2">
      <button
        v-for="type in ['menu', 'queue', 'end']"
        :key="type"
        type="button"
        :disabled="modelValue.nodes.length >= IVR_NODES_LIMIT"
        class="rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11"
        :data-ivr-add="type"
        @click="change(graph => addIvrNode(graph, type))"
      >
        {{
          t('JRC_CONTACT_CENTER.LOCAL_IVR.ADD_NODE', { type: typeLabel(type) })
        }}
      </button>
    </div>
    <p v-if="!modelValue.nodes.length" class="text-sm text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.EMPTY_GRAPH') }}
    </p>
    <article
      v-for="(node, index) in modelValue.nodes"
      :key="node.id"
      class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-3"
      :data-ivr-node="node.id"
    >
      <header class="flex flex-wrap items-center justify-between gap-2">
        <h4
          class="flex items-center gap-2 break-all font-semibold text-n-slate-12"
        >
          <Icon
            :icon="nodeIcons[node.type]"
            class="size-4 shrink-0 text-n-blue-11"
          />
          {{ node.id }} · {{ typeLabel(node.type) }}
        </h4>
        <button
          type="button"
          class="rounded-lg border border-n-ruby-6 px-2 py-1 text-xs text-n-ruby-11"
          @click="change(graph => removeIvrNode(graph, node.id))"
        >
          {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.REMOVE_NODE') }}
        </button>
      </header>
      <template v-if="node.type === 'menu'">
        <div class="grid min-w-0 gap-3 sm:grid-cols-2">
          <label
            class="text-sm text-n-slate-12"
            :for="`ivr-timeout-${index}`"
            >{{ t('JRC_CONTACT_CENTER.LOCAL_IVR.TIMEOUT') }}</label
          >
          <input
            :id="`ivr-timeout-${index}`"
            :value="node.timeout_seconds"
            type="number"
            min="1"
            max="2147483647"
            class="h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
            @input="
              set(
                index,
                'timeout_seconds',
                $event.target.value === '' ? '' : Number($event.target.value)
              )
            "
          />
          <label
            class="text-sm text-n-slate-12"
            :for="`ivr-attempts-${index}`"
            >{{ t('JRC_CONTACT_CENTER.LOCAL_IVR.ATTEMPTS') }}</label
          >
          <input
            :id="`ivr-attempts-${index}`"
            :value="node.max_attempts"
            type="number"
            min="1"
            max="128"
            class="h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-n-slate-12"
            @input="
              set(
                index,
                'max_attempts',
                $event.target.value === '' ? '' : Number($event.target.value)
              )
            "
          />
        </div>
        <div
          v-for="(choice, choiceIndex) in node.options"
          :key="choiceIndex"
          class="grid min-w-0 gap-2 rounded-lg border border-n-weak p-2 sm:grid-cols-3"
        >
          <div class="min-w-0">
            <label
              class="text-sm text-n-slate-12"
              :for="`ivr-digit-${index}-${choiceIndex}`"
            >
              {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.DIGIT') }}
            </label>
            <select
              :id="`ivr-digit-${index}-${choiceIndex}`"
              :value="choice.digit"
              class="mt-1 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2"
              @change="option(index, choiceIndex, 'digit', $event.target.value)"
            >
              <option value="" disabled>
                {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.CHOOSE_DIGIT') }}
              </option>
              <option
                v-for="digit in '0123456789*#'"
                :key="digit"
                :value="digit"
              >
                {{ digit }}
              </option>
            </select>
          </div>
          <div class="min-w-0">
            <label
              class="text-sm text-n-slate-12"
              :for="`ivr-target-${index}-${choiceIndex}`"
            >
              {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.DESTINATION') }}
            </label>
            <select
              :id="`ivr-target-${index}-${choiceIndex}`"
              :value="choice.target"
              class="mt-1 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2"
              @change="
                option(index, choiceIndex, 'target', $event.target.value)
              "
            >
              <option value="" disabled>
                {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.CHOOSE_NODE') }}
              </option>
              <option
                v-for="target in modelValue.nodes"
                :key="target.id"
                :value="target.id"
              >
                {{ target.id }}
              </option>
            </select>
          </div>
          <button
            type="button"
            class="self-end rounded-lg border border-n-weak px-2 py-2 text-xs text-n-ruby-11"
            @click="
              change(graph => {
                graph.nodes[index].options.splice(choiceIndex, 1);
              })
            "
          >
            {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.REMOVE_OPTION') }}
          </button>
        </div>
        <button
          type="button"
          :disabled="node.options.length >= 12"
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
          @click="
            change(graph => {
              graph.nodes[index].options.push({ digit: '', target: '' });
            })
          "
        >
          {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.ADD_OPTION') }}
        </button>
        <div
          v-for="field in ['on_timeout', 'on_invalid']"
          :key="field"
          class="min-w-0"
        >
          <label
            class="mb-1 block text-sm text-n-slate-12"
            :for="`ivr-${field}-${index}`"
          >
            {{ t(`JRC_CONTACT_CENTER.LOCAL_IVR.${field.toUpperCase()}`) }}
          </label>
          <select
            :id="`ivr-${field}-${index}`"
            :value="node[field]"
            class="mt-1 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2"
            @change="set(index, field, $event.target.value)"
          >
            <option value="" disabled>
              {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.CHOOSE_NODE') }}
            </option>
            <option
              v-for="target in modelValue.nodes"
              :key="target.id"
              :value="target.id"
            >
              {{ target.id }}
            </option>
          </select>
        </div>
      </template>
      <template v-else-if="node.type === 'queue'">
        <label
          class="block text-sm text-n-slate-12"
          :for="`ivr-queue-${index}`"
          >{{ t('JRC_CONTACT_CENTER.ADMIN.QUEUE') }}</label
        >
        <IvrReferencePicker
          :account-id="accountId"
          resource="queues"
          :unit-id="unitId"
          :input-id="`ivr-queue-${index}`"
          :model-value="node.queue_id"
          :disabled="disabled"
          @update:model-value="set(index, 'queue_id', $event)"
        />
      </template>
      <p v-else class="text-sm text-n-slate-11">
        {{ t('JRC_CONTACT_CENTER.LOCAL_IVR.END_HINT') }}
      </p>
    </article>
  </fieldset>
</template>
