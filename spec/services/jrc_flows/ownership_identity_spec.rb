require 'rails_helper'
require 'tmpdir'
require 'openssl'

RSpec.describe JrcFlows::OwnershipIdentity do
  let(:source) { 'a' * 40 }
  let(:payload) do
    observed = (sql_now - 1.second).utc.iso8601(6)
    hash = Digest::SHA256.hexdigest(@guard_bytes)
    { 'hostSourceSha' => source, 'hostImageDigest' => image, 'guardManifestSha256' => hash,
      'observationNonce' => 'n' * 43, 'observedAt' => observed, 'expiresAt' => (sql_now + 1.minute).utc.iso8601(6),
      'workers' => %w[rails worker].each_with_index.map do |role, index|
        { 'containerId' => (index + 1).to_s * 64, 'pid' => 1, 'processStartTicks' => '100', 'role' => role,
          'imageDigest' => image, 'guardManifestSha256' => hash, 'observedAt' => observed, 'observed' => true }
      end }
  end
  let(:image) { 'sha256:' + ('b' * 64) }
  let(:request_tuple) { { 'expectedHostSourceSha' => source, 'expectedHostImageDigest' => image } }
  let(:signing_key) { OpenSSL::PKey.generate_key('ED25519') }
  let(:sql_now) { ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time }
  let(:original_root) { Rails.root }
  let(:guard_paths) { JrcFlows::OwnershipGuard::PATHS }

  around do |example|
    Dir.mktmpdir('jrc-ownership-identity-') do |temporary|
      @proof_root = Pathname.new(temporary)
      guard_paths.each_value do |relative|
        target = @proof_root.join(relative)
        FileUtils.mkdir_p(target.dirname)
        File.binwrite(target, File.binread(original_root.join(relative)))
      end
      @guard_bytes = JSON.generate({ 'paths' => guard_paths.keys, 'files' => guard_paths.values.index_with do |file|
        Digest::SHA256.file(@proof_root.join(file)).hexdigest
      end })
      FileUtils.mkdir_p(@proof_root.join('config'))
      File.write(@proof_root.join('config/jrc_flow_ownership_guards.json'), @guard_bytes)
      File.write(@proof_root.join('jrc_flow_ownership_attestation_public.pem'), signing_key.public_to_pem, perm: 0o644)
      with_modified_env(JRC_FLOW_OWNERSHIP_ATTESTATION_DIR: temporary) { example.run }
    end
  end

  before { allow(Rails).to receive(:root).and_return(@proof_root) }

  def publish_fixture(value)
    signature = Base64.strict_encode64(signing_key.sign(nil, JSON.generate(value)))
    File.write(@proof_root.join('jrc_flow_ownership_attestation.json'), JSON.generate({ payload: value, signature: signature }), perm: 0o644)
  end

  it 'accepts a signed short observation from an external read-only-mounted directory' do
    publish_fixture(payload)
    expect(described_class.verify!(request_tuple)).to eq(source: source, image: image, paths: guard_paths.keys)
  end

  it 'does not trust a legacy application-owned proof when the external observation is absent' do
    publish_fixture(payload)
    FileUtils.cp(@proof_root.join('jrc_flow_ownership_attestation.json'), @proof_root.join('config/jrc_flow_ownership_attestation.json'))
    FileUtils.cp(@proof_root.join('jrc_flow_ownership_attestation_public.pem'), @proof_root.join('config/jrc_flow_ownership_attestation_public.pem'))
    File.unlink(@proof_root.join('jrc_flow_ownership_attestation.json'))
    expect { described_class.verify!(request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
  end

  it 'rejects a signed self-declaration without measured Rails and worker processes' do
    payload['workers'] = [{ 'imageDigest' => image, 'guardManifestSha256' => payload['guardManifestSha256'], 'observed' => true }]
    publish_fixture(payload)
    expect { described_class.verify!(request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
  end

  it 'rejects an expired signed observation using the SQL clock' do
    payload['observedAt'] = (sql_now - 2.minutes).utc.iso8601(6)
    payload['expiresAt'] = (sql_now - 1.second).utc.iso8601(6)
    publish_fixture(payload)
    expect { described_class.verify!(request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
  end

  it 'rejects a changed installed guard file even under a valid signature' do
    publish_fixture(payload)
    File.write(@proof_root.join(guard_paths.values.first), '# replaced')
    expect { described_class.verify!(request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
  end

  it 'rejects a signature altered after the external observation' do
    publish_fixture(payload)
    proof = JSON.parse(File.read(@proof_root.join('jrc_flow_ownership_attestation.json')))
    proof['payload']['hostSourceSha'] = 'f' * 40
    File.write(@proof_root.join('jrc_flow_ownership_attestation.json'), JSON.generate(proof))
    expect { described_class.verify!(request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
  end

  it 'rejects an absent observation nonce, a missing role and duplicate process identities' do
    mutations = [
      ->(value) { value.delete('observationNonce') },
      ->(value) { value['workers'].pop },
      ->(value) { value['workers'] << value['workers'].first.deep_dup },
      ->(value) { value['workers'].first['processStartTicks'] = 'unknown' },
      ->(value) { value['workers'].first['observedAt'] = (sql_now + 1.minute).utc.iso8601(6) }
    ]
    mutations.each do |mutate|
      value = payload.deep_dup
      mutate.call(value)
      publish_fixture(value)
      expect { described_class.verify!(request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
    end
  end

  it 'rejects a guard file whose ancestor symlink resolves outside the installed artifact' do
    publish_fixture(payload)
    Dir.mktmpdir('jrc-ownership-escaped-') do |escaped|
      FileUtils.mv(@proof_root.join('app'), File.join(escaped, 'app'))
      File.symlink(File.join(escaped, 'app'), @proof_root.join('app'))
      expect { described_class.verify!(request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
    end
  end
end
