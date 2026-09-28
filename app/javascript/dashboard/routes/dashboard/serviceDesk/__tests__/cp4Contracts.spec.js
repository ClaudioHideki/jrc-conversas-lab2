import { describe, it } from 'vitest';
import assert from 'node:assert/strict';
import { registerCp4Cases } from './cp4Cases.js';
describe('CP4 operational contracts and non-optimistic readback', () => { registerCp4Cases(it, assert); });
