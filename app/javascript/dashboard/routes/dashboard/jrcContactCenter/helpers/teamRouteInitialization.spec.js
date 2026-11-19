import { describe, expect, it, vi } from 'vitest';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import teamRoutes from 'dashboard/routes/dashboard/settings/teams/teams.routes';

const { initialized } = vi.hoisted(() => ({ initialized: [] }));

vi.mock('dashboard/routes/dashboard/settings/teams/Index.vue', () => ({
  default: {},
}));
vi.mock('dashboard/routes/dashboard/settings/teams/Create/Index.vue', () => ({
  default: {},
}));
vi.mock('dashboard/routes/dashboard/settings/teams/Edit/Index.vue', () => ({
  default: {},
}));
vi.mock('dashboard/routes/dashboard/settings/teams/FinishSetup.vue', () => ({
  default: {},
}));
vi.mock('dashboard/routes/dashboard/settings/Wrapper.vue', () => ({
  default: {},
}));
vi.mock('dashboard/routes/dashboard/settings/SettingsWrapper.vue', () => ({
  default: {},
}));
vi.mock(
  'dashboard/routes/dashboard/settings/teams/Create/CreateTeam.vue',
  () => {
    initialized.push('create');
    return { default: { name: 'CreateTeam' } };
  }
);
vi.mock('dashboard/routes/dashboard/settings/teams/Edit/EditTeam.vue', () => {
  initialized.push('edit');
  return { default: { name: 'EditTeam' } };
});
vi.mock(
  'dashboard/routes/dashboard/settings/teams/Create/AddAgents.vue',
  () => {
    initialized.push('addAgents');
    return { default: { name: 'AddAgents' } };
  }
);
vi.mock('dashboard/routes/dashboard/settings/teams/Edit/EditAgents.vue', () => {
  initialized.push('editAgents');
  return { default: { name: 'EditAgents' } };
});

const descendants = routes =>
  routes.flatMap(route => [route, ...descendants(route.children || [])]);

describe('native Team route initialization', () => {
  it('defers router-dependent forms and preserves their exact native access metadata', async () => {
    expect(initialized).toEqual([]);
    const routes = descendants(teamRoutes.routes);
    const expected = [
      ['settings_teams_new', 'CreateTeam'],
      ['settings_teams_edit', 'EditTeam'],
      ['settings_teams_add_agents', 'AddAgents'],
      ['settings_teams_edit_members', 'EditAgents'],
    ];
    await Promise.all(
      expected.map(async ([name, component]) => {
        const route = routes.find(candidate => candidate.name === name);
        expect(route.meta).toEqual({
          featureFlag: FEATURE_FLAGS.TEAM_MANAGEMENT,
          permissions: ['administrator'],
        });
        expect(typeof route.component).toBe('function');
        expect((await route.component()).default.name).toBe(component);
      })
    );
    expect(initialized.toSorted()).toEqual([
      'addAgents',
      'create',
      'edit',
      'editAgents',
    ]);
  });
});
