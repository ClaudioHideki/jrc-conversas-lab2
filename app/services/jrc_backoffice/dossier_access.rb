# Current native ownership plus the original corporate/customer boundaries.
# Moving an origin cannot turn a historical private archive into a new grant.
class JrcBackoffice::DossierAccess
  def initialize(access, request_id)
    @access = access
    @request_id = request_id
  end

  def source_links
    request = @access.request(@request_id)
    order = request.sales_order.reload
    { 'order_id' => order.id, 'contract_id' => request.contract_id,
      'contact_id' => order.contact_id, 'customer_company_id' => order.contact&.company_id || order.deal&.company_id }
  end

  def unit_refs
    request = @access.request(@request_id)
    ids = [request.business_unit_id, request.sales_order.business_unit_id, request.contract&.business_unit_id].compact.uniq
    @access.account.jrc_crm_business_units.where(id: ids).order(:id).map { |unit| { 'id' => unit.id, 'company_id' => unit.company_id } }
  end

  def authorize!(dossier)
    raise ActiveStorage::IntegrityError unless dossier.integrity?
    raise ActiveRecord::RecordNotFound unless dossier.account_id == @access.account.id && dossier.backoffice_request_id.to_s == @request_id.to_s

    source = dossier.snapshot
    raise ActiveRecord::RecordNotFound unless source.fetch('source_links') == source_links

    authorize_units!(source.fetch('unit_refs'))

    @access.contract!(@access.request(@request_id)) if source.dig('source_links', 'contract_id')
    verify_files!(source.fetch('manifest'))
    dossier
  end

  private

  def authorize_units!(refs)
    units = @access.account.jrc_crm_business_units.where(id: refs.pluck('id'))
    scoped = JrcCrm::OrganizationalVisibility.new(account: @access.account, user: @access.actor, relation: units).call
    actual = scoped.order(:id).map { |unit| { 'id' => unit.id, 'company_id' => unit.company_id } }
    raise ActiveRecord::RecordNotFound unless actual == refs
  end

  def verify_files!(manifest)
    request = @access.request(@request_id)
    versions = JrcBackoffice::ContractVersions.new(account: @access.account, actor: @access.actor, request_id: @request_id)
    manifest.fetch('files').each { |file| verify_file!(file, request, versions) }
    reader = JrcBackoffice::Signatures::History.new(account: @access.account, actor: @access.actor, request_id: @request_id)
    manifest.fetch('signature_history').each { |delivery| reader.show(delivery.fetch('id')) }
  end

  def verify_file!(file, request, versions)
    if file.fetch('kind') == 'contract_version'
      version = versions.scope.find(file.fetch('id'))
      raise ActiveStorage::IntegrityError unless version.pdf_sha256 == file.fetch('sha256')
    else
      version = request.document_versions.where(account_id: @access.account.id).find(file.fetch('id'))
      raise ActiveStorage::IntegrityError unless version.sha256 == file.fetch('sha256')
      raise JrcBackoffice::DocumentSafety::NotClean unless JrcBackoffice::DocumentSafety.new(version).current&.clean?
    end
  end
end
