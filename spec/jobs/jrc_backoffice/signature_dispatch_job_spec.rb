require 'rails_helper'

RSpec.describe JrcBackoffice::SignatureDispatchJob, :approval_core, :authority_core, :signature_delivery_core, type: :job do
  self.use_transactional_tests = false
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:connection) { domain.fetch(:connection) }
  let(:external_id) { SecureRandom.uuid }
  let(:root) { "https://demo.docusign.net/restapi/v2.1/accounts/#{connection.external_account_id}" }

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Owned dispatch job database required' unless Rails.env.test? && config.database == 'jrc_four_domains_schema_admission_test' &&
                                                        config.host == 'jrc-rel-v2-pg-20261101'

    domain
    clear_enqueued_jobs
    stub_request(:post, 'https://account-d.docusign.com/oauth/token')
      .to_return(status: 200, body: { access_token: 'synthetic-dispatch-job-token', expires_in: 3600 }.to_json)
    stub_request(:get, 'https://account-d.docusign.com/oauth/userinfo')
      .to_return(status: 200, body: { sub: connection.impersonated_user_id,
                                      accounts: [{ account_id: connection.external_account_id, base_uri: 'https://demo.docusign.net' }] }.to_json)
  end

  it 'recovers a committed prepared admission after a lost enqueue and dispatches only once across duplicate jobs' do
    stub_request(:post, "#{root}/envelopes").to_return do
      expect(ApplicationRecord.connection.transaction_open?).to be(false)
      { status: 201, body: { envelopeId: external_id, status: 'sent' }.to_json }
    end
    expect { JrcBackoffice::SignatureDispatchRecoveryJob.perform_now }.to have_enqueued_job(described_class).with(delivery.id)
    2.times { described_class.perform_now(delivery.id) }
    expect(delivery.reload.state).to eq('sent')
    expect(delivery.external_id).to eq(external_id)
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
    clear_enqueued_jobs
    expect { JrcBackoffice::SignatureDispatchRecoveryJob.perform_now }.not_to have_enqueued_job(described_class).with(delivery.id)
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
  end

  it 'preserves an uncertain claim and does not resend it on queue retries or the prepared-intent sweeper' do
    stub_request(:post, "#{root}/envelopes").to_timeout
    2.times { described_class.perform_now(delivery.id) }
    expect(delivery.reload.state).to eq('uncertain')
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
    expect { JrcBackoffice::SignatureDispatchRecoveryJob.perform_now }.not_to have_enqueued_job(described_class).with(delivery.id)
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  it 'blocks the queued intent after coverage is revoked and never contacts the provider' do
    source = delivery.snapshot
    domain[:account].jrc_crm_user_business_units.where(user: domain[:actor]).each { |row| row.update!(active: false) }
    described_class.perform_now(delivery.id)
    expect(delivery.reload.state).to eq('blocked')
    expect(delivery.snapshot).to eq(source)
    expect(WebMock).not_to have_requested(:any, /docusign/)
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
  end

  it 'never dispatches a locally canceled prepared intent even when its old queued job runs' do
    JrcBackoffice::Signatures::Admissions.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id)
                                         .cancel_prepared!(delivery.id)
    described_class.perform_now(delivery.id)
    expect(delivery.reload.state).to eq('canceled')
    expect(WebMock).not_to have_requested(:any, /docusign/)
    expect { JrcBackoffice::SignatureDispatchRecoveryJob.perform_now }.not_to have_enqueued_job(described_class).with(delivery.id)
  end
end
