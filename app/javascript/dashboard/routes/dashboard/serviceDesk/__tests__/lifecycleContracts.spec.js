import { describe, it } from 'vitest';
import assert from 'node:assert/strict';
import { registerLifecycleCases } from './lifecycleCases.js';
describe('CP4-D01 lifecycle contracts and independent confirmation', () => registerLifecycleCases(it, assert));
