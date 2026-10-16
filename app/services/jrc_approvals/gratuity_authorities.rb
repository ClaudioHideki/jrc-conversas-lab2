# Native identities are bound by an explicit organizational configuration and audit reference.
class JrcApprovals::GratuityAuthorities
  STEPS = { 'gratuidade_comercial' => 'commercial', 'gratuidade_financeira' => 'financial' }.freeze

  def initialize(account:, company_id:)
    @account = account
    @company_id = company_id
  end

  def profile
    if @company_id
      company = @account.master_companies.where(relationship_type: 'internal').find(@company_id)
      JrcCrm::CorporateProfile.read(company)
    else
      @account.custom_attributes.fetch(JrcCrm::OrganizationalStructureService::SETTINGS_KEY, {}).fetch('approval_authorities', {})
    end
  end

  def validate_definition!(definition)
    valid = definition.slice('execution', 'completion', 'allow_self_approval', 'reopen_mode') == {
      'execution' => 'sequential', 'completion' => 'all_steps', 'allow_self_approval' => false, 'reopen_mode' => 'restart_all'
    } && definition['steps'].pluck('code') == STEPS.keys
    raise JrcApprovals::Error, 'INVALID_GRATUITY_SEQUENCE' unless valid
    raise JrcApprovals::Error, 'GRATUITY_AUTHORITIES_PENDING' if profile['authorization_reference'].blank?

    definition['steps'].each { |step| validate_step!(step) }
    principals = STEPS.values.map { |name| profile["#{name}_gratuity_principal_id"] }
    raise JrcApprovals::Error, 'GRATUITY_AUTHORITY_CONFLICT' unless principals.uniq.length == 2
  end

  def validate_step!(step)
    principal = profile["#{STEPS.fetch(step['code'])}_gratuity_principal_id"]
    expected = { 'mode' => 'all', 'quorum' => 1, 'assignees' => [{ 'type' => 'account_user', 'id' => principal }], 'on_reject' => 'rejected' }
    return if principal.is_a?(Integer) && step.slice(*expected.keys) == expected

    raise JrcApprovals::Error, 'GRATUITY_AUTHORITIES_PENDING'
  end

  def validate_delegation!(step_code:, principal_id:, delegate_id:, absence_authorization:)
    prefix = STEPS.fetch(step_code) { raise JrcApprovals::Error, 'INVALID_GRATUITY_SEQUENCE' }
    reference = absence_authorization
    valid = reference.is_a?(String) && reference.strip.length.between?(3, 500) &&
            profile['authorization_reference'].present? &&
            profile["#{prefix}_gratuity_principal_id"] == principal_id &&
            profile["#{prefix}_gratuity_substitute_id"] == delegate_id
    raise JrcApprovals::Error, 'GRATUITY_ABSENCE_AUTHORIZATION_REQUIRED' unless valid
  end
end
