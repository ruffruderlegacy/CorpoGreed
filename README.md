# CorpoGreed

**Your own Auction House toolkit for WoW Forever** — price history & charts, a sell/smelt/craft advisor, best-crafts ranking, and full gold bookkeeping. Think Auctionator + TradeSkillMaster, but lightweight and built for the Forever client.

> ⚠️ Work in progress — looking for testers! Found a bug or have an idea? Open an [Issue](../../issues).

![Interface](https://img.shields.io/badge/Interface-16001-blue) ![Status](https://img.shields.io/badge/status-beta-orange)

---

## What it does

- **📈 Trading view** — candlestick / line price charts with moving average, Bollinger bands, Fibonacci levels, and listed-quantity volume. Plus an average-price-by-time-of-day panel so you know *when* to buy and sell.
- **🔍 Full AH scans** — one-click market snapshot (server-limited to ~every 15 min), with live price capture from your normal AH searches in between.
- **🧮 Advisor** — tells you whether to sell, smelt, craft, or hold each item, following craft chains to the most profitable outcome.
- **⚒️ Worth Making** — ranks the recipes you know by profit, in a panel docked next to any profession window.
- **📒 Ledger** — full bookkeeping: sales, deposits, vendor runs, loot, and gold-per-character over time.
- **⛏️ Session tracker** — live gold/hour while you farm mining / herbs / skinning / fishing.

## Install

1. Download the latest **[Release](../../releases)** zip (or the green **Code → Download ZIP**).
2. Unzip it. You'll get a folder named `CorpoGreed`.
3. Drop that folder into:
   `World of Warcraft\_forever_\Interface\AddOns\`
   (the folder must be `...\AddOns\CorpoGreed\CorpoGreed.toc`)
4. Restart WoW, or type `/reload` if you're already logged in.
5. Open the Auction House and click the **CorpoGreed** button above the AH window. Run a **Full Scan** to get started.

## Compatibility

Built for the **Forever** client (Interface **16001**). It's a modern-core engine running vanilla content, so CorpoGreed uses modern APIs where available and falls back gracefully.

## Usage

- `/cg` — open / close the window
- The gold **Donate** tab holds project info + links (it's free; if it made you gold, send a little to charity 💛).
- Right-click items in the lists for a menu (track price, ignore, search AH).
- Drag any item onto the chart to start tracking its price.

## Reporting bugs / feedback

This is being actively polished — **tester reports are gold.** Please open an [Issue](../../issues) with:
- What you were doing
- What happened vs. what you expected
- Any red Lua error text (enable with `/console scriptErrors 1`)

## License

MIT — see [LICENSE](LICENSE). Free to use, share, and modify.
