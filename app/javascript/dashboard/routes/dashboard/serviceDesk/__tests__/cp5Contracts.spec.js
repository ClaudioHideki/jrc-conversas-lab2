import { describe, it } from 'vitest';
import assert from 'node:assert/strict';
import { registerCp5Cases } from './cp5Cases.js';
describe('CP5 native integration contracts (isolated transport)', () => { registerCp5Cases(it, assert); });
