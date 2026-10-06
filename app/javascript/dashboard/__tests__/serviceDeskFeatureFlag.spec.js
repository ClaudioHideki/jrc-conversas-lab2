import { FEATURE_FLAGS, PREMIUM_FEATURES } from '../featureFlags';
import baseline from '../../../../spec/fixtures/jrc_service_desk/checkpoint1_feature_baseline.json';

describe('JRC Service Desk feature registration', () => {
  it('registers the independent Service Desk flag', () => {
    expect(FEATURE_FLAGS.JRC_SERVICE_DESK).toBe('jrc_service_desk');
  });

  it('preserves all existing feature identifiers and their order', () => {
    const existing = Object.entries(FEATURE_FLAGS).filter(
      // These flags were introduced after the frozen CP1 catalog. Legacy keys
      // must remain byte-for-byte compatible and in the same relative order.
      ([key]) =>
        ![
          'JRC_SERVICE_DESK',
          'JRC_CUSTOMER_MASTER',
          'JRC_RELATIONSHIP',
        ].includes(key)
    );
    expect(existing).toEqual(Object.entries(baseline.frontend_flags));
  });

  it('registers native Customer Master and Relationship with independent flags', () => {
    expect(FEATURE_FLAGS.JRC_CUSTOMER_MASTER).toBe('jrc_customer_master');
    expect(FEATURE_FLAGS.JRC_RELATIONSHIP).toBe('jrc_relationship');
  });

  it('does not alter the existing premium feature list', () => {
    expect(PREMIUM_FEATURES).toEqual(
      baseline.premium_features.map(key => FEATURE_FLAGS[key])
    );
  });
});
