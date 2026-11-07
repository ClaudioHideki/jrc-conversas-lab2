<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, ref, onMounted, onBeforeUnmount, watch } from 'vue';
import { useRoute, RouterLink } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass, date, message } from './definitions';
const props = defineProps({
  analystId: { type: Number, required: true },
  formatting: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['close', 'changed']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const result = ref(null);
const selected = ref(null);
const reason = ref('');
const draftFor = ref(null);
const busy = ref(false);
const error = ref('');
const notice = ref('');
const page = ref(1);
const pages = computed(() =>
  Math.max(1, Math.ceil((result.value?.meta.total || 0) / 10))
);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.analystId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
  ])
);
let generation = 0;
let controller;
const clear = (draft = true) => {
  generation += 1;
  controller?.abort();
  result.value = null;
  selected.value = null;
  busy.value = false;
  if (draft) {
    reason.value = '';
    draftFor.value = null;
  }
};
const load = async (target = 1) => {
  clear(false);
  const token = generation;
  controller = new AbortController();
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.analystCadences(
      route.params.accountId,
      props.analystId,
      { page: target },
      { signal: controller.signal }
    );
    if (token !== generation) return;
    const lastPage = Math.max(1, Math.ceil(data.meta.total / 10));
    if (data.meta.page > lastPage) {
      await load(lastPage);
      return;
    }
    result.value = data;
    page.value = data.meta.page;
  } catch (err) {
    if (token !== generation) return;
    clear();
    error.value = message(err);
  } finally {
    if (token === generation) busy.value = false;
  }
};
const review = row => {
  if (draftFor.value !== row.id) reason.value = '';
  draftFor.value = row.id;
  selected.value = row;
  notice.value = '';
};
const stop = async () => {
  if (
    busy.value ||
    !selected.value ||
    !reason.value.trim() ||
    reason.value.length > 4000
  )
    return;
  const row = selected.value;
  const token = generation;
  const sourceIdentity = identity.value;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.stopAnalystCadence(
      route.params.accountId,
      props.analystId,
      row.id,
      { expected_revision: row.revision, reason: reason.value }
    );
    if (token !== generation) return;
    if (data.state !== 'stopped')
      throw new Error(t('RELATIONSHIP.CADENCE_TEAM.UNCONFIRMED'));
    reason.value = '';
    draftFor.value = null;
    await load(page.value);
    if (sourceIdentity !== identity.value) return;
    notice.value = t('RELATIONSHIP.CADENCE_TEAM.STOPPED');
    emit('changed');
  } catch (err) {
    if (token !== generation) return;
    if ([403, 404].includes(err.response?.status)) clear();
    if (err.response?.status === 409) await load(page.value);
    if (sourceIdentity !== identity.value) return;
    error.value = message(err);
  } finally {
    busy.value = false;
  }
};
watch(identity, () => {
  clear();
  emit('close');
});
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(clear);
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('RELATIONSHIP.CADENCE_TEAM.TITLE')"
    :description="t('RELATIONSHIP.CADENCE_TEAM.NOTICE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :dismissible="!busy"
    show-close-button
    width="2xl"
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-3">
      <p
        v-if="busy"
        role="status"
      >
        {{ t('RELATIONSHIP.LOADING') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p
        v-if="notice"
        role="status"
        class="text-n-teal-11"
      >
        {{ notice }}
      </p>
      <h3
        v-if="result"
        class="break-words font-semibold"
      >
        {{ result.analyst.name }}
      </h3>
      <form
        v-if="selected"
        data-testid="cadence-team-stop"
        class="min-w-0 space-y-3 rounded-lg border border-n-amber-6 bg-n-amber-2 p-3"
        @submit.prevent="stop"
      >
        <h4 class="break-words font-semibold">{{ selected.customer_name }}</h4>
        <p>
          {{
            t('RELATIONSHIP.CADENCE_TEAM.CONFIRM', {
              count: selected.pending_steps,
            })
          }}
        </p>
        <label class="block text-sm">
          <span class="block">{{ t('RELATIONSHIP.FIELDS.reason') }}</span>
          <textarea
            v-model="reason"
            data-testid="cadence-team-reason"
            :class="inputClass"
            maxlength="4000"
            rows="3"
            required
          />
        </label>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="selected = null"
          >
            {{ t('RELATIONSHIP.CADENCE_TEAM.BACK') }}
          </button>
          <button
            type="submit"
            data-testid="cadence-team-confirm"
            :class="buttonClass"
            class="border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11"
            :disabled="busy || !reason.trim()"
          >
            {{ t('RELATIONSHIP.CADENCE_TEAM.STOP') }}
          </button>
        </div>
      </form>
      <section
        v-else-if="result"
        class="min-w-0 space-y-2"
      >
        <p v-if="!result.payload.length">{{ t('RELATIONSHIP.EMPTY') }}</p>
        <article
          v-for="row in result.payload"
          :key="row.id"
          data-testid="cadence-team-row"
          class="min-w-0 space-y-2 rounded-lg border border-n-weak p-3"
        >
          <RouterLink
            :to="{
              ...row.customer_360,
              params: {
                ...row.customer_360.params,
                accountId: route.params.accountId,
              },
            }"
            class="block break-words text-n-blue-11 underline"
          >
            {{ row.customer_name }}
          </RouterLink>
          <p class="text-sm">
            {{
              t('RELATIONSHIP.CADENCE_TEAM.PENDING', {
                count: row.pending_steps,
                revision: row.revision,
              })
            }}
          </p>
          <p
            v-if="row.responsibility"
            class="text-sm text-n-slate-11"
          >
            {{
              t(`RELATIONSHIP.CADENCE_TEAM.DEPENDENCIES.${row.responsibility}`)
            }}
          </p>
          <p
            v-if="row.next_due_at"
            class="text-sm"
          >
            {{ date(row.next_due_at, formatting) }}
          </p>
          <button
            v-if="result.can_stop"
            type="button"
            data-testid="cadence-team-review"
            :class="buttonClass"
            :disabled="busy"
            @click="review(row)"
          >
            {{ t('RELATIONSHIP.CADENCE_TEAM.REVIEW') }}
          </button>
        </article>
        <div
          v-if="pages > 1"
          class="flex flex-wrap items-center gap-2"
        >
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy || page === 1"
            data-testid="cadence-team-previous"
            @click="load(page - 1)"
          >
            {{ t('RELATIONSHIP.RESPONSIBILITIES.PREVIOUS') }}
          </button>
          <span>{{
            t('RELATIONSHIP.RESPONSIBILITIES.PAGE', { page, pages })
          }}</span>
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy || page >= pages"
            data-testid="cadence-team-next"
            @click="load(page + 1)"
          >
            {{ t('RELATIONSHIP.RESPONSIBILITIES.NEXT') }}
          </button>
        </div>
      </section>
    </div>
  </Dialog>
</template>
