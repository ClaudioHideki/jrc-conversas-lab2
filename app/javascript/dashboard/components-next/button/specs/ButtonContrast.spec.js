import { mount } from '@vue/test-utils';
import { readFileSync } from 'node:fs';
import postcss from 'postcss';
import tailwindcss from 'tailwindcss';
import config from '../../../../../../tailwind.config';
import { colors } from '../../../../../../theme/colors';
import Button from '../Button.vue';
import LegacyButton from 'shared/components/Button.vue';

const nextColors = readFileSync(
  'app/javascript/dashboard/assets/scss/_next-colors.scss',
  'utf8'
);

const luminance = rgb => {
  const values = rgb.map(value => {
    const channel = value / 255;
    return channel <= 0.04045
      ? channel / 12.92
      : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722;
};
const contrast = (first, second) => {
  const values = [luminance(first), luminance(second)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
};
const hexRgb = hex =>
  hex.match(/[a-f\d]{2}/gi).map(value => parseInt(value, 16));

describe('JRC action colors', () => {
  it('generates backgrounds and text for the Tailwind families used by JRC screens', async () => {
    const families = [
      'blue',
      'emerald',
      'amber',
      'teal',
      'cyan',
      'rose',
      'orange',
    ];
    const raw = families
      .map(color => `bg-${color}-500 text-${color}-700 border-${color}-200`)
      .join(' ');
    const result = await postcss([
      tailwindcss({
        ...config,
        content: [{ raw, extension: 'html' }],
        plugins: [],
        safelist: [],
      }),
    ]).process('@tailwind utilities;', { from: undefined });
    families.forEach(color => {
      expect(result.css).toContain(`.bg-${color}-500`);
      expect(result.css).toContain(`.text-${color}-700`);
      expect(result.css).toContain(`.border-${color}-200`);
    });
  });

  it('keeps solid action labels readable in both token themes', () => {
    expect(
      contrast(hexRgb(colors.n.brand), [255, 255, 255])
    ).toBeGreaterThanOrEqual(4.5);
    const modes = nextColors.split('.dark {');
    modes.forEach(mode => {
      ['blue', 'ruby', 'teal'].forEach(color => {
        [9, 10].forEach(step => {
          const rgb = mode
            .match(new RegExp(`--${color}-${step}: ([0-9 ]+);`))[1]
            .split(' ')
            .map(Number);
          expect(contrast(rgb, [255, 255, 255])).toBeGreaterThanOrEqual(4.5);
        });
        const readToken = name =>
          mode
            .match(new RegExp(`--${name}: ([0-9 ]+);`))[1]
            .split(' ')
            .map(Number);
        const fill = readToken(`${color}-9`);
        const hoveredFaded = readToken('solid-2').map(
          (channel, index) => channel * 0.8 + fill[index] * 0.2
        );
        expect(
          contrast(readToken(`${color}-11`), hoveredFaded)
        ).toBeGreaterThanOrEqual(4.5);
      });
      const amber = mode
        .match(/--amber-9: ([\d ]+);/)[1]
        .split(' ')
        .map(Number);
      expect(
        contrast(amber, hexRgb(colors.n['on-amber']))
      ).toBeGreaterThanOrEqual(4.5);
    });
  });

  it('keeps a disabled action legible and prevents activation', async () => {
    const clicked = vi.fn();
    const wrapper = mount(Button, {
      props: { label: 'Save', color: 'amber' },
      attrs: { disabled: true, onClick: clicked },
    });
    expect(wrapper.classes()).toContain('text-n-on-amber');
    expect(wrapper.classes()).toContain('disabled:opacity-100');
    expect(wrapper.classes()).toContain('disabled:text-n-slate-11');
    await wrapper.trigger('click');
    expect(clicked).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('uses the disabled colors for legacy buttons even with custom enabled colors', async () => {
    const wrapper = mount(LegacyButton, {
      props: { bgColor: '#ffffff', textColor: '#111111', disabled: true },
      slots: { default: 'Save' },
    });
    expect(wrapper.element.style.backgroundColor).toBe('');
    expect(wrapper.element.disabled).toBe(true);
    await wrapper.setProps({ disabled: false });
    expect(wrapper.element.style.backgroundColor).toBe('rgb(255, 255, 255)');
    wrapper.unmount();
  });
});
