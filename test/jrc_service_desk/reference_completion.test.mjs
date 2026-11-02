import test from 'node:test';
import assert from 'node:assert/strict';
import '../jrc_customers/service_desk_node_harness.mjs';
const { registerReferenceCompletionCases } = await import(
  '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/referenceCompletionCases.js'
);
registerReferenceCompletionCases(test, assert);
