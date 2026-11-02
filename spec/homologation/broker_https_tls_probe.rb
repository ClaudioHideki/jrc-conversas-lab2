# Loads the production SafeFetch implementation, not Rails or a transport double.
require 'json'
require 'openssl'
require 'tempfile'
require 'active_support/all'
require 'active_model'
require_relative 'broker_https_harness'

runtime = BrokerHttpsHarness.runtime!(ENV)
root = File.expand_path('../..', __dir__)
require File.join(root, 'lib/safe_fetch')
require File.join(root, 'lib/safe_fetch/request_options')
require File.join(root, 'lib/safe_fetch/private_network_request')
require File.join(root, 'lib/safe_fetch/fetcher')
abort 'SAFE_FETCH_MUST_BE_REAL' unless SafeFetch.method(:fetch).source_location.first == File.join(root, 'lib/safe_fetch.rb')
context = OpenSSL::SSL::SSLContext.new
context.set_params
abort 'TLS_PEER_VERIFICATION_REQUIRED' unless context.verify_mode == OpenSSL::SSL::VERIFY_PEER
mode = ARGV.fetch(0)
url = case mode
      when 'trusted', 'wrong-ca' then "#{runtime.fetch('origin')}/health"
      when 'wrong-hostname' then 'https://broker-https-lab.test:444/health'
      else abort 'UNKNOWN_TLS_PROBE'
      end
begin
  SafeFetch.fetch(url, method: :get, validate_content_type: false, max_bytes: 4096, open_timeout: 5, read_timeout: 5) { |_result| nil }
  abort 'TLS_NEGATIVE_PROBE_WAS_ACCEPTED' unless mode == 'trusted'

  puts JSON.generate(mode: mode, peer_verified: true, safe_fetch_source: 'lib/safe_fetch.rb')
rescue SafeFetch::FetchError => e
  # A timeout/refused connection must never be counted as a certificate rejection.
  raise unless mode != 'trusted' && e.cause.is_a?(OpenSSL::SSL::SSLError)

  puts JSON.generate(mode: mode, rejected_by_tls: true, cause_class: e.cause.class.name,
                     safe_fetch_source: 'lib/safe_fetch.rb', verify_peer: true)
end
