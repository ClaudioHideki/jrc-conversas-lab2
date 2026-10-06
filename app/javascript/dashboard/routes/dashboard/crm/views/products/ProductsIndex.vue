<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, reactive, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useFormDraft } from '../../helpers/useFormDraft';
import { useAlert } from 'dashboard/composables';
import { productsAPI } from 'dashboard/api/crm';
import { useCrmMetrics } from '../../composables/useCrmMetrics';
import CrmPageHeader from '../../components/shared/CrmPageHeader.vue';
import CrmStatCard from '../../components/shared/CrmStatCard.vue';

const { t } = useI18n();
const store = useStore();
const { formatBRL } = useCrmMetrics();

const products = computed(
  () => store.getters['jrcCrm/products/allProducts'] || []
);
const isLoading = computed(
  () => store.getters['jrcCrm/products/isLoading'] || false
);
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);

const showForm = ref(false);
const saving = ref(false);
const editingId = ref(null);
const activeTab = ref('information');
const search = ref('');
const typeFilter = ref('');
const billingFilter = ref('');
const statusFilter = ref('');
const importInput = ref(null);
const importing = ref(false);

const documentSources = {contract_generated:'Contrato gerado',contract_signed:'Contrato assinado',customer_registration:'Cadastro do cliente',billing_registration:'Dados de faturamento',technical_owner:'Responsável técnico',financial_owner:'Responsável financeiro',implementation_info:'Dados de implantação',manual:'Documento manual'};
const defaultForm = () => ({
  document_rules: [],
  name: '',
  sku: '',
  product_type: 'service',
  category: '',
  subcategory: '',
  description: '',
  tags_text: '',
  billing_model: 'monthly',
  sales_unit: 'unidade',
  unit_price: 0,
  cost: 0,
  setup_fee: 0,
  minimum_price: 0,
  tax_rate: 0,
  commission_rate: 0,
  minimum_quantity: 1,
  allow_variable_quantity: true,
  rollover_allowance: false,
  contract_term_months: 12,
  included_quantity: 0,
  included_unit: 'chamadas',
  overage_unit_price: 0,
  maximum_discount_percent: 20,
  discount_approval_percent: 10,
  renewal_type: 'automatic',
  adjustment_index: 'IPCA',
  adjustment_period_months: 12,
  cancellation_penalty_percent: 0,
  allow_standalone_sale: true,
  requires_contract: false,
  availability_text: 'Todas as empresas',
  integration_financial: false,
  integration_contracts: false,
  integration_implementation: false,
  proposal_template_name: '',
  contract_template_name: '',
  fiscal_service_code: '',
  activation_days: 0,
  validation_period_days: 0,
  sales_notes: '',
  technical_requirements: '',
  scope_included: '',
  scope_excluded: '',
  active: true,
});

const form = reactive(defaultForm());

const typeOptions = [
  { value: 'product', label: 'Produto' },
  { value: 'service', label: 'Serviço' },
  { value: 'license', label: 'Licença' },
  { value: 'project', label: 'Projeto' },
];

const billingOptions = [
  { value: 'one_time', label: 'Cobrança única' },
  { value: 'monthly', label: 'Mensal' },
  { value: 'annual', label: 'Anual' },
  { value: 'usage', label: 'Por uso' },
];

const tabs = [
  { id: 'information', label: 'Informações', icon: 'i-lucide-package-search' },
  { id: 'pricing', label: 'Preços e cobrança', icon: 'i-lucide-badge-dollar-sign' },
  { id: 'rules', label: 'Regras comerciais', icon: 'i-lucide-shield-check' },
  { id: 'integrations', label: 'Documentos e integrações', icon: 'i-lucide-files' },
];

const toCents = value => Math.round(Number(value || 0) * 100);
const fromCents = value => Number(value || 0) / 100;
const splitList = value =>
  String(value || '')
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);

const normalizeImportKey = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9]/g, '')
    .toLowerCase();

const parseLocalizedNumber = value => {
  const sanitized = String(value ?? '')
    .trim()
    .replace(/R\$/gi, '')
    .replace(/%/g, '')
    .replace(/\s/g, '');
  if (!sanitized) return 0;

  const normalized = sanitized.includes(',')
    ? sanitized.replace(/\./g, '').replace(',', '.')
    : sanitized;
  const number = Number(normalized);
  return Number.isFinite(number) ? number : 0;
};

const parseImportBoolean = (value, fallback = false) => {
  if (value === undefined || value === null || value === '') return fallback;
  return ['1', 'sim', 's', 'true', 'ativo', 'ativada', 'yes'].includes(
    normalizeImportKey(value)
  );
};

const splitImportList = value =>
  String(value || '')
    .split(/[|,]/)
    .map(item => item.trim())
    .filter(Boolean);

