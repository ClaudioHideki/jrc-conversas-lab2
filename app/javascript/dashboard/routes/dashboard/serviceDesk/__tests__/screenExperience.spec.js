import { it } from 'vitest';
import assert from 'node:assert/strict';
import { registerScreenExperienceCases } from './screenExperienceCases.js';
registerScreenExperienceCases(it, assert);
