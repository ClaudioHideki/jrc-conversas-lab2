import { mount, flushPromises } from '@vue/test-utils';
import { computed, defineComponent, ref } from 'vue';
import {
  useQualificationForms,
  endingReasonContext,
} from './useQualificationForms';
import API from 'dashboard/api/jrcContactCenter';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { qualificationFormContext: vi.fn() },
}));
const definition = {
  fields: [
    {
      key: 'verified',
      label: 'SYNTHETIC verification',
      type: 'boolean',
      required: true,
    },
  ],
};
const form = {
  rule_id: 'synthetic',
  form_id: '15',
  revision: 1,
  integrity_sha256: 'a'.repeat(64),
  name: 'SYNTHETIC original',
  definition,
};
const response = (selected = form, extra = {}) => ({
  data: {
    item: {
      id: 55,
      account_id: 1,
      account_user_id: 8,
      reason_code: 'order',
      acw_form_context: { selected, answers: {} },
      ...extra,
    },
  },
});
const fixture = ({ legacy = false } = {}) => {
  const pending = ref({
    id: 55,
    account_user_id: 8,
    ...(legacy ? {} : { acw_form_context: { selected: null, answers: {} } }),
  });
  const reason = ref('order');
  const answers = ref({});
  const accountId = ref(1);
  const profile = ref('synthetic_actor');
  const onDenied = vi.fn();
  let forms;
  const wrapper = mount(
    defineComponent({
      setup() {
        forms = useQualificationForms({
          pending,
          reason,
          answers,
          accountId,
          authorityKey: computed(() => profile.value),
          onDenied,
        });
        return () => null;
      },
    })
  );
  return {
    wrapper,
    forms,
    pending,
    reason,
    answers,
    accountId,
    profile,
    onDenied,
  };
};
afterEach(() => vi.resetAllMocks());

describe('Own immutable ACW form lookup', () => {
  it('uses only the owned attendance endpoint and blocks completion until the typed required fields are present', async () => {
    API.qualificationFormContext.mockResolvedValue(response());
    const f = fixture();
    await flushPromises();
    expect(API.qualificationFormContext).toHaveBeenCalledWith(1, 55, 'order');
    expect(f.forms.selected.value).toEqual(form);
    expect(f.forms.ready.value).toBe(false);
    f.forms.update({ verified: false });
    expect(f.forms.ready.value).toBe(true);
    expect(f.answers.value).toEqual({ synthetic: { verified: false } });
    f.wrapper.unmount();
  });

  it('keeps legacy attendance on the existing path without a catalogue or schema request', async () => {
    const f = fixture({ legacy: true });
    await flushPromises();
    expect(API.qualificationFormContext).not.toHaveBeenCalled();
    expect(f.forms.ready.value).toBe(true);
    expect(f.forms.present.value).toBe(false);
    f.wrapper.unmount();
  });

  it('accepts an explicit authorized no-form selection for a reason without weakening the server completion checks', async () => {
    API.qualificationFormContext.mockResolvedValue(response(null));
    const f = fixture();
    await flushPromises();
    expect(f.forms.ready.value).toBe(true);
    expect(f.forms.selected.value).toBeNull();
    expect(f.forms.error.value).toBe(false);
    f.wrapper.unmount();
  });

  it.each([
    { account_id: 2 },
    { account_user_id: 9 },
    { id: 56 },
    { reason_code: 'resolved' },
    { acw_form_context: null },
  ])(
    'rejects a successful response whose current native identity or explicit context is incompatible %j',
    async extra => {
      API.qualificationFormContext.mockResolvedValue(response(form, extra));
      const f = fixture();
      await flushPromises();
      expect(f.forms.error.value).toBe(true);
      expect(f.forms.ready.value).toBe(false);
      expect(f.forms.selected.value).toBeNull();
      f.wrapper.unmount();
    }
  );

  it('ignores a late result after the reason changes and never restores the old form', async () => {
    let settle;
    API.qualificationFormContext
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            settle = resolve;
          })
      )
      .mockResolvedValueOnce(response(null, { reason_code: 'resolved' }));
    const f = fixture();
    f.reason.value = 'resolved';
    await flushPromises();
    settle(response());
    await flushPromises();
    expect(f.forms.selected.value).toBeNull();
    expect(f.forms.ready.value).toBe(true);
    expect(API.qualificationFormContext).toHaveBeenCalledTimes(2);
    f.wrapper.unmount();
  });

  it('ignores a late result after account/profile removal and leaves no old schema visible', async () => {
    let settle;
    API.qualificationFormContext.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          settle = resolve;
        })
    );
    const f = fixture();
    f.accountId.value = 2;
    f.profile.value = 'other';
    f.pending.value = null;
    await flushPromises();
    settle(response());
    await flushPromises();
    expect(f.forms.present.value).toBe(false);
    expect(f.forms.selected.value).toBeNull();
    expect(API.qualificationFormContext).toHaveBeenCalledTimes(1);
    f.wrapper.unmount();
  });

  it('preserves local responses on a failed read and retries only through the explicit refresh action', async () => {
    API.qualificationFormContext
      .mockRejectedValueOnce(new Error('synthetic read failure'))
      .mockResolvedValueOnce(response());
    const f = fixture();
    f.answers.value = { synthetic: { verified: false } };
    await flushPromises();
    expect(f.forms.error.value).toBe(true);
    expect(f.answers.value.synthetic.verified).toBe(false);
    expect(API.qualificationFormContext).toHaveBeenCalledTimes(1);
    await f.forms.load();
    expect(f.forms.ready.value).toBe(true);
    expect(API.qualificationFormContext).toHaveBeenCalledTimes(2);
    f.wrapper.unmount();
  });

  it.each([401, 403, 404])(
    'signals current authority denial %i without keeping a previous schema',
    async status => {
      const failure = { response: { status } };
      API.qualificationFormContext.mockRejectedValue(failure);
      const f = fixture();
      await flushPromises();
      expect(f.onDenied).toHaveBeenCalledWith(failure);
      expect(f.forms.selected.value).toBeNull();
      expect(f.forms.ready.value).toBe(false);
      f.wrapper.unmount();
    }
  );

  it('rejects an imprecise numeric form reference instead of accepting a coercion as an exact version identity', async () => {
    API.qualificationFormContext.mockResolvedValue(
      response({ ...form, form_id: 15 })
    );
    const f = fixture();
    await flushPromises();
    expect(f.forms.error.value).toBe(true);
    expect(f.forms.ready.value).toBe(false);
    f.wrapper.unmount();
  });
});

