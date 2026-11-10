require 'json'
require 'digest'

# A closed, typed vocabulary. No eval, arbitrary model paths or submitted proof.
class JrcBackoffice::RequirementDefinition
  KINDS = %w[document information validation approval signature field conditional consultation confirmation human_activity].freeze
  LEAF_KINDS = (KINDS - ['conditional']).freeze
  STAGES = %w[documentation approval contract implementation provisioning finance].freeze
  INFORMATION_TYPES = %w[text boolean number email phone].freeze
  FIELDS = %w[customer.name customer.tax_id contact.name contact.email contact.phone_number order.payment_condition].freeze
  HUMAN_KINDS = %w[consultation confirmation human_activity].freeze
  VALIDATIONS = %w[manual_review customer_registration billing_registration implementation_info signatory_powers].freeze
  APPROVALS = %w[crm.order_price crm.order_terms backoffice.release contracts.company_signature contracts.draft_review].freeze
  CONDITION_FIELDS = %w[request_kind business_unit_id product_id customer_kind].freeze
  OPERATORS = %w[equal not_equal in].freeze
  KEYS = %w[label kind required blocking stage document_key answer_type source field conditions requirement_kind instructions reviewer_ids reviewer_team_ids requires_human_review].freeze
  MISSING = Object.new.freeze

  def self.normalize(input)
    raise ArgumentError, 'Requirement must be an object' unless input.is_a?(Hash)

    row = input.transform_keys(&:to_s)
    raise ArgumentError, 'Unsupported requirement fields' unless (row.keys - KEYS).empty?
    raise ArgumentError, 'Provide a requirement label of at most 200 characters' unless text?(row['label'], 200)
    raise ArgumentError, 'Unsupported requirement kind' unless KINDS.include?(row['kind'])
    raise ArgumentError, 'Select the stage where the requirement must be satisfied' unless STAGES.include?(row['stage'])
    %w[required blocking].each do |key|
      raise ArgumentError, "#{key} must be an explicit boolean" unless [true, false].include?(row[key])
    end
    raise ArgumentError, 'Only a required item may block the workflow' if row['blocking'] && !row['required']

    kind = leaf_kind(row)
    validate_conditions!(row)
    validate_leaf!(row, kind)
    validate_human!(row, kind)
    row.merge('label' => row['label'].strip)
  end

  def self.leaf_kind(row)
    return row['kind'] unless row['kind'] == 'conditional'

    kind = row['requirement_kind']
    raise ArgumentError, 'A conditional requirement needs an explicit supported type' unless LEAF_KINDS.include?(kind)

    kind
  end

  # The company-signature gate consumes the accepted signature evidence. It is
  # a release requirement, not a prerequisite for dispatching that signature.
  def self.post_signature?(row)
    kind = leaf_kind(row)
    kind == 'signature' || (kind == 'approval' && row['source'] == 'contracts.company_signature')
  end

  def self.validate_leaf!(row, kind)
    case kind
    when 'document'
      key = row['document_key']
      raise ArgumentError, 'Provide a configured document key' unless key.is_a?(String) && key.match?(/\A[a-z0-9_-]{1,80}\z/)
      raise ArgumentError, 'Signature artifacts are managed by their native flow' if key.start_with?('signature_delivery_') ||
        %w[contract_signed contract_generated].include?(key)
    when 'information'
      raise ArgumentError, 'Unsupported information type' unless INFORMATION_TYPES.include?(row['answer_type'])
    when 'validation'
      raise ArgumentError, 'Unsupported native validation' unless VALIDATIONS.include?(row['source'])
      if row['source'] == 'signatory_powers' && STAGES.index(row['stage']) < STAGES.index('contract')
        raise ArgumentError, 'Signatory powers require a generated native contract version'
      end
    when 'approval'
      raise ArgumentError, 'Select a native approval gate' unless APPROVALS.include?(row['source'])
      stage = row['source'].start_with?('contracts.') ? 'contract' : 'approval'
      raise ArgumentError, 'Approval must be checked at its native release stage' unless row['stage'] == stage
    when 'signature'
      raise ArgumentError, 'Signature can only block the contract stage or a later stage' if STAGES.index(row['stage']) < STAGES.index('contract')
    when 'field'
      raise ArgumentError, 'Unsupported native registration field' unless FIELDS.include?(row['field'])
    end
    allowed = { 'document' => ['document_key'], 'information' => ['answer_type'],
                'validation' => ['source'], 'approval' => ['source'], 'signature' => [], 'field' => ['field'],
                'consultation' => [], 'confirmation' => [], 'human_activity' => [] }.fetch(kind)
    extras = row.keys & %w[document_key answer_type source field]
    raise ArgumentError, 'Fields do not match the requirement type' unless (extras - allowed).empty?
  end

  def self.validate_human!(row, kind)
    if row.key?('requires_human_review')
      raise ArgumentError, 'Human review must be an explicit document flag' unless kind == 'document' && [true, false].include?(row['requires_human_review'])
    end
    fields = row.keys & %w[instructions reviewer_ids reviewer_team_ids]
    return if fields.empty? && !HUMAN_KINDS.include?(kind)
    raise ArgumentError, 'Reviewer fields require a human requirement' unless HUMAN_KINDS.include?(kind)
    raise ArgumentError, 'Describe the human check explicitly' unless text?(row['instructions'], 4000)
    ids, teams = row.fetch('reviewer_ids', []), row.fetch('reviewer_team_ids', [])
    [ids, teams].each do |values|
      unless values.is_a?(Array) && values.size <= 50 && values.uniq == values && values.all? { |id| id.is_a?(Integer) && id.positive? }
        raise ArgumentError, 'Reviewers must be explicit native user or team IDs'
      end
    end
    raise ArgumentError, 'Configure at least one responsible human or team' if ids.empty? && teams.empty?
  end

  def self.response_payload!(definition, payload)
    kind = leaf_kind(definition)
    raise ArgumentError, 'Response must be an object' unless payload.is_a?(Hash)
    if kind == 'information'
      raise ArgumentError, 'Only the value may be supplied' unless payload.keys == ['value']
      answer!(definition, payload.fetch('value'))
    elsif kind == 'validation' && definition['source'] == 'manual_review'
      raise ArgumentError, 'Choose an explicit manual decision' unless payload.keys == ['decision'] && %w[approved rejected].include?(payload['decision'])
    elsif HUMAN_KINDS.include?(kind)
      allowed = kind == 'confirmation' ? %w[confirmed rejected] : %w[completed rejected]
      unless payload.keys.sort == %w[decision note] && allowed.include?(payload['decision']) && text?(payload['note'], 4000)
        raise ArgumentError, 'Record an explicit human result and supporting note'
      end
    else
      raise ArgumentError, 'This requirement is verified by its native module'
    end
    payload
  end

  def self.validate_conditions!(row)
    if row['kind'] != 'conditional'
      raise ArgumentError, 'Conditions require the conditional type' if row.key?('conditions') || row.key?('requirement_kind')
      return
    end
    conditions = row['conditions']
    raise ArgumentError, 'Provide one to ten explicit conditions' unless conditions.is_a?(Array) && conditions.size.between?(1, 10)

    conditions.each do |condition|
      raise ArgumentError, 'Invalid condition fields' unless condition.is_a?(Hash) && condition.keys.sort == %w[field operator value]
      field, operator, value = condition.values_at('field', 'operator', 'value')
      raise ArgumentError, 'Unsupported condition field or operator' unless CONDITION_FIELDS.include?(field) && OPERATORS.include?(operator)
      values = operator == 'in' ? value : [value]
      raise ArgumentError, 'Condition needs one to twenty values' unless values.is_a?(Array) && values.size.between?(1, 20)
      valid = values.all? do |item|
        case field
        when 'business_unit_id', 'product_id' then item.is_a?(Integer) && item.positive?
        when 'customer_kind' then %w[individual company].include?(item)
        when 'request_kind' then %w[fulfillment approval change cancellation].include?(item)
        end
      end
      raise ArgumentError, 'Invalid condition value' unless valid
    end
  end

  # Unknown facts cannot turn a blocking requirement into 'not applicable'.
  def self.applicable(row, facts)
    return true unless row['kind'] == 'conditional'

    outcomes = row.fetch('conditions').map do |condition|
      actual = facts.fetch(condition.fetch('field'), MISSING)
      next :unknown if actual.equal?(MISSING) || actual.nil?

      expected = condition.fetch('value')
      case condition.fetch('operator')
      when 'equal' then actual.is_a?(Array) ? actual.include?(expected) : actual == expected
      when 'not_equal' then actual.is_a?(Array) ? !actual.include?(expected) : actual != expected
      when 'in' then actual.is_a?(Array) ? (actual & expected).any? : expected.include?(actual)
      end
    end
    return false if outcomes.include?(false)
    return :unknown if outcomes.include?(:unknown)

    true
  end

  def self.answer!(row, value)
    raise ArgumentError, 'Only information requirements accept values' unless leaf_kind(row) == 'information'

    valid = case row.fetch('answer_type')
            when 'boolean' then [true, false].include?(value)
            when 'number' then value.is_a?(Numeric) && value.finite?
            when 'email' then text?(value, 254) && value.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
            when 'phone' then text?(value, 40) && value.match?(/\A[+\d(). -]+\z/) && value.count('0-9').between?(7, 20)
            else text?(value, 4000)
            end
    raise ArgumentError, 'Invalid information value' unless valid

    value.is_a?(String) ? value.strip : value
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def self.canonical(value)
    case value
    when Hash then value.keys.map(&:to_s).sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def self.text?(value, maximum)
    value.is_a?(String) && value.strip.length.between?(1, maximum)
  end
end
