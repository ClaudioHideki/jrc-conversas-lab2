const DAY = 86_400_000;
const time = value => {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
};
const average = values =>
  values.length
    ? values.reduce((sum, value) => sum + value, 0) / values.length
    : null;

function stageVisits(deal, asOf) {
  const visits = new Map();
  const begin = time(deal.created_at);
  let stage = null;
  let arrival = null;
  let rank = 0;
  const observe = (id, at) => {
    if (id == null) return;
    const previous = visits.get(id);
    if (previous) previous.lastRank = rank;
    else visits.set(id, { firstAt: at, intervals: [], rank, lastRank: rank });
    rank += 1;
  };

  deal.moves.forEach(move => {
    const at = time(move.at);
    if (at === null || (begin !== null && at < begin) || at > asOf) return;
    observe(move.from, null);
    if (stage === move.from && arrival !== null && at >= arrival) {
      visits.get(stage).intervals.push({ arrival, days: (at - arrival) / DAY });
    }
    stage = move.to;
    arrival = at;
    observe(stage, arrival);
  });

  if (stage !== deal.stage_id) {
    arrival = deal.status === 'won' ? time(deal.won_at) : null;
    if (begin === time(deal.updated_at) && !visits.size) arrival = begin;
  }
  observe(deal.stage_id, arrival);
  return { visits, arrival };
}

export function funnelMetrics(report, mode) {
  const asOf = time(report.as_of) ?? Date.now();
  const records = report.deals.map(item => ({
    ...item,
    ...stageVisits(item, asOf),
  }));
  const portfolio = mode === 'portfolio';
  const row = (deal, enteredAt = time(deal.created_at)) => ({
    deal,
    enteredAt,
  });
  const entry = {
    key: 'entry',
    rows: records.map(deal => row(deal)),
    averageDays: null,
  };
  const won = records.filter(deal => deal.status === 'won');
  const cycles = won.flatMap(deal => {
    const start = time(deal.created_at);
    const end = time(deal.won_at);
    return start !== null && end !== null && end >= start
      ? [(end - start) / DAY]
      : [];
  });
  const stages = report.stages
    .map(stage => {
      const reached = records.filter(deal =>
        portfolio ? deal.stage_id === stage.id : deal.visits.has(stage.id)
      );
      const rows = reached.map(deal =>
        row(deal, portfolio ? deal.arrival : deal.visits.get(stage.id).firstAt)
      );
      const measured = reached.flatMap(deal => {
        if (portfolio) {
          return deal.arrival !== null && asOf >= deal.arrival
            ? [
                {
                  ...row(deal, deal.arrival),
                  days: (asOf - deal.arrival) / DAY,
                },
              ]
            : [];
        }
        const { intervals } = deal.visits.get(stage.id);
        return intervals.length
          ? [
              {
                ...row(deal, intervals[0].arrival),
                days: intervals.reduce(
                  (sum, interval) => sum + interval.days,
                  0
                ),
              },
            ]
          : [];
      });
      return {
        ...stage,
        key: String(stage.id),
        rows,
        measured,
        averageDays: average(measured.map(item => item.days)),
      };
    })
    .filter(stage => stage.active || stage.rows.length);

  const bars = portfolio
    ? stages
    : [entry, ...stages.filter(stage => !stage.is_lost)];
  let awaitingWin = null;
  const advancement = {};
  if (!portfolio) {
    bars.forEach((item, index) => {
      const next = bars[index + 1];
      if (!item.rows.length || !next) return;
      const pending = item.rows.filter(({ deal }) => {
        const rank = item.id ? deal.visits.get(item.id)?.rank : -1;
        const nextRank = deal.visits.get(next.id)?.lastRank;
        return nextRank === undefined || nextRank <= rank;
      });
      advancement[item.key] =
        (100 * (item.rows.length - pending.length)) / item.rows.length;
      if (item.id && next.is_won && pending.length)
        awaitingWin = { from: item.name, to: next.name, rows: pending };
    });
  }

  const open = records.filter(deal => deal.status === 'open');
  return {
    entry,
    won: won.map(deal => row(deal, time(deal.won_at))),
    averageCycle: average(cycles),
    conversion: records.length ? (100 * won.length) / records.length : null,
    stages,
    bars,
    advancement,
    withoutActivity: open
      .filter(deal => !deal.next_activity)
      .map(deal => row(deal, deal.arrival)),
    stalled: open
      .filter(
        deal =>
          time(deal.updated_at) !== null &&
          asOf - time(deal.updated_at) > 15 * DAY
      )
      .map(deal => row(deal, deal.arrival)),
    awaitingWin,
  };
}

export function funnelTotals(rows) {
  const totals = new Map();
  rows.forEach(({ deal }) => {
    const currency = /^[A-Z]{3}$/.test(deal.currency) ? deal.currency : 'BRL';
    totals.set(
      currency,
      (totals.get(currency) || 0) + Number(deal.value_cents || 0)
    );
  });
  return [...totals];
}

export const formatFunnelMoney = (cents, currency, locale) =>
  new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: /^[A-Z]{3}$/.test(currency) ? currency : 'BRL',
  }).format(cents / 100);
