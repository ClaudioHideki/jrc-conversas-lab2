require 'rails_helper'
require 'timeout'

RSpec.describe 'Ending original actor identity and transaction context' do
  self.use_transactional_tests = false

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' &&
            ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable original actor database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?
  end

  include_context 'with native ending execution original evidence'

  subject(:execution) { JrcContactCenter::EndingActions::OriginalActorContext.new(account: account, origin_id: origin.id) }

  it 'installs the attested original actor and restores the previous native context after the attempt' do
    target = execution
    previous = JrcServiceDesk::NativeExecutionContext::FIELDS.index_with { |field| Current.public_send(field) }
    result = target.call do |acting, original|
      expect(acting.id).to eq(original.actor_account_user_id)
      expect(Current.account_user.id).to eq(member.id)
      expect(Current.user.id).to eq(actor.id)
      expect(Current.account.id).to eq(account.id)
      :authorized_source_only
    end
    expect(result).to eq(:authorized_source_only)
    expect(JrcServiceDesk::NativeExecutionContext::FIELDS.index_with { |field| Current.public_send(field) }).to eq(previous)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'restores the previous native context when an authorized destination attempt rolls back' do
    target = execution
    previous = JrcServiceDesk::NativeExecutionContext::FIELDS.index_with { |field| Current.public_send(field) }
    expect { target.call { raise 'SYNTHETIC destination rollback' } }.to raise_error(RuntimeError, 'SYNTHETIC destination rollback')
    expect(JrcServiceDesk::NativeExecutionContext::FIELDS.index_with { |field| Current.public_send(field) }).to eq(previous)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'waits for a real native authority update and denies the now-restricted original actor before yielding' do
    original_id = origin.id
    account_id = account.id
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    ready = Queue.new
    result = Queue.new
    worker = nil
    account.with_lock do
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ready << connection.raw_connection.backend_pid
          target = JrcContactCenter::EndingActions::OriginalActorContext.new(account: Account.find(account_id), origin_id: original_id)
          result << target.call { :unexpected_authorized_execution }
        end
      rescue StandardError => e
        result << e
      end
      pid = Timeout.timeout(8) { ready.pop }
      sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
      Timeout.timeout(8) do
        ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
      end
      member.update!(custom_role: role)
    end
    expect(Timeout.timeout(20) { result.pop }).to be_a(Pundit::NotAuthorizedError)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  ensure
    worker&.join(20)
    raise 'Synthetic original actor worker remained active' if worker&.alive?
  end
end
