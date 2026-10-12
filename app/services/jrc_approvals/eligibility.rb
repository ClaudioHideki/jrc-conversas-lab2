class JrcApprovals::Eligibility
  def initialize(account:, company_id:, unit_id:, catalog_key: nil)
    @account, @company_id, @unit_id, @catalog_key = account, company_id, unit_id, catalog_key
  end

  def candidates(step)
    ids = step.fetch('assignees').flat_map do |rule|
      case rule.fetch('type')
      when 'account_user' then [@account.account_users.find(rule.fetch('id')).id]
      when 'team'
        team = Team.where(account_id: @account.id).find(rule.fetch('id'))
        covered = JrcCrm::TeamScope.active.where(account_id: @account.id, team_id: team.id)
          .any? { |scope| scope.covers?(company_id: @company_id, business_unit_id: @unit_id) }
        raise JrcApprovals::Error, 'TEAM_SCOPE_NOT_AUTHORIZED' unless covered

        @account.account_users.where(user_id: team.members.select(:id)).pluck(:id)
      when 'custom_role'
        role = CustomRole.where(account_id: @account.id).find(rule.fetch('id'))
        @account.account_users.where(custom_role_id: role.id).pluck(:id)
      end
    end.uniq
    @account.account_users.includes(:user).where(id: ids).filter_map do |member|
      member.id if capable?(member)
    end.sort
  end

  def capable?(member)
    commercial = @catalog_key && (JrcApprovals::CommercialCatalog::EVENTS.key?(@catalog_key) ||
      @catalog_key == JrcApprovals::CommercialCatalog::PRICE_FAMILY)
    if commercial
      return false unless @account.feature_enabled?('jrc_crm') && member.permissions.include?('jrc_crm')
    end
    JrcApprovals::Authorization.new(account: @account, user: member.user)
      .authorize!('decide', company_id: @company_id, unit_id: @unit_id)
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def plan!(definition, requester_id: nil)
    definition.fetch('steps').map do |step|
      ids = candidates(step)
      ids -= [requester_id] unless definition.fetch('allow_self_approval')
      quorum = step['mode'] == 'all' ? ids.size : step['quorum']
      # 'all' explicitly declares both its intended roster size and unanimity; disappearing members cannot lower it.
      raise JrcApprovals::Error, 'INSUFFICIENT_APPROVERS' if ids.empty? || quorum > ids.size ||
        (step['mode'] == 'all' && step['quorum'] != ids.size)

      { 'code' => step['code'], 'principal_ids' => ids, 'quorum' => quorum }
    end
  end
end