const parseCsv = text => {
  const content = String(text || '').replace(/^\uFEFF/, '');
  const firstLine = content.split(/\r?\n/, 1)[0] || '';
  const delimiter = firstLine.includes(';') ? ';' : ',';
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;

  for (let index = 0; index < content.length; index += 1) {
    const character = content[index];
    const nextCharacter = content[index + 1];

    if (character === '"' && quoted && nextCharacter === '"') {
      cell += '"';
      index += 1;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (character === delimiter && !quoted) {
      row.push(cell.trim());
      cell = '';
    } else if ((character === '\n' || character === '\r') && !quoted) {
      if (character === '\r' && nextCharacter === '\n') index += 1;
      row.push(cell.trim());
      if (row.some(value => value !== '')) rows.push(row);
      row = [];
      cell = '';
    } else {
      cell += character;
    }
  }

  row.push(cell.trim());
  if (row.some(value => value !== '')) rows.push(row);
  return rows;
};

const productTypeFromImport = value => {
  const normalized = normalizeImportKey(value);
  return {
    produto: 'product',
    product: 'product',
    servico: 'service',
    service: 'service',
    licenca: 'license',
    license: 'license',
    projeto: 'project',
    project: 'project',
  }[normalized] || 'service';
};

const billingFromImport = value => {
  const normalized = normalizeImportKey(value);
  return {
    cobrancaunica: 'one_time',
    unica: 'one_time',
    onetime: 'one_time',
    mensal: 'monthly',
    monthly: 'monthly',
    anual: 'annual',
    annual: 'annual',
    poruso: 'usage',
    uso: 'usage',
    usage: 'usage',
  }[normalized] || 'monthly';
};

const renewalFromImport = value => {
  const normalized = normalizeImportKey(value);
  return {
    automatica: 'automatic',
    automatico: 'automatic',
    automatic: 'automatic',
    manual: 'manual',
    semrenovacao: 'none',
    nenhuma: 'none',
    none: 'none',
  }[normalized] || 'automatic';
};

const productTypeLabel = value =>
  typeOptions.find(option => option.value === value)?.label || 'Serviço';
const billingLabel = value =>
  billingOptions.find(option => option.value === value)?.label || 'Mensal';
const renewalLabel = value =>
  ({ automatic: 'Automática', manual: 'Manual', none: 'Sem renovação' })[
    value
  ] || 'Automática';
const integrationLabel = value =>
  ({ financial: 'Financeiro', contracts: 'Contratos', implementation: 'Implantação' })[
    value
  ] || value;

const filteredProducts = computed(() => {
  const query = search.value.trim().toLocaleLowerCase('pt-BR');
  return products.value.filter(product => {
    const haystack = [
      product.name,
      product.sku,
      product.category,
      product.subcategory,
      product.description,
      ...(product.tags || []),
    ]
      .filter(Boolean)
      .join(' ')
      .toLocaleLowerCase('pt-BR');

    const matchesSearch = !query || haystack.includes(query);
    const matchesType =
      !typeFilter.value || product.product_type === typeFilter.value;
    const matchesBilling =
      !billingFilter.value || product.billing_model === billingFilter.value;
    const matchesStatus =
      !statusFilter.value ||
      (statusFilter.value === 'active' ? product.active : !product.active);

    return matchesSearch && matchesType && matchesBilling && matchesStatus;
  });
});

const activeProducts = computed(() =>
  products.value.filter(product => product.active)
);
const recurringProducts = computed(() =>
  activeProducts.value.filter(product => product.recurring)
);
const monthlyRevenue = computed(() =>
  recurringProducts.value.reduce(
    (total, product) =>
      total + Number(product.monthly_equivalent_cents || 0),
    0
  )
);
const averageMargin = computed(() => {
  const productsWithPrice = activeProducts.value.filter(
    product => Number(product.unit_price_cents || 0) > 0
  );
  if (!productsWithPrice.length) return 0;
  return Math.round(
    productsWithPrice.reduce(
      (total, product) => total + Number(product.estimated_margin_percent || 0),
      0
    ) / productsWithPrice.length
  );
});

const productStats = computed(() => {
  const stats = [
    {
      label: 'Produtos ativos',
      value: activeProducts.value.length,
      detail: 'Disponíveis para venda',
      icon: 'i-lucide-package-check',
      tone: 'teal',
    },
    {
      label: 'Serviços recorrentes',
      value: recurringProducts.value.length,
      detail: 'Mensal, anual ou por uso',
      icon: 'i-lucide-refresh-cw',
      tone: 'iris',
    },
    {
      label: 'Receita mensal equivalente',
      value: formatBRL(monthlyRevenue.value),
      detail: 'Base ativa do catálogo',
      icon: 'i-lucide-circle-dollar-sign',
      tone: 'blue',
    },
    {
      label: 'Itens inativos',
      value: products.value.filter(product => !product.active).length,
      detail: 'Fora do catálogo atual',
      icon: 'i-lucide-package-x',
      tone: 'ruby',
    },
  ];

  if (isAdmin.value) {
    stats.splice(3, 0, {
      label: 'Margem média',
      value: `${averageMargin.value}%`,
      detail: 'Preço menos custo interno',
      icon: 'i-lucide-chart-no-axes-combined',
      tone: 'teal',
    });
  }

  return stats;
});

const marginPreview = computed(() => {
  const price = toCents(form.unit_price);
  const cost = toCents(form.cost);
  if (!price) return 0;
  return Math.round(((price - cost) / price) * 100);
});

const monthlyPreview = computed(() => {
  const price = toCents(form.unit_price);
  if (form.billing_model === 'monthly') return price;
  if (form.billing_model === 'annual') return Math.round(price / 12);
  if (form.billing_model === 'usage') return price;
  return 0;
});

const resetForm = () => {
  Object.assign(form, defaultForm());
  editingId.value = null;
  activeTab.value = 'information';
};

const createActive = ref(false);
const productDraft = useFormDraft('crm:new_product', {
  active: createActive, snapshot: () => ({ ...form }), restore: value => Object.assign(form, value),
  reset: resetForm,
});
const openCreate = () => {
  productDraft.open();
  createActive.value = true;
  showForm.value = true;
};

const openEdit = product => {
  Object.assign(form, {
    ...defaultForm(),
    ...product,
    document_rules: structuredClone(product.document_rules || []),
    tags_text: (product.tags || []).join(', '),
    availability_text: (product.available_for || []).join(', '),
    unit_price: fromCents(product.unit_price_cents),
    cost: fromCents(product.cost_cents),
    setup_fee: fromCents(product.setup_fee_cents),
    minimum_price: fromCents(product.minimum_price_cents),
    overage_unit_price: fromCents(product.overage_unit_price_cents),
    integration_financial: (product.integrations || []).includes('financial'),
    integration_contracts: (product.integrations || []).includes('contracts'),
    integration_implementation: (product.integrations || []).includes('implementation'),
  });
  editingId.value = product.id;
  activeTab.value = 'information';
  showForm.value = true;
};

const closeForm = () => {
  createActive.value = false;
  showForm.value = false;
};

const payload = () => ({
  product: {
    name: form.name,
    sku: form.sku || null,
    product_type: form.product_type,
    category: form.category || null,
    subcategory: form.subcategory || null,
    description: form.description || null,
    tags: splitList(form.tags_text),
    billing_model: form.billing_model,
    sales_unit: form.sales_unit,
    unit_price_cents: toCents(form.unit_price),
    cost_cents: toCents(form.cost),
    setup_fee_cents: toCents(form.setup_fee),
    minimum_price_cents: toCents(form.minimum_price),
    tax_rate: Number(form.tax_rate || 0),
    commission_rate: Number(form.commission_rate || 0),
    minimum_quantity: Number(form.minimum_quantity || 1),
    allow_variable_quantity: form.allow_variable_quantity,
    rollover_allowance: form.rollover_allowance,
    contract_term_months: Number(form.contract_term_months || 12),
    included_quantity: Number(form.included_quantity || 0),
    included_unit: form.included_unit || null,
    overage_unit_price_cents: toCents(form.overage_unit_price),
    maximum_discount_percent: Number(form.maximum_discount_percent || 0),
    discount_approval_percent: Number(
      form.discount_approval_percent || 0
    ),
    renewal_type: form.renewal_type,
    adjustment_index: form.adjustment_index || 'IPCA',
    adjustment_period_months: Number(form.adjustment_period_months || 12),
    cancellation_penalty_percent: Number(
      form.cancellation_penalty_percent || 0
    ),
    allow_standalone_sale: form.allow_standalone_sale,
    requires_contract: form.requires_contract,
    document_rules: form.document_rules,
    available_for: splitList(form.availability_text).length
      ? splitList(form.availability_text)
      : ['all'],
    integrations: [
      form.integration_financial ? 'financial' : null,
      form.integration_contracts ? 'contracts' : null,
      form.integration_implementation ? 'implementation' : null,
    ].filter(Boolean),
    proposal_template_name: form.proposal_template_name || null,
    contract_template_name: form.contract_template_name || null,
    fiscal_service_code: form.fiscal_service_code || null,
    activation_days: Number(form.activation_days || 0),
    validation_period_days: Number(form.validation_period_days || 0),
    sales_notes: form.sales_notes || null,
    technical_requirements: form.technical_requirements || null,
    scope_included: form.scope_included || null,
    scope_excluded: form.scope_excluded || null,
    active: form.active,
  },
});

const saveProduct = async () => {
  const savingDraftKey = productDraft.key.value;
  saving.value = true;
  try {
    if (editingId.value) {
      await productsAPI.update(editingId.value, payload());
      useAlert('Produto atualizado com sucesso.');
    } else {
      await productsAPI.create(payload());
      if (!productDraft.complete(savingDraftKey)) return;
      useAlert('Produto criado com sucesso.');
    }
    closeForm();
    await refresh();
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível salvar o produto.'
    );
  } finally {
    saving.value = false;
  }
};

