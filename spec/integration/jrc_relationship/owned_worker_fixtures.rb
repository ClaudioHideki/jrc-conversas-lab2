# Synthetic-only helpers; caller must validate the owned database before use.
module JrcOwnedWorkerFixtures
  private

  def acknowledgments
    return unless @validated

    Sidekiq.redis { |redis| redis.call('SCARD', @receipt_key) }
  end

  def retained_acknowledgments
    return 5 if ENV['JRC_G_APPROVAL_FINALIZE'] == 'true'

    ENV['JRC_G_APPROVAL_RESUME'].present? ? 2 : 0
  end

  def resume_fixtures!
    check!('preserved exact synthetic counts', Account.count == 2 && User.count == 3 && JrcRelationship::Assignment.count == 15)
    pending_count = Sidekiq::Queue.new(@queue).size
    check!('no prior business delivery', acknowledgments.zero? && pending_count.zero?)
    @account = Account.find_by!(name: 'Synthetic owned worker primary')
    load_success_fixture!
    load_blocked_fixture!
    verify_preserved_selections!
    @originals = @records.map(&:attributes)
    @blocked_originals = @blocked_records.map(&:attributes)
    @pinned = @blocked.attributes.slice('inputs', 'snapshot', 'digest', 'actor_id', 'account_id')
    foreign_account = Account.find_by!(name: 'Synthetic owned worker foreign')
    @foreign = JrcRelationship::Assignment.find_by!(account: foreign_account)
    @foreign_attributes = @foreign.attributes
    renew_expired_success!
  end

  def load_success_fixture!
    @actor = User.find_by!(email: "success-#{@nonce}@example.invalid")
    check!('success authority remains native administrator', @account.account_users.find_by!(user: @actor).administrator?)
    @group = JrcRelationship::PortfolioGroup.where(account: @account).find_by!(name: 'Synthetic successful grouping')
    @success = JrcRelationship::BatchReview.find_by!(account: @account, actor: @actor, state: 'running')
    @records = @success.items.order(:ordinal).map(&:assignment)
  end

  def load_blocked_fixture!
    @revoked_actor = User.find_by!(email: "revoked-#{@nonce}@example.invalid")
    @blocked_group = JrcRelationship::PortfolioGroup.where(account: @account).find_by!(name: 'Synthetic revoked grouping')
    @blocked = JrcRelationship::BatchReview.find_by!(account: @account, actor: @revoked_actor, state: 'running')
    @blocked_records = @blocked.items.order(:ordinal).map(&:assignment)
    entry = @account.account_users.find_by!(user: @revoked_actor)
    check!('revoked authority remains view only', entry.agent? && entry.custom_role.permissions.sort == %w[contact_manage jrc_relationship_view])
  end

  def verify_preserved_selections!
    check!('preserved selection sizes', @records.size == 12 && @blocked_records.size == 2)
    [@success, @blocked].each { |review| check!('preserved pending items', review.items.where.not(state: 'pending').none?) }
    check!('no preserved group links', @group.customer_links.none? && @blocked_group.customer_links.none?)
    check!('same pinned membership groups', @success.inputs['portfolio_group_id'].to_i == @group.id &&
           @blocked.inputs['portfolio_group_id'].to_i == @blocked_group.id)
  end

  def renew_expired_success!
    @expired_success = @success
    @expired_attributes = @expired_success.attributes
    @expired_items = @expired_success.items.order(:ordinal).map(&:attributes)
    check!('expired original review retained', @expired_success.expires_at < Time.current)
    context = JrcRelationship::Context.new(@account.account_users.find_by!(user: @actor))
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    inputs = @expired_success.inputs.merge('request_id' => SecureRandom.uuid,
                                           'justification' => 'Synthetic fresh approval after retained startup failure')
    fresh = service.preview(inputs)
    service.approve(fresh.fetch('id'), digest: fresh.fetch('digest'))
    @success = JrcRelationship::BatchReview.find(fresh.fetch('id'))
  end

  def verify_expired_unchanged!
    return unless @expired_success

    check!('original expired approval unchanged', @expired_success.reload.attributes == @expired_attributes &&
           @expired_success.items.order(:ordinal).map(&:attributes) == @expired_items)
  end

  def owned_directory?
    base = "/tmp/jrc_g_worker_#{@nonce}"
    @directory == base || @directory.match?(%r{\A#{Regexp.escape(base)}/attempt_[0-9a-f]{8}\z})
  end

  def synthetic_actor(account, label)
    actor = User.create!(name: "Synthetic #{label}", email: "#{label}-#{@nonce}@example.invalid",
                         password: "Aa1!#{SecureRandom.hex(20)}", confirmed_at: Time.current)
    AccountUser.create!(account: account, user: actor, role: :administrator)
    actor
  end

  def synthetic_account(label)
    account = Account.create!(name: "Synthetic owned worker #{label}")
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    account
  end

  def reviewed(account, actor, count, label)
    context = JrcRelationship::Context.new(account.account_users.find_by!(user: actor))
    records = Array.new(count) do |index|
      contact = account.contacts.create!(name: "Synthetic #{label} #{index}")
      JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact)
    end
    group = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: "Synthetic #{label} grouping")
    service = JrcRelationship::ReviewedPortfolioBatch.new(context)
    preview = service.preview('operation' => 'portfolio_membership', 'ids' => records.map(&:id), 'portfolio_group_id' => group.id,
                              'expected_version' => group.lock_version, 'active' => true,
                              'justification' => 'Synthetic real queue delivery gate', 'request_id' => SecureRandom.uuid)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    [JrcRelationship::BatchReview.find(preview.fetch('id')), group, records]
  end
end
