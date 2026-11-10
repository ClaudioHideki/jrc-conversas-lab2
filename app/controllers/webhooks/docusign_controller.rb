class Webhooks::DocusignController < ActionController::API
  def events
    JrcBackoffice::Docusign::ConnectInbox.receive!(public_id: request.path_parameters[:integration_id], raw_body: @raw_body,
                                                   signatures: (1..5).filter_map { |index| request.headers["X-Docusign-Signature-#{index}"] })
    head :accepted
  rescue JrcBackoffice::Docusign::ConnectInbox::Rejected
    head :unauthorized
  end

  protected

  # Runs before ActionController instrumentation parses/logs the Connect payload.
  # Keep this filter local: existing webhooks keep their native logging behavior.
  def process_action(*)
    request.set_header('action_dispatch.parameter_filter', [/.*/])
    @raw_body = request.body.read(2.megabytes + 1).to_s
    request.body.rewind
    return head :payload_too_large if @raw_body.bytesize > 2.megabytes

    super
  end
end
