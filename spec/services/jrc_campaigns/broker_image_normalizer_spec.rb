require 'rails_helper'
require 'vips'

RSpec.describe JrcCampaigns::BrokerImageNormalizer do
  let(:webp_bytes) { Rails.root.join('spec/assets/jrc_campaign_static.webp').binread }
  let(:webp_file) { { io: StringIO.new(webp_bytes), filename: 'campanha.webp', content_type: 'image/webp' } }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:delivery) do
    JrcCampaigns::TestDelivery.create!(
      account: account, inbox: inbox, requested_by: admin, phone_number: '+5511999999000',
      idempotency_key: SecureRandom.uuid, payload_digest: 'synthetic-image', status: 'sending'
    )
  end
  let(:asset) do
    record = account.jrc_campaign_media_assets.new(kind: 'image', created_by: admin)
    record.file.attach(webp_file)
    record.save!
    record
  end
  let(:caption) { 'Imagem da campanha com legenda preservada.' }

  it 'normalizes a campaign library WebP before persisting its canonical attachment' do
    original_blob = asset.file.blob
    original_checksum = original_blob.checksum
    message = JrcCampaigns::BrokerMessageSender.call(
      delivery: delivery, user: admin, phone_number: delivery.phone_number,
      step: { 'kind' => 'image', 'body' => caption, 'media_asset_id' => asset.id }, attributes: { 'campaign_id' => 'test:synthetic' }
    )

    expect(message.content).to eq(caption)
    expect(message.attachments.sole.file.content_type).to eq('image/png')
    expect(message.attachments.sole.file.download).to start_with("\x89PNG\r\n\x1A\n".b)
    expect(message.attachments.sole.file.blob_id).not_to eq(original_blob.id)
    expect(asset.reload.file.blob).to have_attributes(id: original_blob.id, checksum: original_checksum)
    expect(original_blob.download).to eq(webp_bytes)
    expect(delivery.reload.metadata['message_id']).to eq(message.id)
  end

  it 'normalizes a fetched WebP before saving the outgoing message' do
    result = SafeFetch::Result.new(tempfile: StringIO.new(webp_bytes), filename: 'campanha.webp', content_type: 'image/webp')
    allow(SafeFetch).to receive(:allow_private_network?).and_return(false)
    expect(SafeFetch).to receive(:fetch).with('https://media.example.test/campanha.webp', any_args).and_yield(result)

    message = JrcCampaigns::BrokerMessageSender.call(
      delivery: delivery, user: admin, phone_number: delivery.phone_number,
      step: { 'kind' => 'image', 'body' => caption, 'media_url' => 'https://media.example.test/campanha.webp' }, attributes: {}
    )

    expect(message.content).to eq(caption)
    expect(message.attachments.sole.file.content_type).to eq('image/png')
    expect(message.attachments.sole.file.download).to start_with("\x89PNG\r\n\x1A\n".b)
  end

  it 'normalizes fetched WebP bytes even when the server claims they are PNG' do
    result = SafeFetch::Result.new(tempfile: StringIO.new(webp_bytes), filename: 'claimed.png', content_type: 'image/png')
    allow(SafeFetch).to receive(:allow_private_network?).and_return(false)
    expect(SafeFetch).to receive(:fetch).with('https://media.example.test/claimed.png', any_args).and_yield(result)

    message = JrcCampaigns::BrokerMessageSender.call(
      delivery: delivery, user: admin, phone_number: delivery.phone_number,
      step: { 'kind' => 'image', 'body' => caption, 'media_url' => 'https://media.example.test/claimed.png' }, attributes: {}
    )

    expect(message.content).to eq(caption)
    expect(message.attachments.sole.file.content_type).to eq('image/png')
    expect(message.attachments.sole.file.download).to start_with("\x89PNG\r\n\x1A\n".b)
  end

  it 'preserves an existing PNG library blob and its campaign caption' do
    asset.file.attach(io: StringIO.new(Rails.root.join('spec/assets/avatar.png').binread), filename: 'original.png', content_type: 'image/png')
    original_blob_id = asset.file.blob_id
    message = JrcCampaigns::BrokerMessageSender.call(
      delivery: delivery, user: admin, phone_number: delivery.phone_number,
      step: { 'kind' => 'image', 'body' => caption, 'media_asset_id' => asset.id }, attributes: {}
    )

    expect(message.content).to eq(caption)
    expect(message.attachments.sole.file.blob_id).to eq(original_blob_id)
  end

  it 'reuses a persisted delivery without creating another derived PNG blob' do
    values = { delivery: delivery, user: admin, phone_number: delivery.phone_number,
               step: { 'kind' => 'image', 'body' => caption, 'media_asset_id' => asset.id }, attributes: {} }
    message = JrcCampaigns::BrokerMessageSender.call(**values)

    expect do
      expect(JrcCampaigns::BrokerMessageSender.call(**values).id).to eq(message.id)
    end.not_to change(ActiveStorage::Blob, :count)
  end

  it 'rolls back a rejected animated campaign image without creating a message or replacing its source' do
    asset.file.attach(io: StringIO.new(Rails.root.join('spec/assets/jrc_campaign_animated.webp').binread),
                      filename: 'animated.webp', content_type: 'image/webp')
    original_blob_id = asset.file.blob_id

    expect do
      JrcCampaigns::BrokerMessageSender.call(
        delivery: delivery, user: admin, phone_number: delivery.phone_number,
        step: { 'kind' => 'image', 'body' => caption, 'media_asset_id' => asset.id }, attributes: {}
      )
    end.to raise_error(ArgumentError, /animad/i)

    expect(account.messages).to be_empty
    expect(delivery.reload.metadata).not_to have_key('message_id')
    expect(asset.reload.file.blob_id).to eq(original_blob_id)
    expect(ActiveStorage::Blob.exists?(original_blob_id)).to be(true)
  end

  it 'rolls back the derived attachment when a later delivery write fails' do
    original_blob_id = asset.file.blob_id
    delivery
    blob_ids = ActiveStorage::Blob.pluck(:id)
    allow(delivery).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(delivery))

    expect do
      JrcCampaigns::BrokerMessageSender.call(
        delivery: delivery, user: admin, phone_number: delivery.phone_number,
        step: { 'kind' => 'image', 'body' => caption, 'media_asset_id' => asset.id }, attributes: {}
      )
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(account.messages).to be_empty
    expect(ActiveStorage::Blob.pluck(:id)).to match_array(blob_ids)
    expect(asset.reload.file.blob_id).to eq(original_blob_id)
    expect(delivery.reload.metadata).not_to have_key('message_id')
  end

  describe 'isolated normalizer' do
    subject(:normalized) { described_class.call(kind: kind, file: file) }

    let(:kind) { 'image' }
    let(:file) { webp_file }

    it 'decodes an actual static WebP into a PNG with the same pixels and alpha' do
      expect(normalized).to include(filename: 'campanha.png', content_type: 'image/png')
      image = Vips::Image.new_from_buffer(normalized.fetch(:io).string, '')
      expect([image.width, image.height]).to eq([2, 2])
      expect(image.getpoint(0, 0)).to eq([0, 128, 255, 128])
      expect(normalized.fetch(:io).size).to be <= 5.megabytes
    end

    it 'reads an existing blob without changing its bytes or checksum' do
      blob = asset.file.blob
      expect { described_class.call(kind: kind, file: blob) }.not_to(change { blob.reload.checksum })
      expect(blob.download).to eq(webp_bytes)
    end

    %w[lossy extended].each do |encoding|
      it "normalizes a real #{encoding} static WebP" do
        file[:io] = StringIO.new(Rails.root.join("spec/assets/jrc_campaign_#{encoding}.webp").binread)
        image = Vips::Image.new_from_buffer(normalized.fetch(:io).string, '')
        expect([image.width, image.height]).to eq([2, 2])
        expect(normalized.fetch(:content_type)).to eq('image/png')
      end
    end

    %w[image/png image/jpeg].each do |mime|
      context "with existing #{mime}" do
        let(:image_bytes) do
          path = mime == 'image/png' ? 'spec/assets/avatar.png' : 'spec/assets/jrc_campaign_static.jpg'
          Rails.root.join(path).binread
        end
        let(:file) { { io: StringIO.new(image_bytes), filename: 'original', content_type: mime } }

        it 'returns the original attachable with its original bytes and stream position' do
          expect(normalized).to equal(file)
          expect(file.fetch(:io).read).to eq(image_bytes)
        end

        it 'cannot hide WebP bytes behind another declared image MIME' do
          file[:io] = StringIO.new(webp_bytes)
          expect(normalized).to include(content_type: 'image/png')
          expect(normalized.fetch(:io).string).to start_with("\x89PNG\r\n\x1A\n".b)
        end
      end
    end

    %w[sticker document].each do |media_kind|
      context "with an intentional #{media_kind}" do
        let(:kind) { media_kind }

        it 'preserves the existing WebP path unchanged' do
          expect(file.fetch(:io)).not_to receive(:read)
          expect(normalized).to equal(file)
        end
      end
    end

    it 'rejects corrupt WebP instead of falling back to a sticker' do
      file[:io] = StringIO.new('RIFF'.b + [12].pack('V') + 'WEBPinvalid!'.b)
      expect { normalized }.to raise_error(ArgumentError, /WebP/i)
    end

    it 'rejects another file format disguised as WebP' do
      file[:io] = StringIO.new(Rails.root.join('spec/assets/avatar.png').binread)
      expect { normalized }.to raise_error(ArgumentError, /WebP/i)
    end

    it 'rejects a real two-frame WebP rather than silently sending only its first frame' do
      file[:io] = StringIO.new(Rails.root.join('spec/assets/jrc_campaign_animated.webp').binread)
      expect { normalized }.to raise_error(ArgumentError, /animad/i)
    end

    it 'bounds source bytes before conversion' do
      stub_const('JrcCampaigns::BrokerImageNormalizer::MAX_INPUT_BYTES', webp_bytes.bytesize - 1)
      expect { normalized }.to raise_error(ArgumentError, /10 MB/)
    end

    it 'bounds decoded pixels before encoding PNG' do
      stub_const('JrcCampaigns::BrokerImageNormalizer::MAX_PIXELS', 3)
      expect(Vips::Image).not_to receive(:new_from_buffer)
      expect { normalized }.to raise_error(ArgumentError, /pixels/)
    end

    it 'rejects a truncated RIFF container before starting the decoder' do
      file[:io] = StringIO.new(webp_bytes.byteslice(0, webp_bytes.bytesize - 2))
      expect(Vips::Image).not_to receive(:new_from_buffer)
      expect { normalized }.to raise_error(ArgumentError, /WebP/)
    end

    it 'rejects an overflowing RIFF chunk length before starting the decoder' do
      bytes = webp_bytes.dup
      bytes[16, 4] = [0xFFFFFFFF].pack('V')
      file[:io] = StringIO.new(bytes)
      expect(Vips::Image).not_to receive(:new_from_buffer)
      expect { normalized }.to raise_error(ArgumentError, /WebP/)
    end

    it 'checks the encoded frame even when an extended header claims a small canvas' do
      bytes = Rails.root.join('spec/assets/jrc_campaign_extended.webp').binread
      frame = bytes.index('VP8 ', 30) + 8
      bytes[frame + 6, 4] = [5000, 5000].pack('v2')
      file[:io] = StringIO.new(bytes)
      expect(Vips::Image).not_to receive(:new_from_buffer)
      expect { normalized }.to raise_error(ArgumentError, /pixels/)
    end

    it 'rejects huge canvas arithmetic before starting the decoder' do
      bytes = Rails.root.join('spec/assets/jrc_campaign_extended.webp').binread
      bytes[24, 6] = "\xFF".b * 6
      file[:io] = StringIO.new(bytes)
      expect(Vips::Image).not_to receive(:new_from_buffer)
      expect { normalized }.to raise_error(ArgumentError, /pixels/)
    end

    it 'bounds the encoded PNG before returning an attachable' do
      stub_const('JrcCampaigns::BrokerImageNormalizer::MAX_OUTPUT_BYTES', 32)
      expect { normalized }.to raise_error(ArgumentError, /5 MB/)
    end

    it 'restores the original source position and leaves it open' do
      file.fetch(:io).read(3)
      normalized
      expect(file.fetch(:io).pos).to eq(3)
      expect(file.fetch(:io)).not_to be_closed
    end

    it 'also restores the original source position after conversion is rejected' do
      file[:io] = StringIO.new('corrupt WebP')
      file.fetch(:io).read(2)
      expect { normalized }.to raise_error(ArgumentError)
      expect(file.fetch(:io).pos).to eq(2)
      expect(file.fetch(:io)).not_to be_closed
    end
  end
end
