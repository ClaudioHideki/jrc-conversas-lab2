module JrcOperations
  class OptionsController < BaseController
    def index
      projects = Access.project_access?(Current.account_user)
      account = Current.account
      data = {
        users: account.users.order('users.name').limit(1000).pluck('users.id', 'users.name').map { |id, name| { id: id, name: name } },
        teams: account.teams.order(:name).limit(1000).pluck(:id, :name).map { |id, name| { id: id, name: name } }
      }
      data[:templates] = id_name_options(JrcProjects::ProjectTemplate.where(account_id: account.id, active: true)) if projects
      render json: { data: data }
    end

    def tickets
      scope = Access.tickets(Current.account_user).includes(:status)
      if params[:q].present?
        scope = scope.where('title ILIKE ?', "%#{JrcServiceDesk::Ticket.sanitize_sql_like(params[:q].to_s)}%")
      end
      render json: { data: scope.order(updated_at: :desc).limit(30).filter_map { |ticket|
        policy = JrcServiceDesk::TicketPolicy.new(Access.r2_context(Current.account_user), ticket)
        next unless policy.update?
        { id: ticket.id, number: ticket.id, title: ticket.title, status: ticket.status.name, unit_id: ticket.unit_id, can_update: true }
      } }
    end

    def deals
      raise Pundit::NotAuthorizedError unless Access.crm?(Current.account_user)
      scope = JrcCrm::Deal.where(account_id: Current.account.id, status: 'won')
      scope = scope.where(owner_id: Current.user.id) unless Access.admin?(Current.account_user)
      q = params[:q].to_s.strip
      scope = scope.where('title ILIKE ?', "%#{JrcCrm::Deal.sanitize_sql_like(q)}%") if q.present?
      render json: { data: scope.order(updated_at: :desc).limit(30).as_json(only: %i[id title contact_id status]) }
    end

    def contacts
      scope = Current.account.contacts
      if params[:id].present?
        record = Access.contact!(Current.account_user, params[:id])
        render json: { data: [record.as_json(only: %i[id name email phone_number])] }
      else
        q = params[:q].to_s.strip
        scope = scope.where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q', q: "%#{Contact.sanitize_sql_like(q)}%") if q.present?
        records = scope.order(:name).limit(25).filter_map do |record|
          record.as_json(only: %i[id name email phone_number]) if ContactPolicy.new(Access.user_context(Current.account_user), record).show?
        end
        render json: { data: records }
      end
    end

    private

    def id_name_options(scope)
      scope.order(:name).limit(1000).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    end
  end
end
