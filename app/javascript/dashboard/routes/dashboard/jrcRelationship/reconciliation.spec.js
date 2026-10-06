import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import SurveyDeliveryPanel from './SurveyDeliveryPanel.vue';
import WorkContextPanel from './WorkContextPanel.vue';
import MetricsPanel from './MetricsPanel.vue';
import NicoSummaryPanel from './NicoSummaryPanel.vue';
import RecordEditor from './RecordEditor.vue';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';
import { date, money } from './definitions';
const mocks = vi.hoisted(() => ({route:null,store:null,api:{channels:vi.fn(),deliverSurvey:vi.fn(),nativeCsat:vi.fn(),workContext:vi.fn()}}));
vi.mock('vue-router',()=>({useRoute:()=>mocks.route}));
vi.mock('vuex', async original=>({...await original(),useStore:()=>mocks.store}));
vi.mock('dashboard/api/jrcRelationship',()=>({default:mocks.api}));
beforeEach(()=>{
  mocks.route=reactive({params:{accountId:'12'}});mocks.store={getters:reactive({getCurrentUserID:7})};
  mocks.api.channels.mockResolvedValue({data:{channel_conversations:[{id:55,display_id:10,inbox:'E-mail'}]}});
  mocks.api.deliverSurvey.mockResolvedValue({data:{message_id:5}});
  mocks.api.nativeCsat.mockResolvedValue({data:{message_id:6}});
  mocks.api.workContext.mockResolvedValue({data:{executive_summary:'Contexto atual',period:{from:'2026-09-01',to:'2026-10-05'},contracts:[],risks:[],projects:[]}});
});
describe('Final reconciliation native projections',()=>{
  it('formats the same instant using the selected account timezone while preserving calendar dates',()=>{
    expect(date('2026-10-05T03:30:00Z',{locale:'pt-BR',timeZone:'America/Sao_Paulo'})).toContain('00:30');
    expect(date('2026-10-05T03:30:00Z',{locale:'pt-BR',timeZone:'Asia/Tokyo'})).toContain('12:30');
    expect(date('2026-10-05',{locale:'pt-BR',timeZone:'America/Los_Angeles'})).toBe('05/10/2026');
  });
  it('uses account locale for the native BRL monetary values',()=>{
    expect(money(220000,{locale:'pt-BR',currency:'BRL'})).toContain('2.200,00');
    expect(money(220000,{locale:'en-US',currency:'BRL'})).toContain('2,200.00');
  });
  it('opens the existing NICO with a daily consultation prompt and the authorized priority customer',async()=>{
    const copilot=useJrcCopilot();copilot.consumePrompt();copilot.close();
    const w=mount(NicoSummaryPanel,{props:{enabled:true,metrics:{actions_today:2,priority_actions:[{assignment_id:19,customer:'Authorized customer',reason:'Renewal',due_at:'2026-10-05'}]}}});
    await w.findAll('button')[0].trigger('click');expect(w.emitted('customer')[0]).toEqual([19]);
    await w.findAll('button')[1].trigger('click');expect(copilot.mode.value).toBe('full');expect(copilot.pendingPrompt.value).toBeTruthy();
    copilot.consumePrompt();copilot.close();w.unmount();
  });
  it('shows both native satisfaction trends',()=>{
    const w=mount(MetricsPanel,{props:{metrics:{nps_evolution:[{day:'2026-10-04',score:-100}],csat_evolution:[{day:'2026-10-05',score:4}]}}});
    expect(w.findAll('details').length).toBe(2);expect(w.text()).toContain('-100.0');expect(w.text()).toContain('4.0');w.unmount();
  });
  it('offers configured risk reasons without losing a manually described reason',()=>{
    const w=mount(RecordEditor,{props:{kind:'risks',record:{reason:'Motivo específico'},metadata:{risk_reasons:['Insatisfação','Renovação']}}});
    expect(w.findAll('datalist option').map(row=>row.attributes('value'))).toEqual(['Insatisfação','Renovação']);
    expect(w.find('input[list="relationship-risk-reasons"]').element.value).toBe('Motivo específico');w.unmount();
  });
  it('sends a survey only after explicit submit, bound to the selected account and conversation',async()=>{
    const w=mount(SurveyDeliveryPanel,{props:{assignmentId:19,surveyId:30}});await flushPromises();
    expect(mocks.api.deliverSurvey).not.toHaveBeenCalled();
    await w.find('select').setValue('55');await w.find('form').trigger('submit');await flushPromises();
    expect(mocks.api.deliverSurvey).toHaveBeenCalledWith('12',30,55);expect(w.emitted('sent')[0]).toEqual([{message_id:5}]);w.unmount();
  });
  it('reuses native CSAT instead of creating a relational CSAT copy',async()=>{
    const w=mount(SurveyDeliveryPanel,{props:{assignmentId:19}});await flushPromises();
    await w.find('select').setValue('55');await w.find('form').trigger('submit');await flushPromises();
    expect(mocks.api.nativeCsat).toHaveBeenCalledWith('12',19,55);expect(mocks.api.deliverSurvey).not.toHaveBeenCalled();w.unmount();
  });
  it('discards late conversation choices after switching account',async()=>{
    let resolve;mocks.api.channels.mockImplementationOnce(()=>new Promise(r=>{resolve=r;}));
    const w=mount(SurveyDeliveryPanel,{props:{assignmentId:19,surveyId:30}});mocks.route.params.accountId='13';await flushPromises();
    resolve({data:{channel_conversations:[{id:99,display_id:99,inbox:'Old tenant'}]}});await flushPromises();
    expect(w.text()).not.toContain('Old tenant');expect(w.find('option[value="55"]').exists()).toBe(true);w.unmount();
  });
  it('restores the saved QBR period and loads authorized native context',async()=>{
    const w=mount(WorkContextPanel,{props:{assignmentId:19,initialPeriod:{period_from:'2026-09-01',period_to:'2026-10-05'}}});await flushPromises();
    expect(mocks.api.workContext).toHaveBeenCalledWith('12',19,{from:'2026-09-01',to:'2026-10-05'},expect.objectContaining({signal:expect.any(AbortSignal)}));
    expect(w.text()).toContain('Contexto atual');w.unmount();
  });
  it('clears stale period context when the user changes account',async()=>{
    let resolve;mocks.api.workContext.mockImplementationOnce(()=>new Promise(r=>{resolve=r;}));
    const w=mount(WorkContextPanel,{props:{assignmentId:19}});mocks.route.params.accountId='13';await flushPromises();
    resolve({data:{executive_summary:'Unauthorized old context',period:{from:'2026-01-01',to:'2026-02-01'}}});await flushPromises();
    expect(w.text()).not.toContain('Unauthorized old context');expect(w.text()).toContain('Contexto atual');w.unmount();
  });
  it('exposes all five real renewal windows as drilldowns',async()=>{
    const w=mount(MetricsPanel,{props:{metrics:{renewals:{15:1,30:2,60:3,90:4,120:5}}}});
    const windows=w.findAll('button').slice(-5);for(const b of windows)await b.trigger('click');
    expect(w.emitted('filter').map(e=>e[0])).toEqual([15,30,60,90,120].map(renewal_days=>({renewal_days})));w.unmount();
  });
});
