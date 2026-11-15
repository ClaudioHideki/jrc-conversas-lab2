const { test, expect } = require(process.env.JRC_PLAYWRIGHT_MODULE);
const fs = require('fs');
const fixture = JSON.parse(fs.readFileSync(process.env.JRC_BROWSER_CREDENTIALS, 'utf8'));
const locale = JSON.parse(fs.readFileSync(process.env.JRC_BROWSER_LOCALE_FILE, 'utf8')).JRC_APPROVALS;
const management = JSON.parse(fs.readFileSync(process.env.JRC_BROWSER_LOCALE_FILE.replace('jrcApprovals.json','cannedMgmt.json'), 'utf8')).CANNED_MGMT;
const q = JSON.parse(fs.readFileSync(process.env.JRC_BROWSER_LOCALE_FILE.replace('jrcApprovals.json','cannedMgmt.json'), 'utf8')).CANNED_MGMT.QUICK;
const origin = process.env.JRC_BROWSER_ORIGIN;
if (origin !== 'http://127.0.0.1:3000' || fixture.product_sha !== process.env.JRC_BROWSER_PRODUCT_SHA) throw Error('Wrong owned source/origin');
const sessions = new Map();
async function session(browser, role = 'reviewer') {
  if (!sessions.has(role)) {
    const context = await browser.newContext();
    await context.route('**/*', route => route.request().url().startsWith(origin + '/') ? route.continue() : route.abort('blockedbyclient'));
    await context.routeWebSocket('**/*', socket => socket.url().startsWith('ws://127.0.0.1:3000/') ? socket.connectToServer() : socket.close());
    const page = await context.newPage();
    await page.goto(origin + '/app/login');
    await page.locator('input[name="email_address"]').fill(fixture.users[role].email);
    await page.locator('input[type="password"]').fill(fixture.users[role].password);
    const login = page.waitForResponse(r => new URL(r.url()).pathname === '/auth/sign_in' && r.request().method() === 'POST');
    await page.locator('button[type="submit"]').click();
    const response = await login; expect(response.status()).toBe(200);
    await page.waitForURL(/\/app\/accounts\/\d+/);
    const h = await response.allHeaders();
    const headers = Object.fromEntries(['access-token','client','uid','token-type'].filter(k => h[k]).map(k => [k,h[k]]));
    sessions.set(role, { page, context, headers });
  }
  return sessions.get(role);
}
const modes = [
  {name:'desktop-light',width:1440,height:1000,dark:false},
  {name:'desktop-dark',width:1440,height:1000,dark:true},
  {name:'mobile-light',width:390,height:844,dark:false},
  {name:'mobile-dark',width:390,height:844,dark:true},
];
async function theme(page, mode) {
  await page.setViewportSize({width:mode.width,height:mode.height});
  await page.emulateMedia({colorScheme:mode.dark?'dark':'light'});
  await page.evaluate(dark => localStorage.setItem('color_scheme',dark?'dark':'light'),mode.dark);
  await page.reload();
  await expect.poll(()=>page.evaluate(()=>document.body.classList.contains('dark'))).toBe(mode.dark);
  await expect.poll(()=>page.evaluate(()=>getComputedStyle(document.documentElement).colorScheme)).toBe(mode.dark?'dark':'light');
}
async function capture(page,mode,name) {
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  await page.screenshot({path:`${process.env.JRC_BROWSER_OUTPUT}/${mode.name}-${name}.png`,fullPage:true});
  test.info().annotations.push({type:'source-theme',description:JSON.stringify({product:fixture.product_sha,viewport:mode.width,dark:mode.dark})});
}
test.afterEach(async ({},info)=> {
  if(info.status!==info.expectedStatus) for (const [role,s] of sessions) if (!s.page.isClosed()) await s.page.screenshot({path:process.env.JRC_BROWSER_OUTPUT+'/failed-'+role+'.png',fullPage:true});
});
test.afterAll(async()=> {for(const s of sessions.values()) await s.context.close();});
for (const [index,mode] of modes.entries()) {
  test(`real contextual quick replies ${mode.name}`,async({browser})=>{
    const {page,context,headers}=await session(browser);
    await theme(page,mode);
    await page.goto(`${origin}/app/accounts/${fixture.account_id}/inbox-view/conversation/${fixture.conversation_id}`);
    const entry=page.getByRole('button',{name:q.TITLE,exact:true});
    await expect(entry).toBeVisible();
    if(index===0) {
      const editor=page.locator('.ProseMirror').first();await editor.click();await page.keyboard.type('/qa-imagem',{delay:40});
      const slash=page.getByRole('button',{name:/\/qa-imagem$/});await expect(slash).toBeVisible();await slash.click();
      const review=page.getByRole('dialog').filter({has:page.getByRole('heading',{name:q.TITLE,exact:true})});
      await expect(review.locator('img')).toBeVisible();await expect.poll(()=>review.locator('img').evaluate(el=>el.complete&&el.naturalWidth>0)).toBe(true);await expect(review.getByText('synthetic.png',{exact:true})).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(editor).not.toContainText('/qa-imagem');
    }
    await expect(entry).toHaveCount(1);
    await entry.click();
    let dialog=page.getByRole('dialog').filter({has:page.getByRole('heading',{name:q.TITLE,exact:true})});
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button').filter({hasText:'qa-contexto'}).click();
    const text=dialog.locator('textarea');
    await expect(text).toHaveValue(new RegExp('Cliente Sintético Um.*'+fixture.reviewer_name));
    expect(await text.inputValue()).not.toContain('Synthetic recipient');
    await capture(page,mode,'quick-review');
    await dialog.getByRole('button',{name:q.INSERT,exact:true}).click();
    await expect(dialog).not.toBeVisible();
    await expect(page.locator('.ProseMirror').first()).toContainText('Cliente Sintético Um');
    if(index===0) {
      await entry.click();await dialog.getByRole('button').filter({hasText:'qa-legado'}).click();
      await dialog.getByRole('button',{name:q.INSERT,exact:true}).click();
      await expect(page.locator('.ProseMirror strong').first()).toContainText('Olá Cliente Sintético Um');
    }
    // Direct delivery is a separate explicit confirmation, never the insertion action.
    await entry.click();
    await dialog.getByRole('button').filter({hasText:'qa-contexto'}).click();
    const reviewed=`Synthetic reviewed ${mode.name}`;
    await dialog.locator('textarea').fill(reviewed);
    let sends=0;
    const count=r=>{if(r.url().endsWith('/deliver')&&r.method()==='POST')sends++;};
    page.on('request',count);
    await dialog.getByRole('button',{name:q.SEND,exact:true}).click();
    expect(sends).toBe(0);
    const confirm=page.getByRole('dialog').filter({has:page.getByRole('heading',{name:q.CONFIRM,exact:true})});
    await expect(confirm).toBeVisible();
    await capture(page,mode,'quick-confirmation');
    let committedId;
    await page.route('**/canned_responses/*/deliver',async route=>{
      const actual=await route.fetch();expect(actual.status()).toBe(200);committedId=(await actual.json()).id;
      await route.abort('failed'); // Server committed; only this owned browser loses the response.
    },{times:1});
    const lost=page.waitForEvent('requestfailed',r=>r.url().endsWith('/deliver'));
    await confirm.getByRole('button',{name:q.SEND,exact:true}).click();await lost;
    await expect(dialog.getByRole('alert')).toHaveText(q.SEND_ERROR);
    await expect(dialog.locator('textarea')).toHaveValue(reviewed);
    await dialog.getByRole('button',{name:q.SEND,exact:true}).click();
    await expect(confirm).toBeVisible();
    const submitted=page.waitForResponse(r=>r.url().endsWith('/deliver')&&r.request().method()==='POST');
    await confirm.getByRole('button',{name:q.SEND,exact:true}).click();
    const reply=await submitted;expect(reply.status()).toBe(200);expect(sends).toBe(2);
    const message=await reply.json();expect(message.id).toBe(committedId);expect(message.content).toBe(reviewed);
    const same=await context.request.post(reply.url(),{headers,data:reply.request().postDataJSON()});
    expect(same.status()).toBe(200);expect((await same.json()).id).toBe(message.id);
    page.off('request',count);
    await page.reload();
    await expect(page.getByText(reviewed,{exact:true}).first()).toBeVisible();
    await entry.click();
    await dialog.getByRole('button').filter({hasText:'qa-imagem'}).click();
    await expect(dialog.locator('img')).toBeVisible();await expect.poll(()=>dialog.locator('img').evaluate(el=>el.complete&&el.naturalWidth>0)).toBe(true);
    await expect(dialog.getByText('synthetic.png',{exact:true})).toBeVisible();
    await capture(page,mode,'quick-image');
    await dialog.getByRole('button',{name:q.INSERT,exact:true}).click();
    await expect(dialog).not.toBeVisible();
    const insertedText='Synthetic native inserted image '+mode.name;
    await page.locator('.ProseMirror').first().fill(insertedText);
    const nativeSend=page.locator('.reply-box .right-wrap button');
    await expect(nativeSend).toBeEnabled();
    await capture(page,mode,'quick-native-image-editor');
    const nativePosted=page.waitForResponse(r=>new URL(r.url()).pathname===`/api/v1/accounts/${fixture.account_id}/conversations/${fixture.conversation_id}/messages`&&r.request().method()==='POST');
    await nativeSend.click();
    const nativeResponse=await nativePosted;expect(nativeResponse.status()).toBe(200);
    const nativeMessage=await nativeResponse.json();expect(nativeMessage.attachments).toHaveLength(1);expect(nativeMessage.attachments[0].file_type).toBe('image');
    const imageAddress=new URL(nativeMessage.attachments[0].data_url,origin);expect(imageAddress.origin).toBe(origin);
    const actualImage=await context.request.get(imageAddress.href,{headers});expect(actualImage.status()).toBe(200);expect(Buffer.compare(await actualImage.body(),fs.readFileSync('spec/assets/sample.png'))).toBe(0);
    await page.reload();await expect(page.getByText(insertedText,{exact:true}).first()).toBeVisible();
    await page.goto(`${origin}/app/accounts/${fixture.account_id}/inbox-view/conversation/${fixture.second_conversation_id}`);
    await entry.click();await dialog.getByRole('button').filter({hasText:'qa-contexto'}).click();
    await expect(dialog.locator('textarea')).toHaveValue(/Cliente Sintético Dois/);
    expect(await dialog.locator('textarea').inputValue()).not.toContain('Cliente Sintético Um');
    await page.keyboard.press('Escape');
  });
  test(`real translated approval configuration ${mode.name}`,async({browser})=>{
    const {page}=await session(browser);
    await theme(page,mode);
    await page.goto(`${origin}/app/accounts/${fixture.account_id}/approvals/own-delegations`);
    await expect(page.getByRole('heading',{name:locale.ownDelegations,exact:true})).toBeVisible();
    expect(await page.locator('body').innerText()).not.toContain('My delegations');
    await capture(page,mode,'translated-delegations');
    await page.getByRole('button',{name:locale.workspace.configure,exact:true}).click();
    const popup=page.getByRole('dialog');await expect(popup).toBeVisible();
    await popup.getByRole('button',{name:locale.importCatalog.title,exact:true}).click();
    await popup.locator('select').first().selectOption({index:1});
    const seed={schema_version:'1.0',activate:false,tenant:'RESOLVER_NO_AMBIENTE',people:Array.from({length:11},(_,i)=>({full_name:'Pessoa Sintética '+i,role:'Synthetic'})),approval_rules:Array.from({length:20},(_,i)=>({code:'QA_'+mode.name.replaceAll('-','_').toUpperCase()+'_'+i,module:'Synthetic',title:'Synthetic catalog '+i,enabled:false,workflow_state:'draft',approver_user_ids:[],self_approval_allowed:false}))};
    await popup.locator('input[type="file"]').setInputFiles({name:'synthetic-catalog.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(seed))});
    const preview=page.waitForResponse(r=>r.url().endsWith('/policies/import')&&r.request().method()==='POST');
    await popup.getByRole('button',{name:locale.importCatalog.preview,exact:true}).click();
    const response=await preview;expect(response.status()).toBe(200);const report=await response.json();
    expect(report.rows.length).toBe(20);expect(report.people.length).toBe(11);expect(report.requests_created).toBe(0);expect(report.activated).toBe(false);
    expect(report.people.every(p=>p.status==='pending_identity'&&!p.approval_authority_granted)).toBe(true);
    await expect(popup.locator('article')).toHaveCount(20);
    expect(await popup.getByRole('button',{name:locale.importCatalog.apply,exact:true}).isDisabled()).toBe(true);
    await popup.locator('article').first().scrollIntoViewIfNeeded();
    await capture(page,mode,'approval-import-diff');
    const mapping=popup.locator('article').first().locator('select');
    const target=await mapping.locator('option').evaluateAll((options,choice)=>options.map(o=>o.value).filter(value=>value&&value!=='crm.proposal_send')[choice],index);
    expect(target).toBeTruthy();
    await mapping.selectOption(target);
    const revised=page.waitForResponse(r=>r.url().endsWith('/policies/import')&&r.request().method()==='POST');
    await popup.getByRole('button',{name:locale.importCatalog.preview,exact:true}).click();
    expect((await revised).status()).toBe(200);
    await popup.locator('input[type="checkbox"]').check();
    await expect(popup.getByRole('button',{name:locale.importCatalog.apply,exact:true})).toBeEnabled();
    const applied=page.waitForResponse(r=>r.url().endsWith('/policies/import')&&r.request().method()==='POST');
    await popup.getByRole('button',{name:locale.importCatalog.apply,exact:true}).click();
    const imported=await applied;expect(imported.status()).toBe(200);const batch=await imported.json();
    expect(batch.activated).toBe(false);expect(batch.requests_created).toBe(0);expect(batch.rows.filter(r=>r.policy_id)).toHaveLength(1);
    await expect(popup.getByText(locale.importCatalog.saved,{exact:true})).toBeVisible();
    await capture(page,mode,'approval-import-saved');
    test.info().annotations.push({type:'synthetic-mapping',description:target});
    await page.keyboard.press('Escape');
    await page.goto(`${origin}/app/accounts/${fixture.account_id}/approvals/policies`);
    await expect(page.getByText('Synthetic catalog 0 #'+batch.rows[0].policy_id,{exact:true})).toBeVisible();
    await expect(page.locator('form select option[value="draft"]')).toHaveText(locale.workspace.states.draft);
    await capture(page,mode,'approval-import-list');
    await page.goto(`${origin}/app/accounts/${fixture.account_id}/approvals/policies/new`);
    const editor=page.getByRole('dialog');await expect(editor).toBeVisible();
    await expect(editor.getByRole('tab')).toHaveCount(4);
    await capture(page,mode,'approval-policy-popup');
    const title='Synthetic popup '+mode.name;
    await editor.getByLabel(locale.name,{exact:true}).fill(title);
    await editor.locator('select:visible').first().selectOption({index:1});
    await editor.locator('select:visible').nth(1).selectOption('crm.proposal_send');
    const created=page.waitForResponse(r=>r.url().endsWith('/approvals/policies')&&r.request().method()==='POST');
    await editor.getByRole('button',{name:locale.saveDraft,exact:true}).click();
    const persisted=await created;expect(persisted.status()).toBe(201);const policy=await persisted.json();
    expect(policy.state).toBe('draft');expect(policy.enabled).toBe(false);
    await page.waitForURL(new RegExp('/approvals/policies/'+policy.id+'$'));
    await page.reload();await expect(editor).toBeVisible();
    await expect(editor.getByLabel(locale.name,{exact:true})).toHaveValue(title);
    await editor.getByLabel(locale.name,{exact:true}).fill(title+' edited');
    const edited=page.waitForResponse(r=>r.url().endsWith('/approvals/policies/'+policy.id)&&r.request().method()==='PATCH');
    await editor.getByRole('button',{name:locale.saveDraft,exact:true}).click();expect((await edited).status()).toBe(200);
    await page.reload();await expect(editor.getByLabel(locale.name,{exact:true})).toHaveValue(title+' edited');
    await page.keyboard.press('Escape');
  });
}
test('real account unit and conversation denials',async({browser})=>{
  const {context,headers}=await session(browser);const api=`${origin}/api/v1/accounts/${fixture.account_id}`;
  const ok=await context.request.get(api+'/approvals/requests/'+fixture.request_ids[0],{headers});expect(ok.status()).toBe(200);
  const noUnit=await context.request.get(api+'/approvals/requests/'+fixture.other_unit_request_id,{headers});expect(noUnit.status()).toBe(401);
  const foreign=await context.request.post(`${origin}/api/v1/accounts/${fixture.foreign_account_id}/canned_responses/${fixture.quick_reply_id}/preview`,{headers,data:{conversation_id:fixture.conversation_id}});expect([401,403,404]).toContain(foreign.status());
  const denied=await session(browser,'denied');
  const hidden=await denied.context.request.post(api+'/canned_responses/'+fixture.quick_reply_id+'/preview',{headers:denied.headers,data:{conversation_id:fixture.conversation_id}});expect([401,403,404]).toContain(hidden.status());
});

for (const mode of modes) test(`real quick reply attachment settings ${mode.name}`,async({browser})=>{
  const {page,context,headers}=await session(browser,'manager');await theme(page,mode);
  await page.goto(`${origin}/app/accounts/${fixture.account_id}/settings/canned-response/list`);
  await page.getByRole('button',{name:management.HEADER_BTN_TXT,exact:true}).click();
  let form=page.locator('form:visible').last();const code='qa-created-'+mode.name;
  await form.locator('input[type="text"]').fill(code);
  await form.locator('.ProseMirror').fill('Olá [nome], revisão sintética.');
  const png=fs.readFileSync('spec/assets/sample.png');
  await form.locator('input[type="file"]').setInputFiles({name:'ui-synthetic.png',mimeType:'image/png',buffer:png});
  await expect(form.locator('img')).toBeVisible();await expect.poll(()=>form.locator('img').evaluate(el=>el.complete&&el.naturalWidth>0)).toBe(true);await capture(page,mode,'settings-create-image');
  await page.route('**/canned_responses',route=>route.abort('failed'),{times:1});
  const broken=page.waitForEvent('requestfailed',r=>r.url().endsWith('/canned_responses'));
  await form.getByRole('button',{name:management.ADD.FORM.SUBMIT,exact:true}).click();await broken;
  await expect(form.getByRole('button',{name:management.ADD.FORM.SUBMIT,exact:true})).toBeEnabled();
  await expect(form.locator('input[type="text"]')).toHaveValue(code);await expect(form.locator('img')).toBeVisible();await expect.poll(()=>form.locator('img').evaluate(el=>el.complete&&el.naturalWidth>0)).toBe(true);
  const created=page.waitForResponse(r=>r.url().endsWith('/canned_responses')&&r.request().method()==='POST');
  await form.getByRole('button',{name:management.ADD.FORM.SUBMIT,exact:true}).click();
  const response=await created;expect(response.status()).toBe(200);const record=await response.json();expect(record.file.filename).toBe('ui-synthetic.png');
  await page.reload();let row=page.getByRole('row').filter({hasText:code});await expect(row).toBeVisible();
  await row.getByRole('button').first().click();form=page.locator('form:visible').last();
  await expect(form.getByText('ui-synthetic.png',{exact:true})).toBeVisible();
  await form.getByRole('button',{name:q.REMOVE,exact:true}).click();
  const changed=page.waitForResponse(r=>r.url().endsWith('/canned_responses/'+record.id)&&r.request().method()==='PATCH');
  await form.getByRole('button',{name:management.EDIT.FORM.SUBMIT,exact:true}).click();expect((await changed).status()).toBe(200);
  const read=await context.request.get(`${origin}/api/v1/accounts/${fixture.account_id}/canned_responses`,{headers});expect(read.status()).toBe(200);
  expect((await read.json()).find(r=>r.id===record.id).file).toBeUndefined();
});
