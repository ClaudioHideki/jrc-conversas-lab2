# frozen_string_literal: true

module JrcContactCenter::AdministrativeAuditable
  extend ActiveSupport::Concern

  included do
    before_update :capture_cc_configuration_before
    after_create :audit_cc_configuration_create
    after_update :audit_cc_configuration_update
    before_destroy :audit_cc_configuration_destroy, prepend: true
  end

  private

  def capture_cc_configuration_before
    row = self.class.lock.where(account_id: account_id).find(id)
    @cc_configuration_before = JrcContactCenter::ConfigurationAuditSnapshot.capture(row)
  end

  def audit_cc_configuration_create
    JrcContactCenter::ConfigurationAudit.write!(
      self, action: 'create', before: nil, after: JrcContactCenter::ConfigurationAuditSnapshot.capture(self)
    )
  end

  def audit_cc_configuration_update
    snapshot = self.class.uncached { JrcContactCenter::ConfigurationAuditSnapshot.capture(self.class.find(id)) }
    JrcContactCenter::ConfigurationAudit.write!(self, action: 'update', before: @cc_configuration_before, after: snapshot)
  end

  def audit_cc_configuration_destroy
    capture_cc_configuration_before
    JrcContactCenter::ConfigurationAudit.write!(self, action: 'destroy', before: @cc_configuration_before, after: nil)
  end
end
