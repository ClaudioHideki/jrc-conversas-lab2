export const providerBases = {
  openai: 'https://api.openai.com/v1',
  anthropic: 'https://api.anthropic.com/v1',
  google_gemini: 'https://generativelanguage.googleapis.com/v1beta',
};

// Recommendations always refer to IDs actually returned by this connection.
export function recommendedModels(type, models) {
  const ids = models.map(model => model.id);
  const find = pattern => ids.find(id => pattern.test(id)) || '';
  const family = name => models.find(model => model.family === name)?.id || '';
  if (type === 'anthropic')
    return {
      fast_model: family('haiku') || find(/haiku/),
      default_model: family('sonnet') || find(/sonnet/),
      advanced_model: family('opus') || find(/opus/),
    };
  if (type === 'google_gemini')
    return {
      fast_model: find(/flash-lite/),
      default_model: find(/flash(?!-lite)/),
      advanced_model: find(/pro/),
    };
  const ordered = [...ids].sort((a, b) =>
    b.localeCompare(a, undefined, { numeric: true })
  );
  const standard =
    ordered.find(
      id =>
        /^gpt-\d/.test(id) &&
        !/mini|nano|preview|chat|\d{4}-\d{2}-\d{2}/.test(id)
    ) || '';
  return {
    fast_model: ordered.find(id => /mini|nano/.test(id)) || '',
    default_model: standard,
    advanced_model: standard,
  };
}
