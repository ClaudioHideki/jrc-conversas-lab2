# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private, :protected, :ssn,
  :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes, :identifier_hash,
  :message, :context, :history, :summary, :suggested_reply, :body, :audio, :audio_base64, :arguments, :objective,
  :source_ciphertext, :credential_ciphertext, :content, :workflow_json, :secrets, :payload_ciphertext, :flow_approvals
]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]
Rails.application.config.filter_parameters += [:encrypted_control_key, :control_key, :controlKey, :pairing_code, :qrcode, :qr_code]
Rails.application.config.filter_parameters += [:pabx_username, :api_username]

Rails.application.config.filter_parameters += [:csv]

# Backoffice documentary content and human review are never request-log payloads.
Rails.application.config.filter_parameters += [:file, :files, :reason, :description, :extracted_fields]
Rails.application.config.filter_parameters += [:next_step, :customer_feedback, :change_reason, :result, :notes]
Rails.application.config.filter_parameters += [:personal_tax_identifier, :cpf, :lookup_digest]
Rails.application.config.filter_parameters += [:column_mapping, :import_options]
