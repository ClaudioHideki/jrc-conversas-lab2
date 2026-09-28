import { it } from 'vitest';
import assert from 'node:assert/strict';
import { registerConfigurationCases } from './configurationCases.js';
registerConfigurationCases(it, assert);
