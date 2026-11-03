import { parseMigrationFile } from '../migrationFile';

it('preserves source identifiers and quoted multiline CSV fields', () => {
  expect(
    parseMigrationFile(
      'legacy_id,name\r\n0001,"One, two\nThree ""four"""\r\n',
      'fixture.csv'
    )
  ).toEqual([{ legacy_id: '0001', name: 'One, two\nThree "four"' }]);
});

it('rejects ambiguous headers, truncated rows and unmatched quotes', () => {
  ['id,id\n1,2', 'id,name\n1', 'id,name\n1,"unfinished'].forEach(csv => {
    expect(() => parseMigrationFile(csv, 'fixture.csv')).toThrow();
  });
});
