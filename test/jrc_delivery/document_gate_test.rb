require 'minitest/autorun'
require 'ostruct'
module ActiveStorage
  class IntegrityError < StandardError; end
end
module JrcBackoffice
  class Requirements
    class Blocked < StandardError; end
  end
  class Documents
    def initialize(request:, actor:); @request = request; end
    def requirements; @request.test_requirements; end
  end
  class DocumentSafety
    class NotClean < StandardError; end
    def initialize(version); @version = version; end
    def current; @version.scan; end
    def bytes!
      @version.bytes_calls = @version.bytes_calls.to_i + 1
      raise ActiveStorage::IntegrityError if @version.unsafe
      'synthetic bytes'
    end
  end
end
require_relative '../../app/services/jrc_backoffice/document_gate'

# Only relations and scan observations are doubles; the gate under test is the
# production implementation. These are not native PostgreSQL acceptance tests.
class DocumentGateTest < Minitest::Test
  Scan = Struct.new(:clean?)
  Version = Struct.new(:document_key, :status, :scan, :bytes_calls, :unsafe)
  class Rows < Array
    attr_reader :filters, :projection, :ordering
    def where(**kwargs); @filters = kwargs; self; end
    def select(sql); @projection = sql; self; end
    def order(*args, **kwargs); @ordering = [args, kwargs]; self; end
    def index_by; to_h { |row| [yield(row), row] }; end
  end
  def request(version: 2, records: [], statuses: {'required' => 'approved'})
    OpenStruct.new(workflow_version: version, account_id: 7, metadata: {'document_statuses' => statuses},
      test_requirements: [{'key' => 'required'}], document_versions: Rows.new(records))
  end
  def test_legacy_status_contract_preserved
    item = request(version: 1)
    assert_equal({'required' => 'approved'}, JrcBackoffice::DocumentGate.statuses(item))
    assert_nil item.document_versions.filters
  end
  def test_missing_file_cannot_use_cached_approval
    assert_equal 'pending', JrcBackoffice::DocumentGate.statuses(request)['required']
  end
  def test_current_clean_approval_is_valid
    v = Version.new('required', 'approved', Scan.new(true))
    assert_equal 'approved', JrcBackoffice::DocumentGate.statuses(request(records: [v]))['required']
  end
  def test_expiration_overrides_cached_approval
    v = Version.new('required', 'expired', Scan.new(true))
    assert_equal 'expired', JrcBackoffice::DocumentGate.statuses(request(records: [v]))['required']
  end
  def test_new_rejection_overrides_cached_approval
    v = Version.new('required', 'rejected', Scan.new(true))
    assert_equal 'rejected', JrcBackoffice::DocumentGate.statuses(request(records: [v]))['required']
  end
  def test_pending_scan_is_not_approval
    v = Version.new('required', 'approved', nil)
    assert_equal 'quarantined', JrcBackoffice::DocumentGate.statuses(request(records: [v]))['required']
  end
  def test_later_quarantine_blocks_cached_approval
    v = Version.new('required', 'approved', Scan.new(false))
    assert_equal 'quarantined', JrcBackoffice::DocumentGate.statuses(request(records: [v]))['required']
  end
  def test_does_not_write_statuses_or_invent_audit
    item = request
    before = Marshal.dump(item.metadata)
    JrcBackoffice::DocumentGate.statuses(item)
    assert_equal before, Marshal.dump(item.metadata)
  end
  def test_query_is_account_scoped_and_selects_latest_versions
    item = request
    JrcBackoffice::DocumentGate.statuses(item)
    assert_equal({account_id: 7, document_key: ['required']}, item.document_versions.filters)
    assert_includes item.document_versions.projection, 'DISTINCT ON (document_key)'
    assert_equal([[:document_key], {version: :desc}], item.document_versions.ordering)
  end
  def test_other_native_registration_evidence_is_preserved
    item = request(statuses: {'required' => 'approved', 'customer_registration' => 'approved'})
    assert_equal 'approved', JrcBackoffice::DocumentGate.statuses(item)['customer_registration']
  end
  def test_critical_gate_verifies_bytes_of_required_files
    v = Version.new('required', 'approved', Scan.new(true))
    JrcBackoffice::DocumentGate.check!(request(records: [v]), required_keys: ['required'])
    assert_equal 1, v.bytes_calls
  end
  def test_preview_does_not_download_private_files
    v = Version.new('required', 'approved', Scan.new(true))
    JrcBackoffice::DocumentGate.statuses(request(records: [v]))
    assert_nil v.bytes_calls
  end
  def test_tampered_bytes_block_a_previously_clean_document
    v = Version.new('required', 'approved', Scan.new(true), 0, true)
    assert_raises(JrcBackoffice::Requirements::Blocked) do
      JrcBackoffice::DocumentGate.check!(request(records: [v]), required_keys: ['required'])
    end
  end
  def test_expired_current_version_blocks_critical_transition
    v = Version.new('required', 'expired', Scan.new(true))
    assert_raises(JrcBackoffice::Requirements::Blocked) do
      JrcBackoffice::DocumentGate.check!(request(records: [v]), required_keys: ['required'])
    end
  end
  def test_non_file_evidence_is_not_replaced_by_an_upload_requirement
    assert_nil JrcBackoffice::DocumentGate.check!(request, required_keys: ['contract_signed'])
  end
  def test_v1_gate_does_not_reinterpret_legacy_approvals
    assert_nil JrcBackoffice::DocumentGate.check!(request(version: 1), required_keys: ['required'])
  end

end
