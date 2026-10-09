import test from 'node:test';
import assert from 'node:assert/strict';
import '../jrc_customers/service_desk_node_harness.mjs';
const { registerTicketCreationCases } = await import(
  '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/ticketCreationCases.js'
);
registerTicketCreationCases(test, assert);
