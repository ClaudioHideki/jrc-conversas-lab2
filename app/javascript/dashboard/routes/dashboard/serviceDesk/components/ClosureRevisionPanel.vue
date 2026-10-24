<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/serviceDeskClosureRevisions';
import LifecycleAPI from 'dashboard/api/serviceDeskLifecycle';
import ScopeBar from './ScopeBar.vue';
import Panel from './ServiceDeskPanel.vue';
import { useOperationalScope } from '../composables/useOperationalScope';
const { t } = useI18n();
const unitId = ref('');
const operatorId = ref('');
const scope = useOperationalScope(
  unitId,
  context =>
    context?.capabilities?.lifecycle_policies?.publish === true &&
    [
      'tickets_view_all',
      'history_view',
      'sla_view',
      'contract_conditions_view',
    ].every(key =>
      context.effective_permissions?.includes(`jrc_service_desk_${key}`)
    )
);
const versions = ref([]);
const versionPage = ref(1);
const versionTotal = ref(0);
const sourceId = ref('');
const targetId = ref('');
const proposal = ref(null);
const rows = ref([]);
const counts = ref({});
const total = ref(0);
const page = ref(1);
const selected = ref([]);
const reviewed = ref(false);
const reason = ref('');
const preview = ref(null);
const result = ref(null);
const batchId = ref('');
const previewOperation = ref(false);
const busy = ref(false);
const feedback = ref('');
const source = computed(() =>
  versions.value.find(row => row.id === sourceId.value)
);
const eligible = computed(() => rows.value.filter(row => !row.reason));
const changedRules = computed(() =>
  (proposal.value?.definition?.transitions || []).filter(row =>
    ['resolve', 'close'].includes(row.action)
  )
);
const storageKey = () =>
  `jrc-sd-closure-batch:${scope.identity.value}:${unitId.value}`;
const code = value =>
  t(`JRC_SERVICE_DESK.CLOSURE_REVISION.reasons.${value || 'eligible'}`);
const request = (lease, action, values = {}, opts = {}) =>
  API.request(
    lease.context.account_id,
    action,
    { unit_id: lease.unit, ...values },
    { signal: lease.signal, ...opts }
  );
