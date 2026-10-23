require 'rails_helper'

RSpec.describe JrcBroker::Context do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:organization_id) { SecureRandom.uuid }
  let(:origin) { 'https://broker.example.test' }
  let(:prefix) { "#{origin}/v1/integrations/chatwoot/control" }
  let(:connections) { [] }
  let(:integration) { JrcBrokerIntegration.find_by!(account: account) }
  let(:context) { described_class.new(account: account, user: admin) }

  around do |example|
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: origin,
                      JRC_BROKER_CREDENTIAL_KEY: Base64.strict_encode64('k' * 32), FRONTEND_URL: 'https://chatwoot.example.test') { example.run }
  end

  before do
    admin
    account.enable_features!('jrc_broker')
    encrypted = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-control')
    JrcBrokerIntegration.create!(account: account, broker_origin: origin, organization_id: organization_id,
                                 destination_revision: 1, encrypted_control_key: encrypted)
    stub_request(:get, "#{prefix}/context").to_return(status: 200, body: {
      organizationId: organization_id, accountId: account.id, chatwootOrigin: 'https://chatwoot.example.test', destinationRevision: 1
    }.to_json)
    stub_request(:get, "#{prefix}/resources").to_return do
      { status: 200, body: { providers: [], instances: [], connections: connections }.to_json }
    end
    clear_enqueued_jobs
  end

  def remote_inbox(owner: account, callback_origin: origin)
    id = SecureRandom.uuid
    inbox = create(:channel_api, account: owner, webhook_url: "#{callback_origin}/v1/integrations/chatwoot/#{id}/events").inbox
    connection = { 'integrationId' => id, 'inboxId' => inbox.id, 'name' => 'Synthetic sender' }
    connections << connection
    health = { 'integrationId' => id, 'inboxId' => inbox.id, 'instanceId' => SecureRandom.uuid, 'integrationStatus' => 'READY',
               'instanceStatus' => 'DISCONNECTED', 'identityApproved' => false }
    stub_request(:get, "#{prefix}/connections/#{id}/status").to_return(status: 200, body: health.to_json)
    [inbox, health]
  end

  it 'registers every matching inbox without creating duplicates or approving a disconnected number' do
    first, health = remote_inbox
    second, = remote_inbox
    2.times { context.sync_inboxes! }
    bindings = JrcBrokerInboxBinding.where(account: account)
    expect(bindings.pluck(:inbox_id)).to contain_exactly(first.id, second.id)
    expect(bindings.find_by!(inbox: first).instance_id).to eq(health.fetch('instanceId'))
    expect(account.inboxes.count).to eq(2)
    expect(WebMock).not_to have_requested(:post, /confirm-identity|pair|campaign/)
  end

  it 'ignores foreign accounts and callbacks that do not match the configured Broker' do
    allowed, = remote_inbox
    foreign, = remote_inbox(owner: create(:account))
    unrelated, = remote_inbox(callback_origin: 'https://elsewhere.example.test')
    context.sync_inboxes!
    expect(JrcBrokerInboxBinding.where(account: account).pluck(:inbox_id)).to eq([allowed.id])
    expect(JrcBrokerInboxBinding.where(inbox_id: [foreign.id, unrelated.id])).not_to exist
  end

  it 'does not overwrite an existing association when another integration advertises the same inbox' do
    inbox, = remote_inbox
    original = JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    context.sync_inboxes!
    expect(original.reload.integration_id).not_to eq(connections.sole.fetch('integrationId'))
    expect(JrcBrokerInboxBinding.where(inbox: inbox).count).to eq(1)
  end

  it 'keeps processing other inboxes when one connection is unavailable or has mismatched identifiers' do
    unavailable, bad_health = remote_inbox
    allowed, = remote_inbox
    stub_request(:get, "#{prefix}/connections/#{bad_health.fetch('integrationId')}/status")
      .to_return(status: 200, body: bad_health.merge('inboxId' => allowed.id).to_json)
    context.sync_inboxes!
    expect(JrcBrokerInboxBinding.where(inbox: unavailable)).not_to exist
    expect(JrcBrokerInboxBinding.where(inbox: allowed)).to exist
  end

  it 'does not save a binding if the local callback changes while verifying the remote inbox' do
    inbox, health = remote_inbox
    stub_request(:get, "#{prefix}/connections/#{health.fetch('integrationId')}/status").to_return do
      inbox.channel.update!(webhook_url: 'https://elsewhere.example.test/events')
      { status: 200, body: health.to_json }
    end
    context.sync_inboxes!
    expect(JrcBrokerInboxBinding.where(inbox: inbox)).not_to exist
  end

  it 'does not save a binding authorized by a replaced account credential' do
    inbox, health = remote_inbox
    second, = remote_inbox
    stub_request(:get, "#{prefix}/connections/#{health.fetch('integrationId')}/status").to_return do
      integration.update!(destination_revision: 2)
      { status: 200, body: health.to_json }
    end
    context.sync_inboxes!
    expect(JrcBrokerInboxBinding.where(inbox_id: [inbox.id, second.id])).not_to exist
  end

  it 'rejects an ambiguous discovery response before registering any inbox' do
    inbox, = remote_inbox
    connections << connections.sole.dup
    expect { context.sync_inboxes! }.to raise_error(JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE')
    expect(JrcBrokerInboxBinding.where(inbox: inbox)).not_to exist
  end

  it 'continues registering other senders if an advertised inbox is deleted during verification' do
    first, health = remote_inbox
    removed, = remote_inbox
    last, = remote_inbox
    stub_request(:get, "#{prefix}/connections/#{health.fetch('integrationId')}/status").to_return do
      removed.destroy!
      { status: 200, body: health.to_json }
    end

    context.sync_inboxes!

    expect(JrcBrokerInboxBinding.where(account: account).pluck(:inbox_id)).to contain_exactly(first.id, last.id)
  end

  it 'does not let unrelated discovery rows starve a matching inbox' do
    11.times { remote_inbox(callback_origin: 'https://elsewhere.example.test') }
    allowed, = remote_inbox
    context.sync_inboxes!
    expect(JrcBrokerInboxBinding.where(account: account).pluck(:inbox_id)).to eq([allowed.id])
  end

  it 'continues bounded discovery past failing inboxes so they cannot starve later senders' do
    10.times do
      _, health = remote_inbox
      stub_request(:get, "#{prefix}/connections/#{health.fetch('integrationId')}/status").to_return(status: 503)
    end
    allowed, = remote_inbox
    clear_enqueued_jobs
    JrcBroker::InboxSyncJob.perform_now(account.id)
    expect(JrcBrokerInboxBinding.where(inbox: allowed)).not_to exist
    perform_enqueued_jobs(only: JrcBroker::InboxSyncJob)
    expect(JrcBrokerInboxBinding.where(account: account).pluck(:inbox_id)).to eq([allowed.id])
  end

  it 'does not run duplicate discovery while the account is already being synchronized' do
    inbox, = remote_inbox
    key = "jrc:broker:inbox-sync:#{account.id}"
    Redis::Alfred.set(key, 'another-worker', nx: true, ex: 300)
    JrcBroker::InboxSyncJob.perform_now(account.id)
    expect(JrcBrokerInboxBinding.where(inbox: inbox)).not_to exist
    expect(WebMock).not_to have_requested(:get, "#{prefix}/resources")
    expect(Redis::Alfred.get(key)).to eq('another-worker')
  ensure
    Redis::Alfred.delete_if_equals(key, 'another-worker') if key
  end

  it 'synchronizes newly created inboxes in a background job using this account only' do
    inbox, = remote_inbox
    JrcBroker::InboxSyncJob.perform_now(account.id)
    expect(JrcBrokerInboxBinding.where(account: account, inbox: inbox)).to exist
  end

  it 'queues registration when an API inbox is created or its callback changes' do
    expect { remote_inbox }.to have_enqueued_job(JrcBroker::InboxSyncJob).with(account.id)
    inbox = account.inboxes.last
    clear_enqueued_jobs
    expect { inbox.channel.update!(webhook_url: "#{inbox.channel.webhook_url}?changed=1") }
      .to have_enqueued_job(JrcBroker::InboxSyncJob).with(account.id)
  end

  it 'recovers Broker-created inboxes whose initial callback ran before the connection became READY' do
    inbox, = remote_inbox
    clear_enqueued_jobs
    expect { JrcBroker::InboxSyncSchedulerJob.perform_now }.to have_enqueued_job(JrcBroker::InboxSyncJob).with(account.id)
    perform_enqueued_jobs(only: JrcBroker::InboxSyncJob)
    expect(JrcBrokerInboxBinding.where(account: account, inbox: inbox)).to exist
  end

  it 'does not discover or register inboxes for disabled accounts or installations' do
    inbox, = remote_inbox
    account.disable_features!('jrc_broker')
    JrcBroker::InboxSyncJob.perform_now(account.id)
    expect(JrcBrokerInboxBinding.where(inbox: inbox)).not_to exist
    expect(WebMock).not_to have_requested(:get, "#{prefix}/resources")
  end

  it 'queues existing inbox registration after the account integration is configured or updated' do
    expect { integration.update!(destination_revision: 2) }.to have_enqueued_job(JrcBroker::InboxSyncJob).with(account.id)
  end

  it 'never uses an agent identity for account-wide automatic discovery' do
    inbox, = remote_inbox
    account.account_users.find_by!(user: admin).update!(role: :agent)
    JrcBroker::InboxSyncJob.perform_now(account.id)
    expect(JrcBrokerInboxBinding.where(inbox: inbox)).not_to exist
    expect(WebMock).not_to have_requested(:get, "#{prefix}/context")
  end

  it 'does not enqueue discovery for a suspended account' do
    account.update!(status: :suspended)
    clear_enqueued_jobs

    expect { JrcBroker::InboxSyncJob.enqueue_for(account) }.not_to have_enqueued_job(JrcBroker::InboxSyncJob)
  end

  it 'does not perform discovery already queued for a suspended account' do
    inbox, = remote_inbox
    account.update!(status: :suspended)
    JrcBroker::InboxSyncJob.perform_now(account.id)

    expect(JrcBrokerInboxBinding.where(inbox: inbox)).not_to exist
    expect(WebMock).not_to have_requested(:get, /#{Regexp.escape(prefix)}/)
  end

  it 'does not persist either inbox when the account is suspended during status verification' do
    first, health = remote_inbox
    second, = remote_inbox
    stub_request(:get, "#{prefix}/connections/#{health.fetch('integrationId')}/status").to_return do
      account.update!(status: :suspended)
      { status: 200, body: health.to_json }
    end

    context.sync_inboxes!

    expect(JrcBrokerInboxBinding.where(inbox_id: [first.id, second.id])).not_to exist
  end

  it 'does not persist either inbox when the administrator is demoted during status verification' do
    first, health = remote_inbox
    second, = remote_inbox
    stub_request(:get, "#{prefix}/connections/#{health.fetch('integrationId')}/status").to_return do
      account.account_users.find_by!(user: admin).update!(role: :agent)
      { status: 200, body: health.to_json }
    end

    context.sync_inboxes!

    expect(JrcBrokerInboxBinding.where(inbox_id: [first.id, second.id])).not_to exist
  end

  it 'does not persist either inbox when the administrator membership is removed during status verification' do
    first, health = remote_inbox
    second, = remote_inbox
    stub_request(:get, "#{prefix}/connections/#{health.fetch('integrationId')}/status").to_return do
      account.account_users.find_by!(user: admin).destroy!
      { status: 200, body: health.to_json }
    end

    context.sync_inboxes!

    expect(JrcBrokerInboxBinding.where(inbox_id: [first.id, second.id])).not_to exist
  end

  it 'finishes all HTTP requests before starting the local binding transaction' do
    inbox, health = remote_inbox
    baseline = ActiveRecord::Base.connection.open_transactions
    depths = []
    responses = {
      "#{prefix}/context" => { organizationId: organization_id, accountId: account.id,
                               chatwootOrigin: 'https://chatwoot.example.test', destinationRevision: 1 },
      "#{prefix}/resources" => { providers: [], instances: [], connections: connections },
      "#{prefix}/connections/#{health.fetch('integrationId')}/status" => health
    }
    responses.each do |url, body|
      stub_request(:get, url).to_return do
        depths << ActiveRecord::Base.connection.open_transactions
        { status: 200, body: body.to_json }
      end
    end

    context.sync_inboxes!

    expect(depths).to eq([baseline, baseline, baseline])
    expect(JrcBrokerInboxBinding.where(inbox: inbox)).to exist
  end
end
