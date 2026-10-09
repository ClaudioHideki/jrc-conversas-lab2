import { it } from 'vitest';
import assert from 'node:assert/strict';
import { registerTicketCreationCases } from './ticketCreationCases';
registerTicketCreationCases(it, assert);