const toggleActive = async product => {
  if (!isAdmin.value) return;
  try {
    await productsAPI.toggleActive(product.id);
    await refresh();
    useAlert(product.active ? 'Produto desativado.' : 'Produto ativado.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível alterar o status.'
    );
  }
};

const clearFilters = () => {
  search.value = '';
  typeFilter.value = '';
  billingFilter.value = '';
  statusFilter.value = '';
};

const requestCatalogImport = () => {
  if (!isAdmin.value || importing.value) return;
  importInput.value?.click();
};

const importRowValue = (record, aliases) => {
  for (const alias of aliases) {
    const value = record[normalizeImportKey(alias)];
    if (value !== undefined && value !== '') return value;
  }
  return '';
};

const buildImportedProduct = record => {
  const name = importRowValue(record, ['nome', 'name']).trim();
  const approvalPercent = parseLocalizedNumber(
    importRowValue(record, [
      'aprovação a partir de',
      'aprovacao a partir de',
      'limite de aprovação',
      'limite de aprovacao',
    ])
  );
  const maximumDiscount = Math.max(
    approvalPercent,
    parseLocalizedNumber(
      importRowValue(record, ['desconto máximo', 'desconto maximo'])
    )
  );

  const integrations = splitImportList(
    importRowValue(record, ['integrações', 'integracoes'])
  )
    .map(value => {
      const normalized = normalizeImportKey(value);
      return {
        financeiro: 'financial',
        financial: 'financial',
        contratos: 'contracts',
        contracts: 'contracts',
        implantacao: 'implementation',
        implementation: 'implementation',
      }[normalized];
    })
    .filter(Boolean);

  return {
    name,
    sku: importRowValue(record, ['sku', 'código', 'codigo']).trim() || null,
    product_type: productTypeFromImport(
      importRowValue(record, ['tipo', 'product type'])
    ),
    category: importRowValue(record, ['categoria']).trim() || null,
    subcategory: importRowValue(record, ['subcategoria']).trim() || null,
    description:
      importRowValue(record, ['descrição', 'descricao']).trim() || null,
    tags: splitImportList(importRowValue(record, ['tags', 'etiquetas'])),
    billing_model: billingFromImport(
      importRowValue(record, ['cobrança', 'cobranca', 'modelo de cobrança'])
    ),
    sales_unit:
      importRowValue(record, ['unidade', 'unidade de venda']).trim() ||
      'unidade',
    unit_price_cents: toCents(
      parseLocalizedNumber(
        importRowValue(record, ['preço', 'preco', 'preço de venda'])
      )
    ),
    cost_cents: toCents(
      parseLocalizedNumber(importRowValue(record, ['custo', 'custo interno']))
    ),
    setup_fee_cents: toCents(
      parseLocalizedNumber(
        importRowValue(record, ['implantação', 'implantacao', 'setup'])
      )
    ),
    minimum_price_cents: toCents(
      parseLocalizedNumber(
        importRowValue(record, ['preço mínimo', 'preco minimo'])
      )
    ),
    tax_rate: parseLocalizedNumber(
      importRowValue(record, ['impostos', 'taxa de impostos'])
    ),
    commission_rate: parseLocalizedNumber(
      importRowValue(record, ['comissão', 'comissao'])
    ),
    included_quantity: parseLocalizedNumber(
      importRowValue(record, ['franquia incluída', 'franquia incluida'])
    ),
    included_unit:
      importRowValue(record, ['unidade da franquia']).trim() || 'chamadas',
    overage_unit_price_cents: toCents(
      parseLocalizedNumber(
        importRowValue(record, ['valor excedente', 'preço excedente'])
      )
    ),
    minimum_quantity: Math.max(
      1,
      Math.round(
        parseLocalizedNumber(
          importRowValue(record, ['quantidade mínima', 'quantidade minima'])
        ) || 1
      )
    ),
    allow_variable_quantity: parseImportBoolean(
      importRowValue(record, ['quantidade variável', 'quantidade variavel']),
      true
    ),
    activation_days: Math.max(
      0,
      Math.round(
        parseLocalizedNumber(
          importRowValue(record, ['prazo de ativação', 'prazo de ativacao'])
        )
      )
    ),
    validation_period_days: Math.max(
      0,
      Math.round(
        parseLocalizedNumber(
          importRowValue(record, ['período de validação', 'periodo de validacao'])
        )
      )
    ),
    rollover_allowance: parseImportBoolean(
      importRowValue(record, ['rollover de franquia', 'rollover']),
      false
    ),
    contract_term_months: Math.max(
      1,
      Math.round(
        parseLocalizedNumber(
          importRowValue(record, ['vigência', 'vigencia', 'vigência meses'])
        ) || 12
      )
    ),
    maximum_discount_percent: maximumDiscount,
    discount_approval_percent: approvalPercent,
    renewal_type: renewalFromImport(
      importRowValue(record, ['renovação', 'renovacao'])
    ),
    adjustment_index:
      importRowValue(record, ['índice de reajuste', 'indice de reajuste']).trim() ||
      'IPCA',
    adjustment_period_months: Math.max(
      1,
      Math.round(
        parseLocalizedNumber(
          importRowValue(record, ['período de reajuste', 'periodo de reajuste'])
        ) || 12
      )
    ),
    cancellation_penalty_percent: parseLocalizedNumber(
      importRowValue(record, ['multa de cancelamento', 'multa cancelamento'])
    ),
    allow_standalone_sale: parseImportBoolean(
      importRowValue(record, ['permite venda avulsa', 'venda avulsa']),
      true
    ),
    requires_contract: parseImportBoolean(
      importRowValue(record, ['exige contrato', 'requer contrato']),
      false
    ),
    available_for: splitImportList(
      importRowValue(record, ['disponibilidade', 'disponível para'])
    ).length
      ? splitImportList(
          importRowValue(record, ['disponibilidade', 'disponível para'])
        )
      : ['all'],
    integrations,
    proposal_template_name:
      importRowValue(record, ['modelo de proposta']).trim() || null,
    contract_template_name:
      importRowValue(record, ['modelo de contrato']).trim() || null,
    fiscal_service_code:
      importRowValue(record, ['código fiscal', 'codigo fiscal']).trim() || null,
    sales_notes:
      importRowValue(record, ['observações comerciais', 'observacoes comerciais']).trim() ||
      null,
    technical_requirements:
      importRowValue(record, ['requisitos técnicos', 'requisitos tecnicos']).trim() ||
      null,
    scope_included:
      importRowValue(record, ['escopo incluído', 'escopo incluido']).trim() ||
      null,
    scope_excluded:
      importRowValue(record, ['escopo não incluído', 'escopo nao incluido']).trim() ||
      null,
    active: parseImportBoolean(
      importRowValue(record, ['status', 'ativo']),
      true
    ),
  };
};

