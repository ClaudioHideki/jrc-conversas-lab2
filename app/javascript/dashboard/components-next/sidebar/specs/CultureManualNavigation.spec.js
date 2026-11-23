import { describe, expect, it } from 'vitest';
import { cultureManualLink } from '../cultureManual';
import { universityLink } from '../university';

describe('JRC learning links', () => {
  it('uses a dedicated portal route and preserves the existing University entry', () => {
    expect(cultureManualLink.href).toBe('/portal/manual-de-cultura');
    expect(cultureManualLink.name).not.toBe(universityLink.name);
    expect(universityLink.label).toBe('UniversidadeJRC');
    expect(universityLink.href).toBe(
      'https://universidadejrc.com.br/portal/layout/910/treynando/login_inicial.asp?V29ya3NwYWNlSUQ9MTQwMCZrdF9kaWRheGlzPXRvcA'
    );
  });
});
