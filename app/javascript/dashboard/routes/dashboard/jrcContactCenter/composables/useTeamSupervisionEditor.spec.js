import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useTeamSupervisionEditor } from './useTeamSupervisionEditor';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    configurationRecord: vi.fn(),
    teamSupervisionCandidates: vi.fn(),
    saveTeamSupervision: vi.fn(),
  },
}));
const person = (id = '7', overrides = {}) => ({
  account_user_id: id,
  name: `SYNTHETIC person ${id}`,
  eligible: true,
  reason: null,
  ...overrides,
});
const item = (values = {}, revision = 'a'.repeat(64)) => {
  const primary = values.primary_account_user_id || null;
  const additional = values.additional_account_user_ids || [];
  return {
    id: '4',
    name: 'SYNTHETIC team',
    active: true,
    revision,
    primary_account_user_id: primary,
    additional_account_user_ids: [...additional],
    supervisors: [primary, ...additional].filter(Boolean).map(id => person(id)),
    primary_supervisor: primary ? person(primary).name : null,
    additional_supervisors: additional.map(id => person(id).name),
  };
};
const response = record => ({
  data: { account_id: '1', item: record || item() },
});
const options = (items = [person(), person('8')], page = 1) => ({
  data: {
    account_id: '1',
    items,
    meta: { page, pages: 2, total: 25, per_page: 20 },
  },
});
const fixture = () => {
  const accountId = ref('1');
  const teamId = ref('4');
  const authority = ref('SYNTHETIC profile1');
  const onDenied = vi.fn();
  const onSaved = vi.fn();
  const onClose = vi.fn();
  let state;
  const wrapper = mount(
    defineComponent({
      setup() {
        state = useTeamSupervisionEditor({
          accountId,
          teamId,
          authority,
          onDenied,
          onSaved,
          onClose,
        });
        return () => null;
      },
    })
  );
  return {
    wrapper,
    state,
    accountId,
    teamId,
    authority,
    onDenied,
    onSaved,
    onClose,
  };
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.resetAllMocks();
  API.configurationRecord.mockResolvedValue(response());
  API.teamSupervisionCandidates.mockResolvedValue(options());
  API.saveTeamSupervision.mockImplementation((_account, _team, values) =>
    Promise.resolve(response(item(values, 'b'.repeat(64))))
  );
});

