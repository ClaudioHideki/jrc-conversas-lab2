import { beforeEach, afterEach, describe, it, expect, vi } from 'vitest';
import { reactive, ref, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { createRouter, createMemoryHistory } from 'vue-router';
import messages from 'dashboard/i18n/locale/pt_BR/jrcServiceDesk.json';
import { createServiceDeskSession, createSessionState } from '../helpers/session.js';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from '../routeDefinitions.js';
import { contextPayload, identity, collection, ticket, fakeClient, httpError } from './fixtures.js';

const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({ useServiceDesk: () => holder.session }));
import TicketFormView from '../views/TicketFormView.vue';
import TicketListView from '../views/TicketListView.vue';
import PlannedView from '../views/PlannedView.vue';

const Button = { props:['label','disabled'], template:'<button :disabled="disabled">{{ label }}</button>' };
const Input = { props:['modelValue','label','disabled'], emits:['update:modelValue'], template:'<label>{{ label }}<input :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\',$event.target.value)" /></label>' };
const Select = { props:['modelValue','options','disabled'], emits:['update:modelValue'], template:'<select :value="modelValue" :disabled="disabled" @change="$emit(\'update:modelValue\',$event.target.value)"><option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option></select>' };
const TextArea = { props:['modelValue','label','disabled'], emits:['update:modelValue'], template:'<label>{{ label }}<textarea :value="modelValue" :disabled="disabled" @input="$emit(\'update:modelValue\',$event.target.value)" /></label>' };
const keys = messages.JRC_SERVICE_DESK;
let wrappers;
const setupSession = async client => {
  const session=createServiceDeskSession(client,reactive(createSessionState()));
  holder.session={...session,accountId:ref('1'),userId:ref('7'),enabled:ref(true)};
  await session.start(identity);
  return holder.session;
};
const render = async (component, screen='new') => {
  const router=createRouter({history:createMemoryHistory(),routes:SERVICE_DESK_ROUTES.map(entry=>({path:`/app/accounts/:accountId/service-desk${entry.path?`/${entry.path}`:''}`,name:serviceDeskRouteName(entry.key),component:{template:'<div />'}}))});
  await router.push({name:serviceDeskRouteName(screen),params:{accountId:'1'}});await router.isReady();
  const wrapper = mount(component, {
    props: { screen },
    global: {
      plugins: [
        router,
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: messages },
        }),
        createStore({
          getters: { 'accounts/isFeatureEnabledonAccount': () => () => false },
        }),
      ],
      stubs: {
        Button,
        Input,
        Select,
        TextArea,
        Icon: true,
        Spinner: true,
        PaginationFooter: true,
        TabBar: true,
      },
    },
  });
  wrappers.push(wrapper);await flushPromises();return wrapper;
};
const button = (wrapper, label) => wrapper.findAll('button').find(item=>item.text()===label);
beforeEach(()=>{wrappers=[];});
afterEach(()=>{wrappers.forEach(wrapper=>wrapper.unmount());holder.session?.dispose();holder.session=null;});

describe('CP3 view structures and explicit non-persistence (native Vue pending)',()=>{
  it.each([true, false])(
    'New ticket visibility follows the backend create grant: %s',
    async allowed => {
      await setupSession(
        fakeClient({
          context: async () =>
            contextPayload({
              units: contextPayload().units.map(unit => ({
                ...unit,
                permissions: { create_ticket: allowed },
              })),
            }),
        })
      );
      const wrapper = await render(TicketListView, 'tickets');
      expect(Boolean(button(wrapper, keys.COMMON.open_structure))).toBe(
        allowed
      );
    }
  );
  it('missing API renders pending rather than a fabricated ticket table or zero count',async()=>{
    await setupSession(fakeClient({context:async()=>{throw httpError(404);}}));
    const wrapper=await render(TicketListView,'tickets');
    expect(wrapper.text()).toContain(keys.STATES.pending);expect(wrapper.find('tbody').exists()).toBe(false);
    expect(wrapper.findComponent({name:'PaginationFooter'}).exists()).toBe(false);
  });
  it('a four-step form remains inspectable but inputs need a backend grant',async()=>{
    await setupSession(fakeClient({context:async()=>{throw httpError(404);}}));
    const wrapper=await render(TicketFormView);
    expect(wrapper.findAll('.sd-wizard-step')).toHaveLength(4);
    expect(wrapper.findAll('input').every(input=>input.attributes('disabled')!==undefined)).toBe(true);
    await button(wrapper,keys.COMMON.next).trigger('click');await button(wrapper,keys.COMMON.next).trigger('click');await button(wrapper,keys.COMMON.next).trigger('click');
    expect(button(wrapper,keys.COMMON.create).attributes('disabled')).toBeDefined();
    expect(wrapper.text()).toContain(keys.FORM.draft_notice);
  });
  it('grant permits only a temporary draft, never submission; changing unit clears it',async()=>{
    await setupSession(fakeClient({list:async(_account,resource)=>collection([{id:'33',account_id:'1',unit_id:'10',permissions:{show:true},name:`Fixture ${resource}`}])}));
    const wrapper=await render(TicketFormView);
    // Operator and unit selects are ordered by the native ScopeBar.
    await wrapper.findAll('select')[1].setValue('10');await flushPromises();
    const title=wrapper.findAll('label').find(label=>label.text().startsWith(keys.FIELDS.title)).find('input');
    expect(title.attributes('disabled')).toBeUndefined();await title.setValue('Transient fixture');
    expect(wrapper.text()).toContain('Transient fixture');
    await wrapper.findAll('select')[0].setValue('4');await flushPromises();
    expect(title.element.value).toBe('');expect(wrapper.text()).not.toContain('Transient fixture');
    expect(title.attributes('disabled')).toBeDefined();
  });
  it('tab/form navigation does not post data even with a known context',async()=>{
    const writes=vi.fn();const client={...fakeClient(),create:writes,update:writes,delete:writes};
    await setupSession(client);const wrapper=await render(TicketFormView);
    for(const step of wrapper.findAll('.sd-wizard-step')) await step.trigger('click');
    expect(button(wrapper,keys.COMMON.create).attributes('disabled')).toBeDefined();expect(writes).not.toHaveBeenCalled();
  });
  it('a confirmed empty API response shows an empty state, not an unavailable API',async()=>{
    await setupSession(fakeClient({list:async()=>collection([])}));const wrapper=await render(TicketListView,'tickets');
    expect(wrapper.text()).toContain(keys.STATES.empty);expect(wrapper.text()).not.toContain(keys.STATES.pending_help);
  });
  it('records disappear after a denied refresh instead of staying behind a spinner',async()=>{
    let deny=false;await setupSession(fakeClient({list:async()=>{if(deny)throw httpError(403);return collection([ticket()]);}}));
    const wrapper=await render(TicketListView,'tickets');expect(wrapper.text()).toContain('Synthetic test ticket');
    deny=true;await holder.session.load('tickets:list','tickets');await nextTick();await flushPromises();
    expect(wrapper.text()).not.toContain('Synthetic test ticket');
  });
  it.each(['contracts','knowledge','sla','reports','approvals','surveys','assets','problems','changes','automations','catalog'])('reference %s has no data service or mutation request',async screen=>{
    const list=vi.fn();await setupSession(fakeClient({list}));const wrapper=await render(PlannedView,screen);
    expect(list).not.toHaveBeenCalled();expect(wrapper.text()).toContain(keys.PLANNED.data_notice);
    expect(wrapper.findAll('input').every(input=>input.attributes('disabled')!==undefined)).toBe(true);
  });
});
