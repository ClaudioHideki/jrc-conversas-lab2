import { endingReasonSummary } from './endingReasonPresentation';

describe('native ending reason audit summary', () => {
  it('identifies the exact reviewed historical queue ids without inventing names from a current queue catalogue', () => {
    const result = endingReasonSummary(
      { version: 2, entries: [], required_queue_ids: ['21', '950'] },
      key => key
    );
    expect(result).toContain(
      'JRC_CONTACT_CENTER.ENDING_REASONS.REQUIRED_QUEUES: #21, #950'
    );
    expect(result).toContain('JRC_CONTACT_CENTER.ENDING_REASONS.VERSION 2');
  });

  it('preserves the old audit summary when queue enforcement was absent', () => {
    expect(endingReasonSummary({ version: 1, entries: [] }, key => key)).toBe(
      'JRC_CONTACT_CENTER.ENDING_REASONS.VERSION 1'
    );
  });
});