const operate = async action => {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  feedback.value = '';
  try {
    await action(lease);
  } catch {
    if (scope.live(lease)) feedback.value = 'failed';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
function checkResult(value) {
  if (
    !value ||
    typeof value.batch_id !== 'string' ||
    typeof value.complete !== 'boolean' ||
    !Array.isArray(value.results) ||
    !value.results.every(
      row =>
        /^\d+$/.test(row.ticket_id) &&
        ['applied', 'blocked', 'conflict', 'pending'].includes(row.status)
    )
  )
    throw new TypeError('Invalid batch result');
  return value;
}
const loadVersions = async (lease, nextPage = 1) => {
  const data = await request(lease, 'versions', { page: nextPage });
  if (!scope.live(lease)) return;
  versions.value = [
    ...new Map(
      [...versions.value, ...data.versions].map(row => [row.id, row])
    ).values(),
  ];
  versionPage.value = nextPage;
  versionTotal.value = data.total;
};
const load = async (lease, targetPage = 1) => {
  const data = await request(lease, '', {
    source_version_id: sourceId.value,
    target_version_id: targetId.value,
    page: targetPage,
  });
  if (!scope.live(lease)) return;
  rows.value = data.items;
  counts.value = data.counts;
  total.value = data.total;
  page.value = targetPage;
};
const propose = () =>
  operate(async lease => {
    const data = await request(
      lease,
      'proposal',
      { source_version_id: sourceId.value },
      { method: 'post' }
    );
    if (scope.live(lease)) proposal.value = data;
  });
const publish = () =>
  operate(async lease => {
    const draft = proposal.value;
    const ack = await LifecycleAPI.publish(
      lease.context.account_id,
      lease.unit,
      {
        name: draft.name,
        service_id: draft.service_id,
        enabled: true,
        expected_version: draft.expected_version,
        definition: draft.definition,
      },
      lease.signal
    );
    if (!scope.live(lease)) return;
    await loadVersions(lease);
    if (!scope.live(lease)) return;
    const saved = versions.value.find(
      row =>
        row.id === ack.policy.version_id && row.digest === ack.policy.digest
    );
    if (!saved) throw new TypeError('Unconfirmed publication');
    targetId.value = saved.id;
    proposal.value = null;
    feedback.value = 'published';
  });
const makePreview = () =>
  operate(async lease => {
    const data = await request(
      lease,
      'preview',
      {
        source_version_id: sourceId.value,
        target_version_id: targetId.value,
        ticket_ids: selected.value,
        operational_review: reviewed.value,
        review_reason: reason.value,
      },
      { method: 'post' }
    );
    if (!scope.live(lease)) return;
    if (
      typeof data.preview?.receipt !== 'string' ||
      data.preview.tickets
        .map(row => row.id)
        .sort()
        .join() !== [...selected.value].sort().join()
    )
      throw new TypeError('Invalid selected cohort');
    preview.value = data.preview;
  });
const readResult = async lease => {
  const data = await request(lease, 'result', {
    idempotency_key: batchId.value,
  });
  if (scope.live(lease)) result.value = checkResult(data.result);
};
const apply = () =>
  operate(async lease => {
    if (!preview.value) return;
    if (!previewOperation.value) {
      batchId.value = crypto.randomUUID();
      previewOperation.value = true;
    }
    localStorage.setItem(storageKey(), batchId.value);
    await request(
      lease,
      '',
      { receipt: preview.value.receipt },
      { method: 'post', key: batchId.value }
    );
    if (!scope.live(lease)) return;
    await readResult(lease);
    if (scope.live(lease)) feedback.value = 'confirmed';
  });
const recover = () => operate(readResult);
const resume = () =>
  operate(async lease => {
    await request(
      lease,
      'resume',
      { idempotency_key: batchId.value },
      { method: 'post' }
    );
    if (scope.live(lease)) await readResult(lease);
  });
const resetPreview = () => {
  preview.value = null;
  result.value = null;
  previewOperation.value = false;
};
watch([sourceId, targetId, selected, reviewed, reason], resetPreview, {
  deep: true,
});
watch(sourceId, () => {
  proposal.value = null;
  rows.value = [];
  selected.value = [];
});
watch(
  [scope.identity, unitId],
  () => {
    scope.cancel();
    versions.value = [];
    sourceId.value = '';
    targetId.value = '';
    proposal.value = null;
    rows.value = [];
    selected.value = [];
    counts.value = {};
    total.value = 0;
    reviewed.value = false;
    reason.value = '';
    preview.value = null;
    result.value = null;
    busy.value = false;
    batchId.value = localStorage.getItem(storageKey()) || '';
    if (unitId.value) operate(lease => loadVersions(lease));
  },
  { flush: 'sync' }
);
</script>

<template>
  <Panel :title="t('JRC_SERVICE_DESK.CLOSURE_REVISION.title')">
    <div class="grid gap-4" data-testid="closure-revision-panel">
      <p class="text-sm">
        {{
          t('JRC_SERVICE_DESK.CLOSURE_REVISION.notice', {
            account: scope.session.state.context?.account_id,
          })
        }}
      </p>
      <ScopeBar
        v-model:unit-id="unitId"
        v-model:operator-id="operatorId"
        required
        :disabled="busy"
      />
      <p v-if="!scope.allowed.value" role="status">
        {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.restricted') }}
      </p>
      <template v-else>
        <div class="grid gap-3 md:grid-cols-2">
          <label class="grid gap-1"
            >{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.source') }}
            <select
              v-model="sourceId"
              :disabled="busy"
              class="rounded border border-n-weak bg-n-solid-1 p-2"
              :aria-label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.source')"
            >
              <option value="">
                {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.select') }}
              </option>
              <option
                v-for="version in versions"
                :key="version.id"
                :value="version.id"
              >
                {{
                  t('JRC_SERVICE_DESK.CLOSURE_REVISION.version_option', version)
                }}
              </option>
            </select>
          </label>
          <label class="grid gap-1"
            >{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.target') }}
            <select
              v-model="targetId"
              :disabled="busy"
              class="rounded border border-n-weak bg-n-solid-1 p-2"
              :aria-label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.target')"
            >
              <option value="">
                {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.select') }}
              </option>
              <option
                v-for="version in versions"
                :key="version.id"
                :value="version.id"
              >
                {{
                  t('JRC_SERVICE_DESK.CLOSURE_REVISION.version_option', version)
                }}
              </option>
            </select>
          </label>
        </div>
        <Button
          v-if="versions.length < versionTotal"
          :disabled="busy"
          :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.older')"
          variant="outline"
          @click="operate(lease => loadVersions(lease, versionPage + 1))"
        />
        <p v-if="source" class="rounded bg-n-amber-2 p-3 text-sm">
          {{
            t('JRC_SERVICE_DESK.CLOSURE_REVISION.source_notice', {
              version: source.version,
              obligation:
                source.definition.sla.obligation ||
                t('JRC_SERVICE_DESK.CLOSURE_REVISION.undeclared'),
              mode: source.definition.sla.mode,
            })
          }}
        </p>
        <details v-if="source" class="rounded border border-n-weak p-3 text-sm">
          <summary>
            {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.source_definition') }}
          </summary>
          <p>
            {{
              t('JRC_SERVICE_DESK.CLOSURE_REVISION.service_scope', {
                id:
                  source.service_id ||
                  t('JRC_SERVICE_DESK.CLOSURE_REVISION.all_services'),
              })
            }}
          </p>
          <pre class="overflow-auto whitespace-pre-wrap break-words text-xs">{{
            JSON.stringify(source.definition, null, 2)
          }}</pre>
        </details>
        <label class="flex gap-2 text-sm"
          ><input v-model="reviewed" type="checkbox" :disabled="busy" />{{
            t('JRC_SERVICE_DESK.CLOSURE_REVISION.reviewed')
          }}</label
        >
        <label class="grid gap-1 text-sm"
          >{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.review_reason')
          }}<textarea
            v-model="reason"
            :disabled="busy"
            maxlength="4000"
            class="rounded border border-n-weak bg-n-solid-1 p-2"
          />
        </label>
        <Button
          :disabled="busy || !sourceId"
          variant="outline"
          :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.propose')"
          @click="propose"
        />
        <section
          v-if="proposal"
          class="grid gap-3 rounded border border-n-weak p-4"
          data-testid="closure-revision-proposal"
        >
          <h4 class="font-semibold">
            {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.draft') }}
          </h4>
          <p>{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.future_notice') }}</p>
          <p v-for="rule in changedRules" :key="rule.key">
            {{
              t('JRC_SERVICE_DESK.CLOSURE_REVISION.rule_summary', {
                action: rule.action,
              })
            }}
          </p>
          <p>{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.clock_preserved') }}</p>
          <Button
            :disabled="busy || !reviewed || !reason.trim()"
            :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.publish')"
            @click="publish"
          />
        </section>
        <Button
          :disabled="busy || !sourceId || !targetId"
          :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.list')"
          @click="operate(lease => load(lease))"
        />
        <p v-if="total">
          {{
            t('JRC_SERVICE_DESK.CLOSURE_REVISION.totals', {
              total,
              eligible: counts.eligible || 0,
            })
          }}
        </p>
        <ul class="text-sm">
          <li v-for="(count, why) in counts" :key="why">
            {{
              t('JRC_SERVICE_DESK.CLOSURE_REVISION.count_item', {
                label: code(why),
                count,
              })
            }}
          </li>
        </ul>
        <div v-if="rows.length" class="overflow-x-auto">
          <Button
            :disabled="busy"
            variant="outline"
            :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.select_page')"
            @click="
              selected = [
                ...new Set([...selected, ...eligible.map(row => row.id)]),
              ].slice(0, 100)
            "
          />
          <table class="w-full text-left text-sm">
            <thead>
              <tr>
                <th>{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.selected') }}</th>
                <th>{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.ticket') }}</th>
                <th>{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.state') }}</th>
                <th>
                  {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.eligibility') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in rows" :key="row.id">
                <td class="p-2">
                  <input
                    v-model="selected"
                    type="checkbox"
                    :value="row.id"
                    :disabled="
                      busy ||
                      !!row.reason ||
                      (selected.length >= 100 && !selected.includes(row.id))
                    "
                    :aria-label="
                      t('JRC_SERVICE_DESK.CLOSURE_REVISION.select_ticket', {
                        id: row.id,
                      })
                    "
                  />
                </td>
                <td class="p-2">
                  {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.ticket_item', row) }}
                </td>
                <td class="p-2">{{ row.status }}</td>
                <td class="p-2">{{ code(row.reason) }}</td>
              </tr>
            </tbody>
          </table>
          <div class="flex gap-2">
            <Button
              :disabled="busy || page <= 1"
              variant="outline"
              :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.previous')"
              @click="operate(lease => load(lease, page - 1))"
            /><Button
              :disabled="busy || page * 25 >= total"
              variant="outline"
              :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.next')"
              @click="operate(lease => load(lease, page + 1))"
            />
          </div>
        </div>
        <p>
          {{
            t('JRC_SERVICE_DESK.CLOSURE_REVISION.selection', {
              count: selected.length,
            })
          }}
        </p>
        <Button
          :disabled="busy || !reviewed || !reason.trim() || !selected.length"
          :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.preview')"
          @click="makePreview"
        />
        <section
          v-if="preview"
          class="grid gap-3 rounded border border-n-blue-5 bg-n-blue-2 p-4"
          data-testid="closure-revision-preview"
        >
          <h4 class="font-semibold">
            {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.preview_title') }}
          </h4>
          <p>
            {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.preview_counts', preview) }}
          </p>
          <p>{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.clock_preserved') }}</p>
          <ul>
            <li v-for="row in preview.tickets" :key="row.id">
              {{
                t('JRC_SERVICE_DESK.CLOSURE_REVISION.preview_item', {
                  id: row.id,
                  state: code(row.reason),
                })
              }}
            </li>
          </ul>
          <Button
            :disabled="busy || !preview.eligible || !!result"
            :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.apply')"
            @click="apply"
          />
        </section>
        <label class="grid gap-1 text-sm"
          >{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.recover_id')
          }}<input
            v-model="batchId"
            maxlength="120"
            :disabled="busy"
            class="rounded border border-n-weak bg-n-solid-1 p-2"
            @input="
              previewOperation = false;
              result = null;
            "
        /></label>
        <div v-if="batchId" class="grid gap-3">
          <p class="break-all">
            {{
              t('JRC_SERVICE_DESK.CLOSURE_REVISION.operation', { id: batchId })
            }}
          </p>
          <Button
            :disabled="busy"
            variant="outline"
            :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.recover')"
            @click="recover"
          /><Button
            v-if="result && !result.complete"
            :disabled="busy"
            :label="t('JRC_SERVICE_DESK.CLOSURE_REVISION.resume')"
            @click="resume"
          />
        </div>
        <section
          v-if="result"
          data-testid="closure-revision-result"
          class="rounded border border-n-weak p-4"
        >
          <h4 class="font-semibold">
            {{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.results') }}
          </h4>
          <p>{{ t('JRC_SERVICE_DESK.CLOSURE_REVISION.confirmed_notice') }}</p>
          <ul>
            <li v-for="row in result.results" :key="row.ticket_id">
              {{
                t('JRC_SERVICE_DESK.CLOSURE_REVISION.result_item', {
                  id: row.ticket_id,
                  state: t(
                    `JRC_SERVICE_DESK.CLOSURE_REVISION.statuses.${row.status}`
                  ),
                  reason: row.reason ? code(row.reason) : '',
                })
              }}
            </li>
          </ul>
        </section>
        <p v-if="feedback" role="status">
          {{ t(`JRC_SERVICE_DESK.CLOSURE_REVISION.${feedback}`) }}
        </p>
      </template>
    </div>
  </Panel>
</template>
