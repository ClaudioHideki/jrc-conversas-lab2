import { it, expect } from 'vitest';
import { registerReferenceCompletionCases } from './referenceCompletionCases';
const assert = {
  equal(actual, expected) {
    expect(actual).toBe(expected);
  },
  deepEqual(actual, expected) {
    expect(actual).toEqual(expected);
  },
};
registerReferenceCompletionCases(it, assert);
