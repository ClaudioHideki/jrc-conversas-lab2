# frozen_string_literal: true

class JrcCulture::Publications
  class Invalid < StandardError; end

  def initialize(access)
    @access = access
  end

  def create!(manual_id:, title:, description:, unit_ids:, pdf:, pptx: nil)
    @access.admin!
    scoped_unit_ids!(unit_ids)
    manual = find_manual!(manual_id) if manual_id.present?
    blobs = {}
    blobs['pdf'] = JrcCulture::Files.upload!(pdf, kind: 'pdf')
    blobs['pptx'] = JrcCulture::Files.upload!(pptx, kind: 'pptx') if pptx.present?
    @access.account.with_lock('FOR NO KEY UPDATE') do
      scopes = scoped_unit_ids!(unit_ids)
      manual = find_manual!(manual_id) if manual_id.present?
      manual ||= JrcCulture::Manual.create!(account: @access.account, name: title)
      version = manual.versions.create!(number: manual.versions.maximum(:number).to_i + 1, title: title, description: description)
      scopes.each { |unit_id| version.audiences.create!(unit_id: unit_id) }
      blobs.each { |kind, blob| version.assets.create!(kind: kind, blob: blob) }
      JrcCulture::Event.record!(@access, 'version_created', version)
      version
    end
  rescue StandardError
    blobs&.each_value { |blob| JrcCulture::Files.discard_unowned(blob) }
    raise
  end

  def transition!(version_id, action)
    @access.account.with_lock('FOR NO KEY UPDATE') do
      version = @access.admin_versions.find(version_id)
      @access.manage_version!(version)
      state = case action
              when 'publish' then publish!(version)
              when 'deactivate' then version.state == 'published' ? 'inactive' : nil
              when 'withdraw' then 'withdrawn' unless version.state == 'withdrawn'
              end
      raise Invalid unless state

      version.update!(state: state)
      JrcCulture::Event.record!(@access, "version_#{action}", version)
      version
    end
  end

  private

  def find_manual!(id)
    known = @access.version_scope.where(manual_id: id).order(number: :desc).first!
    @access.manage_version!(known)
    known.manual
  end

  def scoped_unit_ids!(ids)
    values = Array(ids).uniq
    raise Invalid if values.empty? || values.size > 100

    values.map { |id| @access.admin_scope_id!(id) }.uniq
  end

  def publish!(version)
    raise Invalid unless %w[draft inactive].include?(version.state)

    latest = version.manual.versions.where.not(published_at: nil).maximum(:number)
    raise Invalid if latest && latest > version.number

    earlier = version.manual.versions.published.first
    if earlier
      @access.manage_version!(earlier)
      earlier.update!(state: 'inactive')
      JrcCulture::Event.record!(@access, 'version_superseded', earlier)
    end

    units = version.audiences.pluck(:unit_id)
    eligible = JrcCulture::Grant.eligible.where(account: @access.account, role: 'employee', unit_id: units)
    JrcCulture::Participations.enroll!(version, eligible)
    version.published_at ||= Time.current
    'published'
  end
end
