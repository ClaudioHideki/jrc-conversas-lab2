<script setup>
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, inputClass } from './definitions';
import {
  localRoleDraft,
  validateLocalRoleDraft,
  addLocalRoleMember,
  LOCAL_ROLES,
  LOCAL_SCOPES,
  editableRoleActions,
  editableRoleGrants,
} from './localRoleDraft';
const props = defineProps({
  modelValue: { type: Object, default: null },
  scopeKey: { type: String, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'validity']);
const { t } = useI18n();
const route = useRoute();
const store = useStore();
const draft = ref(localRoleDraft(props.modelValue));
const editingRole = ref('analyst');
const memberID = ref(null);
const role = ref('analyst');
const users = ref([]);
const page = ref(1);
const total = ref(0);
const query = ref('');
const loading = ref(false);
const failed = ref(false);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.scopeKey,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess),
  ])
);
let generation = 0;
let controller;
const valid = computed(() => validateLocalRoleDraft(draft.value));
const publish = () => {
  emit('validity', valid.value);
  emit('update:modelValue', JSON.parse(JSON.stringify(draft.value)));
};
watch(
  () => props.modelValue,
  value => {
    draft.value = localRoleDraft(value);
    emit('validity', validateLocalRoleDraft(value));
  },
  { deep: true }
);
const options = async () => {
  generation += 1;
  const token = generation;
  const access = identity.value;
  controller?.abort();
  controller = new AbortController();
  users.value = [];
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await API.localRoleOptions(
      route.params.accountId,
      { scope_key: props.scopeKey, page: page.value, q: query.value },
      { signal: controller.signal }
    );
    if (token !== generation || access !== identity.value) return;
    users.value = data.payload;
    total.value = data.meta.total;
  } catch {
    if (token === generation && access === identity.value) failed.value = true;
  } finally {
    if (token === generation && access === identity.value)
      loading.value = false;
  }
};
watch(
  identity,
  (_value, previous) => {
    if (previous) {
      draft.value = localRoleDraft(null);
      emit('validity', false);
    }
    generation += 1;
    controller?.abort();
    users.value = [];
    memberID.value = null;
    page.value = 1;
    query.value = '';
    options();
  },
  { immediate: true }
);
const add = () => {
  if (props.disabled || !memberID.value || loading.value) return;
  draft.value = addLocalRoleMember(
    draft.value,
    Number(memberID.value),
    role.value
  );
  memberID.value = null;
  publish();
};
const remove = id => {
  if (props.disabled) return;
  draft.value.members = draft.value.members.filter(
    member => member.user_id !== id
  );
  publish();
};
const move = delta => {
  page.value += delta;
  memberID.value = null;
  options();
};
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <fieldset
    class="my-4 space-y-4 rounded border p-4"
    :disabled="disabled"
  >
    <legend class="font-semibold">
      {{ t('RELATIONSHIP.LOCAL_ROLES.TITLE') }}
    </legend>
    <p class="text-sm">{{ t('RELATIONSHIP.LOCAL_ROLES.HELP') }}</p>
    <label
      ><input
        v-model="draft.enabled"
        type="checkbox"
        @change="publish"
      />
      {{ t('RELATIONSHIP.LOCAL_ROLES.ENABLED') }}</label
    >
    <details>
      <summary>{{ t('RELATIONSHIP.LOCAL_ROLES.ROLE_SETTINGS') }}</summary>
      <label
        >{{ t('RELATIONSHIP.LOCAL_ROLES.ROLE')
        }}<select
          v-model="editingRole"
          :class="inputClass"
        >
          <option
            v-for="key in LOCAL_ROLES"
            :key="key"
            :value="key"
          >
            {{ t(`RELATIONSHIP.LOCAL_ROLES.ROLES.${key}`) }}
          </option>
        </select></label
      >
      <label
        >{{ t('RELATIONSHIP.LOCAL_ROLES.SCOPE')
        }}<select
          v-model="draft.roles[editingRole].scope"
          :class="inputClass"
          @change="publish"
        >
          <option
            v-for="key in LOCAL_SCOPES"
            :key="key"
            :value="key"
          >
            {{ t(`RELATIONSHIP.LOCAL_ROLES.SCOPES.${key}`) }}
          </option>
        </select></label
      >
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label
          v-for="action in editableRoleActions(
            editingRole,
            draft.roles[editingRole].actions
          )"
          :key="action"
          ><input
            v-model="draft.roles[editingRole].actions"
            :value="action"
            type="checkbox"
            @change="publish"
          />
          {{ t(`RELATIONSHIP.LOCAL_ROLES.ACTIONS.${action}`) }}</label
        >
      </div>
    </details>
    <div class="space-y-2">
      <label
        >{{ t('RELATIONSHIP.LOCAL_ROLES.SEARCH')
        }}<input
          v-model="query"
          :class="inputClass"
          @keydown.enter.prevent="
            page = 1;
            options();
          " /></label
      ><button
        type="button"
        :class="buttonClass"
        @click="
          page = 1;
          options();
        "
      >
        {{ t('RELATIONSHIP.LOCAL_ROLES.SEARCH') }}
      </button>
      <p
        v-if="failed"
        role="alert"
      >
        {{ t('RELATIONSHIP.LOCAL_ROLES.OPTIONS_FAILED') }}
      </p>
      <label
        >{{ t('RELATIONSHIP.LOCAL_ROLES.USER')
        }}<select
          v-model.number="memberID"
          data-testid="local-role-member"
          :class="inputClass"
          :disabled="loading || failed"
        >
          <option :value="null">
            {{ t('RELATIONSHIP.LOCAL_ROLES.CHOOSE') }}
          </option>
          <option
            v-for="user in users"
            :key="user.id"
            :value="user.id"
            :disabled="
              !user.active ||
              draft.members.some(member => member.user_id === user.id)
            "
          >
            {{ user.name }}
          </option>
        </select></label
      >
      <div class="flex gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="page <= 1 || loading"
          @click="move(-1)"
        >
          {{ t('RELATIONSHIP.LOCAL_ROLES.PREVIOUS') }}</button
        ><span>{{ page }}</span
        ><button
          type="button"
          :class="buttonClass"
          :disabled="page * 25 >= total || loading"
          data-testid="local-role-next"
          @click="move(1)"
        >
          {{ t('RELATIONSHIP.LOCAL_ROLES.NEXT') }}
        </button>
      </div>
      <label
        >{{ t('RELATIONSHIP.LOCAL_ROLES.ROLE')
        }}<select
          v-model="role"
          :class="inputClass"
        >
          <option
            v-for="key in LOCAL_ROLES"
            :key="key"
            :value="key"
          >
            {{ t(`RELATIONSHIP.LOCAL_ROLES.ROLES.${key}`) }}
          </option>
        </select></label
      >
      <button
        type="button"
        :disabled="!memberID || loading"
        :class="buttonClass"
        data-testid="local-role-add"
        @click="add"
      >
        {{ t('RELATIONSHIP.LOCAL_ROLES.ADD') }}
      </button>
    </div>
    <details
      v-for="member in draft.members"
      :key="member.user_id"
      class="rounded border p-3"
    >
      <summary>
        {{
          users.find(user => user.id === member.user_id)?.name ||
          `#${member.user_id}`
        }}
        — {{ t(`RELATIONSHIP.LOCAL_ROLES.ROLES.${member.role}`) }}
      </summary>
      <label
        >{{ t('RELATIONSHIP.LOCAL_ROLES.ROLE')
        }}<select
          v-model="member.role"
          :class="inputClass"
          @change="publish"
        >
          <option
            v-for="key in LOCAL_ROLES"
            :key="key"
            :value="key"
          >
            {{ t(`RELATIONSHIP.LOCAL_ROLES.ROLES.${key}`) }}
          </option>
        </select></label
      >
      <p class="text-sm">{{ t('RELATIONSHIP.LOCAL_ROLES.INDEPENDENT') }}</p>
      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label
          v-for="action in editableRoleGrants(member.role, member.grants)"
          :key="action"
          ><input
            v-model="member.grants"
            :value="action"
            type="checkbox"
            @change="publish"
          />
          {{ t(`RELATIONSHIP.LOCAL_ROLES.ACTIONS.${action}`) }}</label
        >
      </div>
      <p class="text-sm">{{ t('RELATIONSHIP.LOCAL_ROLES.DOC_CATEGORIES') }}</p>
      <div class="flex flex-wrap gap-2">
        <label
          v-for="category in ['registration', 'contract', 'evidence', 'other']"
          :key="category"
          ><input
            v-model="member.document_categories"
            :value="category"
            type="checkbox"
            @change="publish"
          />
          {{ t(`RELATIONSHIP.V2.DOCS.CATEGORIES.${category}`) }}</label
        >
      </div>
      <button
        type="button"
        :class="buttonClass"
        @click="remove(member.user_id)"
      >
        {{ t('RELATIONSHIP.LOCAL_ROLES.REMOVE') }}
      </button>
    </details>
    <p
      v-if="!valid"
      role="alert"
    >
      {{ t('RELATIONSHIP.LOCAL_ROLES.INVALID') }}
    </p>
    <p class="text-sm">{{ t('RELATIONSHIP.LOCAL_ROLES.REVIEW_HELP') }}</p>
  </fieldset>
</template>
