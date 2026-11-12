# frozen_string_literal: true

class RequesterPortal::Employee::ServicesController < Api::V1::Accounts::JrcServiceDesk::ServiceDefinitionsController
  include RequesterPortal::EmployeeSession
end
