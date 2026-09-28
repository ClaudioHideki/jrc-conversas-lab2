# frozen_string_literal: true

# No grant/revoke API or implicit administrator bypass in CP2.
# A future explicit scope-administration workflow must authorize its own actions.
class JrcServiceDesk::UnitMembershipPolicy < JrcServiceDesk::BasePolicy
end
