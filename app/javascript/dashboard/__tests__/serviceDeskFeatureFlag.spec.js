import { FEATURE_FLAGS, PREMIUM_FEATURES } from '../featureFlags';
import baseline from '../../../../spec/fixtures/jrc_service_desk/checkpoint1_feature_baseline.json';

describe('JRC Service Desk feature registration', () => {
  it('registers the independent Service Desk flag', () => {
    expect(FEATURE_FLAGS.JRC_SERVICE_DESK).toBe('jrc_service_desk');
  });

  it('preserves all existing feature identifiers and their order', () => {
    const existing = Object.entries(FEATURE_FLAGS).filter(
      ([key]) => key !== 'JRC_SERVICE_DESK'
    );
    expect(existing).toEqual(Object.entries(baseline.frontend_flags));
  });

  it('does not alter the existing premium feature list', () => {
    expect(PREMIUM_FEATURES).toEqual(
      baseline.premium_features.map(key => FEATURE_FLAGS[key])
    );
  });
});
