import { describe, expect, it } from 'vitest';
import {
  ASSIGNEE_FILTERS,
  canManageAssigneeFilters,
  assigneeFilterOptions,
  resolveAssigneeFilter,
  matchesAssigneeFilter,
} from './omnichannelFilters';

describe('omnichannel inbox assignee filters', () => {
  it('treats an AgentBot assignment as lacking a human owner without exposing it as personal or shared work', () => {
    const conversation = {
      inbox_id: 8,
      meta: { assignee: { id: 42 }, assignee_type: 'AgentBot' },
    };
    expect(matchesAssigneeFilter(conversation, 'unassigned', 42)).toBe(true);
    expect(matchesAssigneeFilter(conversation, 'me', 42)).toBe(false);
    expect(matchesAssigneeFilter(conversation, 'mine_or_shared', 42, [8])).toBe(
      false
    );
    expect(matchesAssigneeFilter(conversation, 'all', 42)).toBe(true);
  });
  it('offers an additive shared filter only with a server capability', () => {
    expect(
      assigneeFilterOptions(false, true).map(option => option.key)
    ).toEqual(['mine_or_shared', 'me']);
    expect(resolveAssigneeFilter(undefined, false, true)).toBe(
      'mine_or_shared'
    );
    expect(resolveAssigneeFilter('mine_or_shared', false, false)).toBe('me');
  });

  it('matches shared inboxes including another assignee, while preserving own work and rejecting bots', () => {
    const shared = {
      inbox_id: 8,
      meta: { assignee: { id: 99 }, assignee_type: 'User' },
    };
    expect(matchesAssigneeFilter(shared, 'mine_or_shared', 42, [8])).toBe(true);
    expect(matchesAssigneeFilter(shared, 'mine_or_shared', 42, [])).toBe(false);
    expect(
      matchesAssigneeFilter(
        { ...shared, meta: { assignee: { id: 42 } } },
        'mine_or_shared',
        42,
        []
      )
    ).toBe(true);
    expect(
      matchesAssigneeFilter(
        {
          ...shared,
          meta: { assignee: { id: 99 }, assignee_type: 'AgentBot' },
        },
        'mine_or_shared',
        42,
        [8]
      )
    ).toBe(false);
    expect(matchesAssigneeFilter(shared, 'me', 42, [8])).toBe(false);
  });
  it.each([
    'conversation_participating_manage',
    'conversation_unassigned_manage',
  ])('does not grant full assignment management for %s', permission => {
    expect(
      canManageAssigneeFilters({
        role: 'agent',
        customRoleId: 4,
        permissions: [permission],
      })
    ).toBe(false);
  });

  it.each([
    'conversation_manage',
    'jrc_contact_center_supervise',
    'jrc_contact_center_configure',
  ])('allows assignment management for %s', permission => {
    expect(
      canManageAssigneeFilters({
        role: 'agent',
        customRoleId: 4,
        permissions: [permission],
      })
    ).toBe(true);
  });

  it('uses custom role permissions instead of an underlying administrator role', () => {
    expect(
      canManageAssigneeFilters({ role: 'administrator', customRoleId: 4 })
    ).toBe(false);
    expect(
      canManageAssigneeFilters({ role: 'administrator', customRoleId: null })
    ).toBe(true);
  });
  it('keeps ordinary agents restricted to their own assignments', () => {
    expect(assigneeFilterOptions(false).map(option => option.key)).toEqual([
      ASSIGNEE_FILTERS.ME,
    ]);
    expect(resolveAssigneeFilter(ASSIGNEE_FILTERS.ALL, false)).toBe(
      ASSIGNEE_FILTERS.ME
    );
  });

  it('allows authorized managers to select unassigned and all work', () => {
    expect(assigneeFilterOptions(true).map(option => option.key)).toEqual([
      ASSIGNEE_FILTERS.ME,
      ASSIGNEE_FILTERS.UNASSIGNED,
      ASSIGNEE_FILTERS.ALL,
    ]);
    expect(resolveAssigneeFilter(ASSIGNEE_FILTERS.ALL, true)).toBe(
      ASSIGNEE_FILTERS.ALL
    );
  });
});
