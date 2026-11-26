# frozen_string_literal: true

# New disposable queue metadata only; no auth tokens or old test sessions copied.
require 'json'
require 'securerandom'
require_relative '../spec/integration/jrc_contact_center/owned_public_ending_queue'

owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test? &&
        ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_DATABASE'] == SyntheticPublicEndingQueue::DATABASE &&
        ApplicationRecord.connection.current_database == SyntheticPublicEndingQueue::DATABASE &&
        ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
raise 'Owned public ending queue preparation required' unless owned

session = JSON.parse(File.binread('/tmp/call-center-e2e-session.private'))
projects = %w[desktop-light desktop-dark mobile-light mobile-dark]
accounts = projects.map { |project| Integer(session.fetch('pause_targets').fetch(project).fetch('ending_operational').fetch('account_id')) }
raise 'Four unique synthetic accounts required' unless accounts.uniq.length == 4

nonce = SecureRandom.hex(12)
accounts.each do |id|
  account = Account.find(id)
  raise 'Expected new owned synthetic account' unless account.name.start_with?('SYNTHETIC ') &&
                                                     account.custom_attributes[SyntheticPublicEndingQueue::MARKER].nil?

  account.update!(custom_attributes: account.custom_attributes.merge(SyntheticPublicEndingQueue::MARKER => nonce))
end
control = { nonce: nonce, queue: "jrc_cc_public_#{nonce}", source_sha: ENV.fetch('GITHUB_SHA'), account_ids: accounts }
filename = "/tmp/jrc-cc-public-ending-#{nonce}.private"
File.open(filename, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.generate(control)) }
ENV['JRC_CC_PUBLIC_QUEUE_CONTROL'] = filename
SyntheticPublicEndingQueue.configuration!
File.write('/tmp/call-center-public-ending-control-path.txt', filename)
puts({ source_sha: control.fetch(:source_sha), account_count: accounts.length, queue_control_ready: true,
       no_provider_commands: true, no_other_queue_consumed: true }.to_json)
