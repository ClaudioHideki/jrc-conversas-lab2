/* global axios */
export const runNicoModuleAction = async (
  accountId,
  action,
  { whatsapp } = {}
) => {
  const args = action.parameters;
  const base = `/api/v1/accounts/${Number(accountId)}`;
  const without = (...keys) =>
    Object.fromEntries(
      Object.entries(args).filter(([key]) => !keys.includes(key))
    );
  const proposal = `${base}/crm/proposals/${Number(args.proposal_id)}`;
  const campaign = `${base}/jrc_campaigns/campaigns/${Number(args.campaign_id)}`;
  const projectTasks = `${base}/projects/projects/${Number(args.project_id)}/tasks`;
  let response;
  switch (action.operation) {
    case 'create_project_task':
      response = await axios.post(projectTasks, {
        task: without('project_id'),
      });
      break;
    case 'update_project_task': {
      const task = without(
        'project_id',
        'task_id',
        'clear_assignee',
        'clear_parent'
      );
      if (args.clear_assignee) task.assignee_id = null;
      if (args.clear_parent) task.parent_id = null;
      response = await axios.patch(`${projectTasks}/${Number(args.task_id)}`, {
        task,
      });
      break;
    }
    case 'create_product':
      response = await axios.post(`${base}/crm/products`, { product: args });
      break;
    case 'update_product':
      response = await axios.patch(
        `${base}/crm/products/${Number(args.product_id)}`,
        { product: without('product_id') }
      );
      break;
    case 'update_inbox_settings':
      response = await axios.patch(
        `${base}/inboxes/${Number(args.inbox_id)}`,
        without('inbox_id')
      );
      break;
    case 'update_account_profile':
      response = await axios.patch(base, args);
      break;
    case 'create_deal':
      response = await axios.post(`${base}/crm/deals`, { deal: args });
      break;
    case 'update_deal':
      response = await axios.patch(
        `${base}/crm/deals/${Number(args.deal_id)}`,
        { deal: without('deal_id') }
      );
      break;
    case 'update_proposal':
      response = await axios.patch(proposal, {
        proposal: without('proposal_id'),
      });
      break;
    case 'add_proposal_item':
      response = await axios.post(`${proposal}/items`, {
        item: without('proposal_id'),
      });
      break;
    case 'request_proposal_approval':
      response = await axios.post(`${proposal}/request_approval`);
      break;
    case 'approve_proposal':
      response = await axios.post(
        `${proposal}/approve`,
        without('proposal_id')
      );
      break;
    case 'send_proposal':
      response = await axios.post(`${proposal}/send_proposal`, {
        channel: args.channel,
      });
      break;
    case 'update_campaign':
      response = await axios.patch(campaign, {
        campaign: without('campaign_id'),
      });
      break;
    case 'approve_campaign':
      response = await axios.post(`${campaign}/approve`, {
        digest: args.digest,
      });
      break;
    case 'create_email':
      response = await axios.post(`${base}/conversations`, {
        inbox_id: args.inbox_id,
        contact_id: args.contact_id,
        status: 'open',
        additional_attributes: { mail_subject: args.subject },
        message: { content: args.content, private: false },
      });
      break;
    case 'set_availability':
      response = await axios.post('/api/v1/profile/availability', {
        profile: {
          account_id: Number(accountId),
          availability: args.availability,
        },
      });
      break;
    case 'whatsapp_call': {
      const result = await whatsapp.initiateOutboundCall({
        conversationId: args.conversation_id,
      });
      if (!result?.id)
        throw new Error(
          result?.message ||
            'A chamada não foi iniciada. Verifique a permissão do cliente e o estado do canal.'
        );
      return `Chamada ${result.id} iniciada. Acompanhe o estado no painel de chamadas.`;
    }
    case 'proposal_pdf':
    case 'export_campaign': {
      const pdf = action.operation === 'proposal_pdf';
      response = await axios.get(
        pdf ? `${proposal}/pdf?download=true` : `${campaign}/export`,
        { responseType: 'blob' }
      );
      const url = URL.createObjectURL(response.data);
      const link = document.createElement('a');
      link.href = url;
      link.download = pdf
        ? `proposta-${args.proposal_id}.pdf`
        : `campanha-${args.campaign_id}.csv`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      return 'Arquivo gerado pelo módulo e disponibilizado para download.';
    }
    default:
      throw new Error('Operação não disponível.');
  }
  const data = response.data?.data || response.data;
  const id = data?.id || data?.proposal?.id || data?.deal?.id;
  return `O módulo confirmou a operação${id ? ` no registro ${id}` : ''}${data?.status ? ` (estado: ${data.status})` : ''}.`;
};
