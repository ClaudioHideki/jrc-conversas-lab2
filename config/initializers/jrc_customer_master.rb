# Optional injectable provider. Keep nil unless a reviewed adapter with bounded
# timeouts, fixed allowed host and per-account credentials is explicitly installed.
# Never accept provider URLs or credentials from browser requests.
Rails.application.config.x.jrc_customer_master.tax_lookup_provider = nil
