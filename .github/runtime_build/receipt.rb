# frozen_string_literal: true
# Identity/persistence contract shared by the isolated worker and its verifier.
require 'json'
module RuntimeSmokeReceipt
  def self.build(product_sha:, nonce:, pid:)
    data = { 'product_sha' => product_sha, 'nonce' => nonce, 'pid' => pid }
    verify!(data: data, persisted: data, product_sha: product_sha, nonce: nonce)
    data
  end

  def self.verify!(data:, persisted:, product_sha:, nonce:)
    raise 'Invalid expected source' unless product_sha.is_a?(String) && product_sha.match?(/\A[0-9a-f]{40}\z/)
    raise 'Invalid expected nonce' unless nonce.is_a?(String) && nonce.match?(/\A[0-9a-f]{32}\z/)
    raise 'Worker receipt is not an object' unless data.is_a?(Hash)
    raise 'Wrong worker identity' unless data.keys.sort == %w[nonce pid product_sha] &&
                                         data['product_sha'] == product_sha && data['nonce'] == nonce
    raise 'Invalid worker PID' unless data['pid'].instance_of?(Integer) && data['pid'].positive?
    raise 'Real database persistence missing or inconsistent' unless persisted.is_a?(Hash) && persisted == data
    true
  end
end
