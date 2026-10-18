# Trade report

The economy simulation made visible: press N anywhere in a game (or use the pause menu, or the
freight office's READ THE TRADE REPORT). scripts/trade_report.gd (TradeReport, a CanvasLayer attached
to every scene but the title by GameSettings.apply_scene) draws it; scripts/trade_data.gd (TradeData)
works out what to show; scripts/sim/sim_stats.gd (SimStats) keeps the history it reads.

The game pauses while it's open. 1-5 or Tab switch pages; N or Esc closes. Keys go nowhere else while
it's open; N is ignored while typing in a text field or with the pause menu up.

## History (SimStats, in EconomySim.stats, saved with the sim)

- `days`: the last 30 days, oldest first. Each: freight paid, goods value delivered, tonnes moved and
  deliveries; `flows` by lane ("A>B": tonnes, money, tonnes the player carried, tonnes by goods);
  goods tonnes; freight earned by company; the player's day (tonnes and money, in-system runs,
  salvage, shortages relieved); and at the turn of the day each system's price index (mean of quote
  / reference over what its buyers use; 1.0 is the going rate) and how many goods are short or worse.
- `player`: lifetime totals: interstellar tonnes and pay, deliveries, in-system tonnes, pay and runs,
  salvage and finds sold, shortages relieved, tonnes by destination system and by buyer facility,
  and the day records began.
- Hooks: `EconomySim._deliver` (every leg, and goods reaching the buyer, with its shortage state
  beforehand), `EconomySim.step_hour` at midnight (prices and shortages), `Session._deliver_local`
  (in-system runs), `Salvage.sell` and `Session.sell_finds` (salvage and finds; cargo sold to a
  facility counts as supplying it). Recording moves no goods or money.
- The warm start includes the warm-up's days, so a new game opens with about two weeks of history.
  An older save without history opens a report with none, and fills it from then on.

## Pages

- **Overview**: freight paid, goods delivered and tonnes moved over the last 7 days against the 7
  before, each with a 30-day line; ships at work and under way loaded, jobs on the boards and being
  hauled, carriers' cash. Running short: buyers with goods out, critical or short, worst first, with
  the goods, days of cover and the dearest price against the going rate. Prices: every system's
  index as a bar either side of the going rate, with an arrow for the week's move. Your system is green.
- **Flows**: known space (StarMap.space_chart positions) with the week's freight on each lane, width
  by tonnes, cargo dots running A to B (lanes offset so both directions show), your lanes green;
  systems ringed amber (sends out more than it takes in) or blue, sized by tonnage; every ship between
  systems as a diamond (amber loaded, grey empty, green you). The busiest lanes listed beside it.
- **Companies**: every carrier company with ships, ships at work, freight earned over 30 days (bar and
  share) and cash, ranked by earnings; in-system runs count towards yours.
- **Your mark**: tonnes delivered (between systems and in-system), money earned hauling, share of all
  freight paid over 30 days, rank among the companies, deliveries that reached a shelf running short,
  salvage and finds sold, takings day by day, where you've delivered and who you've supplied.
- **Growth** (since 0.17.0): frontier growth (docs/runtime/development.md). The system you're in, site by
  site: a bar from abandoned to core with the canon size ticked, the stage, an arrow for which way it's
  going over the last week, and why ("short: traffic brings 78% of the 5 t a day it needs", "you bring
  67% of it"). Then what grew, shrank, emptied or was resettled anywhere in the last 30 days, and every
  system's stage. `TradeData.growth(sim, system)`.

A one-time concourse hint ("trade", Hints) points at N after the first delivery.
