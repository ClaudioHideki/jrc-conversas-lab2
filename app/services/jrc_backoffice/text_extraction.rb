require 'open3'
require 'tmpdir'

# Local parsers only: document bytes and extracted text never leave this process.
# Extraction is deliberately bounded and cannot constitute documentary approval.
class JrcBackoffice::TextExtraction
  def self.call(path, content_type)
    new.call(path, content_type)
  end

  def call(path, content_type)
    Dir.mktmpdir('backoffice-analysis') do |directory|
      if content_type == 'application/pdf'
        output = File.join(directory, 'text.txt')
        return failure('invalid_pdf') unless run('pdftotext', '-f', '1', '-l', '5', '-enc', 'UTF-8', path, output)

        text = File.read(output, 200_000, encoding: 'UTF-8').scrub
        return { text: text, engine: 'poppler', page_limit: 5 } if text.strip.length >= 40

        image = File.join(directory, 'page')
        return failure('render_failed') unless run('pdftoppm', '-f', '1', '-l', '1', '-scale-to', '2000', '-singlefile', '-png', path, image)

        path = "#{image}.png"
      end
      if content_type != 'application/pdf'
        dimensions, _, status = Open3.capture3('timeout', '5', 'identify', '-ping', '-format', '%w %h', path)
        width, height = dimensions.split.map(&:to_i)
        return failure('image_dimensions_exceeded') unless status.success? && width&.positive? && height&.positive? && width * height <= 20_000_000
      end
      ocr(path)
    end
  rescue Errno::ENOENT
    failure('analyzer_unavailable')
  end

  private

  def run(*arguments)
    _, _, status = Open3.capture3('timeout', '30', *arguments)
    status.success?
  end

  def ocr(path)
    output, _, status = Open3.capture3('timeout', '30', 'tesseract', path, 'stdout', '-l', 'por+eng', 'tsv')
    return failure('ocr_unavailable_or_failed') unless status.success?

    words = output.lines.drop(1).filter_map do |line|
      values = line.chomp.split("\t", 12)
      next unless values.length == 12 && values[0] == '5' && values[11].present?

      { text: values[11], confidence: values[10].to_f }
    end
    confidences = words.map { |word| word[:confidence] }.reject(&:negative?)
    { text: words.map { |word| word[:text] }.join(' ').first(200_000), engine: 'tesseract', page_limit: 1,
      ocr_confidence: confidences.any? ? (confidences.sum / confidences.size).round(2) : nil }
  end

  def failure(reason)
    { text: '', engine: 'unavailable', reason: reason }
  end
end
