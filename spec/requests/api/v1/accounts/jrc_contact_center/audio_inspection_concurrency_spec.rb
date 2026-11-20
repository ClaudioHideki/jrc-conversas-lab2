require 'rails_helper'
require 'timeout'

RSpec.describe 'Institutional audio committed inspection concurrency', type: :request do
  self.use_transactional_tests = false

  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && config.database == 'corporate_gratuity_disposable'
    raise 'Exclusive committed synthetic audio inspection database required' unless owned && !ActiveRecord::Base.connection.transaction_open?
    raise 'Owned synthetic scanner required' unless ENV.fetch('JRC_CC_AUDIO_CLAMAV_SOCKET', '').start_with?('/run/jrc-cc-audio-')
  end

  include_context 'with an institutional audio receipt'

  let(:workers) { [] }
  let(:barriers) { { arrived: Queue.new, release: Queue.new, results: Queue.new } }
  let(:version) do
    JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                 .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC concurrent inspection' }, file: upload, key: key)
  end

  after do
    2.times { barriers.fetch(:release) << true }
    workers.each { |worker| worker.join(20) }
    raise 'Owned synthetic inspection worker still active' if workers.any?(&:alive?)

    # Preserve immutable rows and their bytes until disposal of this exclusively owned database/storage.
  end

  def start_native_inspections(keys)
    identifiers = { account: account.id, user: actor.id, account_user: member.id, asset: version.audio_asset_id, version: version.id }
    observation_barrier
    keys.each do |value|
      workers << Thread.new { execute_inspection_worker(identifiers, value) }
    end
    2.times { Timeout.timeout(25) { barriers.fetch(:arrived).pop } }
  end

  def observation_barrier
    # Scheduling instrumentation only: the actual scanner/decoder result is neither replaced nor fabricated.
    allow(JrcContactCenter::AudioSafetyObservation).to receive(:new).and_wrap_original do |constructor, **arguments|
      observation = constructor.call(**arguments)
      allow(observation).to receive(:call).and_wrap_original do |original, **selected|
        observed = original.call(**selected)
        barriers.fetch(:arrived) << true
        Timeout.timeout(20) { barriers.fetch(:release).pop }
        observed
      end
      observation
    end
  end

  def execute_inspection_worker(ids, value)
    ActiveRecord::Base.connection_pool.with_connection do
      scope = { account: Account.find(ids[:account]), user: User.find(ids[:user]), account_user: AccountUser.find(ids[:account_user]) }
      service = JrcContactCenter::AudioInspections.new(access: JrcContactCenter::AudioLibraryAccess.new(context: scope))
      barriers.fetch(:results) << service.create!(asset_id: ids[:asset], version_id: ids[:version], key: value)
    end
  rescue StandardError => e
    barriers.fetch(:results) << e
  end

  def finish_native_inspections
    2.times { barriers.fetch(:release) << true }
    Array.new(2) { Timeout.timeout(25) { barriers.fetch(:results).pop } }
  end

  it 'accepts exactly one observation and audit for simultaneous identical keys after actual native media IO' do
    start_native_inspections(['synthetic-inspection-race-key', 'synthetic-inspection-race-key'])
    outcomes = finish_native_inspections
    expect(outcomes.map(&:class)).to eq([JrcContactCenter::AudioInspection, JrcContactCenter::AudioInspection])
    expect(outcomes.map(&:id).uniq.length).to eq(1)
    expect(outcomes.map(&:ready?)).to eq([true, true])
    expect(JrcContactCenter::AudioInspection.where(account: account).count).to eq(1)
    audits = Audited.audit_class.where(auditable_type: 'JrcContactCenter::AudioInspection', auditable_id: outcomes.first.id, action: 'create')
    expect(audits.count).to eq(1)
  end

  it 'serializes deliberately distinct attempts without overwriting history or duplicating a version sequence' do
    start_native_inspections(%w[synthetic-inspection-race-key-1 synthetic-inspection-race-key-2])
    outcomes = finish_native_inspections
    expect(outcomes.map(&:class)).to eq([JrcContactCenter::AudioInspection, JrcContactCenter::AudioInspection])
    expect(outcomes.map(&:attempt).sort).to eq([1, 2])
    expect(outcomes.map(&:ready?)).to eq([true, true])
    expect(JrcContactCenter::AudioInspection.where(audio_version: version).order(:attempt).pluck(:attempt)).to eq([1, 2])
    expect(version.reload.blob.download).to eq(bytes)
  end

  it 'does not persist an earlier authorized observation after the profile is withdrawn before final commit' do
    start_native_inspections(%w[synthetic-inspection-race-key-1 synthetic-inspection-race-key-2])
    member.custom_role.update!(permissions: %w[jrc_contact_center_view])
    outcomes = finish_native_inspections
    expect(outcomes.map { |row| row.class.name }).to eq(%w[Pundit::NotAuthorizedError Pundit::NotAuthorizedError])
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(version.reload.blob.download).to eq(bytes)
  end
end
