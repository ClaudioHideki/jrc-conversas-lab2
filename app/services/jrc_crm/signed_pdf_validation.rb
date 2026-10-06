module JrcCrm
  class SignedPdfValidation
    MAX_BYTES = 20 * 1024 * 1024
    def self.validate!(file)
      raise ArgumentError, 'Anexe o PDF assinado.' unless file && file.respond_to?(:tempfile)
      unless file.size.positive? && file.size <= MAX_BYTES && file.content_type == 'application/pdf' && File.extname(file.original_filename).downcase == '.pdf'
        raise ArgumentError, 'O documento assinado deve ser PDF de até 20 MB.'
      end
      file.tempfile.rewind
      bytes = file.tempfile.read
      unless bytes.start_with?('%PDF-') && bytes.rstrip.end_with?('%%EOF') && bytes.include?('/Type') && bytes.include?('startxref')
        raise ArgumentError, 'O arquivo não contém uma estrutura PDF válida.'
      end
      true
    ensure
      file.tempfile.rewind if file&.respond_to?(:tempfile)
    end
  end
end
