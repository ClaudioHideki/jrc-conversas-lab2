require 'csv'
require 'time'

class JrcCampaigns::ConsentImporter
  HEADERS = %w[phone_number source granted_at evidence].freeze
  MAX_ROWS = 500
  MAX_BYTES = 1.megabyte

  def initialize(account:, user:, csv:)
    @account = account
    @user = user
    @csv = csv.to_s
  end

  def preview
    rows = parsed_rows
    { rows: rows, total: rows.size, ready: rows.count { |row| row[:status] == 'ready' },
      existing: rows.count { |row| row[:status] == 'existing' }, errors: rows.count { |row| row[:status] == 'error' } }
  end

  def import!
    result = nil
    @account.with_lock do
      result = preview
      raise ArgumentError, 'Corrija as linhas com erro antes de importar. Nenhum consentimento foi gravado.' if result[:errors].positive?

      result[:rows].select { |row| row[:status] == 'ready' }.each do |row|
        JrcCampaigns::Consent.create!(account: @account, recorded_by: @user, phone_number: row[:phone_number],
                                     granted_at: Time.iso8601(row[:granted_at]), purpose: 'whatsapp_campaigns',
                                     evidence: "Origem: #{row[:source]}\nEvidência: #{row[:evidence]}")
      end
    end
    result.slice(:total, :existing).merge(imported: result[:ready])
  end

  private

  def parsed_rows
    raise ArgumentError, 'Envie um CSV UTF-8 de até 1 MB.' if @csv.bytesize > MAX_BYTES || !@csv.valid_encoding?

    text = @csv.delete_prefix("\uFEFF")
    separator = text.lines.first.to_s.include?(';') ? ';' : ','
    table = CSV.parse(text, headers: true, col_sep: separator, skip_blanks: true)
    unless table.headers == HEADERS
      raise ArgumentError, 'Use as colunas phone_number,source,granted_at,evidence, nessa ordem, sem colunas adicionais.'
    end
    raise ArgumentError, 'Envie entre 1 e 500 destinatários por arquivo.' unless table.size.between?(1, MAX_ROWS)

    seen = Set.new
    table.each_with_index.map do |entry, index|
      row = entry.to_h.transform_values { |value| value.to_s.strip }.symbolize_keys
      row[:phone_number] = JrcCampaigns::PhoneNormalizer.call(row[:phone_number])
      reason = rejection_reason(row, seen)
      seen << row[:phone_number]
      existing = JrcCampaigns::Consent.where(account: @account, phone_number: row[:phone_number], revoked_at: nil).first
      reason ||= 'Registro histórico sem finalidade: confirme individualmente com nova evidência.' if existing && existing.purpose != 'whatsapp_campaigns'
      row.merge(line: index + 2, status: reason ? 'error' : (existing ? 'existing' : 'ready'), reason: reason)
    end
  rescue CSV::MalformedCSVError
    raise ArgumentError, 'CSV inválido. Confira separadores e aspas; use o modelo fornecido.'
  end

  def rejection_reason(row, seen)
    return 'Quantidade de colunas inválida.' if row.key?(nil) || row.keys != HEADERS.map(&:to_sym)
    return 'Telefone inválido; informe DDI e DDD.' unless row[:phone_number]&.match?(/\A\+[1-9]\d{7,14}\z/)
    return 'Telefone repetido neste arquivo.' if seen.include?(row[:phone_number])
    return 'Informe origem e evidência da autorização contínua.' if row[:source].blank? || row[:evidence].blank?
    return 'Origem ou evidência muito longa (máximo 2000 caracteres por campo).' if [row[:source], row[:evidence]].any? { |value| value.size > 2000 }
    return 'Data deve incluir horário e fuso, por exemplo 2026-10-20T14:00:00-03:00.' unless row[:granted_at].match?(/T.*(?:Z|[+-]\d{2}:\d{2})\z/)

    granted_at = Time.iso8601(row[:granted_at])
    return 'Data da autorização não pode estar no futuro.' if granted_at > Time.current

    revoked_at = JrcCampaigns::Consent.where(account: @account, phone_number: row[:phone_number]).maximum(:revoked_at)
    return 'Autorização anterior à revogação: obtenha nova autorização do titular.' if revoked_at && granted_at <= revoked_at

    nil
  rescue ArgumentError
    'Data da autorização inválida; use ISO 8601 com horário e fuso.'
  end
end
