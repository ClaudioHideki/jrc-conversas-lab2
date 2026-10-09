import { it } from 'vitest';
import assert from 'node:assert/strict';
import { registerTicketHistoryCases } from './ticketHistoryCases';
registerTicketHistoryCases(it, assert);
