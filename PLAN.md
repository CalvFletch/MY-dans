# MY-DANS Project Plan

## Architecture (Current)

```
┌──────────────────────┐       ┌────────────────────────────────────┐
│   Flutter App         │       │   FastAPI server (LXC 108)         │
│   (Android)           │       │                                    │
│                       │  HTTP │   :8000 → Public API (CF Tunnel)   │
│  ┌─────────────────┐  │◀──────│   :8001 → Admin Panel (Tailscale) │
│  │ Local SQLite     │  │──────▶│   :8002 → Admin API (LAN-only)    │
│  │ (offline-first)  │  │       │                                    │
│  └─────────────────┘  │       │  ┌──────────────────────────────┐ │
│                       │       │  │ DuckDB (single file)          │ │
│  ┌─────────────────┐  │       │  │ - products (25,850)           │ │
│  │ Chrome Extension │──┼──────▶│  │ - price_history              │ │
│  │ (DS capturer)    │  │       │  │ - product_popularity         │ │
│  └─────────────────┘  │       │  │ - tokens, traffic, jobs       │ │
└──────────────────────┘       │  └──────────────────────────────┘ │
                               │                                    │
                               │  ┌──────────────────────────────┐ │
                               │  │ DM API proxy (key on server)  │ │
                               │  │ - /api/product/{code}         │ │
                               │  │ - /api/search?q=              │ │
                               │  └──────────────────────────────┘ │
                               └────────────────────────────────────┘
```

**Key points:**
- DuckDB (columnar, single-file) replaced SQLite for server DB
- Chrome extension captures Data Studio batchedDataV2 → POSTs to :8002
- Enrichment fills DM API data for Data Studio products
- DM API key NEVER on client — all proxied through server

---

## Data Pipeline (Implemented)

### 1. Catalog: 25,850 products

| Source | Count | Fields |
|--------|-------|--------|
| DM API scrape | 24,703 | 22 fields (brand, varietal, ratings, images, etc.) |
| Data Studio | ~1,147 | 3 fields (code, name, category) → enriched via DM API |

### 2. Extension Capture Flow (working)

```
Server says "capture needed" (:8000/api/capture/needed)
  → Extension popup shows status + badge (!)
  → "Capture Now" opens Data Studio with date range
  → MAIN world injection sets XHR interceptor + auto-filters Brand→DM, Date
  → batchedDataV2 caught → postMessage relay → content script → background → POST :8002
  → Server ingests, upserts articles, triggers auto-enrich
  → capture/done marks complete, badge turns green
```

### 3. Enrichment Pipeline

- Products with `enriched=0` → DM API proxy → save full fields
- 404 from DM API → marked `discontinued=1` (kept in DB, shown as "no longer stocked")
- Auto-enrich worker runs in API process (asyncio background task)

---

## Popularity Scoring (Planned)

### Data Source
Sales data from batchedDataV2 fact table columns:
- `article_id`, `qty` (units sold), `sale_date`
- Monthly sales dumps from Data Studio via extension

### Scoring Approach: Percentile Rank (1–100)

Each product gets a score based on its sales percentile:
- Top 1% sellers → score 100
- Median sellers → score 50
- Bottom sellers → score 1
- No sales data → score 1 (default lowest)

**Why percentile over raw rank:**
- 100 buckets = meaningful grouping without ties dominating
- New products start at 1, climb naturally
- Stable across catalog size changes
- Efficient for ORDER BY (integer sort)

### API Exposure
- `/api/popularity/{code}` → advanced users only
- `/api/search` returns results **ordered by popularity** (all users), scores hidden from basic
- Basic users see sort order, not values — offline sorts by relevance instead

---

## Price History (Planned)

### Data Source
- DM API product detail (`Prices` field) polled every 15 min via `price_monitor.py`
- Batch saved to `price_history` table: `{code, date, price}`

### Most-Common-Price Per Day
For a given (product, day), take the **mode** (most frequent price):
- Handles intra-day price changes
- Ignores outlier one-off prices
- Single agreed-upon "price for that day"

### API Exposure
- `/api/price-history/{code}` → **advanced users only**
- Basic users build their own price history from product views over time (local DB)

---

## Client Search Workflow (Planned)

### Step-by-step

```
1. User types "shiraz >$20" in Flutter app
2. App searches LOCAL SQLite → finds 100 results
3. App sends to server: {query: "shiraz >$20", resultCount: 100, staleIds: [42 codes older than 1 day]}
4. Server runs same search on DuckDB → gets 104 results
5. Server returns:
   {
     order: [104 codes sorted by popularity],
     missing: [4 new codes not in client],
     refreshed: [{code: ..., data: ...} for 42 stale products]
   }
6. Client:
   a. Fetches missing 4 products from /api/product/{code}
   b. Updates 42 stale products with refreshed data
   c. Re-sorts its 104 results by server `order`
   d. Saves updates to local DB
```

### Web API Scraping (text searches)
- When user searches text like "st remy martin":
  - Server also calls DM's web search API (`/api/search?q=st remy martin`)
  - New products found on DM but not in our DB → added to catalog + sent to client
  - This keeps our DB growing organically

### Nightly Sync
- All updates from day's searches propagated to all clients
- `/api/db/diff` returns changes since last client sync version
- WiFi-only, background WorkManager in Flutter app

---

## API Access Tiers

| Feature | Basic (auto) | Advanced (approved) |
|---------|-------------|---------------------|
| Get API key | ✅ `/auth/register` | ✅ |
| Product search | ✅ | ✅ |
| Product detail | ✅ | ✅ |
| Popularity ordering | ✅ (order only, no scores) | ✅ |
| Popularity scores | ❌ | ✅ |
| Price history (ours) | ❌ | ✅ |
| Price history (build own) | ✅ | ✅ |
| Full DB download | ✅ (weekly) | ✅ (daily) |

---

## Current Status

| Phase | Status |
|-------|--------|
| Catalog (25,850 products) | ✅ Done |
| Extension capture pipeline | ✅ Working |
| Enrichment (auto) | 🔧 Fixing |
| Discontinued products | ✅ Column added |
| Popularity compute | ❌ Needs sales data |
| Price history | 🔧 Table exists, monitor running |
| Flutter auth flow | ❌ Not started |
| Flutter search + sync | ❌ Not started |
| Admin data migration | ⏭️ Skippable |