describe('frozen registered ending reasons on the existing own context', () => {
  const context = () => ({
    revision: 3,
    integrity_sha256: 'c'.repeat(64),
    required: true,
    options: [{ code: 'registered', name: 'SYNTHETIC registered' }],
  });
  it('loads an ending-only native context without showing or requiring a fake form', async () => {
    API.qualificationFormContext.mockResolvedValue(
      response(null, {
        reason_code: 'registered',
        acw_form_context: undefined,
        ending_reason_context: context(),
      })
    );
    const f = fixture({ legacy: true });
    f.pending.value.ending_reason_context = context();
    f.reason.value = 'registered';
    await flushPromises();
    expect(f.forms.present.value).toBe(false);
    expect(f.forms.reasonRequired.value).toBe(true);
    expect(f.forms.reasonOptions.value).toEqual(context().options);
    expect(f.forms.ready.value).toBe(true);
    expect(API.qualificationFormContext).toHaveBeenCalledWith(
      1,
      55,
      'registered'
    );
    f.reason.value = 'resolved';
    await flushPromises();
    expect(f.forms.ready.value).toBe(false);
    f.wrapper.unmount();
  });

  it('rejects a response that substitutes another frozen catalogue revision', async () => {
    API.qualificationFormContext.mockResolvedValue(
      response(null, {
        reason_code: 'registered',
        ending_reason_context: { ...context(), revision: 4 },
      })
    );
    const f = fixture({ legacy: true });
    f.pending.value.ending_reason_context = context();
    f.reason.value = 'registered';
    await flushPromises();
    expect(f.forms.error.value).toBe(true);
    expect(f.forms.ready.value).toBe(false);
    f.wrapper.unmount();
  });

  it.each([
    null,
    false,
    { required: true },
    { ...context(), required: 'true' },
    { ...context(), options: [] },
    { ...context(), options: [...context().options, ...context().options] },
  ])('rejects malformed frozen catalogue %j', value => {
    expect(() => endingReasonContext(value)).toThrow(TypeError);
  });
});
