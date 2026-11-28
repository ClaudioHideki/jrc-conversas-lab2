const labels = ['positivo', 'neutro', 'negativo'];
const count = value => Number.isSafeInteger(value) && value >= 0;
const score = value =>
  value === null || (Number.isFinite(value) && value >= 0 && value <= 100);

// A server response is evidence only when its denominator and measured values
// agree. Unknown sentiment and absent analysis remain distinct.
export const validRecordingQualitySummary = (data, items, total) => {
  const summary = data.quality_summary;
  if (
    !summary ||
    summary.denominator !== 'latest_original_analyses' ||
    !Number.isFinite(Date.parse(data.observed_at)) ||
    !count(total) ||
    ![
      summary.universe,
      summary.analyzed,
      summary.without_analysis,
      summary.unclassified,
      summary.quality_measured,
    ].every(count) ||
    summary.universe !== summary.analyzed + summary.without_analysis ||
    total > summary.universe ||
    summary.quality_measured > summary.analyzed ||
    !score(summary.quality_average) ||
    (summary.quality_measured === 0) !== (summary.quality_average === null)
  )
    return false;
  if (
    !labels.every(label => count(summary.counts?.[label])) ||
    labels.reduce((sum, label) => sum + summary.counts[label], 0) +
      summary.unclassified !==
      summary.analyzed
  )
    return false;
  return (
    labels.every(label => {
      const percent = summary.percentages?.[label];
      if (summary.analyzed === 0) return percent === null;
      return (
        Number.isFinite(percent) &&
        Math.abs(percent - (100 * summary.counts[label]) / summary.analyzed) <
          0.011
      );
    }) &&
    items.every(row => {
      const quality = row.quality;
      if (quality?.available === false)
        return quality.sentiment === null && quality.quality_score === null;
      return (
        quality?.available === true &&
        [...labels, 'unclassified'].includes(quality.sentiment) &&
        score(quality.quality_score) &&
        Number.isFinite(Date.parse(quality.observed_at))
      );
    })
  );
};
