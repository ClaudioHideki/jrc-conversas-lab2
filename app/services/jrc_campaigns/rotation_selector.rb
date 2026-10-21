class JrcCampaigns::RotationSelector
  def initialize(campaign)
    @campaign = campaign
    @items = campaign.sending_inbox_links
    @usage = existing_usage
  end

  def inbox_for(index)
    raise ActiveRecord::RecordNotFound, 'Nenhuma caixa de envio selecionada' if items.empty?

    case campaign.rotation_mode
    when 'random' then items.sample.inbox
    when 'weighted' then weighted_item(index).inbox
    when 'least_used' then least_used_item.inbox
    when 'priority' then items.min_by { |item| item.respond_to?(:position) ? item.position : 0 }.inbox
    else items[index % items.length].inbox
    end
  end

  private

  attr_reader :campaign, :items

  def existing_usage
    inbox_ids = items.map { |item| item.inbox.id }
    counts = JrcCampaigns::Recipient.where(inbox_id: inbox_ids)
                                     .where('scheduled_at >= ?', Time.current.beginning_of_day)
                                     .group(:inbox_id)
                                     .count
    Hash.new(0).merge(counts)
  end

  def least_used_item
    item = items.min_by do |candidate|
      position = candidate.respond_to?(:position) ? candidate.position : 0
      [@usage[candidate.inbox.id], position]
    end
    @usage[item.inbox.id] += 1
    item
  end

  def weighted_item(index)
    expanded = items.flat_map { |item| Array.new(item.weight.clamp(1, 100), item) }
    expanded[index % expanded.length]
  end
end
