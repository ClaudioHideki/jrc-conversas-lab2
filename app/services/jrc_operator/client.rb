class JrcOperator::Client
  def initialize(binding)
    @binding = binding
    routes = JSON.parse(ENV.fetch('JRC_OPERATOR_ROUTES', '{}'))
    @config = routes.fetch("#{binding.account_id}:#{binding.company_id}")
    @transport = JrcOperator::Transport.new(@config)
  rescue KeyError, JSON::ParserError
    raise JrcOperator::Error.new('INTEGRATION_NOT_CONFIGURED', 503)
  end

  def inspect
    '#<JrcOperator::Client [FILTERED]>'
  end

  def bemtevi(path, payload, pdf: false)
    allowed = { 'cliente' => :get, 'cliente/planos' => :get, 'cobrancas' => :get, 'cobranca/segundaVia' => :post }
    raise JrcOperator::Error, 'INVALID_ROUTE' unless allowed.key?(path)
    raise JrcOperator::Error, 'SECOND_COPY_NOT_VERIFIED' if pdf && @config['second_copy_verified'] != true

    @transport.request(:btv, allowed.fetch(path), "/#{path}", payload.merge('codcliente' => @binding.bemtevi_customer_id.to_i), pdf: pdf)
  end

  def rede(action, payload, key: nil)
    paths = { ddds: [:get, '/ddds'], availability: [:get, '/availability'], reserve: [:post, '/reservations'],
              release: [:post, '/reservations/release'], reservation: [:get, '/reservations/status'], operation: [:get, '/operations'] }
    method, path = paths.fetch(action)
    @transport.request(:rede, method, "/api/integrations/jrc/v1#{path}",
                       payload.merge('account_id' => @binding.account_id, 'issuer_company_id' => @binding.company_id), key: key)
  end

  def charges
    result = bemtevi('cobrancas', {})
    validate_charge_rows!(result)
    result.map { |row| normalized_charge(row) }
  rescue KeyError
    raise JrcOperator::Error, 'UNSUPPORTED_CHARGES_SCHEMA'
  end

  def collectible!(id)
    charge = charges.find { |row| row['id'] == id.to_s }
    raise JrcOperator::Error, 'CHARGE_NOT_COLLECTIBLE' unless charge && %w[open overdue partial].include?(charge['official_status'])

    charge
  end

  private

  def validate_charge_rows!(rows)
    raise JrcOperator::Error, 'UNSUPPORTED_CHARGES_SCHEMA' unless rows.is_a?(Array)
    raise JrcOperator::Error, 'CUSTOMER_MISMATCH' unless rows.all? do |row|
      row.is_a?(Hash) && row['cod_cliente'].to_s == @binding.bemtevi_customer_id
    end
    raise JrcOperator::Error, 'AMBIGUOUS_CHARGE' unless rows.map { |row| row['codcobranca'].to_s }.uniq.size == rows.size
  end

  def normalized_charge(row)
    id = row.fetch('codcobranca').to_s
    raise JrcOperator::Error, 'UNSUPPORTED_CHARGES_SCHEMA' unless /\A[1-9]\d{0,12}\z/.match?(id)

    { 'id' => id, 'amount' => row['valorcobranca'].to_s, 'due_on' => row['datavencimento'].to_s,
      'official_status' => official_status(row['situacao'].to_s) }
  end

  def official_status(source)
    status = source.present? ? @config.fetch('status_codes', {}).fetch(source, 'unknown') : 'unknown'
    %w[open overdue partial paid cancelled unknown].include?(status) ? status : 'unknown'
  end
end
