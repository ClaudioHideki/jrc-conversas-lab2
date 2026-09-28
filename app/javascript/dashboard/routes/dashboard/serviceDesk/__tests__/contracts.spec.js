import { describe, it } from 'vitest';
import assert from 'node:assert/strict';
import { registerContractCases } from './contractCases.js';
describe('Service Desk CP3 pure contracts and scoped read session', () => {
  registerContractCases(it, assert);
});
