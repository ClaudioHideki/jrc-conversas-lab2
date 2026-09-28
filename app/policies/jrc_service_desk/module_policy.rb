# frozen_string_literal: true

class JrcServiceDesk::ModulePolicy < JrcServiceDesk::OperationalPolicy
  def show?
    any_unit_allowed? && capability?(:module_view)
  end

  def settings?
    show? && capability?(:settings_view)
  end

  def dashboard?
    show? && capability?(:dashboard_view)
  end
end
