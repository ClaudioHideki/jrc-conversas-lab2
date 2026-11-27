require 'vips'

class JrcCampaigns::MetaMedia
  TYPES = {
    'image' => %w[image/jpeg image/png],
    'video' => %w[video/mp4 video/3gpp],
    'document' => %w[application/pdf]
  }.freeze
  LIMITS = { 'image' => 5.megabytes, 'video' => 16.megabytes, 'document' => 100.megabytes }.freeze

  def self.validate!(asset)
    types = TYPES.fetch(asset.kind) { raise ArgumentError, 'Mídia não suportada em templates Meta.' }
    raise ArgumentError, 'Formato não suportado pelo template Meta.' unless types.include?(asset.file.content_type)
    raise ArgumentError, 'Arquivo excede o limite Meta.' if asset.file.byte_size > LIMITS.fetch(asset.kind)
    raise ArgumentError, 'Arquivo indisponível no armazenamento.' unless asset.file.blob.service.exist?(asset.file.blob.key)

    asset.file.open { |io| validate_io!(io, asset.kind) }
    true
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError, Vips::Error
    raise ArgumentError, 'Mídia inválida ou indisponível.'
  end

  def self.validate_io!(io, kind)
    types = TYPES.fetch(kind) { raise ArgumentError, 'Tipo não suportado para templates Meta.' }
    raise ArgumentError, 'Arquivo excede o limite Meta.' if io.size > LIMITS.fetch(kind)

    io.rewind
    detected = Marcel::MimeType.for(io, name: nil)
    raise ArgumentError, 'Conteúdo real do arquivo incompatível.' unless types.include?(detected)

    io.rewind
    if kind == 'image'
      image = Vips::Image.new_from_buffer(io.read, '', access: :sequential, fail_on: :error)
      raise ArgumentError, 'Imagem excede 20 milhões de pixels.' if image.width * image.height > 20_000_000
    elsif kind == 'document'
      content = io.read
      raise ArgumentError, 'PDF com conteúdo ativo não permitido.' if content.match?(%r{/(JavaScript|JS|Launch|EmbeddedFile|RichMedia)\b}i)
    end
    io.rewind
    true
  rescue Vips::Error
    raise ArgumentError, 'Imagem inválida ou corrompida.'
  end

  def self.import!(account:, user:, kind:, url:, source_key: nil)
    uri = URI.parse(url.to_s)
    raise ArgumentError, 'Informe uma URL HTTPS pública válida.' unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
    raise ArgumentError, 'Importação pública indisponível com rede privada habilitada.' if SafeFetch.allow_private_network?

    asset = nil
    SafeFetch.fetch(url, max_bytes: LIMITS.fetch(kind), allowed_content_type_prefixes: [], allowed_content_types: TYPES.fetch(kind)) do |result|
      validate_io!(result.tempfile, kind)
      asset = account.jrc_campaign_media_assets.new(kind: kind, created_by: user, source_key: source_key)
      asset.file.attach(io: result.tempfile, filename: result.filename, content_type: result.content_type)
      asset.save!
      validate!(asset)
    end
    asset
  rescue SafeFetch::Error, URI::InvalidURIError, KeyError
    raise ArgumentError, 'Não foi possível importar a mídia HTTPS pública no formato e tamanho permitidos.'
  end
end
