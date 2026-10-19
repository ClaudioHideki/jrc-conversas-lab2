import { test } from 'node:test';
import assert from 'node:assert/strict';
import { operationPrompt } from '../src/operations.ts';

test('explains operator voice separately from contacting customers without inventing an action', () => {
  const prompt = operationPrompt('operator');
  assert.match(prompt, /Conversar com o NICO/);
  assert.match(prompt, /microfone.*operador/i);
  assert.match(prompt, /não.*liga.*contato/i);
  assert.match(prompt, /navegador.*provedor/i);
  assert.match(prompt, /não.*ativ.*microfone.*texto/i);
  assert.match(prompt, /tool vazio.*dúvida.*voz/i);
  assert.match(prompt, /sem uma ferramenta correspondente realmente executada/);
});
