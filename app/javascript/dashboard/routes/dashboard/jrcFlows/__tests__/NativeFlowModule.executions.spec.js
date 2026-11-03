import {mount,flushPromises} from '@vue/test-utils';
import {ref} from 'vue';
import {createStore} from 'vuex';
import NativeFlowModule from '../NativeFlowModule.vue';
const api=vi.hoisted(()=>({inboxes:vi.fn(async()=>[{id:7,name:'Inbox'}]),configuration:vi.fn(async()=>({configured:true})),session:vi.fn(async()=>{throw Error('stop before mounting editor');})}));
vi.mock('dashboard/composables/useAccount',()=>({useAccount:()=>({accountId:ref(1),accountScopedRoute:()=>({name:'flows'})})}));
vi.mock('dashboard/api/jrcFlowNative',()=>({createJrcFlowNativeApi:()=>api}));
vi.mock('vue-i18n',()=>({useI18n:()=>({t:key=>key})}));
let wrapper;
afterEach(()=>{wrapper?.unmount();vi.clearAllMocks();});
it('keeps legacy session scopes until the administrator explicitly asks for execution history',async()=>{
 const store=createStore({getters:{getCurrentRole:()=> 'administrator',getCurrentCustomRoleId:()=>null}});
 wrapper=mount(NativeFlowModule,{global:{plugins:[store],stubs:{RouterLink:true}}});await flushPromises();
 await wrapper.find('input[type="checkbox"][value="7"]').setValue(true);
 const open=()=>wrapper.findAll('button').find(button=>button.text()==='NATIVE.OPEN_SESSION');
 await open().trigger('click');await flushPromises();expect(api.session.mock.calls[0][1]).not.toContain('flow:executions:read');
 await wrapper.find('[data-test="execution-history-scope"]').setValue(true);await open().trigger('click');await flushPromises();
 expect(api.session.mock.calls[1][1]).toContain('flow:executions:read');
});
