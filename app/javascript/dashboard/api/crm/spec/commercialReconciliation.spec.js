import { contractsAPI, backofficeAPI } from '../commercialCycle';
describe('Commercial reconciliation API',()=>{
  beforeEach(()=>{vi.stubGlobal('axios',{post:vi.fn().mockResolvedValue({data:{}})});window.history.replaceState({},'', '/app/accounts/12/crm');});
  afterEach(()=>{vi.unstubAllGlobals();window.history.replaceState({},'', '/');});
  it('registers the actual signed PDF with an explicit timezone and native multipart endpoint',async()=>{
    const file=new File(['%PDF-1.7'],'assinado.pdf',{type:'application/pdf'});
    await contractsAPI.registerManualSignature(9,{signed_by_name:'Thiago',signed_at:'2026-10-05T10:30:00-03:00',signed_file:file});
    const [url,body,options]=axios.post.mock.calls[0];expect(url).toBe('/api/v1/accounts/12/crm/contracts/9/register_manual_signature');
    expect(body.get('signed_at')).toBe('2026-10-05T13:30:00.000Z');expect(body.get('signed_file')).toBe(file);expect(options.headers['Content-Type']).toBe('multipart/form-data');
  });
  it('sends a distinct native Backoffice decision with reason',async()=>{
    await backofficeAPI.decideOrder(8,{decision:'returned',reason:'Confirmar dados'});
    expect(axios.post).toHaveBeenCalledWith('/api/v1/accounts/12/crm/backoffice_requests/8/decide_order',{decision:'returned',reason:'Confirmar dados'});
  });
});
