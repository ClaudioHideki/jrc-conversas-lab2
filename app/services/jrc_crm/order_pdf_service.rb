module JrcCrm
  class OrderPdfService
    def initialize(record)
      @record = record
    end

    def call
      CommercialDocumentService.new(kind: :order, record: @record).call
    end
  end
end
