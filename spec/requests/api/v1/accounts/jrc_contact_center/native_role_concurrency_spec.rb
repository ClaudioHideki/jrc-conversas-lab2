require 'rails_helper'
require 'timeout'

RSpec.describe 'Call Center native role concurrent revocation', type: :request do
  self.use_transactional_tests = false

  before do
    raise 'Owned synthetic database required' unless Rails.env.test? &&
                                                   ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?

    @account = create(:account)
    @account.enable_features!('jrc_contact_center', 'custom_roles')
    @actor = create(:user, account: @account, role: :administrator)
    @target = create(:custom_role, account: @account, permissions: %w[jrc_contact_center_view jrc_contact_center_publish])
    @headers = @actor.create_new_auth_token
    @threads = []
    @entered = Queue.new
    @read = Queue.new
    @release = Queue.new
    @results = Queue.new
  end

  after do
    @release << true
    @threads.each { |thread| thread.join(20) }
    raise 'Synthetic request still active' if @threads.any?(&:alive?)

    ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
    @account.destroy!
  end

  it 'does not restore a concurrently revoked power using a stale role read' do
    target_id = @target.id
    @subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |event|
      sql = event.payload[:sql]
      next unless Thread.current[:cc_native_role_request] && sql.start_with?('SELECT') && sql.include?('"custom_roles"')
      next if sql.include?('FOR UPDATE')
      next unless event.payload[:binds].any? { |bind| bind.name == 'id' && bind.value_for_database == target_id }

      @read << true
    end
    @threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        CustomRole.find(target_id).with_lock do
          CustomRole.find(target_id).update!(permissions: ['jrc_contact_center_view'])
          @entered << true
          Timeout.timeout(10) { @release.pop }
        end
      end
    rescue StandardError => error
      @results << error
    end
    Timeout.timeout(5) { @entered.pop }
    @threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:cc_native_role_request] = true
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.patch "/api/v1/accounts/#{@account.id}/custom_roles/#{target_id}", headers: @headers,
                      params: { custom_role: { permissions: %w[jrc_contact_center_view jrc_contact_center_publish] } }
        @results << session.response.status
      end
    rescue StandardError => error
      @results << error
    end
    Timeout.timeout(5) { @read.pop }
    @release << true
    Timeout.timeout(15) { @threads.each(&:join) }
    expect(@results.pop).to eq(401)
    expect(@target.reload.permissions).to eq(['jrc_contact_center_view'])
  end
end
