<script setup>
import { ref, watch } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useBackofficePresentation } from './useBackofficePresentation';
import { useContractVersions } from './useContractVersions';
import ContractVersionDetails from './ContractVersionDetails.vue';
import ContractDraftEditor from './ContractDraftEditor.vue';

const props = defineProps({ record: { type: Object, required: true } });
const { text, date } = useBackofficePresentation();
const {
  accountId,
  identity,
  result,
  reason,
  loading,
  saving,
  busy,
  error,
  notice,
  canGenerate,
  canSave,
  page,
  pages,
  load,
  generate,
  download,
  changePage,
  deny,
} = useContractVersions(props);
const dialog = ref(null);
const selected = ref(null);
const editing = ref(false);
const mode = ref('pdf');
const view = (version, selection) => {
  selected.value = version;
  mode.value = selection;
};
const save = async () => {
  if (await generate()) dialog.value.close();
};
const draftSaved = async () => {
  editing.value = false;
  if (await load()) notice.value = text('CONTRACT_VERSIONS.DRAFT_SAVED');
};
watch(identity, () => {
  selected.value = null;
  editing.value = false;
  dialog.value?.close();
});
</script>

<template>
  <section
    class="space-y-4"
    :aria-busy="busy"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-blue-6 bg-n-blue-3 p-4"
    >
      <div>
        <h3 class="font-bold text-n-blue-12">
          {{ text('CONTRACT_VERSIONS.TITLE') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-11">
          {{
            result?.contract?.number || text('CONTRACT_VERSIONS.NO_CONTRACT')
          }}
        </p>
      </div>
      <div class="flex gap-2">
        <button
          type="button"
          class="rounded-lg border border-n-blue-6 bg-n-solid-2 px-3 py-2 text-sm text-n-blue-12 disabled:opacity-50"
          :disabled="!canGenerate"
          @click="editing = true"
        >
          {{ text('CONTRACT_VERSIONS.EDIT_DRAFT') }}
        </button>
        <button
          type="button"
          class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm disabled:opacity-50"
          :disabled="busy"
          @click="load"
        >
          {{ text('REFRESH') }}
        </button>
        <button
          type="button"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
          :disabled="!canGenerate"
          @click="dialog.open()"
        >
          {{ text('CONTRACT_VERSIONS.GENERATE') }}
        </button>
      </div>
    </header>
    <p
      v-if="loading"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ text('CONTRACT_VERSIONS.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
    >
      {{ error }}
    </p>
    <p
      v-if="notice"
      role="status"
      class="rounded-lg border border-n-teal-6 bg-n-teal-3 p-3 text-sm text-n-teal-12"
    >
      {{ notice }}
    </p>
    <p
      class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
    >
      {{ text('CONTRACT_VERSIONS.SIGNATURE_NOTE') }}
    </p>
    <template v-if="result">
      <p
        v-if="!canGenerate && !busy"
        class="text-sm text-n-slate-11"
      >
        {{ text('CONTRACT_VERSIONS.LOCKED') }}
      </p>
      <div
        v-if="result.data.length"
        class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-2"
      >
        <table class="w-full text-left text-sm">
          <thead class="bg-n-slate-3 text-n-slate-11">
            <tr>
              <th class="p-3">{{ text('CONTRACT_VERSIONS.VERSION') }}</th>
              <th class="p-3">{{ text('CONTRACT_VERSIONS.CREATED_AT') }}</th>
              <th class="p-3">{{ text('CONTRACT_VERSIONS.AUTHOR') }}</th>
              <th class="p-3">{{ text('CONTRACT_VERSIONS.REASON') }}</th>
              <th class="p-3">{{ text('CONTRACT_VERSIONS.ACTIONS') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="version in result.data"
              :key="version.id"
              class="border-t border-n-weak"
            >
              <td class="p-3 font-semibold">
                {{ text('CONTRACT_VERSIONS.VERSION') }} {{ version.number }}
                <span
                  v-if="version.current"
                  class="rounded-full bg-n-teal-3 px-2 py-1 text-xs text-n-teal-12"
                >
                  {{ text('CONTRACT_VERSIONS.CURRENT') }}
                </span>
              </td>
              <td class="p-3">{{ date(version.created_at) }}</td>
              <td class="p-3">{{ version.created_by_name }}</td>
              <td class="max-w-xs whitespace-pre-wrap p-3">
                {{ version.change_reason }}
              </td>
              <td class="p-3">
                <div class="flex flex-wrap gap-2">
                  <button
                    type="button"
                    class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-2 py-1 text-n-blue-12"
                    @click="view(version, 'pdf')"
                  >
                    {{ text('CONTRACT_VERSIONS.VIEW') }}
                  </button>
                  <button
                    type="button"
                    class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-2 py-1 text-n-blue-12"
                    @click="download(version)"
                  >
                    {{ text('CONTRACT_VERSIONS.DOWNLOAD') }}
                  </button>
                  <button
                    type="button"
                    class="rounded-lg border border-n-violet-6 bg-n-violet-3 px-2 py-1 text-n-violet-12"
                    @click="view(version, 'differences')"
                  >
                    {{ text('CONTRACT_VERSIONS.DIFFERENCES') }}
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p
        v-else
        class="rounded-xl border border-dashed border-n-weak p-5 text-sm text-n-slate-11"
      >
        {{ text('CONTRACT_VERSIONS.EMPTY') }}
      </p>
      <nav
        v-if="pages > 1"
        class="flex items-center justify-end gap-3"
        :aria-label="text('CONTRACT_VERSIONS.PAGINATION')"
      >
        <button
          type="button"
          :disabled="busy || page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          @click="changePage(page - 1)"
        >
          {{ text('CONTRACT_VERSIONS.PREVIOUS') }}
        </button>
        <span class="text-sm">
          {{ page }} {{ text('CONTRACT_VERSIONS.OF') }} {{ pages }}
        </span>
        <button
          type="button"
          :disabled="busy || page >= pages"
          class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
          @click="changePage(page + 1)"
        >
          {{ text('CONTRACT_VERSIONS.NEXT') }}
        </button>
      </nav>
    </template>
    <Dialog
      ref="dialog"
      :title="text('CONTRACT_VERSIONS.GENERATE')"
      :show-confirm-button="false"
      :show-cancel-button="false"
      :use-form="false"
      show-close-button
      contained
      :dismissible="!saving"
    >
      <form
        class="space-y-4"
        @submit.prevent="save"
      >
        <p class="text-sm text-n-slate-11">
          {{ text('CONTRACT_VERSIONS.IMMUTABLE_NOTE') }}
        </p>
        <label class="block text-sm font-semibold">
          {{ text('CONTRACT_VERSIONS.REASON') }}
          <textarea
            v-model="reason"
            required
            maxlength="2000"
            :disabled="busy"
            class="mt-2 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3 text-n-slate-12"
          />
        </label>
        <p
          v-if="error"
          role="alert"
          class="text-sm text-n-ruby-12"
        >
          {{ error }}
        </p>
        <button
          type="button"
          :disabled="busy"
          class="mr-2 rounded-lg border border-n-weak px-4 py-2 disabled:opacity-50"
          @click="load"
        >
          {{ text('REFRESH') }}
        </button>
        <button
          type="submit"
          :disabled="!canSave"
          class="rounded-lg bg-n-blue-9 px-4 py-2 font-semibold text-white disabled:opacity-50"
        >
          {{ text('CONTRACT_VERSIONS.GENERATE') }}
        </button>
      </form>
    </Dialog>
    <ContractVersionDetails
      v-if="selected"
      :key="`${identity}:${selected.id}:${mode}`"
      :account-id="accountId"
      :request-id="record.id"
      :version="selected"
      :mode="mode"
      @close="selected = null"
      @denied="
        deny();
        selected = null;
      "
    />
    <ContractDraftEditor
      v-if="editing"
      :key="identity"
      :account-id="accountId"
      :request-id="record.id"
      @close="editing = false"
      @saved="draftSaved"
      @denied="
        deny();
        editing = false;
      "
    />
  </section>
</template>
