// Static source inventory. A discovered handler is not a successful functional test.
// Usage: node scripts/audit-jrc-surface.cjs <output-directory>
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { parse } = require('@vue/compiler-sfc');
const compilerRequire = require('node:module').createRequire(
  require.resolve('@vue/compiler-sfc')
);
const { parse: parseTemplate } = compilerRequire('@vue/compiler-dom');

const root = path.resolve(__dirname, '..');
const destination = process.argv[2] && path.resolve(process.argv[2]);
if (!destination || destination === root)
  throw new Error('Supply a separate evidence directory');
const relative = file => path.relative(root, file).replaceAll('\\', '/');
const walk = directory =>
  fs.existsSync(directory)
    ? fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
        const file = path.join(directory, entry.name);
        return entry.isDirectory() ? walk(file) : [file];
      })
    : [];
const moduleOf = file => {
  const modules = [
    [/jrc_service_desk|jrcServiceDesk|serviceDesk/i, 'Service Desk R2'],
    [/jrc_operations|jrcOperations|jrcProjects/i, 'Projetos / Minha Agenda'],
    [/jrc_broker|jrcBroker|jrc-broker/i, 'WhatsApp JRC / Broker'],
    [/jrc_flows|jrcFlows/i, 'Flows'],
    [/jrc_nico|jrcCopilot|jrcAI/i, 'NICO / IA'],
    [/crm|jrc_crm/i, 'CRM'],
    [/Contacts|contacts/i, 'Contatos'],
    [/jrcService|cockpit/i, 'Cockpit'],
    [/campaign/i, 'Campanhas'],
    [/webphone|call|video/i, 'Ligações / vídeo'],
    [/conversation|inbox/i, 'Conversas / caixas'],
    [/sidebar/i, 'Sidebar'],
  ];
  return (
    modules.find(([pattern]) => pattern.test(file))?.[1] ||
    'Compartilhado / outros'
  );
};
const occurrences = (source, pattern) =>
  [...source.matchAll(pattern)].map(match => ({
    line: source.slice(0, match.index).split('\n').length,
    value: match[0].trim(),
  }));
const files = walk(path.join(root, 'app/javascript/dashboard'));
const tests = files
  .filter(file => /\.(?:spec|test)\.[jt]s$/.test(file))
  .map(relative);
const controls = [];
const routes = [];
const errors = [];
for (const file of files.filter(
  file => /\.(?:vue|js|ts)$/.test(file) && !/\.(?:spec|test|story)\./.test(file)
)) {
  const source = fs.readFileSync(file, 'utf8');
  const filename = relative(file);
  if (/routes?\.[jt]s$/.test(file))
    routes.push({
      file: filename,
      module: moduleOf(filename),
      declarations: occurrences(
        source,
        /(?:path|name|component|permissions|featureFlag)\s*:\s*[^\n]+/g
      ),
    });
  if (!file.endsWith('.vue')) continue;
  const { descriptor, errors: parseErrors } = parse(source, { filename });
  if (parseErrors.length)
    errors.push({ file: filename, error: String(parseErrors[0]) });
  if (!descriptor.template) continue;
  let ast;
  try {
    ast = parseTemplate(descriptor.template.content);
  } catch (error) {
    errors.push({ file: filename, error: error.message });
    continue;
  }
  const scripts = `${descriptor.script?.content || ''}\n${descriptor.scriptSetup?.content || ''}`;
  const apiImports = occurrences(
    scripts,
    /import\s+[^;]+?from\s+['"][^'"]*(?:api|store|policy|permissions|featureFlags)[^'"]*['"]/g
  ).map(row => row.value);
  const routeReferences = occurrences(
    scripts,
    /(?:name|path)\s*:\s*['"][^'"]+['"]/g
  ).map(row => row.value);
  const gates = occurrences(
    source,
    /(?:checkPermissions|hasPermissions|isFeatureEnabled\w*|capability|permission|featureFlag)[^\n]{0,140}/g
  ).map(row => row.value);
  const screenTests = tests.filter(test =>
    test.includes(path.basename(file, '.vue'))
  );
  const visit = node => {
    if (node.type === 1) {
      const handlers = node.props
        .filter(prop => prop.type === 7 && prop.name === 'on')
        .map(prop => ({
          event: prop.arg?.content || 'dynamic',
          expression: prop.exp?.content || '',
        }));
      if (
        handlers.length ||
        /button|input|select|textarea|form|dropdown|modal|dialog|tabs?|table|kanban|pagination|scroll|router-link|checkbox|radio|toggle|badge/i.test(
          node.tag
        )
      ) {
        const bindings = node.props
          .filter(
            prop =>
              prop.type === 7 &&
              ['bind', 'model', 'if', 'show', 'for'].includes(prop.name)
          )
          .map(
            prop =>
              `${prop.name}:${prop.arg?.content || ''}=${prop.exp?.content || ''}`
          );
        const attributes = node.props
          .filter(
            prop =>
              prop.type === 6 && /label|title|type|role|name/.test(prop.name)
          )
          .map(prop => `${prop.name}=${prop.value?.content || ''}`);
        controls.push({
          module: moduleOf(filename),
          screen: filename,
          line: descriptor.template.loc.start.line + node.loc.start.line - 1,
          action: node.tag,
          handlers,
          attributes,
          bindings,
          routes: routeReferences,
          api_store_imports: apiImports,
          authorization_references: gates,
          test_candidates: screenTests,
          nico: 'Cruzar com catálogo de ferramentas; correspondência não inferida por nome',
          result: 'PENDENTE HOMOLOGAÇÃO MANUAL',
          observation:
            'Inventário estático: existência de controle/handler não comprova efeito, policy, persistência ou contraste',
        });
      }
    }
    for (const child of node.children || []) visit(child);
  };
  visit(ast);
}
const backend = [
  'app/controllers',
  'app/services',
  'app/policies',
  'enterprise/app/controllers',
  'enterprise/app/services',
  'enterprise/app/policies',
]
  .flatMap(folder => walk(path.join(root, folder)))
  .filter(file => file.endsWith('.rb'))
  .map(file => {
    const source = fs.readFileSync(file, 'utf8');
    return {
      file: relative(file),
      module: moduleOf(relative(file)),
      methods: occurrences(source, /^\s*def\s+[^\n]+/gm),
      authorization: occurrences(
        source,
        /^.*(?:authorize|policy_scope|capability|feature_enabled\?|before_action|crm_scope|visible_to_current_user).*$/gm
      ),
    };
  });
const nico = walk(path.join(root, 'app/services/jrc_nico'))
  .filter(file => /catalog\.rb$/.test(file))
  .map(file => ({
    file: relative(file),
    entries: occurrences(
      fs.readFileSync(file, 'utf8'),
      /^\s*'[^']+'\s*=>[^\n]+/gm
    ),
  }));