const handleCatalogImport = async event => {
  const [file] = Array.from(event.target.files || []);
  event.target.value = '';
  if (!file || !isAdmin.value) return;

  importing.value = true;
  try {
    const rows = parseCsv(await file.text());
    if (rows.length < 2) {
      useAlert('O CSV precisa ter cabeçalho e pelo menos um produto.');
      return;
    }

    const headers = rows[0].map(normalizeImportKey);
    const records = rows.slice(1).map(row =>
      headers.reduce((record, header, index) => {
        if (header) record[header] = row[index] || '';
        return record;
      }, {})
    );

    if (records.length > 500) {
      useAlert('Importe no máximo 500 produtos por arquivo.');
      return;
    }

    const knownKeys = new Set();
    products.value.forEach(product => {
      if (product.sku) knownKeys.add(`sku:${normalizeImportKey(product.sku)}`);
      knownKeys.add(`name:${normalizeImportKey(product.name)}`);
    });

    const skipped = [];
    const pending = [];
    records.forEach((record, index) => {
      const product = buildImportedProduct(record);
      if (!product.name) {
        skipped.push(`linha ${index + 2}: nome ausente`);
        return;
      }

      const identity = product.sku
        ? `sku:${normalizeImportKey(product.sku)}`
        : `name:${normalizeImportKey(product.name)}`;
      if (knownKeys.has(identity)) {
        skipped.push(`linha ${index + 2}: produto duplicado`);
        return;
      }

      knownKeys.add(identity);
      pending.push({ line: index + 2, product });
    });

    if (!pending.length) {
      useAlert(
        skipped.length
          ? 'Nenhum produto novo foi encontrado; revise nomes e SKUs duplicados.'
          : 'Nenhum produto válido foi encontrado no arquivo.'
      );
      return;
    }

    const confirmed = window.confirm(
      `Serão criados ${pending.length} produtos. ${skipped.length} linhas serão ignoradas. Deseja continuar?`
    );
    if (!confirmed) return;

    let imported = 0;
    const failures = [];
    for (const item of pending) {
      try {
        await productsAPI.create({ product: item.product });
        imported += 1;
      } catch (error) {
        const message =
          error.response?.data?.errors?.join(', ') || 'erro não identificado';
        failures.push(`linha ${item.line}: ${message}`);
      }
    }

    await refresh();
    const summary = [
      `${imported} produto(s) importado(s).`,
      skipped.length ? `${skipped.length} linha(s) ignorada(s).` : '',
      failures.length ? `${failures.length} linha(s) com erro.` : '',
    ]
      .filter(Boolean)
      .join(' ');
    useAlert(summary);
  } catch (error) {
    useAlert('Não foi possível ler o catálogo. Confirme o formato CSV.');
  } finally {
    importing.value = false;
  }
};

const exportCatalog = () => {
  const headers = [
    'Nome',
    'SKU',
    'Tipo',
    'Categoria',
    'Subcategoria',
    'Descrição',
    'Tags',
    'Cobrança',
    'Unidade de venda',
    'Preço de venda',
    'Custo interno',
    'Implantação',
    'Preço mínimo',
    'Impostos (%)',
    'Comissão (%)',
    'Quantidade mínima',
    'Quantidade variável',
    'Franquia incluída',
    'Unidade da franquia',
    'Valor excedente',
    'Rollover de franquia',
    'Vigência (meses)',
    'Desconto máximo (%)',
    'Aprovação a partir de (%)',
    'Renovação',
    'Índice de reajuste',
    'Período de reajuste (meses)',
    'Multa de cancelamento (%)',
    'Permite venda avulsa',
    'Exige contrato',
    'Disponibilidade',
    'Integrações',
    'Modelo de proposta',
    'Modelo de contrato',
    'Código fiscal',
    'Prazo de ativação',
    'Período de validação',
    'Observações comerciais',
    'Requisitos técnicos',
    'Escopo incluído',
    'Escopo não incluído',
    'Status',
  ];
  const rows = filteredProducts.value.map(product => [
    product.name,
    product.sku || '',
    productTypeLabel(product.product_type),
    product.category || '',
    product.subcategory || '',
    product.description || '',
    (product.tags || []).join('|'),
    billingLabel(product.billing_model),
    product.sales_unit || 'unidade',
    (Number(product.unit_price_cents || 0) / 100).toFixed(2),
    (Number(product.cost_cents || 0) / 100).toFixed(2),
    (Number(product.setup_fee_cents || 0) / 100).toFixed(2),
    (Number(product.minimum_price_cents || 0) / 100).toFixed(2),
    product.tax_rate || 0,
    product.commission_rate || 0,
    product.minimum_quantity || 1,
    product.allow_variable_quantity ? 'Sim' : 'Não',
    product.included_quantity || 0,
    product.included_unit || '',
    (Number(product.overage_unit_price_cents || 0) / 100).toFixed(2),
    product.rollover_allowance ? 'Sim' : 'Não',
    product.contract_term_months || 12,
    product.maximum_discount_percent || 0,
    product.discount_approval_percent || 0,
    renewalLabel(product.renewal_type),
    product.adjustment_index || 'IPCA',
    product.adjustment_period_months || 12,
    product.cancellation_penalty_percent || 0,
    product.allow_standalone_sale ? 'Sim' : 'Não',
    product.requires_contract ? 'Sim' : 'Não',
    (product.available_for || []).join('|'),
    (product.integrations || []).map(integrationLabel).join('|'),
    product.proposal_template_name || '',
    product.contract_template_name || '',
    product.fiscal_service_code || '',
    product.activation_days || 0,
    product.validation_period_days || 0,
    product.sales_notes || '',
    product.technical_requirements || '',
    product.scope_included || '',
    product.scope_excluded || '',
    product.active ? 'Ativo' : 'Inativo',
  ]);
  const escape = value => `"${String(value).replaceAll('"', '""')}"`;
  const csv = [headers, ...rows]
    .map(row => row.map(escape).join(';'))
    .join('\n');
  const blob = new Blob([`\uFEFF${csv}`], {
    type: 'text/csv;charset=utf-8',
  });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = 'catalogo-jrc-conversas.csv';
  link.click();
  URL.revokeObjectURL(link.href);
};

const refresh = () => store.dispatch('jrcCrm/products/fetchProducts');

onMounted(refresh);
</script>

