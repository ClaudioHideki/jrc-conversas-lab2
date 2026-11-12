# frozen_string_literal: true

class RequesterPortal::Employee::ContextController < Api::V1::Accounts::JrcServiceDesk::UiContextController
  include RequesterPortal::EmployeeSession
end
