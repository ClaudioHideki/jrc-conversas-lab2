# Resolves only the selected, authorized conversation. Uses the same Liquid drops as Message.
class CannedResponses::Preview
  def initialize(response:, conversation:, user:)
    @response, @conversation, @user = response, conversation, user
    raise ActiveRecord::RecordNotFound unless response.account_id == conversation.account_id
  end

  def call
    contact = @conversation.contact
    message = @conversation.messages.build(sender: @user, inbox: @conversation.inbox, account: @conversation.account)
    attributes = contact.additional_attributes || {}
    aliases = {
      'nome' => contact.name, 'vendedor' => @user.name, 'empresa' => company_name(contact),
      'cidade' => attributes['city'], 'região' => attributes['region'],
      'data' => Time.current.in_time_zone(@conversation.account.reporting_timezone.presence || Time.zone).strftime('%d/%m/%Y'),
      'produto/serviço' => @conversation.custom_attributes&.[]('produto_servico')
    }
    text = @response.content.gsub(/\[(nome|vendedor|empresa|cidade|região|data|produto\/serviço)\]/) do |token|
      aliases[Regexp.last_match(1)].presence || token
    end
    begin
      # No new Liquid engine: retain the native drops, filters and syntax.
      text = Liquid::Template.parse(text).render!(message.send(:message_drops), strict_variables: true)
    rescue Liquid::Error
      # Keep the template visible for manual correction instead of silently erasing missing data.
    end
    { content: text, unresolved: text.scan(/\[[^\]\n]+\]|\{\{[^}]+\}\}/).uniq }
  end

  private

  def company_name(contact)
    return unless contact.company_id && JrcCustomers::DirectoryPolicy.new(@user, :directory).access?

    JrcCrm::CorporateCoverage.new(account: @conversation.account, user: @user)
      .companies(@conversation.account.master_companies).find_by(id: contact.company_id)&.name
  end
end
