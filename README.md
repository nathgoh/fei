# Fei

A personal finance tracker for Android and the web, built in Flutter. It's the
successor to the Streamlit [finance-tracker](https://github.com/nathgoh/finance-tracker),
with a Monarch-inspired layout and a local relational database (SQLite via
[Drift](https://drift.simonbinder.eu/)), designed to sync with a Postgres
server later.

## Features

| Tab | What it does |
| --- | --- |
| **Dashboard** | Month at a glance: income / expenses / saved, flexible spending vs. last month, top categories, upcoming recurring, recent transactions |
| **Transactions** | Search and filter by month, type, category and account; grouped by day; swipe to delete (with undo) |
| **Cash Flow** | Year view: totals, savings rate, averages (with and without fixed costs), income → expenses → categories Sankey, monthly income vs. expense chart, per-category monthly averages, monthly breakdown. Tap a month or category to drill into its transactions. CSV export. |
| **Recurring** | Recurring expenses/income with next dates, 30-day outlook and monthly cost; edit (future-only or including past), end today, or delete |
| **Assistant** | Chat about your finances using a model on your Ollama server; the model calls tools that query the local database |

**Settings:** categories (groups, emoji, colours, the *fixed cost* flag),
accounts (optional "paid with" labels, no balances), AI assistant, import and
export.

### Differences from the web app

* **One `transactions` table**: income and expenses are both transactions,
  and categories have a kind (`income` / `expense`) and belong to groups.
  The web app's income *source* becomes an income category.
* **Fixed costs are a category flag**, not hard-coded to Rent. Rent is
  flagged by default; flag others (e.g. Utility) to leave them out of
  "flexible" spending and the "avg excl. fixed" figure.
* **Recurring series are rules**: occurrences are generated as their dates
  arrive (on launch and on resume), not all up front. The end date is optional.

## Getting started

The Flutter SDK is managed per project with [fvm](https://fvm.app). This
project pins **Flutter 3.47.9** in `.fvmrc`.

```sh
fvm install            # installs the pinned SDK
fvm flutter pub get
fvm dart run build_runner build   # generates lib/data/database.g.dart

fvm flutter run -d chrome         # web
fvm flutter run -d <android-id>   # Android device or emulator
```

To preview with about 10 months of sample data, run the demo entrypoint
(it seeds only when the database is empty):

```sh
fvm flutter run -t tool/demo_main.dart
```

### Bringing over your web app data

Settings → Import & export → **Choose JSON files**, then select
`categories.json`, `expenses.json` and `incomes.json` from the web app's
`data/` folder. Importing is idempotent, so running it again skips anything
already imported. CSV import also accepts the web app's CSV exports and typical
bank exports.

### AI assistant

Settings → AI assistant: enter your Ollama URL (e.g. `http://192.168.68.52:11434`)
and use **Test & fetch models**. The app talks to Ollama's OpenAI-compatible
API. On the web build, Ollama must allow the page's origin: start it with
`OLLAMA_ORIGINS="*"` (or the specific origin).

## Project layout

```
lib/
  core/        dates (recurrence maths) and money (integer cents) helpers
  data/        Drift schema (tables.dart), database + queries, seed, import/export
  domain/      pure analytics: period summaries, Sankey data, recurring outlook
  ai/          agent loop (OpenAI-compatible) and finance tools
  state/       Riverpod providers
  ui/          screens, charts, theme
tool/demo_main.dart   sample-data entrypoint
web/sqlite3.wasm, web/drift_worker.js   Drift's web runtime
```

* Money is stored as **integer cents**; dates as `YYYY-MM-DD` text.
* On web, Drift uses SQLite compiled to WASM, stored in OPFS/IndexedDB.
  `web/sqlite3.wasm` and `web/drift_worker.js` must match the resolved
  `sqlite3` and `drift` package versions. After upgrading those packages,
  download the matching files from the
  [sqlite3.dart](https://github.com/simolus3/sqlite3.dart/releases) and
  [drift](https://github.com/simolus3/drift/releases) releases.

## Sync readiness

Every table carries a client-generated UUID v7 `id`, plus `created_at`,
`updated_at` (bumped on every write) and `deleted_at` (deletes are soft). That
lets a future sync against Postgres work with a thin API:

* **push**: rows with `updated_at` later than the last successful push
* **pull**: server rows changed since the last pull, last-writer-wins on
  `updated_at`

Timestamps are stored as ISO-8601 text, which maps directly to `timestamptz`.

## Tests

```sh
fvm flutter test
```

The tests cover recurrence maths, database behaviour (soft deletes, recurring
generation, category reassignment), analytics and the Sankey builder, JSON/CSV
import/export round-trips, the AI tools and agent loop (with a mocked HTTP
client), and a widget smoke test that navigates every tab.
