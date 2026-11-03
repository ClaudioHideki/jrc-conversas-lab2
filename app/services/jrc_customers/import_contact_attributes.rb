class JrcCustomers::ImportContactAttributes
  attr_reader :values, :personal_identifier, :labels

  def initialize(account:, source:)
    @account = account
    @values = source.transform_values { |value| value.to_s.strip.presence }.compact
    @personal_identifier = @values.delete('personal_tax_identifier')
    @labels = @values.delete('labels').to_s.split(',').map { |label| label.strip.downcase }.reject(&:blank?).uniq
    normalize!
  end

  def validate!
    JrcCustomers::ImportContactFields.new(account: @account).apply!(@values)
    @values['company_id'] = positive_id(@values['company_id'], 'company_id') if @values['company_id']
    if @values.key?('company_primary')
      raw = @values['company_primary']
      raise JrcCustomers::ImportIssue.new('Use true or false', field: 'company_primary') unless %w[true false].include?(raw)

      @values['company_primary'] = raw == 'true'
    end
    unknown = @labels - @account.labels.pluck(:title).map(&:downcase)
    return self if unknown.empty?

    raise JrcCustomers::ImportIssue.new('Choose only configured labels', field: 'labels', code: 'UNKNOWN_LABEL')
  end

  private

  def normalize!
    @values['id'] = positive_id(@values['id'], 'id') if @values['id']
    @values['email'] = JrcCustomers::Identity.email(@values['email']) || @values['email'] if @values['email']
    return unless @values['phone_number']

    @values['phone_number'] = JrcCustomers::Identity.phone(@values['phone_number'], country: 'BR') || @values['phone_number']
  end

  def positive_id(value, field)
    parsed = Integer(value, 10)
    return parsed if parsed.positive?

    raise ArgumentError
  rescue ArgumentError
    raise JrcCustomers::ImportIssue.new('Use a positive internal ID', field: field)
  end
end
