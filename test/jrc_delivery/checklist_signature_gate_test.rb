require 'minitest/autorun'
require 'time'

module JrcCrm; end
module JrcBackoffice
  class SignatureRelease
    class << self
      attr_accessor :verified, :calls
      def satisfied?(request)
        self.calls << request
        verified
      end
    end
  end
end
root = ENV.fetch('JRC_SOURCE_ROOT', File.expand_path('../..', __dir__))
require File.join(root, 'app/services/jrc_crm/backoffice_document_checklist')

# Tests the actual checklist's source projection. The external/native evidence
# verifier is stubbed: this is NOT a signature, antivirus or PostgreSQL test.
class ChecklistSignatureGateTest < Minitest::Test
  Attachment = Struct.new(:id, :present) do
    def attached? = present
  end
  Contract = Struct.new(:id, :signature_status, :signed_document, :signed_at)
  Order = Struct.new(:contact, :snapshot)
  Request = Struct.new(:contract, :workflow_version, :sales_order)

  def setup
    JrcBackoffice::SignatureRelease.calls = []
    JrcBackoffice::SignatureRelease.verified = false
    snapshot = {}
    def snapshot.with_indifferent_access = self
    @contract = Contract.new(11, 'signed', Attachment.new(27, true), Time.iso8601('2026-11-09T12:00:00Z'))
    @request = Request.new(@contract, 2, Order.new(nil, snapshot))
  end

  def project
    JrcCrm::BackofficeDocumentChecklist.new(request: @request).send(:source_evidence, 'contract_signed')
  end

  def test_v2_signed_status_and_file_are_not_sufficient_evidence
    assert_nil project
    assert_equal [@request], JrcBackoffice::SignatureRelease.calls
  end

  def test_v2_verified_exact_version_projects_native_document_identity
    JrcBackoffice::SignatureRelease.verified = true
    assert_equal({ contract_id: 11, document_id: 27, signed_at: @contract.signed_at }, project)
    assert_equal [@request], JrcBackoffice::SignatureRelease.calls
  end

  def test_v1_legacy_behavior_does_not_require_the_v2_gate
    @request.workflow_version = 1
    assert_equal 27, project[:document_id]
    assert_empty JrcBackoffice::SignatureRelease.calls
  end

  def test_later_security_invalidation_removes_the_approved_projection
    JrcBackoffice::SignatureRelease.verified = true
    assert project
    JrcBackoffice::SignatureRelease.verified = false
    assert_nil project
    assert_equal 'signed', @contract.signature_status
    assert @contract.signed_document.attached?
  end

  def test_missing_document_is_not_approved
    @contract.signed_document.present = false
    JrcBackoffice::SignatureRelease.verified = true
    assert_nil project
    assert_empty JrcBackoffice::SignatureRelease.calls
  end

  def test_pending_signature_is_not_approved
    @contract.signature_status = 'sent'
    JrcBackoffice::SignatureRelease.verified = true
    assert_nil project
  end

  def test_missing_contract_is_not_approved
    @request.contract = nil
    assert_nil project
  end
end
