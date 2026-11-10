require 'digest'
require 'stringio'

class JrcBackoffice::CompletionDossiers
  class Unavailable < StandardError; end
  MARKER = 'jrc_backoffice_dossier_archive'.freeze

  def initialize(account:, actor:, request_id:)
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @request_id = request_id
    @history = JrcBackoffice::DossierAccess.new(@access, request_id)
    @package = JrcBackoffice::CompletionPackage.new(account: account, actor: actor, request_id: request_id)
  end

  def show(page: 1)
    request = @access.request(@request_id)
    candidate = completed?(request) ? @package.manifest : nil
    digest = candidate && candidate_digest(candidate)
    rows = visible_rows.order(number: :desc)
    data, meta = paginate(rows, page, digest)
    @access.request(@request_id)
    { data: data, meta: meta,
      candidate_digest: digest, can_seal: candidate_ready?(request, candidate) && !rows.exists?(manifest_digest: digest) }
  end

  def seal!(expected_manifest_digest:)
    @pending_blob = nil
    @access.account.with_lock('FOR NO KEY UPDATE', requires_new: true) do
      request = @access.request(@request_id)
      request.sales_order.with_lock('FOR NO KEY UPDATE') do
        request.with_lock('FOR NO KEY UPDATE') { seal_current!(request, expected_manifest_digest) }
      end
    end
  rescue StandardError
    JrcBackoffice::PrivateBlob.clean_uncommitted(@pending_blob, marker: MARKER)
    raise
  ensure
    @pending_blob = nil
  end

  def download(id)
    row = @history.authorize!(scope.find(id))
    bytes = row.archive_blob.open(&:read)
    unless bytes.bytesize == row.snapshot.fetch('archive_bytes') && Digest::SHA256.hexdigest(bytes) == row.archive_sha256
      raise ActiveStorage::IntegrityError
    end

    @history.authorize!(row.reload)
    audit!(row, 'backoffice_completion_dossier_accessed')
    [row, bytes]
  end

  private

  def scope
    @access.request(@request_id)
    JrcBackoffice::CompletionDossier.where(account_id: @access.account.id, backoffice_request_id: @request_id)
  end

  def completed?(request)
    request.completed? && request.stage == 'completed' && request.completed_at
  end

  def candidate_ready?(request, manifest)
    JrcBackoffice::Requirements.check!(request: request, actor: @access.actor, through: 'finance')
    manifest.is_a?(Hash) && manifest[:coverage] == 'available' && request.stage_blockers.empty?
  rescue JrcBackoffice::Requirements::Blocked
    false
  end

  def candidate_digest(manifest)
    JrcBackoffice::CompletionDossier.manifest_digest(manifest.as_json, @history.source_links, @history.unit_refs)
  end

  def paginate(rows, page, digest)
    total = rows.count
    pages = [(total / 10.0).ceil, 1].max
    page = page.to_i.clamp(1, pages)
    data = rows.offset((page - 1) * 10).limit(10).map { |row| summary(row, digest) }
    [data, { page: page, pages: pages, total: total }]
  end

  def visible_rows
    records = scope.order(:id).limit(1001).to_a
    raise JrcBackoffice::CompletionReport::TooLarge if records.length > 1000

    ids = records.filter_map do |row|
      @history.authorize!(row)
      row.id
    rescue JrcBackoffice::DocumentSafety::NotClean
      row.id
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
      nil
    end
    scope.where(id: ids)
  end

  def summary(row, digest)
    @history.authorize!(row)
    row.presentation.merge(current: row.manifest_digest == digest, can_download: true)
  rescue JrcBackoffice::DocumentSafety::NotClean
    row.presentation.merge(current: false, can_download: false, code: 'DOSSIER_SECURITY_CHANGED')
  end

  def seal_current!(request, expected)
    candidate = @package.manifest
    digest = candidate_digest(candidate)
    raise JrcBackoffice::CompletionPackage::Changed unless digest == expected
    raise Unavailable unless candidate_ready?(request, candidate)

    existing = scope.find_by(manifest_digest: digest)
    return @history.authorize!(existing) if existing

    manifest, bytes = @package.export
    raise JrcBackoffice::CompletionPackage::Changed unless manifest == candidate

    links = @history.source_links
    units = @history.unit_refs
    @pending_blob = JrcBackoffice::PrivateBlob.upload_owned(io: StringIO.new(bytes), filename: 'sealed-dossier.tar.gz',
                                                            content_type: 'application/gzip', marker: MARKER)
    revalidate_candidate!(candidate, links, units)
    persist!(manifest, digest, bytes, links, units)
  end

  def revalidate_candidate!(candidate, links, units)
    return if @package.manifest == candidate && @history.source_links == links && @history.unit_refs == units &&
              candidate_ready?(@access.request(@request_id), candidate)

    raise JrcBackoffice::CompletionPackage::Changed
  end

  def persist!(manifest, digest, bytes, links, units)
    data = { 'format_version' => 1, 'account_id' => @access.account.id, 'backoffice_request_id' => @request_id.to_i,
             'archive_blob_id' => @pending_blob.id, 'sealed_by_id' => @access.actor.id, 'manifest_digest' => digest,
             'archive_sha256' => Digest::SHA256.hexdigest(bytes), 'archive_bytes' => bytes.bytesize,
             'number' => scope.maximum(:number).to_i + 1, 'source_links' => links, 'unit_refs' => units, 'manifest' => manifest.as_json }
    attributes = data.slice('account_id', 'backoffice_request_id', 'archive_blob_id', 'sealed_by_id', 'number', 'manifest_digest', 'archive_sha256')
    row = JrcBackoffice::CompletionDossier.create!(attributes.merge(source_snapshot: JSON.generate(data),
                                                                    source_digest: JrcBackoffice::CompletionDossier.digest(data)))
    @history.authorize!(row)
    audit!(row, 'backoffice_completion_dossier_sealed')
    row
  end

  def audit!(row, event)
    JrcCrm::AuditEvent.create!(account: @access.account, actor_type: 'User', actor_id: @access.actor.id,
                               resource_type: 'JrcCrm::BackofficeRequest', resource_id: @request_id, event_type: event, from_value: {}, to_value: {},
                               metadata: row.presentation.slice(:id, :number, :source_digest, :archive_sha256))
  end
end
