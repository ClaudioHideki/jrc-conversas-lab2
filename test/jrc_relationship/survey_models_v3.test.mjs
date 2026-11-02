// Independent Node tests: pure editor contracts, no Vue/Rails/database claims.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('../../app/javascript/dashboard/routes/dashboard/serviceDesk/surveys/modelForm.js', import.meta.url), 'utf8');
const H = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const fresh = () => H.newModel({ id: 9, operator_id: 3 });
const valid = () => { const m=fresh();m.name='Pesquisa sintética';m.channels.public_link.enabled=true;m.rules.execution_member_id=7;return m; };
test('six steps follow the approved order',()=>assert.deepEqual(H.STEPS,['Informações','Perguntas','Canais','Regras de envio','Permissões','Revisão']));
test('new drafts never enable a sending channel',()=>assert.ok(Object.values(fresh().channels).every(c=>!c.enabled)));
test('draft uses the selected unit/operator',()=>assert.equal(fresh().unit_id,9));
test('new models have no relationship sharing consent assumed',()=>assert.equal(fresh().permissions.share_relationship,false));
test('stable equality ignores database JSON object key ordering',()=>assert.equal(H.stable({b:{z:1,a:2},a:3}),H.stable({a:3,b:{a:2,z:1}})));
test('stable comparison preserves question order',()=>assert.notEqual(H.stable([1,2]),H.stable([2,1])));
test('valid configured portal model passes all client steps',()=>assert.deepEqual(H.allErrors(valid()),[]));
for(const [label,mutate,step] of [
 ['empty name',m=>m.name='',0],['missing unit',m=>m.unit_id=null,0],['missing operator',m=>m.operator_id=null,0],['invalid code',m=>m.code='UPPER / bad',0],
 ['no questions',m=>m.questions=[],1],['duplicate codes',m=>m.questions[1].key='score',1],['empty text',m=>m.questions[0].text='',1],['bad NPS',m=>m.questions[0].max=5,1],['optional principal',m=>m.questions[0].required=false,1],['missing channel',m=>m.channels.public_link.enabled=false,2],
 ['email missing inbox',m=>m.channels.email.enabled=true,2],['email missing marker',m=>{m.channels.email.enabled=true;m.channels.email.inbox_id=1;m.channels.email.message='no link'},2],
 ['missing executor',m=>m.rules.execution_member_id=null,3],['unsupported event',m=>m.rules.event='anything',3],['negative delay',m=>m.rules.delay_minutes=-1,3],['fractional frequency',m=>m.rules.frequency_days=0.5,3],['zero expiry',m=>m.rules.expires_hours=0,3],
 ['empty send days',m=>{m.rules.send_window.enabled=true;m.rules.send_window.days=[]},3],['reversed send interval',m=>{m.rules.send_window.enabled=true;m.rules.send_window.start='20:00';m.rules.send_window.end='08:00'},3],
 ['removing native admin',m=>m.permissions.edit_roles=[],4]
]) test(`validation rejects ${label}`,()=>{const m=valid();mutate(m);assert.ok(H.validateStep(m,step).length>0)});
test('CSAT/CES kind change resets only the principal question',()=>{const m=valid();const last=H.clone(m.questions[1]);H.setKind(m,'csat');assert.equal(m.questions[0].min,1);assert.equal(m.questions[0].max,5);assert.deepEqual(m.questions[1],last);H.setKind(m,'ces');assert.equal(m.questions[0].max,10)});
test('kind change preserves custom question text',()=>{const m=valid();m.questions[0].text='Texto customizado';H.setKind(m,'csat');assert.equal(m.questions[0].text,'Texto customizado')});
test('add rating uses native scale format and stars presentation',()=>{const m=valid();const i=H.addQuestion(m,'rating');assert.deepEqual([m.questions[i].type,m.questions[i].presentation,m.questions[i].min,m.questions[i].max],['scale','stars',1,5])});
test('choice question requires filled option labels',()=>{const m=valid();H.addQuestion(m,'choice');assert.ok(H.validateStep(m,1).length)});
test('reordering never moves the principal question',()=>{const m=valid();assert.equal(H.moveQuestion(m,0,1),false);assert.equal(H.moveQuestion(m,1,-1),false)});
test('reordering cannot break backward dependencies',()=>{const m=valid();H.addQuestion(m,'text');m.questions[2].condition={question:'comment',operator:'eq',value:'yes'};assert.equal(H.moveQuestion(m,2,-1),false)});
test('reordering independent questions preserves their content',()=>{const m=valid();H.addQuestion(m,'text');const a=m.questions[1];assert.equal(H.moveQuestion(m,2,-1),true);assert.equal(m.questions[2],a)});
test('conflict gets an explicit Portuguese error',()=>assert.match(H.messageErrors({response:{status:409}})[0].message,/outra sess/));
for(const status of [401,403,404]) test(`access error ${status} never exposes server details`,()=>assert.doesNotMatch(H.messageErrors({response:{status,data:{errors:['SECRET']}}})[0].message,/SECRET/));
test('structured server errors retain field and step',()=>{const e={step:2,field:'inbox',message:'Caixa indisponível'};assert.deepEqual(H.messageErrors({response:{status:422,data:{errors:[e]}}}),[e])});
test('generated code is bounded and identifier-safe',()=>assert.match(fresh().code,/^[a-z0-9_-]{1,32}$/));
test('clone does not share nested references',()=>{const a=valid();const b=H.clone(a);b.questions[0].text='X';assert.notEqual(a.questions[0].text,'X')});