<template>
  <div class="h-full overflow-auto bg-n-surface-1">
    <div
      class="mx-auto flex min-h-full w-full max-w-[1700px] flex-col gap-5 p-4 sm:p-6"
    >
      <CrmPageHeader
        eyebrow="Catálogo comercial"
        title="Catálogo de produtos"
        description="Produtos, serviços, licenças e projetos preparados para propostas recorrentes ou avulsas."
        icon="i-lucide-package"
        tone="teal"
      >
        <template #actions>
          <input
            ref="importInput"
            type="file"
            accept=".csv,text/csv"
            class="hidden"
            @change="handleCatalogImport"
          />
          <button
            v-if="isAdmin"
            type="button"
            class="rounded-xl bg-n-blue-9 px-4 py-2.5 text-sm font-semibold text-white shadow-md transition hover:-translate-y-0.5 disabled:cursor-wait disabled:opacity-60"
            :disabled="importing"
            @click="requestCatalogImport"
          >
            <i class="i-lucide-file-up mr-1 size-4" />
            {{ importing ? 'Importando...' : 'Importar catálogo' }}
          </button>
          <button
            type="button"
            class="rounded-xl bg-n-iris-9 px-4 py-2.5 text-sm font-semibold text-white shadow-md transition hover:-translate-y-0.5"
            @click="exportCatalog"
          >
            <i class="i-lucide-download mr-1 size-4" /> Exportar
          </button>
          <button
            v-if="isAdmin"
            type="button"
            class="rounded-xl bg-n-teal-9 px-4 py-2.5 text-sm font-semibold text-white shadow-md transition hover:-translate-y-0.5"
            @click="openCreate"
          >
            <i class="i-lucide-plus mr-1 size-4" /> Novo produto
          </button>
        </template>
      </CrmPageHeader>

      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <CrmStatCard
          v-for="item in productStats"
          :key="item.label"
          :label="item.label"
          :value="item.value"
          :detail="item.detail"
          :icon="item.icon"
          :tone="item.tone"
        />
      </div>

      <section
        class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
      >
        <div class="grid gap-3 lg:grid-cols-[minmax(260px,1fr)_190px_190px_170px_auto]">
          <label class="relative">
            <i
              class="i-lucide-search absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-9"
            />
            <input
              v-model="search"
              class="w-full rounded-xl border border-n-weak bg-n-solid-2 py-2.5 pl-10 pr-3 text-sm outline-none transition focus:border-n-blue-8"
              placeholder="Buscar por nome, SKU, categoria ou tag"
            />
          </label>
          <select
            v-model="typeFilter"
            class="rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5 text-sm"
          >
            <option value="">Todos os tipos</option>
            <option
              v-for="option in typeOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
          <select
            v-model="billingFilter"
            class="rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5 text-sm"
          >
            <option value="">Todas as cobranças</option>
            <option
              v-for="option in billingOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
          <select
            v-model="statusFilter"
            class="rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5 text-sm"
          >
            <option value="">Todos os status</option>
            <option value="active">Ativos</option>
            <option value="inactive">Inativos</option>
          </select>
          <button
            type="button"
            class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 text-sm font-semibold text-n-slate-11 transition hover:bg-n-alpha-2"
            @click="clearFilters"
          >
            <i class="i-lucide-rotate-ccw mr-1 size-4" /> Limpar
          </button>
        </div>
      </section>

      <section
        class="min-h-[420px] flex-1 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <div
          class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-5 py-4"
        >
          <div>
            <h3 class="font-bold text-n-slate-12">Catálogo atual</h3>
            <p class="text-xs text-n-slate-10">
              {{ filteredProducts.length }} de {{ products.length }} itens
            </p>
          </div>
          <span
            class="rounded-full bg-n-teal-3 px-3 py-1.5 text-xs font-semibold text-n-teal-11"
          >
            Catálogo comercial JRC
          </span>
        </div>

        <div class="overflow-auto">
          <table class="min-w-[1180px] w-full divide-y divide-n-weak text-sm">
            <thead
              class="sticky top-0 z-10 bg-n-alpha-2 text-left text-xs font-semibold uppercase text-n-slate-10"
            >
              <tr>
                <th class="px-5 py-3">Nome / SKU</th>
                <th class="px-5 py-3">Tipo e categoria</th>
                <th class="px-5 py-3">Cobrança</th>
                <th class="px-5 py-3">Preço / implantação</th>
                <th v-if="isAdmin" class="px-5 py-3">Margem</th>
                <th class="px-5 py-3">Vigência</th>
                <th class="px-5 py-3">Status</th>
                <th v-if="isAdmin" class="px-5 py-3 text-right">Ações</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr v-if="isLoading">
                <td :colspan="isAdmin ? 8 : 6" class="px-6 py-14 text-center text-n-slate-10">
                  <i class="i-lucide-loader-circle mr-2 size-5 animate-spin" />
                  Carregando catálogo...
                </td>
              </tr>
              <tr v-else-if="!filteredProducts.length">
                <td :colspan="isAdmin ? 8 : 6" class="px-6 py-14 text-center text-n-slate-10">
                  <div
                    class="mx-auto mb-3 flex size-12 items-center justify-center rounded-2xl bg-n-alpha-3"
                  >
                    <i class="i-lucide-package-search size-6" />
                  </div>
                  Nenhum item encontrado com os filtros informados.
                </td>
              </tr>
              <tr
                v-for="product in filteredProducts"
                v-else
                :key="product.id"
                class="transition hover:bg-n-alpha-2"
              >
                <td class="px-5 py-4">
                  <p class="font-semibold text-n-slate-12">{{ product.name }}</p>
                  <p class="mt-0.5 text-xs text-n-slate-10">
                    {{ product.sku || 'Sem SKU' }}
                  </p>
                  <div v-if="product.tags?.length" class="mt-2 flex flex-wrap gap-1">
                    <span
                      v-for="tag in product.tags.slice(0, 3)"
                      :key="tag"
                      class="rounded-full bg-n-blue-3 px-2 py-0.5 text-[11px] font-medium text-n-blue-11"
                    >
                      {{ tag }}
                    </span>
                  </div>
                </td>
                <td class="px-5 py-4">
                  <span
                    class="inline-flex rounded-full bg-n-iris-3 px-2.5 py-1 text-xs font-semibold text-n-iris-11"
                  >
                    {{ productTypeLabel(product.product_type) }}
                  </span>
                  <p class="mt-2 text-xs text-n-slate-11">
                    {{ product.category || 'Sem categoria' }}
                    <span v-if="product.subcategory"> · {{ product.subcategory }}</span>
                  </p>
                </td>
                <td class="px-5 py-4">
                  <p class="font-medium text-n-slate-12">
                    {{ billingLabel(product.billing_model) }}
                  </p>
                  <p class="mt-1 text-xs text-n-slate-10">
                    {{ product.sales_unit || 'Unidade' }}
                    <span v-if="product.recurring"> · recorrente</span>
                  </p>
                </td>
                <td class="px-5 py-4">
                  <p class="font-bold text-n-slate-12">
                    {{ formatBRL(product.unit_price_cents) }}
                  </p>
                  <p class="mt-1 text-xs text-n-slate-10">
                    Implantação: {{ formatBRL(product.setup_fee_cents) }}
                  </p>
                </td>
                <td v-if="isAdmin" class="px-5 py-4">
                  <p
                    class="font-bold"
                    :class="
                      Number(product.estimated_margin_percent || 0) >= 30
                        ? 'text-n-teal-11'
                        : 'text-n-amber-11'
                    "
                  >
                    {{ product.estimated_margin_percent || 0 }}%
                  </p>
                  <p class="mt-1 text-xs text-n-slate-10">
                    Custo: {{ formatBRL(product.cost_cents) }}
                  </p>
                </td>
                <td class="px-5 py-4 text-n-slate-11">
                  <p>{{ product.contract_term_months || 0 }} meses</p>
                  <p class="mt-1 text-xs text-n-slate-10">
                    Ativação: {{ product.activation_days || 0 }} dias
                  </p>
                </td>
                <td class="px-5 py-4">
                  <span
                    class="rounded-full px-2.5 py-1 text-xs font-semibold"
                    :class="
                      product.active
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : 'bg-n-ruby-3 text-n-ruby-11'
                    "
                  >
                    {{ product.active ? 'Ativo' : 'Inativo' }}
                  </span>
                </td>
                <td v-if="isAdmin" class="px-5 py-4">
                  <div class="flex justify-end gap-2">
                    <button
                      type="button"
                      class="flex size-9 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11 transition hover:bg-n-blue-4"
                      aria-label="Editar produto"
                      title="Editar produto"
                      @click="openEdit(product)"
                    >
                      <i class="i-lucide-pencil size-4" />
                    </button>
                    <button
                      v-if="isAdmin"
                      type="button"
                      class="flex size-9 items-center justify-center rounded-xl transition"
                      :class="
                        product.active
                          ? 'bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4'
                          : 'bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4'
                      "
                      :aria-label="product.active ? 'Desativar produto' : 'Ativar produto'"
                      :title="product.active ? 'Desativar produto' : 'Ativar produto'"
                      @click="toggleActive(product)"
                    >
                      <i
                        class="size-4"
                        :class="product.active ? 'i-lucide-package-x' : 'i-lucide-package-check'"
                      />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>

    <div
      v-if="showForm"
      class="fixed inset-0 z-[90] flex items-center justify-center bg-slate-950/50 p-2 sm:p-4"
      @click.self="closeForm"
      @keydown.esc="closeForm"
    >
      <form
        class="flex max-h-[96vh] w-full max-w-[1450px] flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-2xl"
        @submit.prevent="saveProduct"
      >
        <header
          class="flex shrink-0 items-center justify-between border-b border-n-weak bg-gradient-to-r from-n-teal-2 via-n-blue-2 to-n-iris-2 px-5 py-4 sm:px-6"
        >
          <div class="flex items-center gap-3">
            <span
              class="flex size-11 items-center justify-center rounded-2xl bg-n-teal-9 text-white shadow-md"
            >
              <i class="i-lucide-package-plus size-5" />
            </span>
            <div>
              <h3 class="text-lg font-bold text-n-slate-12">
                {{ editingId ? 'Editar produto ou serviço' : 'Novo produto ou serviço' }}
              </h3>
              <p class="text-xs text-n-slate-10">
                Configure informações comerciais, cobrança e regras de venda da JRC.
              </p>
            </div>
          </div>
          <button
            type="button"
            class="flex size-9 items-center justify-center rounded-xl text-n-slate-10 transition hover:bg-n-alpha-3"
            aria-label="Fechar"
            @click="closeForm"
          >
            <i class="i-lucide-x size-5" />
          </button>
        </header>

        <nav class="shrink-0 overflow-x-auto border-b border-n-weak px-4 py-3 sm:px-6">
          <div class="flex min-w-max gap-2">
            <button
              v-for="(tab, index) in tabs"
              :key="tab.id"
              type="button"
              class="flex items-center gap-2 rounded-xl border px-4 py-2.5 text-sm font-semibold transition"
              :class="
                activeTab === tab.id
                  ? 'border-n-iris-7 bg-n-iris-3 text-n-iris-11 shadow-sm'
                  : 'border-n-weak bg-n-solid-2 text-n-slate-10 hover:bg-n-alpha-2'
              "
              @click="activeTab = tab.id"
            >
              <span
                class="flex size-6 items-center justify-center rounded-lg text-xs font-bold"
                :class="activeTab === tab.id ? 'bg-n-iris-9 text-white' : 'bg-n-alpha-3'"
              >{{ index + 1 }}</span>
              <i :class="[tab.icon, 'size-4']" />
              {{ tab.label }}
            </button>
          </div>
        </nav>

        <div class="grid min-h-0 flex-1 overflow-hidden xl:grid-cols-[minmax(0,1fr)_340px]">
          <div class="overflow-y-auto p-4 sm:p-6">
            <section v-if="activeTab === 'information'" class="space-y-5">
              <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                <label class="text-sm font-medium text-n-slate-11 md:col-span-2">
                  Nome do produto ou serviço *
                  <input
                    v-model.trim="form.name"
                    required
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5 outline-none focus:border-n-blue-8"
                    placeholder="Ex.: STIR/SHAKEN"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  SKU / Código
                  <input
                    v-model.trim="form.sku"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5 outline-none focus:border-n-blue-8"
                    placeholder="JRC-STIR-10000"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Tipo
                  <select
                    v-model="form.product_type"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  >
                    <option
                      v-for="option in typeOptions"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Categoria
                  <input
                    v-model.trim="form.category"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Telefonia e Segurança"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Subcategoria
                  <input
                    v-model.trim="form.subcategory"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Autenticação de chamadas"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11 md:col-span-2 xl:col-span-3">
                  Descrição comercial
                  <textarea
                    v-model.trim="form.description"
                    rows="4"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5 outline-none focus:border-n-blue-8"
                    placeholder="Descreva o benefício, o escopo e o que será apresentado ao cliente."
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11 md:col-span-2">
                  Tags, separadas por vírgula
                  <input
                    v-model.trim="form.tags_text"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Telefonia, Segurança, Recorrente"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Prazo de ativação (dias)
                  <input
                    v-model.number="form.activation_days"
                    type="number"
                    min="0"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Validação inicial (dias)
                  <input
                    v-model.number="form.validation_period_days"
                    type="number"
                    min="0"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Código do serviço fiscal
                  <input
                    v-model.trim="form.fiscal_service_code"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Ex.: 1098"
                  />
                </label>
              </div>
            </section>

            <section v-else-if="activeTab === 'pricing'" class="space-y-5">
              <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                <label class="text-sm font-medium text-n-slate-11">
                  Modelo de cobrança
                  <select
                    v-model="form.billing_model"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  >
                    <option
                      v-for="option in billingOptions"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Unidade de venda
                  <input
                    v-model.trim="form.sales_unit"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Unidade, franquia, usuário..."
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Quantidade mínima
                  <input
                    v-model.number="form.minimum_quantity"
                    type="number"
                    min="1"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Preço de venda (R$) *
                  <input
                    v-model.number="form.unit_price"
                    required
                    type="number"
                    min="0"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Custo interno (R$)
                  <input
                    v-model.number="form.cost"
                    type="number"
                    min="0"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Setup / implantação (R$)
                  <input
                    v-model.number="form.setup_fee"
                    type="number"
                    min="0"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Preço mínimo permitido (R$)
                  <input
                    v-model.number="form.minimum_price"
                    type="number"
                    min="0"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Impostos estimados (%)
                  <input
                    v-model.number="form.tax_rate"
                    type="number"
                    min="0"
                    max="100"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Comissão (%)
                  <input
                    v-model.number="form.commission_rate"
                    type="number"
                    min="0"
                    max="100"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Vigência contratual (meses)
                  <input
                    v-model.number="form.contract_term_months"
                    type="number"
                    min="1"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
              </div>

              <div class="rounded-2xl border border-n-teal-6 bg-n-teal-2 p-5">
                <div class="mb-4 flex items-center gap-2">
                  <i class="i-lucide-gauge size-5 text-n-teal-11" />
                  <h4 class="font-bold text-n-slate-12">Franquia e excedentes</h4>
                </div>
                <div class="grid gap-4 md:grid-cols-3">
                  <label class="text-sm font-medium text-n-slate-11">
                    Quantidade incluída
                    <input
                      v-model.number="form.included_quantity"
                      type="number"
                      min="0"
                      class="mt-1.5 w-full rounded-xl border border-n-teal-6 bg-n-solid-2 px-3 py-2.5"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Unidade da franquia
                    <input
                      v-model.trim="form.included_unit"
                      class="mt-1.5 w-full rounded-xl border border-n-teal-6 bg-n-solid-2 px-3 py-2.5"
                      placeholder="Chamadas, minutos, usuários"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Valor por excedente (R$)
                    <input
                      v-model.number="form.overage_unit_price"
                      type="number"
                      min="0"
                      step="0.01"
                      class="mt-1.5 w-full rounded-xl border border-n-teal-6 bg-n-solid-2 px-3 py-2.5"
                    />
                  </label>
                </div>
              </div>

              <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                <label
                  class="flex items-center justify-between gap-4 rounded-2xl border border-n-weak p-4"
                >
                  <span>
                    <span class="block font-semibold text-n-slate-12">Receita recorrente</span>
                    <span class="text-xs text-n-slate-10">Compõe a recorrência mensal da proposta.</span>
                  </span>
                  <input
                    :checked="form.billing_model !== 'one_time'"
                    type="checkbox"
                    class="size-5 accent-n-teal-9"
                    :disabled="form.billing_model === 'one_time'"
                  />
                </label>
                <label
                  class="flex items-center justify-between gap-4 rounded-2xl border border-n-weak p-4"
                >
                  <span>
                    <span class="block font-semibold text-n-slate-12">Quantidade variável</span>
                    <span class="text-xs text-n-slate-10">Permite ajustar o consumo na venda.</span>
                  </span>
                  <input
                    v-model="form.allow_variable_quantity"
                    type="checkbox"
                    class="size-5 accent-n-blue-9"
                  />
                </label>
                <label
                  class="flex items-center justify-between gap-4 rounded-2xl border border-n-weak p-4"
                >
                  <span>
                    <span class="block font-semibold text-n-slate-12">Acumular franquia</span>
                    <span class="text-xs text-n-slate-10">Permite carregar saldo para o próximo ciclo.</span>
                  </span>
                  <input
                    v-model="form.rollover_allowance"
                    type="checkbox"
                    class="size-5 accent-n-iris-9"
                  />
                </label>
              </div>
            </section>

            <section v-else-if="activeTab === 'rules'" class="space-y-5">
              <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                <label class="text-sm font-medium text-n-slate-11">
                  Desconto máximo (%)
                  <input
                    v-model.number="form.maximum_discount_percent"
                    type="number"
                    min="0"
                    max="100"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Aprovação obrigatória acima de (%)
                  <input
                    v-model.number="form.discount_approval_percent"
                    type="number"
                    min="0"
                    max="100"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Renovação
                  <select
                    v-model="form.renewal_type"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  >
                    <option value="automatic">Automática</option>
                    <option value="manual">Manual</option>
                    <option value="none">Sem renovação</option>
                  </select>
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Índice de reajuste
                  <input
                    v-model.trim="form.adjustment_index"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="IPCA"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Período de reajuste (meses)
                  <input
                    v-model.number="form.adjustment_period_months"
                    type="number"
                    min="1"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Multa de cancelamento (%)
                  <input
                    v-model.number="form.cancellation_penalty_percent"
                    type="number"
                    min="0"
                    max="100"
                    step="0.01"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11 md:col-span-2 xl:col-span-3">
                  Disponível para empresas, separadas por vírgula
                  <input
                    v-model.trim="form.availability_text"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Todas as empresas, Operadora JRC, Unidade comercial"
                  />
                </label>
              </div>

              <div class="grid gap-3 md:grid-cols-3">
                <label
                  class="flex items-center justify-between gap-3 rounded-2xl border border-n-weak p-4"
                >
                  <span>
                    <span class="block font-semibold text-n-slate-12">Venda avulsa</span>
                    <span class="text-xs text-n-slate-10">Pode ser contratado isoladamente.</span>
                  </span>
                  <input v-model="form.allow_standalone_sale" type="checkbox" class="size-5 accent-n-teal-9" />
                </label>
                <label
                  class="flex items-center justify-between gap-3 rounded-2xl border border-n-weak p-4"
                >
                  <span>
                    <span class="block font-semibold text-n-slate-12">Exigir contrato</span>
                    <span class="text-xs text-n-slate-10">Bloqueia envio sem documento.</span>
                  </span>
                  <input v-model="form.requires_contract" type="checkbox" class="size-5 accent-n-iris-9" />
                </label>
                <label
                  class="flex items-center justify-between gap-3 rounded-2xl border border-n-weak p-4"
                >
                  <span>
                    <span class="block font-semibold text-n-slate-12">Produto ativo</span>
                    <span class="text-xs text-n-slate-10">Disponível no catálogo e propostas.</span>
                  </span>
                  <input v-model="form.active" type="checkbox" class="size-5 accent-n-blue-9" />
                </label>
              </div>
            </section>

            <section v-else class="space-y-5"><fieldset class="rounded-xl border p-4"><legend class="px-2 font-semibold">Requisitos documentais do Backoffice</legend><div v-for="(rule,index) in form.document_rules" :key="index" class="mb-3 grid gap-2 sm:grid-cols-3"><input v-model="rule.key" placeholder="Identificador" class="rounded border p-2" /><input v-model="rule.label" placeholder="Nome do requisito" class="rounded border p-2" /><select v-model="rule.source" class="rounded border p-2"><option v-for="(name,key) in documentSources" :key="key" :value="key">{{name}}</option></select><label><input v-model="rule.required" type="checkbox" /> Obrigatório</label><label><input v-model="rule.blocking" type="checkbox" /> Bloqueia avanço</label><button type="button" class="rounded border p-2" @click="form.document_rules.splice(index,1)">Remover</button></div><button type="button" class="rounded border px-3 py-2" @click="form.document_rules.push({key:'document_'+(form.document_rules.length+1),label:'',source:'manual',required:true,blocking:true})">Adicionar requisito</button></fieldset>
              <div class="rounded-2xl border border-n-weak p-5">
                <h4 class="font-bold text-n-slate-12">Integrações internas JRC</h4>
                <p class="mt-1 text-xs text-n-slate-10">
                  Selecione os fluxos internos que devem ser acionados após a venda.
                </p>
                <div class="mt-4 grid gap-3 md:grid-cols-3">
                  <label
                    class="flex items-center justify-between rounded-xl border border-n-weak p-4"
                  >
                    <span class="font-medium text-n-slate-11">Financeiro</span>
                    <input v-model="form.integration_financial" type="checkbox" class="size-5 accent-n-teal-9" />
                  </label>
                  <label
                    class="flex items-center justify-between rounded-xl border border-n-weak p-4"
                  >
                    <span class="font-medium text-n-slate-11">Contratos</span>
                    <input v-model="form.integration_contracts" type="checkbox" class="size-5 accent-n-iris-9" />
                  </label>
                  <label
                    class="flex items-center justify-between rounded-xl border border-n-weak p-4"
                  >
                    <span class="font-medium text-n-slate-11">Implantação</span>
                    <input v-model="form.integration_implementation" type="checkbox" class="size-5 accent-n-blue-9" />
                  </label>
                </div>
              </div>

              <div class="grid gap-4 md:grid-cols-2">
                <label class="text-sm font-medium text-n-slate-11">
                  Modelo de proposta
                  <input
                    v-model.trim="form.proposal_template_name"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="modelo-proposta-stir-shaken.pdf"
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Contrato padrão
                  <input
                    v-model.trim="form.contract_template_name"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="contrato-stir-shaken.docx"
                  />
                </label>
              </div>

              <div class="grid gap-4 md:grid-cols-2">
                <label class="text-sm font-medium text-n-slate-11">
                  Requisitos técnicos
                  <textarea
                    v-model.trim="form.technical_requirements"
                    rows="4"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Pré-requisitos, acessos, dados e dependências técnicas."
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  Observações comerciais internas
                  <textarea
                    v-model.trim="form.sales_notes"
                    rows="4"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Orientações para venda, aprovação e implantação."
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  O que está incluído
                  <textarea
                    v-model.trim="form.scope_included"
                    rows="4"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Escopo, franquias e entregáveis incluídos."
                  />
                </label>
                <label class="text-sm font-medium text-n-slate-11">
                  O que não está incluído
                  <textarea
                    v-model.trim="form.scope_excluded"
                    rows="4"
                    class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    placeholder="Exclusões, excedentes e serviços adicionais."
                  />
                </label>
              </div>

              <div class="rounded-2xl border border-n-blue-6 bg-n-blue-2 p-5">
                <div class="flex gap-3">
                  <i class="i-lucide-info size-5 shrink-0 text-n-blue-11" />
                  <div>
                    <h4 class="font-semibold text-n-slate-12">Documentos comerciais</h4>
                    <p class="mt-1 text-sm text-n-slate-10">
                      Os nomes cadastrados ficam vinculados ao produto e servem como referência na elaboração da proposta. O envio físico do arquivo depende do módulo de anexos do ambiente.
                    </p>
                  </div>
                </div>
              </div>
            </section>
          </div>

          <aside class="overflow-y-auto border-l border-n-weak bg-n-alpha-2 p-5">
            <div class="rounded-2xl border border-n-teal-6 bg-n-solid-2 p-5 shadow-sm">
              <p class="text-xs font-semibold uppercase tracking-wider text-n-teal-11">
                Resumo do produto
              </p>
              <h4 class="mt-3 text-xl font-bold text-n-slate-12">
                {{ form.name || 'Novo produto' }}
              </h4>
              <div class="mt-2 flex flex-wrap gap-2">
                <span class="rounded-full bg-n-teal-3 px-2.5 py-1 text-xs font-semibold text-n-teal-11">
                  {{ productTypeLabel(form.product_type) }}
                </span>
                <span class="rounded-full bg-n-iris-3 px-2.5 py-1 text-xs font-semibold text-n-iris-11">
                  {{ billingLabel(form.billing_model) }}
                </span>
              </div>

              <dl class="mt-5 space-y-3 text-sm">
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-n-slate-10">Preço</dt>
                  <dd class="font-bold text-n-slate-12">{{ formatBRL(toCents(form.unit_price)) }}</dd>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-n-slate-10">Implantação</dt>
                  <dd class="font-medium text-n-slate-12">{{ formatBRL(toCents(form.setup_fee)) }}</dd>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-n-slate-10">Equivalente mensal</dt>
                  <dd class="font-medium text-n-teal-11">{{ formatBRL(monthlyPreview) }}</dd>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-n-slate-10">Margem estimada</dt>
                  <dd
                    class="font-bold"
                    :class="marginPreview >= 30 ? 'text-n-teal-11' : 'text-n-amber-11'"
                  >
                    {{ marginPreview }}%
                  </dd>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <dt class="text-n-slate-10">Vigência</dt>
                  <dd class="font-medium text-n-slate-12">{{ form.contract_term_months }} meses</dd>
                </div>
                <div v-if="form.included_quantity" class="border-t border-n-weak pt-3">
                  <dt class="text-n-slate-10">Franquia incluída</dt>
                  <dd class="mt-1 font-medium text-n-slate-12">
                    {{ form.included_quantity }} {{ form.included_unit || 'unidades' }}
                  </dd>
                  <dd v-if="form.overage_unit_price" class="mt-1 text-xs text-n-slate-10">
                    Excedente: {{ formatBRL(toCents(form.overage_unit_price)) }} por unidade
                  </dd>
                </div>
              </dl>
            </div>

            <div class="mt-4 rounded-2xl border border-n-weak bg-n-solid-2 p-5">
              <p class="text-xs font-semibold uppercase tracking-wider text-n-slate-10">
                Como aparecerá na proposta
              </p>
              <h5 class="mt-3 font-bold text-n-slate-12">{{ form.name || 'Produto JRC' }}</h5>
              <p class="mt-2 text-sm text-n-slate-10">
                {{ form.description || 'A descrição comercial será apresentada ao cliente neste espaço.' }}
              </p>
              <div class="mt-4 rounded-xl bg-n-alpha-2 p-3 text-sm">
                <div class="flex justify-between gap-3">
                  <span class="text-n-slate-10">Valor</span>
                  <strong>{{ formatBRL(toCents(form.unit_price)) }}</strong>
                </div>
                <div class="mt-2 flex justify-between gap-3">
                  <span class="text-n-slate-10">Setup</span>
                  <strong>{{ formatBRL(toCents(form.setup_fee)) }}</strong>
                </div>
                <div class="mt-2 flex justify-between gap-3">
                  <span class="text-n-slate-10">Ativação</span>
                  <strong>{{ form.activation_days }} dias</strong>
                </div>
              </div>
            </div>
          </aside>
        </div>

        <footer
          class="flex shrink-0 flex-wrap items-center justify-between gap-3 border-t border-n-weak bg-n-solid-2 px-5 py-4 sm:px-6"
        >
          <p class="text-xs text-n-slate-10">
            Os valores da proposta serão calculados a partir destes dados comerciais.
          </p>
          <div class="flex gap-3">
            <button v-if="!editingId" type="button" :disabled="saving" class="mr-auto rounded-lg border border-n-weak px-3 py-2" @click="productDraft.discard">{{ t('CRM.CREATION.DISCARD') }}</button>
            <button
              type="button"
              class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 text-sm font-semibold"
              @click="closeForm"
            >
              Cancelar
            </button>
            <button
              type="submit"
              :disabled="saving"
              class="rounded-xl bg-n-teal-9 px-5 py-2.5 text-sm font-semibold text-white shadow-md disabled:opacity-50"
            >
              <i
                class="mr-1 size-4"
                :class="saving ? 'i-lucide-loader-circle animate-spin' : 'i-lucide-check'"
              />
              {{ editingId ? 'Salvar alterações' : 'Criar produto' }}
            </button>
          </div>
        </footer>
      </form>
    </div>
  </div>
</template>
