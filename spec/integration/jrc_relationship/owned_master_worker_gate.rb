# Explicit real-queue entrypoint, loaded only by the owned environment helper.
# Reuse the original strict database, direct-child shutdown and native queue gate.
require_relative 'owned_worker_gate'

class JrcOwnedMasterWorkerGate < JrcOwnedWorkerGate
  private

  def seed!
    check!('explicit fresh master mode', ENV.fetch('JRC_G_MODE') == 'master' && ENV['JRC_G_RESUME'].blank?)
    @account = synthetic_account('master')
    @actor = synthetic_actor(@account, 'master')
    @revoked_actor = synthetic_actor(@account, 'revoked-master')
    @groups = Array.new(2) { |index| group(@actor, "Synthetic product grouping #{index}") }
    @blocked_group = group(@revoked_actor, 'Synthetic revoked master grouping')
    configure_capacity!
    prepare_master_reviews!
    create_foreign_witness!
    revoke_actor!
    check!('no allocation before queue consumption', JrcRelationship::Assignment.where(account: @account).none?)
  end

  def prepare_master_reviews!
    @companies = Array.new(6) { |index| @account.master_companies.create!(name: "Synthetic worker master #{index}") }
    @blocked_companies = Array.new(2) { |index| @account.master_companies.create!(name: "Synthetic worker revoked #{index}") }
    @service = JrcRelationship::ReviewedPortfolioBatch.new(context(@actor))
    @success = review(@service, @groups.first, @companies, @actor)
    @blocked = review(JrcRelationship::ReviewedPortfolioBatch.new(context(@revoked_actor)), @blocked_group,
                      @blocked_companies, @revoked_actor)
    @pinned = @blocked.attributes.slice('inputs', 'snapshot', 'digest', 'actor_id', 'account_id')
  end

  def create_foreign_witness!
    foreign_account = synthetic_account('foreign-master')
    foreign_actor = synthetic_actor(foreign_account, 'foreign-master')
    @foreign = JrcRelationship::Assignment.create!(account: foreign_account, owner: foreign_actor,
                                                   contact: foreign_account.contacts.create!(name: 'Synthetic foreign preserved contact'))
    @foreign_attributes = @foreign.attributes
  end

  def context(actor)
    JrcRelationship::Context.new(@account.account_users.find_by!(user: actor))
  end

  def group(actor, name)
    JrcRelationship::PortfolioGroup.create!(account: @account, owner: actor, name: name)
  end

  def configure_capacity!
    limits = [@actor, @revoked_actor].map do |actor|
      { 'user_id' => actor.id, 'unit' => 'hours', 'maximum' => 6, 'availability' => 1, 'dedication' => 1 }
    end
    JrcRelationship::Configuration.create!(account: @account, rules: { 'portfolio_capacity_limits' => limits })
    (@groups + [@blocked_group]).each do |entry|
      JrcRelationship::Configuration.create!(account: @account, scope_key: "portfolio:#{entry.id}",
                                             rules: { 'portfolio_capacity_limits' => limits })
    end
  end

  def review(service, grouping, companies, actor = nil)
    creations = if actor
                  companies.map do |company|
                    { 'company_id' => company.id, 'owner_id' => actor.id, 'settings' => { 'capacity_workload' => { 'hours' => 1 } } }
                  end
                else
                  []
                end
    result = service.preview('operation' => 'master_allocation', 'ids' => companies.map(&:id),
                             'portfolio_group_id' => grouping.id, 'expected_version' => grouping.lock_version,
                             'creations' => creations, 'justification' => 'Synthetic actual queue master review', 'request_id' => SecureRandom.uuid)
    expected = actor ? { 'create_count' => companies.size, 'reuse_count' => 0 } : { 'create_count' => 0, 'reuse_count' => companies.size }
    check!('native master preview preserves create or reuse decision', result.fetch('summary').slice(*expected.keys) == expected)
    service.approve(result.fetch('id'), digest: result.fetch('digest'))
    JrcRelationship::BatchReview.find(result.fetch('id'))
  end

  def exercise!
    @phase = 'committed_native_master_creation'
    enqueue(@success)
    wait_for('two native master creation deliveries') { @success.reload.state == 'completed' && acknowledgments == 2 }
    verify_created_roots!
    reuse_in_second_portfolio!
    duplicate_delivery!
    revoked_delivery!
    @phase = 'tenant_and_network'
    check!('foreign account allocation unchanged', @foreign.reload.attributes == @foreign_attributes)
    pending_count = Sidekiq::Queue.new(@queue).size
    check!('owned queue drained', pending_count.zero?)
    check!('no HTTP requests attempted', WebMock::RequestRegistry.instance.requested_signatures.hash.empty?)
  end

  def native_roots
    JrcRelationship::Assignment.where(account: @account).order(:id).map(&:attributes)
  end

  def verify_created_roots!
    check!('six native master roots and active links', @success.items.pluck(:state) == ['applied'] * 6 &&
           @groups.first.customer_links.where(active: true).count == 6 && JrcRelationship::Assignment.where(account: @account).count == 6)
    @roots = native_roots
    check!('one explicit synthetic hour per native root', @roots.all? { |row| row.fetch('settings').dig('capacity_workload', 'hours') == 1 })
  end

  def reuse_in_second_portfolio!
    @phase = 'committed_second_active_portfolio'
    @reuse = review(@service, @groups.last, @companies)
    enqueue(@reuse)
    wait_for('two native master reuse deliveries') { @reuse.reload.state == 'completed' && acknowledgments == 4 }
    check!('same six roots preserved across two active portfolios', @reuse.items.pluck(:state) == ['applied'] * 6 &&
           @groups.sum { |entry| entry.customer_links.where(active: true).count } == 12 &&
           native_roots == @roots)
    @completed = [@reuse.attributes, @reuse.items.order(:ordinal).map(&:attributes), @groups.last.reload.attributes]
  end

  def duplicate_delivery!
    @phase = 'duplicate_native_master_delivery'
    enqueue(@reuse)
    wait_for('duplicate master ACK') { acknowledgments == 5 }
    check!('duplicate master delivery has no repeated effect',
           @completed == [@reuse.reload.attributes, @reuse.items.order(:ordinal).map(&:attributes), @groups.last.reload.attributes])
  end

  def revoked_delivery!
    @phase = 'revoked_native_master_authority'
    enqueue(@blocked)
    wait_for('revoked master ACK') { @blocked.reload.state == 'attention' && acknowledgments == 6 }
    check!('revoked master creates no roots or links', @blocked.items.pluck(:state, :error_code) == [%w[canceled BATCH_AUTHORITY_CHANGED]] * 2 &&
           @blocked_group.customer_links.none? && JrcRelationship::Assignment.where(account: @account, company: @blocked_companies).none?)
    check!('revoked master history stays pinned', @blocked.attributes.slice(*@pinned.keys) == @pinned)
  end
end

Signal.trap('USR1') { raise JrcOwnedWorkerGate::Failure, 'Owned master resource guard requested stop' }
JrcOwnedMasterWorkerGate.new.run
