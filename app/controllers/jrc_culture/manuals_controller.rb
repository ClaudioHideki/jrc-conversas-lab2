# frozen_string_literal: true

class JrcCulture::ManualsController < JrcCulture::BaseController
  rescue_from JrcCulture::Participations::VersionUnavailable do
    render json: { code: 'version_unavailable' }, status: :conflict
  end

  def index
    entries = access.own_participations.includes(version: :assets, grant: :unit)
    entries = entries.where(version_id: access.visible_versions.select(:id)).order(version_id: :desc, id: :desc)
    render json: { entries: entries.map { |row| participation_data(row) } }
  end

  def confirm
    row = JrcCulture::Participations.new(access).confirm!(version_id: params[:id], grant_id: params.require(:grant_id))
    render json: participation_data(row)
  end

  def file
    version = access.visible_versions.find(params[:id])
    asset = version.assets.find_by!(kind: params[:kind])
    disposition = asset.kind == 'pdf' && params[:download] != '1' ? 'inline' : 'attachment'
    protected_file(asset.blob, disposition: disposition)
  end

  private

  def participation_data(row)
    version_data(row.version).merge(grant_id: row.grant_id, unit: row.grant.unit.name, current: row.version.state == 'published',
                                    confirmed_at: row.confirmed_at)
  end
end
