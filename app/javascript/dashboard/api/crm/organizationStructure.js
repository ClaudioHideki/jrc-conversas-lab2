/* global axios */
import ApiClient from '../ApiClient';

class OrganizationStructureAPI extends ApiClient {
  constructor() {
    super('crm/organization_structure', { accountScoped: true });
  }

  load() {
    return axios.get(this.url);
  }

  updateSettings(settings) {
    return axios.patch(`${this.url}/settings`, { settings });
  }

  createCompany(company) {
    return axios.post(`${this.url}/companies`, { company });
  }

  updateCompany(id, company, revision) {
    return axios.patch(`${this.url}/companies/${id}`, { company, revision });
  }

  createBusinessUnit(businessUnit) {
    return axios.post(`${this.url}/business_units`, { business_unit: businessUnit });
  }

  updateBusinessUnit(id, businessUnit) {
    return axios.patch(`${this.url}/business_units/${id}`, { business_unit: businessUnit });
  }

  deleteBusinessUnit(id) {
    return axios.delete(`${this.url}/business_units/${id}`);
  }

  createTeamScope(teamScope) {
    return axios.post(`${this.url}/team_scopes`, { team_scope: teamScope });
  }

  updateTeamScope(id, teamScope) {
    return axios.patch(`${this.url}/team_scopes/${id}`, { team_scope: teamScope });
  }

  deleteTeamScope(id) {
    return axios.delete(`${this.url}/team_scopes/${id}`);
  }

  createUserScope(userScope) {
    return axios.post(`${this.url}/user_scopes`, { user_scope: userScope });
  }

  updateUserScope(id, userScope) {
    return axios.patch(`${this.url}/user_scopes/${id}`, { user_scope: userScope });
  }

  deleteUserScope(id) {
    return axios.delete(`${this.url}/user_scopes/${id}`);
  }
}

export default new OrganizationStructureAPI();
