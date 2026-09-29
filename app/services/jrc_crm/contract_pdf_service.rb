module JrcCrm
  class ContractPdfService
    def initialize(record)
      @record = record
    end

    def call
      CommercialDocumentService.new(kind: :contract, record: @record).call
    end
  end
end
