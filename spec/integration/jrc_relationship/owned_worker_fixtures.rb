# Synthetic-only helpers; caller must validate the owned database before use.
module JrcOwnedWorkerFixtures
  private

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
