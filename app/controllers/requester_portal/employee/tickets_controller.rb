# frozen_string_literal: true

class RequesterPortal::Employee::TicketsController < Api::V1::Accounts::JrcServiceDesk::TicketsController
  include RequesterPortal::EmployeeSession
end
