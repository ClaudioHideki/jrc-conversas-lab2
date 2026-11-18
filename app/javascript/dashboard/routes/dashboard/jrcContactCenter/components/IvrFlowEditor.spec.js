import { describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import IvrFlowEditor from './IvrFlowEditor.vue';

const graph = () => ({
  schema_version: 1,
  start: 'menu',
  nodes: [
    {
      id: 'menu',
      type: 'menu',
      timeout_seconds: 8,
      max_attempts: 2,
      options: [{ digit: '1', target: 'end' }],
      on_timeout: 'end',
      on_invalid: 'end',
    },
    { id: 'end', type: 'end' },
  ],
});

describe('accessible native IVR flow controls', () => {
  it('labels DTMF by its actual label rather than concatenating select option text', async () => {
    const wrapper = mount(IvrFlowEditor, {
      props: { accountId: '1', unitId: '1', modelValue: graph() },
    });
    const label = wrapper.get('label[for="ivr-digit-0-0"]');
    expect(label.text()).toBe('Tecla DTMF');
    expect(label.element.control).toBe(wrapper.get('#ivr-digit-0-0').element);
    await wrapper.get('#ivr-digit-0-0').setValue('2');
    expect(
      wrapper.emitted('update:modelValue')[0][0].nodes[0].options[0]
    ).toEqual({ digit: '2', target: 'end' });
  });

  it('keeps destinations individually named and connected to their real controls', () => {
    const wrapper = mount(IvrFlowEditor, {
      props: { accountId: '1', unitId: '1', modelValue: graph() },
    });
    [
      ['ivr-target-0-0', 'Destino lógico'],
      ['ivr-on_timeout-0', 'Destino sem resposta'],
      ['ivr-on_invalid-0', 'Destino após tentativas inválidas'],
    ].forEach(([id, name]) => {
      const label = wrapper.get(`label[for="${id}"]`);
      expect(label.text()).toBe(name);
      expect(label.element.control).toBe(wrapper.get('#' + id).element);
      expect(label.find('option').exists()).toBe(false);
    });
  });
});
