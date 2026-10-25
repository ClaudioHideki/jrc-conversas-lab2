<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import ScopeBar from './ScopeBar.vue';
import Panel from './ServiceDeskPanel.vue';
import { useClosureRevision } from '../composables/useClosureRevision';
const {
  t,
  unitId,
  operatorId,
  scope,
  versions,
  versionPage,
  versionTotal,
  sourceId,
  targetId,
  proposal,
  rows,
  counts,
  total,
  page,
  selected,
  reviewed,
  reason,
  preview,
  result,
  batchId,
  previewOperation,
  busy,
  feedback,
  source,
  eligible,
  changedRules,
  code,
  operate,
  loadVersions,
  load,
  propose,
  publish,
  makePreview,
  apply,
  recover,
  resume,
} = useClosureRevision();
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
