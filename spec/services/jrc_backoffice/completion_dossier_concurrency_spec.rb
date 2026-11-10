require 'rails_helper'

RSpec.describe 'Committed dossier sealing concurrency' do
  self.use_transactional_tests = false

  it 'commits a single seal and private archive for two requests for the same reviewed manifest' do
    raise 'Owned synthetic database only' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    account = create(:account)
    account.enable_features!('jrc_crm')
    actor = create(:user, account: account, role: :administrator)
    order = account.jrc_crm_sales_orders.create!(owner: actor, status: 'approved')
    operation = account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor, request_kind: 'fulfillment',
      stage: 'finance', title: 'Synthetic concurrent seal', metadata: { finance_required: false })
    operation.advance!(actor: actor)
    digest = JrcBackoffice::CompletionDossiers.new(account: account, actor: actor, request_id: operation.id).show.fetch(:candidate_digest)
    ready, start = Queue.new, Queue.new
    workers = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          connection.transaction do
            connection.execute("SET LOCAL lock_timeout = '15s'")
            ready << true
            start.pop
            JrcBackoffice::CompletionDossiers.new(account: Account.find(account.id), actor: User.find(actor.id), request_id: operation.id)
              .seal!(expected_manifest_digest: digest).id
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    ids = workers.map(&:value)
    expect(ids.uniq.size).to eq(1)
    expect(JrcBackoffice::CompletionDossier.where(account: account, backoffice_request: operation).count).to eq(1)
    expect(JrcBackoffice::CompletionDossier.find(ids.first).integrity?).to be(true)
  end
end
