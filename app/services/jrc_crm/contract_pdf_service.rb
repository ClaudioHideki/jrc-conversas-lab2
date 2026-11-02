module JrcCrm
  class ContractPdfService
    def initialize(record, revision: nil)
      @record = record
      @revision = revision
    end

    def call
      CommercialDocumentService.new(kind: :contract, record: @record, revision: @revision).call
    end
  end
end
