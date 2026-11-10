# Bulk contact permission is not the same as ordinary directory access. Keep
# the native Enterprise contact_manage grant and the existing company admin gate.
class JrcCustomers::ImportAccess
  def initialize(account:, actor:)
    @account = account
    @actor = actor
  end

  def available_kinds
    context = current_context
    return JrcCustomers::ImportFile::KINDS.dup if JrcCustomers::DirectoryPolicy.new(context, :directory).administer?

    ContactPolicy.new(context, Contact).import? ? ['contacts'] : []
  end

  def authorize!(kind:)
    raise JrcCustomers::ImportFile::InvalidFile, 'Unsupported import type' unless JrcCustomers::ImportFile::KINDS.include?(kind)
    raise Pundit::NotAuthorizedError unless available_kinds.include?(kind)

    true
  end

  private

  def current_context
    JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).authorize!
    member = AccountUser.find_by!(account_id: @account.id, user_id: @actor.id)
    { account: @account, user: @actor, account_user: member }
  end
end
