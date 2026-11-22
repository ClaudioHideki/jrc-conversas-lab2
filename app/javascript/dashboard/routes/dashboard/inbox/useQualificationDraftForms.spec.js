import { ref } from 'vue';
import { describe, expect, it } from 'vitest';
import { useQualificationDraft } from './useQualificationDraft';

const fixture = () => {
  const reason = ref('');
  const result = ref('');
  const note = ref('');
  const formAnswers = ref({});
  return {
    reason,
    result,
    note,
    formAnswers,
    draft: useQualificationDraft({ reason, result, note, formAnswers }),
  };
};
const record = (
  revision = 'synthetic-first',
  answers = { rule: { verified: false, quantity: 0 } }
) => ({
  id: 12,
  reason_code: 'order',
  outcome_code: '',
  notes: '',
  draft_revision: revision,
  acw_form_context: { selected: null, answers },
});

describe('Private native ACW answers in the existing manual revision', () => {
  it('preserves local answers but refuses to reapply a reason fixed by another confirmed revision', () => {
    const f = fixture();
    f.draft.observe(record());
    f.reason.value = 'local-provisional';
    f.formAnswers.value.rule.quantity = 2;
    f.draft.observe({
      ...record('confirmed'),
      ending_reason_confirmation: { state: 'confirmed', reason_code: 'order' },
    });
    expect(f.draft.conflict.value).toBe(true);
    expect(f.draft.canReapply.value).toBe(false);
    expect(f.draft.reapply()).toBe(false);
    expect(f.reason.value).toBe('local-provisional');
    expect(f.formAnswers.value.rule.quantity).toBe(2);
  });

  it('permits an explicit reviewed reapplication of answers when the confirmed reason itself is unchanged', () => {
    const f = fixture();
    f.draft.observe(record());
    f.formAnswers.value.rule.quantity = 2;
    f.draft.observe({
      ...record('confirmed'),
      ending_reason_confirmation: { state: 'confirmed', reason_code: 'order' },
    });
    expect(f.draft.canReapply.value).toBe(true);
    expect(f.draft.reapply()).toBe(true);
    expect(f.reason.value).toBe('order');
    expect(f.formAnswers.value.rule.quantity).toBe(2);
  });

  it('hydrates typed values and ignores JSON key order when computing dirty state', () => {
    const f = fixture();
    f.draft.observe(record());
    expect(f.formAnswers.value).toEqual({
      rule: { verified: false, quantity: 0 },
    });
    f.formAnswers.value = { rule: { quantity: 0, verified: false } };
    expect(f.draft.dirty.value).toBe(false);
    f.formAnswers.value = { rule: { quantity: 1, verified: false } };
    expect(f.draft.dirty.value).toBe(true);
    expect(f.draft.canSave.value).toBe(true);
  });

  it('does not overwrite local responses on an unchanged clock observation', () => {
    const f = fixture();
    f.draft.observe(record());
    f.formAnswers.value.rule.quantity = 2;
    f.draft.observe({ ...record(), overdue: true, elapsed_seconds: 999 });
    expect(f.formAnswers.value.rule.quantity).toBe(2);
    expect(f.draft.conflict.value).toBe(false);
  });

  it('preserves local responses on conflicts until an explicit reviewed choice is made', () => {
    const f = fixture();
    f.draft.observe(record());
    f.formAnswers.value.rule.quantity = 2;
    f.draft.observe(
      record('synthetic-second', { rule: { quantity: 3, verified: true } })
    );
    expect(f.draft.conflict.value).toBe(true);
    expect(f.formAnswers.value.rule.quantity).toBe(2);
    expect(f.draft.reapply()).toBe(true);
    expect(f.draft.revision.value).toBe('synthetic-second');
    expect(f.formAnswers.value.rule.quantity).toBe(2);
    expect(f.draft.dirty.value).toBe(true);
  });

  it('loads the remote responses only after an explicit choice and does not mutate the received record', () => {
    const f = fixture();
    f.draft.observe(record());
    f.formAnswers.value.rule.quantity = 2;
    const remote = record('synthetic-second');
    f.draft.observe(remote);
    expect(f.draft.useRemote()).toBe(true);
    f.formAnswers.value.rule.quantity = 5;
    expect(remote.acw_form_context.answers.rule.quantity).toBe(0);
  });

  it('does not accept a pending draft receipt that lost its previously captured private form context', () => {
    const f = fixture();
    f.draft.observe(record());
    const submitted = f.draft.localValues();
    const withoutContext = { ...record('synthetic-second') };
    delete withoutContext.acw_form_context;
    expect(() => f.draft.accept(withoutContext, submitted)).toThrow(
      'Invalid native pending draft response'
    );
    expect(f.formAnswers.value.rule.verified).toBe(false);
  });

  it('keeps legacy manual arrays at three values and clears private responses on reset', () => {
    const f = fixture();
    f.draft.observe({ id: 12, reason_code: 'order', draft_revision: 'legacy' });
    expect(f.draft.localValues()).toEqual(['order', '', '']);
    f.draft.observe(record('new'));
    f.draft.reset();
    expect(f.formAnswers.value).toEqual({});
  });
});

describe('Draft confirmation reflects actual persisted content', () => {
  it.each([{}, { rule: {} }, { rule: { verified: null, detail: '' } }])(
    'does not announce a saved draft for a new attendance with no persisted manual content %j',
    answers => {
      const f = fixture();
      f.draft.observe({
        ...record('new', answers),
        reason_code: '',
        outcome_code: '',
        notes: '',
      });
      expect(f.draft.dirty.value).toBe(false);
      expect(f.draft.canSave.value).toBe(false);
      expect(f.draft.saved.value).toBe(false);
    }
  );
  it.each([{ rule: { verified: false } }, { rule: { quantity: 0 } }])(
    'keeps real persisted false/zero answers as saved content %j',
    answers => {
      const f = fixture();
      f.draft.observe({
        ...record('persisted', answers),
        reason_code: '',
        outcome_code: '',
        notes: '',
      });
      expect(f.draft.saved.value).toBe(true);
      expect(f.formAnswers.value).toEqual(answers);
      expect(f.draft.canSave.value).toBe(false);
    }
  );
});
