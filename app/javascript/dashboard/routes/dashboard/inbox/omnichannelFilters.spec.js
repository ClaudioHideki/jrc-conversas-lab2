import { describe, expect, it } from 'vitest';
import {
  ASSIGNEE_FILTERS,
  canManageAssigneeFilters,
  assigneeFilterOptions,
  resolveAssigneeFilter,
} from './omnichannelFilters';

describe('omnichannel inbox assignee filters', () => {
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
