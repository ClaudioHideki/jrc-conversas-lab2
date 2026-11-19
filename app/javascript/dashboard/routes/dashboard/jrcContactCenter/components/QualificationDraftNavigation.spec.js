import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import QualificationDraftNavigation from '../../inbox/QualificationDraftNavigation.vue';

const hooks = vi.hoisted(() => ({
  leave: null,
  update: null,
  opened: 0,
  closed: 0,
}));
vi.mock('vue-router', () => ({
  onBeforeRouteLeave: callback => {
    hooks.leave = callback;
  },
  onBeforeRouteUpdate: callback => {
    hooks.update = callback;
  },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', () => ({
  default: {
    name: 'Dialog',
    emits: ['confirm', 'close'],
    methods: {
      open() {
        hooks.opened += 1;
      },
      close() {
        hooks.closed += 1;
        this.$emit('close');
      },
    },
    template: '<div />',
  },
}));
enableAutoUnmount(afterEach);
beforeEach(() => {
  hooks.leave = null;
  hooks.update = null;
  hooks.opened = 0;
  hooks.closed = 0;
});

describe('native pending qualification navigation review', () => {
  it('allows clean navigation and does not interfere with a normal browser unload', () => {
    mount(QualificationDraftNavigation);
    expect(hooks.leave()).toBe(true);
    const event = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(false);
    expect(hooks.opened).toBe(0);
  });

  it('requires explicit review and keeps edits when the native dialog is cancelled', async () => {
    const wrapper = mount(QualificationDraftNavigation, {
      props: { dirty: true },
    });
    const decision = hooks.leave();
    expect(decision).toBeInstanceOf(Promise);
    expect(hooks.opened).toBe(1);
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('close');
    expect(await decision).toBe(false);
    expect(wrapper.props('dirty')).toBe(true);
  });

  it('permits discarding only after the explicit confirm action and never mutates the draft itself', async () => {
    const wrapper = mount(QualificationDraftNavigation, {
      props: { dirty: true },
    });
    const decision = hooks.leave();
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('confirm');
    expect(await decision).toBe(true);
    expect(wrapper.props('dirty')).toBe(true);
    expect(hooks.closed).toBe(1);
  });

  it('shares one active review instead of opening duplicate dialogs or resolving early', async () => {
    const wrapper = mount(QualificationDraftNavigation, {
      props: { dirty: true },
    });
    const first = hooks.leave();
    expect(hooks.leave()).toBe(first);
    expect(hooks.opened).toBe(1);
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('close');
    expect(await first).toBe(false);
  });

  it('blocks route changes and warns on browser unload while an existing write is in flight', async () => {
    const wrapper = mount(QualificationDraftNavigation, {
      props: { saving: true },
    });
    expect(hooks.leave()).toBe(false);
    const event = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
    expect(hooks.opened).toBe(0);
    await wrapper.setProps({ saving: false });
    expect(hooks.leave()).toBe(true);
  });

  it('ignores query-only navigation but reviews a changed native route identity', async () => {
    const wrapper = mount(QualificationDraftNavigation, {
      props: { dirty: true },
    });
    expect(
      hooks.update(
        { params: { accountId: '1' }, query: { tab: 'new' } },
        { params: { accountId: '1' } }
      )
    ).toBe(true);
    const decision = hooks.update(
      { params: { accountId: '2' } },
      { params: { accountId: '1' } }
    );
    wrapper.findComponent({ name: 'Dialog' }).vm.$emit('close');
    expect(await decision).toBe(false);
  });

  it('invalidates the previous review after a change of authenticated authority', async () => {
    const wrapper = mount(QualificationDraftNavigation, {
      props: { dirty: true, authorityKey: 'old-actor' },
    });
    const decision = hooks.leave();
    await wrapper.setProps({ authorityKey: 'new-actor', dirty: false });
    expect(await decision).toBe(false);
    expect(hooks.leave()).toBe(true);
  });

  it('warns on browser unload for edits or unresolved review, without exposing private values', async () => {
    const wrapper = mount(QualificationDraftNavigation, {
      props: { dirty: true },
    });
    let event = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
    await wrapper.setProps({ dirty: false, conflict: true });
    event = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
    await wrapper.setProps({ enabled: false });
    event = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(false);
  });

  it('cancels the pending decision and removes only its own unload listener on unmount', async () => {
    const otherListener = vi.fn();
    window.addEventListener('beforeunload', otherListener);
    const wrapper = mount(QualificationDraftNavigation, {
      props: { dirty: true },
    });
    const decision = hooks.leave();
    wrapper.unmount();
    expect(await decision).toBe(false);
    const event = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(event);
    window.removeEventListener('beforeunload', otherListener);
    expect(event.defaultPrevented).toBe(false);
    expect(otherListener).toHaveBeenCalledOnce();
  });
});
