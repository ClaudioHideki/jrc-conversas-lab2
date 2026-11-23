# frozen_string_literal: true

# Rails SQL logging reads Base filters, independently of a model's inspect filters.
private_ending_attributes = %i[private_definition definition_sha256 private_rule_code]
Rails.application.config.filter_parameters += private_ending_attributes

ActiveSupport.on_load(:active_record) do
  self.filter_attributes += private_ending_attributes
end
