module JrcCrm::StructureScopeAuthority
  extend ActiveSupport::Concern

  SCOPE_WRITES = %i[
    create_user_scope update_user_scope destroy_user_scope
    create_team_scope update_team_scope destroy_team_scope
  ].freeze

  included do
    around_action :with_current_scope_authority, only: SCOPE_WRITES
  end

  private

  # Scope revocations serialize with native membership and Call Center writes.
  def with_current_scope_authority
    crm_scope.with_lock do
      ActiveRecord::Base.uncached do
        Current.account_user.reload
        Current.user.reload
        raise Pundit::NotAuthorizedError unless crm_scope.active?

        ensure_crm_enabled
        next if performed?

        ensure_crm_access
        ensure_crm_admin!
        authorize_scope_administration!
        yield
      end
    end
  end
end
