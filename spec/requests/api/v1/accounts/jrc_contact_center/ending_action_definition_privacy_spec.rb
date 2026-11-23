require 'rails_helper'
require 'stringio'

# Prepared, unapplied and unexecuted. Existing authenticated APIs and the real native SQL logger are required.
RSpec.describe 'Ending rule private definitions at native serialization and logging boundaries', type: :request do
  include_context 'with native ending rule configuration'

  let(:headers) { actor.create_new_auth_token }

  def secret_marker
    'SYNTHETIC_PRIVATE_TEMPLATE_7f19'
  end

  def capture_ending_version_sql
    previous = ActiveRecord::Base.logger
    output = StringIO.new
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    yield
    output.string
  ensure
    ActiveRecord::Base.logger = previous
  end

  it 'exposes only the random revision head through an actual authenticated Account response' do
    configure_native_ending_rule
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    get "/api/v1/accounts/#{account.id}", headers: headers
    expect(response).to have_http_status(:ok)
    head = response.parsed_body.fetch('settings').fetch(JrcContactCenter::AcwPolicy::KEY).fetch('voice_ending_automations')
    expect(head).to eq('version' => 1, 'nonce' => version.head_nonce)
    expect(response.body).not_to include(secret_marker, 'private_definition', version.definition_sha256)
    expect(version.definition.fetch('entries').first.fetch('actions').first.fetch('parameters').fetch('attributes').fetch('title'))
      .to eq(secret_marker)
  end

  it 'keeps the actual native configuration audit readable under its dedicated permission without returning private content' do
    configure_native_ending_rule
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    account.enable_features!('custom_roles', 'audit_logs')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit])
    member.update!(custom_role: role)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits/#{version.source_audit_id}", headers: headers
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('item')
    expect(item.fetch('id')).to eq(version.source_audit_id)
    expect(item.fetch('after').fetch('voice_ending_automations')).to eq('version' => 1, 'nonce' => version.head_nonce)
    expect(response.body).not_to include(secret_marker, 'private_definition', version.definition_sha256)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'filters the private native INSERT bind while retaining actual SQL diagnostics and the persisted private template' do
    input = rule_input
    log = capture_ending_version_sql { configure_native_ending_rule(input) }
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    expect(log).to include('INSERT INTO', 'jrc_contact_center_ending_action_versions', '[FILTERED]')
    expect(log).not_to include(secret_marker, version.definition_sha256)
    expect(version.definition.fetch('entries').first.fetch('actions').first.fetch('parameters').fetch('attributes').fetch('title'))
      .to eq(secret_marker)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'preserves the private history and head when the ordinary Account API receives an unpermitted automation override' do
    configure_native_ending_rule
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    original = account.reload.settings.deep_dup
    parameters = { jrc_contact_center_acw: { voice_ending_automations: { version: 2, nonce: SecureRandom.uuid } } }
    patch "/api/v1/accounts/#{account.id}", headers: headers, as: :json, params: parameters
    expect(response).to have_http_status(:ok)
    expect(account.reload.settings).to eq(original)
    expect(JrcContactCenter::EndingActions::Catalogue.new(account: account).call).to eq(version.definition)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)).to eq([version.id])
    expect(response.body).not_to include(secret_marker, 'private_definition', version.definition_sha256)
  end

  it 'uses a filtered prepared bind for the private rule identity when looking for a deactivation barrier' do
    input = rule_input.merge('code' => 'SYNTHETIC_PRIVATE_RULE_CODE_7f19')
    configure_native_ending_rule(input)
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    configure_native_ending_rule(input.merge('active' => false))
    result = nil
    log = capture_ending_version_sql do
      result = JrcContactCenter::EndingActions::BlockingRevision.new(account: account, version_id: version.id, rule_code: input.fetch('code')).call
    end
    expect(result).to eq(2)
    expect(log).to include('EndingActionPendingHistory', '[FILTERED]')
    expect(log).not_to include(input.fetch('code'), secret_marker, version.definition_sha256)
    expect(version.reload.definition.fetch('entries').first.fetch('active')).to be(true)
  end
end
