import { describe, expect, it } from 'vitest';
import {
  createIntegratedGuard,
  landingScreen,
  screenAccessible,
} from '../helpers/nativeIntegration';
import { decodeContext } from '../helpers/contracts';
import { SERVICE_DESK_ROUTES } from '../routeDefinitions';
import { contextPayload, identity } from './fixtures';

const profile = (admin, agent) =>
  contextPayload({
    capabilities: {
      ...contextPayload().capabilities,
      settings: { index: admin },
      tickets: { index: agent },
      dashboard: { index: false },
    },
    units: contextPayload().units.map(unit => ({
      ...unit,
      permissions: { create_ticket: agent },
    })),
  });
const definition = key => SERVICE_DESK_ROUTES.find(route => route.key === key);
const administrative = SERVICE_DESK_ROUTES.filter(route =>
  route.path.startsWith('settings')
);
const guardFor = payload =>
  createIntegratedGuard(
    {
      getters: {
        getCurrentUserID: identity.userId,
        'accounts/isFeatureEnabledonAccount': () => true,
      },
    },
    async id => ({ id, features: { jrc_service_desk: true } }),
    async () => payload
  );

describe('Service Desk administration and operation stay independent', () => {
  it.each([
    [true, false, 'settings'],
    [false, true, 'tickets'],
    [true, true, 'tickets'],
  ])(
    'admin=%s agent=%s: menu follows backend capabilities',
    (admin, agent, landing) => {
      const context = decodeContext(profile(admin, agent), identity);
      expect(landingScreen(context)).toBe(landing);
      ['tickets', 'mine', 'detail', 'edit', 'new'].forEach(key => {
        expect(screenAccessible(context, definition(key))).toBe(agent);
      });
      administrative.forEach(route =>
        expect(screenAccessible(context, route)).toBe(admin)
      );
    }
  );

  it.each(administrative)(
    'blocks agent deep link $path despite operational lookup access',
    async route => {
      const guard = guardFor(profile(false, true));
      const result = await guard({
        params: { accountId: '1' },
        meta: { serviceDeskScreen: route.key },
      });
      expect(result.name).toBe('jrc_service_desk_denied');
    }
  );

  it('permits authorized admin settings but denies tickets and My Queue', async () => {
    const guard = guardFor(profile(true, false));
    expect(
      await guard({
        params: { accountId: '1' },
        meta: { serviceDeskScreen: 'settings' },
      })
    ).toBe(true);
    expect(
      (
        await guard({
          params: { accountId: '1' },
          meta: { serviceDeskScreen: 'mine' },
        })
      ).name
    ).toBe('jrc_service_desk_denied');
  });

  it('keeps unit membership and explicit authority mandatory', () => {
    [profile(false, false), { ...profile(true, true), units: [] }].forEach(
      payload => {
        const context = decodeContext(payload, identity);
        expect(screenAccessible(context, definition('tickets'))).toBe(false);
        expect(screenAccessible(context, definition('settings'))).toBe(false);
      }
    );
  });
});
