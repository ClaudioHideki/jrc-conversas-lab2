import { describe, expect, it } from 'vitest';
import {
  audiencesForMode,
  validInteractionFiles,
  visibleTimelineItems,
} from '../detailExperience';

const feed = Object.freeze(
  [
    {
      id: '1',
      kind: 'note',
      visibility: 'internal',
      body: 'Private diagnosis',
    },
    { id: '2', kind: 'note', visibility: 'technical_team', body: 'Team work' },
    { id: '3', kind: 'note', visibility: 'customer', body: 'Customer reply' },
    {
      id: '4',
      kind: 'note',
      visibility: 'public_without_notification',
      body: 'Portal update',
    },
    {
      id: '5',
      kind: 'message',
      private: true,
      visibility: 'internal',
      body: 'Private native message',
    },
    {
      id: '6',
      kind: 'message',
      private: false,
      visibility: 'customer',
      body: 'Incoming customer message',
    },
    { id: '7', kind: 'delivery', state: 'delivered' },
    { id: '8', kind: 'call', recordings: [{ id: '80' }] },
    { id: '9', kind: 'event', event_type: 'status_changed' },
    { id: '10', kind: 'task', title: 'Follow up' },
    {
      id: '11',
      kind: 'note',
      visibility: 'internal',
      attachments: [{ id: '81' }],
    },
  ].map(Object.freeze)
);

describe('Service Desk detail separates audiences and resources', () => {
  it('keeps internal writing within the private audiences granted by the server', () => {
    const granted = Object.freeze([
      'customer',
      'technical_team',
      'public_without_notification',
    ]);
    expect(audiencesForMode(granted, 'internal')).toEqual(['technical_team']);
    expect(audiencesForMode(['internal'], 'conversation')).toEqual([]);
    expect(granted).toEqual([
      'customer',
      'technical_team',
      'public_without_notification',
    ]);
  });

  it('offers only granted public audiences for replies and never sends notifications from file mode', () => {
    const granted = ['internal', 'customer', 'public_without_notification'];
    expect(audiencesForMode(granted, 'conversation')).toEqual([
      'customer',
      'public_without_notification',
    ]);
    expect(audiencesForMode(granted, 'files')).toEqual([
      'internal',
      'public_without_notification',
    ]);
    expect(audiencesForMode(['technical_team'], 'all')).toEqual([
      'technical_team',
    ]);
  });

  it('shows private notes without merging native private messages or public replies', () => {
    const visible = visibleTimelineItems(feed, 'notes');
    expect(visible.map(row => row.id)).toEqual(['1', '2', '11']);
    expect(visible.some(row => row.body === 'Customer reply')).toBe(false);
  });

  it('keeps internal notes and private native messages out of the conversation feed', () => {
    const visible = visibleTimelineItems(feed, 'conversations');
    expect(visible.map(row => row.id)).toEqual(['3', '4', '6', '7', '8']);
    expect(JSON.stringify(visible)).not.toContain('Private diagnosis');
    expect(JSON.stringify(visible)).not.toContain('Private native message');
  });

  it('separates file-bearing sources from audit history while preserving source order', () => {
    expect(visibleTimelineItems(feed, 'files').map(row => row.id)).toEqual([
      '8',
      '11',
    ]);
    expect(visibleTimelineItems(feed, 'history').map(row => row.id)).toEqual([
      '9',
    ]);
    expect(visibleTimelineItems(feed, 'all')).toEqual(feed);
    expect(feed).toHaveLength(11);
  });

  it('accepts at most five nonempty files of at most 20 MB each', () => {
    const maximum = 20 * 1024 * 1024;
    expect(validInteractionFiles([])).toBe(true);
    expect(
      validInteractionFiles(
        Array.from({ length: 5 }, () => ({ size: maximum }))
      )
    ).toBe(true);
    expect(
      validInteractionFiles(Array.from({ length: 6 }, () => ({ size: 1 })))
    ).toBe(false);
    expect(validInteractionFiles([{ size: 0 }])).toBe(false);
    expect(validInteractionFiles([{ size: maximum + 1 }])).toBe(false);
  });
});
