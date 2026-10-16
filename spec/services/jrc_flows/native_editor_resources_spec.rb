require 'spec_helper'
require 'openssl'
require_relative '../../../app/services/jrc_flows/native_editor_operation'
require_relative '../../../app/services/jrc_flows/native_client'
require_relative '../../../app/services/jrc_flows/native_body_limit'

RSpec.describe JrcFlows::NativeEditorOperation do
  let(:root_id) { '11111111-1111-4111-8111-111111111111' }
  let(:channel_id) { '22222222-2222-4222-8222-222222222222' }
  let(:media_id) { '33333333-3333-4333-8333-333333333333' }
  let(:origin) { 'https://broker.example.test' }
  let(:client) { JrcFlows::NativeClient.new(origin: origin, credential: 'a' * 43, allowed_origins: [origin]) }

  it 'maps the scoped channel catalogue with bounded cursor pagination' do
    op = described_class.resolve!('resource_channels', id: root_id, cursor: 'abc')
    expect(op.path).to eq("/v1/delegated-flows/#{root_id}/resource-channels?pageSize=1&cursor=abc")
    expect([op.scope, op.request_limit, op.response_limit]).to eq(['flow:read', 16_384, 16_384])
  end

  it 'maps action catalogue and local resource writes to the exact channel' do
    read = described_class.resolve!('action_catalog', id: root_id, target_id: channel_id, cursor: 'abc')
    write = described_class.resolve!('save_action_resource', id: root_id, target_id: channel_id)
    expect(read.path).to eq("/v1/delegated-flows/#{root_id}/channels/#{channel_id}/action-catalog?pageSize=1&cursor=abc")
    expect(read.response_limit).to eq(2_200_000)
    expect([write.method, write.scope,
            write.path]).to eq([:post, 'flow:edit', "/v1/delegated-flows/#{root_id}/channels/#{channel_id}/action-resources"])
    expect(write.request_limit).to eq(16_384)
  end

  it 'maps media listing and revocation while limiting control requests separately from catalogue replies' do
    read = described_class.resolve!('media_catalog', id: root_id, target_id: channel_id)
    revoke = described_class.resolve!('revoke_media', id: root_id, target_id: channel_id, resource_id: media_id)
    expect(read.path).to eq("/v1/delegated-flows/#{root_id}/channels/#{channel_id}/media")
    expect(read.response_limit).to eq(2_200_000)
    expect([revoke.method, revoke.scope,
            revoke.path]).to eq([:post, 'flow:edit', "/v1/delegated-flows/#{root_id}/channels/#{channel_id}/media/#{media_id}/revoke"])
    expect(revoke.request_limit).to eq(16_384)
  end

  it 'rejects cross-purpose identifiers and path injection before a request' do
    expect { described_class.resolve!('action_catalog', id: root_id, target_id: '../other') }.to raise_error(described_class::Invalid)
    expect { described_class.resolve!('revoke_media', id: root_id, target_id: channel_id) }.to raise_error(described_class::Invalid)
    expect { described_class.resolve!('get', id: root_id, resource_id: media_id) }.to raise_error(described_class::Invalid)
    expect do
      described_class.resolve!('save_action_resource', id: root_id, target_id: channel_id, cursor: 'abc')
    end.to raise_error(described_class::Invalid)
  end

  it 'preserves the binary upload bytes and idempotency headers in the existing native transport' do
    bytes = "\x00\xFF\x89PNG".b
    request = stub_request(:post, "#{origin}/v1/delegated-flows/#{root_id}/channels/#{channel_id}/media")
              .with(body: bytes, headers: { 'Content-Type' => 'application/octet-stream', 'Idempotency-Key' => media_id,
                                            'X-Jrc-Media-Mime' => 'image/png', 'X-Jrc-Media-Kind' => 'image', 'X-Jrc-Media-Name' => 'file.png' })
              .to_return(status: 200, body: '{"ok":true}', headers: { 'Content-Type' => 'application/json' })
    expect(client.upload_media(root_id: root_id, channel_id: channel_id, io: StringIO.new(bytes), byte_size: bytes.bytesize,
                               mime_type: 'image/png', kind: 'image', file_name: 'file.png', idempotency_key: media_id)).to eq('ok' => true)
    expect(request).to have_been_requested.once
  end

  it 'allows a binary body above the control limit only on the exact upload route' do
    bytes = 'x' * 16_385
    app = ->(env) { [200, {}, [env.fetch('rack.input').read]] }
    limiter = JrcFlows::NativeBodyLimit.new(app)
    path = "/api/v1/accounts/1/jrc_flow_delegation/sessions/#{root_id}/flows/#{root_id}/channels/#{channel_id}/media"
    env = { 'PATH_INFO' => path, 'REQUEST_METHOD' => 'POST', 'CONTENT_TYPE' => 'application/octet-stream',
            'CONTENT_LENGTH' => bytes.bytesize.to_s, 'rack.input' => StringIO.new(bytes) }
    expect(limiter.call(env).first).to eq(200)
    expect(limiter.call(env.merge('PATH_INFO' => "#{path}/#{media_id}/revoke", 'rack.input' => StringIO.new(bytes))).first).to eq(413)
  end
end
