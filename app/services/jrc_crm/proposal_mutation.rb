# The native edit path shared by the CRM and the bounded approval adjustment.
class JrcCrm::ProposalMutation
  def self.authorize!(proposal, actor)
    account = proposal.account
    member = crm_member!(account, actor)
    context = { user: actor, account: account, account_user: member }
    raise Pundit::NotAuthorizedError unless JrcCrm::ProposalPolicy.new(context, proposal).update?

    scope = JrcCrm::Proposal.where(account_id: account.id, id: proposal.id)
    scope = scope.where(owner_id: actor.id) unless member.administrator?
    raise Pundit::NotAuthorizedError unless JrcCrm::OrganizationalVisibility.new(account: account, user: actor, relation: scope).call.exists?

    JrcCrm::CorporateIssuer.authorize_resource!(proposal, actor)
  end

  def self.crm_member!(account, actor)
    member = account.account_users.includes(:user).find_by(user_id: actor&.id)
    raise Pundit::NotAuthorizedError unless member
    raise Pundit::NotAuthorizedError unless account.active? && account.feature_enabled?('jrc_crm') &&
                                            member.user.active_for_authentication? && member.permissions.include?('jrc_crm')

    member
  end
  private_class_method :crm_member!

  def self.call!(proposal:, actor:, attributes:)
    proposal.with_lock do
      authorize!(proposal, actor)
      raise JrcApprovals::Error, 'SOURCE_LOCKED' if proposal.locked_for_editing?

      proposal.update!(attributes)
      proposal.reset_approvals! if (proposal.saved_changes.keys - %w[updated_at]).any?
      proposal.recalculate_totals!
      JrcApprovals::CommercialInvalidation.call(resource: proposal.reload, user: actor)
      proposal.events.create!(account_id: proposal.account_id, event_type: 'updated', user_id: actor.id,
                              description: 'Proposta atualizada no CRM')
      proposal.reload
    end
  end
end
