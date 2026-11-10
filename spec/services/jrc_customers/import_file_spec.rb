require 'rails_helper'

RSpec.describe JrcCustomers::ImportFile do
  it 'inspects UTF-8/BOM without changing the original digest or any customer rows' do
    csv = "\uFEFFname,tax_id\nTESTE — Café,11.222.333/0001-81\n"
    expect do
      file = described_class.new(content: csv, kind: 'companies')
      expect(file.metadata).to include(row_count: 1, delimiter: ',', sha256: Digest::SHA256.hexdigest(csv))
      expect(file.metadata[:suggested_mapping]).to eq('name' => 'company.name', 'tax_id' => 'company.tax_id')
      expect(file.mapped_rows(file.metadata[:suggested_mapping]).first[:company]['name']).to eq('TESTE — Café')
    end.not_to change(JrcCustomers::Company, :count)
    expect(csv).to start_with("\uFEFF")
  end

  it 'recognizes semicolons while preserving quoted commas and line breaks exactly' do
    csv = "Empresa;Contato;Observação\n\"TESTE; Matriz\";\"TESTE, Pessoa\";\"Primeira\nSegunda\"\n"
    file = described_class.new(content: csv, kind: 'both')
    expect(file.delimiter).to eq(';')
    expect(file.mapped_rows('Empresa' => 'company.name', 'Contato' => 'contact.name', 'Observação' => nil))
      .to eq([{ line: 2, company: { 'name' => 'TESTE; Matriz' }, contact: { 'name' => 'TESTE, Pessoa' } }])
    expect(file.metadata.to_json).not_to include('TESTE, Pessoa', 'Primeira')
  end

  it 'allows an explicit tab separator and keeps imported values out of metadata inspection' do
    file = described_class.new(content: "name\temail\nTESTE\tpessoa@example.test\n", kind: 'contacts', delimiter: "\t")
    expect(file.mapped_rows(file.metadata[:suggested_mapping]).first[:contact])
      .to eq('name' => 'TESTE', 'email' => 'pessoa@example.test')
    expect(file.metadata.to_json).not_to include('pessoa@example.test')
  end

  it 'requires an explicit choice for every column and refuses ownership or unrelated model destinations' do
    file = described_class.new(content: "Nome,Conta\nTESTE,999\n", kind: 'contacts')
    expect { file.mapped_rows('Nome' => 'contact.name') }.to raise_error(described_class::InvalidFile)
    expect { file.mapped_rows('Nome' => 'contact.name', 'Conta' => 'contact.account_id') }.to raise_error(described_class::InvalidFile)
    expect { file.mapped_rows('Nome' => 'contact.name', 'Conta' => 'User.id') }.to raise_error(described_class::InvalidFile)
    expect(file.mapped_rows('Nome' => 'contact.name', 'Conta' => nil).first[:contact]).to eq('name' => 'TESTE')
  end

  it 'rejects duplicate destinations and ambiguous source headers after whitespace normalization' do
    file = described_class.new(content: "Nome,Alias\nTESTE,A\n", kind: 'contacts')
    expect { file.mapped_rows('Nome' => 'contact.name', 'Alias' => 'contact.name') }.to raise_error(described_class::InvalidFile)
    expect { described_class.new(content: "name, name \nTESTE,A\n", kind: 'contacts') }.to raise_error(described_class::InvalidFile)
  end

  it 'does not guess the entity for an ambiguous unprefixed column in a combined import' do
    file = described_class.new(content: "name,Empresa\nTESTE,Outra\n", kind: 'both')
    expect(file.metadata[:suggested_mapping]).to eq('name' => nil, 'Empresa' => nil)
    expect { file.mapped_rows('name' => 'contact.name', 'Empresa' => nil) }.to raise_error(described_class::InvalidFile)
    expect(file.mapped_rows('name' => 'contact.name', 'Empresa' => 'company.name').first)
      .to include(company: { 'name' => 'Outra' }, contact: { 'name' => 'TESTE' })
  end

  it 'rejects bad encoding, null bytes, unsupported types and malformed quoted rows before any write' do
    expect { described_class.new(content: "name\n\xFF\n", kind: 'companies') }.to raise_error(described_class::InvalidFile)
    expect { described_class.new(content: "name\nA\x00B\n", kind: 'companies') }.to raise_error(described_class::InvalidFile)
    expect { described_class.new(content: "name\nTESTE\n", kind: 'users') }.to raise_error(described_class::InvalidFile)
    expect { described_class.new(content: "name\n\"Incomplete\n", kind: 'contacts') }.to raise_error(described_class::InvalidFile)
    expect { described_class.new(content: "name\nTESTE\n", kind: 'contacts', delimiter: '|') }.to raise_error(described_class::InvalidFile)
    expect { described_class.new(content: "\n", kind: 'contacts', delimiter: ',') }.to raise_error(described_class::InvalidFile)
  end

  it 'bounds bytes, rows and source columns without silently truncating a dataset' do
    expect { described_class.new(content: 'x' * (JrcCustomers::CompanyImport::MAX_BYTES + 1), kind: 'companies') }
      .to raise_error(described_class::InvalidFile)
    expect { described_class.new(content: "name\n#{"TESTE\n" * 501}", kind: 'companies') }.to raise_error(described_class::InvalidFile)
    columns = Array.new(101) { |i| "column_#{i}" }.join(',')
    expect { described_class.new(content: "#{columns}\n#{(['X'] * 101).join(',')}\n", kind: 'companies') }
      .to raise_error(described_class::InvalidFile)
    expect { described_class.new(content: "name,email\nTESTE,pessoa@example.test,EXTRA\n", kind: 'contacts', delimiter: ',') }
      .to raise_error(described_class::InvalidFile)
  end
end
