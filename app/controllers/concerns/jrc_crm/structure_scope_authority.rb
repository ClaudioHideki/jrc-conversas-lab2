module JrcCrm::StructureScopeAuthority
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