describe('native team supervision editor (transport fixtures, not persistence proof)', () => {
  it('loads metadata and candidates only after deliberate opening without manufacturing a principal', async () => {
    const { state } = fixture();
    expect(API.configurationRecord).not.toHaveBeenCalled();
    await state.open();
    expect(API.configurationRecord).toHaveBeenCalledWith(
      '1',
      'team_supervisions',
      '4'
    );
    expect(state.draft.value).toEqual({
      primary_account_user_id: null,
      additional_account_user_ids: [],
    });
    expect(API.teamSupervisionCandidates).toHaveBeenCalledWith('1', '4', {
      page: 1,
      per_page: 20,
      q: '',
    });
    expect(state.canSave.value).toBe(false);
    expect(API.saveTeamSupervision).not.toHaveBeenCalled();
  });

  it('requires explicit review and sends only the two selection fields and actual revision', async () => {
    const { state, onSaved } = fixture();
    await state.open();
    state.choosePrimary(person());
    state.chooseAdditional(person('8'), true);
    await state.save();
    expect(API.saveTeamSupervision).not.toHaveBeenCalled();
    state.review(true);
    expect(state.canSave.value).toBe(true);
    await state.save();
    expect(API.saveTeamSupervision).toHaveBeenCalledWith(
      '1',
      '4',
      {
        primary_account_user_id: '7',
        additional_account_user_ids: ['8'],
      },
      { expected_revision: 'a'.repeat(64) }
    );
    expect(onSaved).toHaveBeenCalledOnce();
    expect(state.reviewed.value).toBe(false);
  });

  it('keeps primary and additional roles distinct without silently retaining a replaced primary as an additional', async () => {
    const { state } = fixture();
    await state.open();
    state.chooseAdditional(person(), true);
    state.choosePrimary(person());
    expect(state.draft.value.additional_account_user_ids).toEqual([]);
    state.review(true);
    state.choosePrimary(person('8'));
    expect(state.draft.value).toEqual({
      primary_account_user_id: '8',
      additional_account_user_ids: [],
    });
    expect(state.reviewed.value).toBe(false);
    expect(API.saveTeamSupervision).not.toHaveBeenCalled();
  });

  it('retains selection and native names across independent candidate search and pagination', async () => {
    const { state } = fixture();
    await state.open();
    state.choosePrimary(person());
    state.query.value = 'SYNTHETIC page2';
    API.teamSupervisionCandidates.mockResolvedValueOnce(
      options([person('8')], 2)
    );
    await state.loadCandidates(2);
    expect(API.teamSupervisionCandidates).toHaveBeenLastCalledWith('1', '4', {
      page: 2,
      per_page: 20,
      q: 'SYNTHETIC page2',
    });
    expect(state.candidates.value.map(row => row.account_user_id)).toEqual([
      '8',
    ]);
    expect(state.presentation.value.primary_supervisor).toBe(person().name);
    expect(state.draft.value.primary_account_user_id).toBe('7');
  });

  it('uses exact bigint strings and numeric ordering without a lossy Number conversion', async () => {
    const { state } = fixture();
    await state.open();
    state.chooseAdditional(person('9007199254740993'), true);
    state.chooseAdditional(person('10'), true);
    state.chooseAdditional(person('2'), true);
    expect(state.draft.value.additional_account_user_ids).toEqual([
      '2',
      '10',
      '9007199254740993',
    ]);
  });

  it('deduplicates an in-flight save and refuses edits until its result is known', async () => {
    let finish;
    API.saveTeamSupervision.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { state, onSaved } = fixture();
    await state.open();
    state.choosePrimary(person());
    state.review(true);
    const first = state.save();
    await state.save();
    state.choosePrimary(person('8'));
    state.chooseAdditional(person('8'), true);
    expect(API.saveTeamSupervision).toHaveBeenCalledOnce();
    expect(state.draft.value.primary_account_user_id).toBe('7');
    finish(response(item({ primary_account_user_id: '7' }, 'b'.repeat(64))));
    await first;
    expect(onSaved).toHaveBeenCalledOnce();
  });

  it.each(['accountId', 'teamId', 'authority'])(
    'forgets private metadata and ignores a late read after changing %s',
    async field => {
      let finish;
      API.configurationRecord.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const context = fixture();
      const pending = context.state.open();
      context[field].value = 'SYNTHETIC changed context';
      finish(response(item({ primary_account_user_id: '7' })));
      await pending;
      expect(context.state.selected.value).toBeNull();
      expect(context.state.known.value).toEqual({});
      expect(context.state.canSave.value).toBe(false);
      expect(context.onClose).toHaveBeenCalledOnce();
    }
  );

  it('ignores a late candidate page from a previous search', async () => {
    let finish;
    const { state } = fixture();
    await state.open();
    API.teamSupervisionCandidates.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const older = state.loadCandidates(1);
    API.teamSupervisionCandidates.mockResolvedValueOnce(
      options([person('8')], 2)
    );
    await state.loadCandidates(2);
    finish(options([person('7')], 1));
    await older;
    expect(state.candidates.value.map(row => row.account_user_id)).toEqual([
      '8',
    ]);
    expect(state.meta.value.page).toBe(2);
  });

  it.each([401, 403, 404])(
    'clears all private state on a native denied %s candidate response',
    async status => {
      const { state, onDenied } = fixture();
      await state.open();
      state.choosePrimary(person());
      API.teamSupervisionCandidates.mockRejectedValueOnce({
        response: { status },
      });
      await state.loadCandidates();
      expect(onDenied).toHaveBeenCalledOnce();
      expect(state.selected.value).toBeNull();
      expect(state.candidates.value).toEqual([]);
      expect(state.known.value).toEqual({});
      expect(API.saveTeamSupervision).not.toHaveBeenCalled();
    }
  );

  it('retains a deliberate selection during a recoverable candidate lookup failure without sending it', async () => {
    const { state } = fixture();
    await state.open();
    state.choosePrimary(person());
    API.teamSupervisionCandidates.mockRejectedValueOnce(
      new Error('SYNTHETIC read failure')
    );
    await state.loadCandidates();
    expect(state.candidateError.value).toBe(true);
    expect(state.draft.value.primary_account_user_id).toBe('7');
    expect(API.saveTeamSupervision).not.toHaveBeenCalled();
    await state.loadCandidates();
    expect(state.candidateError.value).toBe(false);
  });

  it.each([
    { account_id: '2', item: item() },
    { account_id: '1', item: { ...item(), id: '5' } },
    { account_id: '1', item: { ...item(), revision: null } },
  ])(
    'rejects a wrong source identity or missing revision without opening an editable record: %j',
    async data => {
      API.configurationRecord.mockResolvedValueOnce({ data });
      const { state } = fixture();
      await state.open();
      expect(state.selected.value).toBeNull();
      expect(state.error.value).toBe('LOAD_ERROR');
      expect(state.canSave.value).toBe(false);
      expect(API.teamSupervisionCandidates).not.toHaveBeenCalled();
    }
  );

  it('blocks retaining an unavailable saved supervisor but permits explicit removal with fresh review', async () => {
    const record = item({ primary_account_user_id: '7' });
    record.supervisors[0].eligible = false;
    API.configurationRecord.mockResolvedValueOnce(response(record));
    API.teamSupervisionCandidates.mockResolvedValueOnce(
      options([person('7', { eligible: false })])
    );
    const { state } = fixture();
    await state.open();
    state.review(true);
    expect(state.canSave.value).toBe(false);
    state.draft.value.primary_account_user_id = null;
    state.review(true);
    expect(state.canSave.value).toBe(true);
    await state.save();
    expect(
      API.saveTeamSupervision.mock.calls[0][2].primary_account_user_id
    ).toBeNull();
  });

  it('rejects an unavailable additional choice without dropping other selections', async () => {
    const { state } = fixture();
    await state.open();
    state.chooseAdditional(person('8'), true);
    state.choosePrimary(person('7', { eligible: false }));
    state.chooseAdditional(person('9', { eligible: false }), true);
    expect(state.draft.value).toEqual({
      primary_account_user_id: null,
      additional_account_user_ids: ['8'],
    });
  });

  it('keeps draft edits on a definite native eligibility refusal and requires another explicit review', async () => {
    const { state } = fixture();
    await state.open();
    state.choosePrimary(person());
    state.review(true);
    API.saveTeamSupervision.mockRejectedValueOnce({
      response: { status: 422, data: { error: 'ineligible_team_supervisor' } },
    });
    await state.save();
    expect(state.error.value).toBe('INELIGIBLE');
    expect(state.draft.value.primary_account_user_id).toBe('7');
    expect(state.reviewed.value).toBe(false);
    expect(state.canSave.value).toBe(false);
    expect(API.saveTeamSupervision).toHaveBeenCalledOnce();
  });

  it('retains edits on a real revision conflict, reloads the server and requires explicit comparison', async () => {
    const { state } = fixture();
    await state.open();
    state.choosePrimary(person());
    state.review(true);
    API.saveTeamSupervision.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    await state.save();
    expect(state.revision.state.conflict).toBe(true);
    expect(state.draft.value.primary_account_user_id).toBe('7');
    API.configurationRecord.mockResolvedValueOnce(
      response(item({ primary_account_user_id: '8' }, 'b'.repeat(64)))
    );
    await state.reload();
    expect(state.revision.state.latest.primary_account_user_id).toBe('8');
    expect(state.canSave.value).toBe(false);
    state.review(true);
    expect(state.canSave.value).toBe(true);
    state.useServer();
    expect(state.draft.value.primary_account_user_id).toBe('8');
    expect(state.reviewed.value).toBe(false);
  });

  it('does not blindly repeat an uncertain write and permits recovery only after a real server read', async () => {
    const { state } = fixture();
    await state.open();
    state.choosePrimary(person());
    state.review(true);
    API.saveTeamSupervision.mockRejectedValueOnce(
      new Error('SYNTHETIC transport failure')
    );
    await state.save();
    expect(state.uncertain.value).toBe(true);
    await state.save();
    expect(API.saveTeamSupervision).toHaveBeenCalledOnce();
    API.configurationRecord.mockResolvedValueOnce(
      response(item({ primary_account_user_id: '7' }, 'b'.repeat(64)))
    );
    await state.reload();
    expect(state.uncertain.value).toBe(false);
    expect(state.error.value).toBe('');
    expect(state.canSave.value).toBe(false);
  });

  it('ignores a late save result after switching profile instead of resurrecting private data', async () => {
    let finish;
    const { state, authority, onSaved } = fixture();
    await state.open();
    state.choosePrimary(person());
    state.review(true);
    API.saveTeamSupervision.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const pending = state.save();
    authority.value = 'SYNTHETIC restricted profile';
    finish(response(item({ primary_account_user_id: '7' }, 'b'.repeat(64))));
    await pending;
    expect(onSaved).not.toHaveBeenCalled();
    expect(state.selected.value).toBeNull();
    expect(state.known.value).toEqual({});
  });

  it('rejects malformed pagination rather than passing an undefined count to the popup', async () => {
    API.teamSupervisionCandidates.mockResolvedValueOnce({
      data: { account_id: '1', items: [person()] },
    });
    const { state } = fixture();
    await state.open();
    expect(state.candidateError.value).toBe(true);
    expect(state.candidates.value).toEqual([]);
    expect(state.meta.value).toEqual({ page: 1, pages: 0, total: 0 });
  });

  it('clears stale pending reads on unmount without firing another request', async () => {
    let finish;
    API.configurationRecord.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { state, wrapper, onSaved } = fixture();
    const pending = state.open();
    wrapper.unmount();
    finish(response(item({ primary_account_user_id: '7' })));
    await pending;
    expect(onSaved).not.toHaveBeenCalled();
    expect(API.teamSupervisionCandidates).not.toHaveBeenCalled();
  });
});
