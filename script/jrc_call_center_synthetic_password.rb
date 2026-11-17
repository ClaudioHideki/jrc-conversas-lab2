require 'securerandom'

module JrcCallCenterSyntheticPassword
  def self.generate
    "Aa1!#{SecureRandom.base64(32)}"
  end
end
