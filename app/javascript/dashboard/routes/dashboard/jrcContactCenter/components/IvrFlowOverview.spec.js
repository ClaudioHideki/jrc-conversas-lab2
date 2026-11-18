import { describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import IvrFlowOverview from './IvrFlowOverview.vue';

const graph = () => ({
  schema_version: 1,
  start: 'menu',
  nodes: [
    {
      id: 'menu',
      type: 'menu',
      options: [{ digit: '1', target: 'queue' }],
      on_timeout: 'end',
      on_invalid: 'end',
      timeout_seconds: 8,
      max_attempts: 2,
    },
    { id: 'queue', type: 'queue', queue_id: '9223372036854775807' },
    { id: 'end', type: 'end' },
  ],
});

describe('local IVR diagram derived from the actual editing graph', () => {
  it('shows the actual entry, DTMF and exception destinations without claiming provider execution', () => {
    const wrapper = mount(IvrFlowOverview, { props: { modelValue: graph() } });
    expect(wrapper.findAll('[data-ivr-map-node]')).toHaveLength(3);
    const menu = wrapper.get('[data-ivr-map-node="menu"]');
    expect(menu.findAll('li').map(row => row.text())).toEqual(
      expect.arrayContaining([
        expect.stringContaining('queue'),
        expect.stringContaining('end'),
      ])
    );
    expect(menu.text()).toContain('Nó inicial');
    expect(wrapper.text()).toContain('9223372036854775807');
    expect(wrapper.text()).toContain(
      'não representa uma versão aplicada no PABX'
    );
    expect(wrapper.emitted()).toEqual({});
  });

  it('marks incomplete destinations instead of inventing a fallback or mutating the draft', async () => {
    const value = graph();
    value.nodes[0].options[0].target = '';
    const before = JSON.stringify(value);
    const wrapper = mount(IvrFlowOverview, { props: { modelValue: value } });
    expect(wrapper.get('[data-ivr-map-node="menu"]').text()).toContain(
      'Destino pendente'
    );
    expect(JSON.stringify(value)).toBe(before);
    const changed = graph();
    changed.nodes[0].options[0].target = 'end';
    await wrapper.setProps({ modelValue: changed });
    expect(
      wrapper.get('[data-ivr-map-node="menu"]').findAll('li')[0].text()
    ).toContain('end');
    expect(wrapper.text()).not.toContain('Destino pendente');
  });

  it('does not manufacture a diagram for an empty editing graph', () => {
    const wrapper = mount(IvrFlowOverview, {
      props: { modelValue: { schema_version: 1, start: '', nodes: [] } },
    });
    expect(wrapper.find('[data-ivr-map]').exists()).toBe(false);
  });
});
