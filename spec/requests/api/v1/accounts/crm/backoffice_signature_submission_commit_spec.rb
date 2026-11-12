require 'rails_helper'
require 'timeout'

# Real commits and independent PostgreSQL visibility, not transactional-fixture
# evidence. Only the local job broker failure is simulated; no provider I/O.
RSpec.describe 'Backoffice committed signature submission', :approval_core, :authority_core, :signature_delivery_core, type: :request do
  self.use_transactional_tests = false
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:domain) { authority_domain(account, actor) }
  let(:legal) { signature_legal_context(domain) }
  let(:connection) { synthetic_delivery_connection(account) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{domain[:operation].id}/contract_signatures" }
  let(:input) do
    { version_id: legal[:version].id, authority_proposal_id: legal[:proposal].id, expected_connection_id: connection.id,
      expected_source_digest: legal[:version].source_digest, idempotency_key: SecureRandom.uuid }
  end

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Owned committed submission database required' unless Rails.env.test? && config.database == 'jrc_four_domains_schema_admission_test' &&
                                                                config.host == 'jrc-rel-v2-pg-20261101'

    input
    role = create(:custom_role, account: account, permissions: %w[jrc_crm jrc_approvals_request_create])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    clear_enqueued_jobs
  end

  it 'exposes the committed intent to another PostgreSQL connection before publishing its job' do
    expect(JrcBackoffice::SignatureDispatchJob).to receive(:perform_later).and_wrap_original do |method, id|
      expect(ApplicationRecord.connection.transaction_open?).to be(false)
      visible = Timeout.timeout(15) do
        Thread.new do
          ApplicationRecord.connection_pool.with_connection do |sql|
            sql.select_value("SELECT COUNT(*) FROM jrc_backoffice_signature_deliveries WHERE id=#{id}").to_i
          end
        end.value
      end
      expect(visible).to eq(1)
      method.call(id)
    end
    post url, headers: headers, params: { signature_delivery: input }
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to include('state' => 'prepared', 'external_id' => nil)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'preserves the committed intent on broker failure and reuses it when the same confirmation is retried' do
    allow(JrcBackoffice::SignatureDispatchJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, 'synthetic local broker failure')
    # Native test configuration renders uncaught errors as HTTP 500. Assert
    # the public failure response and independently verify the committed row.
    post url, headers: headers, params: { signature_delivery: input }
    expect(response).to have_http_status(:internal_server_error)
    record = JrcBackoffice::SignatureDelivery.find_by!(account: account, created_by: actor, idempotency_key: input[:idempotency_key])
    expect(record.state).to eq('prepared')
    allow(JrcBackoffice::SignatureDispatchJob).to receive(:perform_later).and_call_original
    expect { post url, headers: headers, params: { signature_delivery: input } }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.fetch('id')).to eq(record.id)
    expect(record.events.pluck(:kind)).to eq(['prepared'])
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end
end