// Keep the dependency evidence separate: imports and declarations are candidates,
// never proof that a control reaches an authorized endpoint at runtime.
const clientContracts = files
  .filter(
    file =>
      /\.(?:js|ts)$/.test(file) &&
      /[/\\](?:api|store)[/\\]/.test(file) &&
      !/\.(?:spec|test)\./.test(file)
  )
  .map(file => {
    const source = fs.readFileSync(file, 'utf8');
    return {
      file: relative(file),
      module: moduleOf(relative(file)),
      requests: occurrences(
        source,
        /^.*(?:axios\.|\.get\(|\.post\(|\.put\(|\.patch\(|\.delete\(|super\(|dispatch\(|commit\().*$/gm
      ),
      imports: occurrences(source, /import[^;]+?from\s+['"][^'"]+['"]/g),
    };
  });
const modelContracts = ['app/models', 'enterprise/app/models']
  .flatMap(folder => walk(path.join(root, folder)))
  .filter(file => file.endsWith('.rb'))
  .map(file => ({
    file: relative(file),
    module: moduleOf(relative(file)),
    contracts: occurrences(
      fs.readFileSync(file, 'utf8'),
      /^.*(?:belongs_to|has_many|has_one|scope |validates|before_|after_|enum |include |serialize ).*$/gm
    ),
  }));
const testIndex = ['spec', 'test', 'app/javascript', 'enterprise/spec']
  .flatMap(folder => walk(path.join(root, folder)))
  .filter(file =>
    /(?:_spec\.rb|\.(?:spec|test)\.[cm]?[jt]s|\.test\.mjs)$/.test(file)
  )
  .map(file => ({ file: relative(file), module: moduleOf(relative(file)) }));
const quote = value => `"${String(value ?? '').replaceAll('"', '""')}"`;
const csv = [
  [
    'MÓDULO',
    'TELA',
    'LINHA',
    'AÇÃO/CONTROLE',
    'HANDLER',
    'ROTA',
    'API/STORE',
    'POLICY/CAPABILITY/FLAG',
    'TESTE CANDIDATO',
    'NICO',
    'RESULTADO',
    'OBSERVAÇÃO',
  ],
  ...controls.map(row => [
    row.module,
    row.screen,
    row.line,
    row.action,
    JSON.stringify(row.handlers),
    row.routes.join(' | '),
    row.api_store_imports.join(' | '),
    row.authorization_references.join(' | '),
    row.test_candidates.join(' | '),
    row.nico,
    row.result,
    row.observation,
  ]),
]
  .map(row => row.map(quote).join(','))
  .join('\n');
fs.mkdirSync(destination, { recursive: true });
fs.writeFileSync(path.join(destination, 'controls.csv'), '\ufeff' + csv);
const summary = {
  revision: execFileSync('git', ['rev-parse', 'HEAD'], {
    cwd: root,
    encoding: 'utf8',
  }).trim(),
  working_tree: execFileSync('git', ['status', '--short'], {
    cwd: root,
    encoding: 'utf8',
  }).trim(),
  templates_with_controls: new Set(controls.map(row => row.screen)).size,
  controls: controls.length,
  route_files: routes.length,
  backend_files: backend.length,
  api_store_files: clientContracts.length,
  model_files: modelContracts.length,
  test_files: testIndex.length,
  parse_errors: errors,
  classification:
    'Static discovery only; no automatic PASS for handlers or test-file presence',
  modules: Object.fromEntries(
    [...new Set(controls.map(row => row.module))].map(module => [
      module,
      controls.filter(row => row.module === module).length,
    ])
  ),
};
for (const [name, value] of Object.entries({
  summary,
  controls,
  routes,
  backend,
  nico,
  clientContracts,
  modelContracts,
  testIndex,
})) {
  fs.writeFileSync(
    path.join(destination, `${name}.json`),
    JSON.stringify(value, null, 2)
  );
}
for (const filename of ['config/routes.rb', 'config/features.yml']) {
  fs.copyFileSync(
    path.join(root, filename),
    path.join(destination, filename.split('/').at(-1))
  );
}
fs.writeFileSync(
  path.join(destination, 'migrations.json'),
  JSON.stringify(
    walk(path.join(root, 'db/migrate')).map(relative).sort(),
    null,
    2
  )
);
process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
