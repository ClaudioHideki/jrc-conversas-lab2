import { it } from 'vitest';
import assert from 'node:assert/strict';
import { registerStructureCases } from './structureCases';
registerStructureCases(it, assert);
