# frozen_string_literal: true

class RequesterPortal::Employee::CatalogueController < Api::V1::Accounts::JrcServiceDesk::CatalogueFormsController
  include RequesterPortal::EmployeeSession
end
