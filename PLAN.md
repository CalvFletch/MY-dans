# MY-DANS Project Plan

## Architecture Overview

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Flutter App  │────▶│  FastAPI      │────▶│  PostgreSQL   │
│  (client)     │◀────│  (server)     │◀────│  (database)   │
└──────────────┘     └──────┬───────┘     └──────────────┘
                            │
                     ┌──────▼───────┐
                     │  DM Web API  │
                     │  (scraping)  │
                     └──────────────┘
                            │
                     ┌──────▼───────┐
                     │  Data Studio │
                     │  (MCP/Ext)   │
                     └──────────────┘
```

---

## Phase 1: Data Ingestion Pipeline

### 1.1 batchedDataV2 → Database

**Source**: Data Studio report "Two Years in Motion" batchedDataV2 responses.

**Fact Table Fields** (12 columns from batchedDataV2):

| # | Column | Type | DB Column | Description |
|---|--------|------|-----------|-------------|
| 0 | `qt_8hw1ysaqtd` | long | `fiscal_year` | Fiscal year (e.g., 2026) |
| 1 | `qt_4ptyfuaqtd` | long | `fiscal_week` | Fiscal week number |
| 2 | `qt_avsmsuaqtd` | date | `sale_date` | Date of sale/movement |
| 3 | `qt_xupjwvaqtd` | string | `brand` | Brand (Dan Murphy's, BWS) |
| 4 | `qt_flte0vaqtd` | string | `site_id` | Store site ID |
| 5 | `qt_bg491vaqtd` | string | `site_name` | Store name |
| 6 | `qt_zmtr4vaqtd` | string | `category` | Product category |
| 7 | `qt_3r7a7vaqtd` | string | `article_id` | Article/SKU ID |
| 8 | `qt_xvtlawaqtd` | string | `article_name` | Article display name |
| 9 | `qt_dee3hwaqtd` | string | `movement_type` | Movement type (Delivery, GI, etc.) |
| 10 | `qt_eqppqwaqtd` | double | `cost` | Cost in dollars (can be negative) |
| 11 | `qt_9hw1ysaqtd` | double | `qty` | Movement quantity (can be negative) |

**Dimension Tables** (extracted from separate batchedDataV2 requests):
- Categories (14 values)
- Movement types (49 values)
- Site IDs + Names (~294 DM stores)
- Article IDs + Names (~294 articles in current filter)

**Key Facts**:
- Data is BigQuery-backed, cached (`bqCacheHit: true`)
- ~2M rows for just 1-15 June 2026 (DM only)
- Year-to-date would be 20-50M+ rows
- Costs/quantities can be negative (stocktake adjustments, returns)

### 1.2 Article Master Data

From the dimension tables in batchedDataV2, we extract:

| Source Column | DB Column | Type | Description |
|---------------|-----------|------|-------------|
| Article ID (`qt_3r7a7vaqtd`) | `article_id` | TEXT PK | Dan Murphy's SKU |
| Article Name (`qt_xvtlawaqtd`) | `article_name` | TEXT | Display name |
| Category (`qt_zmtr4vaqtd`) | `category` | TEXT | Product category |

This populates `articles` table. Categories can be normalized into a `categories` lookup.

---

## Phase 2: Popularity / Power Score

### 2.1 Definition

A per-product score derived from sales data that ranks products by "popularity."

### 2.2 Scoring Approaches

| Approach | Pros | Cons |
|----------|------|------|
| **Absolute Rank** (1=best, 24000=worst) | No ties, intuitive ordering | Score changes when new products added, large numbers |
| **Percentile /100** | Compact, bounded 0-100 | Ties possible, less granular |
| **Composite Score** (weighted float) | Continuous, no ties, recency-weighted | Slightly more complex |

### 2.3 Recommendation: Composite Popularity Score

Compute a **0.0–100.0 float** based on:

```
popularity = percentile_rank(total_qty_sold) * recency_weight
```

Where:
- `total_qty_sold` = sum of all positive movement quantities (last 12 months)
- `percentile_rank` = 0.0–100.0 based on distribution of all products
- `recency_weight` = multiplier based on how recently the product sold:
  - Sold within last 7 days: ×1.0
  - Sold within last 30 days: ×0.9
  - Sold within last 90 days: ×0.7
  - Older: ×0.5

**Why this approach**:
- Continuous float → no ties when ordering
- Bounded 0-100 → easy to display as "Popularity: 87/100"
- Recency-weighted → trending products rank higher than stale bestsellers
- Only positive movements count (not returns/stocktake adjustments)
- Products with NO sales data → score = 0.0 (lowest)

### 2.4 Computation Schedule

- Recompute nightly (after data sync)
- Store as `popularity_score` FLOAT column on `articles` table
- Query: `SELECT * FROM articles ORDER BY popularity_score DESC`

### 2.5 Client Access

- Users do NOT see the raw popularity score.
- Users query by search params → API returns results ordered by popularity.
- The order IS the popularity information without exposing the score.

---

## Phase 3: Price History

### 3.1 Definition

For each article, track the "agreed upon" price per day.

### 3.2 Computation

For each article × date:
- Group all sale transactions (`movement_type = 'Delivery'` or positive qty)
- Find the **mode** (most common) unit price = `cost / qty`
- If multiple modes, take the **median**
- Store as `price_history(article_id, date, price)`

### 3.3 Schema

```sql
CREATE TABLE price_history (
    article_id TEXT NOT NULL,
    sale_date DATE NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    sample_count INT,           -- how many transactions contributed
    PRIMARY KEY (article_id, sale_date)
);
```

### 3.4 Notes

- We cannot distinguish member vs. non-member pricing from this data.
- Price computation from 2M+ rows requires batch processing.
- Consider storing only last 12 months of price history.
- Client does NOT see individual price history; only used for "last validated" checks.

---

## Phase 4: Client Search Workflow

### 4.1 Overview

```
Client                    API Server                  DB
  │                          │                          │
  │ 1. Local search          │                          │
  │    (fast, SQLite)        │                          │
  │                          │                          │
  │ 2. POST /api/search      │                          │
  │    {params, count,       │                          │
  │     stale_articles[]}    │                          │
  │                          │ 3. Execute same search   │
  │                          │    on server DB          │
  │                          │                          │
  │                          │ 4. Compare counts        │
  │                          │    client=100, svr=104   │
  │                          │                          │
  │ 5. Response:             │                          │
  │    {article_codes[104],  │                          │
  │     missing_codes[4],    │                          │
  │     updated_products[]}  │                          │
  │                          │                          │
  │ 6. Request missing       │                          │
  │    product details       │                          │
  │                          │                          │
  │ 7. Sort local results    │                          │
  │    by popularity order   │                          │
```

### 4.2 Step-by-Step

1. **Client local search**: User searches "shiraz >$20" → SQLite returns 100 results.
2. **Client → API**: Sends:
   ```json
   {
     "query": "shiraz",
     "filters": {"min_price": 20, "category": "WINE"},
     "client_result_count": 100,
     "stale_articles": ["768384", "758048", ...]  // 42 article IDs not validated in >24h
   }
   ```
3. **API processes**:
   - Executes equivalent search on server DB
   - Gets 104 results → client is missing 4 products
   - Orders all 104 by `popularity_score DESC`
   - Fetches updated info for the 42 stale articles
4. **API → Client**: Returns:
   ```json
   {
     "article_codes": ["768384", "758048", ...],   // 104 codes in popularity order
     "server_result_count": 104,
     "updated_products": [                          // 42 products with fresh data
       {"article_id": "768384", "article_name": "...", "category": "WINE", ...},
       ...
     ]
   }
   ```
5. **Client processes**:
   - Compares `article_codes` with local results → finds 4 missing
   - Requests full details for the 4 missing products
   - Updates local DB with 42 refreshed products
   - Sorts local search results by `article_codes` order (popularity)
6. **Client also**:
   - Adds the 4 new products to local SQLite

### 4.3 Sync at Midnight

- All clients call `/api/sync` → get all products updated since last sync
- Includes popularity scores (as ordering, not raw numbers)
- Includes price updates

### 4.4 Text Search (Web API Fallback)

When user searches text (e.g., "st remy martin"):

```
Client → API: {query: "st remy martin", text_search: true}
API:
  1. Search local DB for "st remy martin"
  2. ALSO scrape DM website search results for "st remy martin"
  3. Compare: any products on DM site not in our DB?
  4. If yes: add to DB, include in response
  5. Return results ordered by popularity
```

**Scraping strategy**:
- DM website search: `https://www.danmurphys.com.au/search?searchTerm=...`
- Extract product cards (name, price, article ID, image)
- Rate limit: max 1 scrape per unique query per hour
- Cache scrape results for 24h

---

## Phase 5: Database Schema

### 5.1 Core Tables

```sql
-- Product catalog
CREATE TABLE articles (
    article_id TEXT PRIMARY KEY,
    article_name TEXT NOT NULL,
    category TEXT,
    popularity_score FLOAT DEFAULT 0.0,
    last_validated TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Categories lookup
CREATE TABLE categories (
    name TEXT PRIMARY KEY
);

-- Daily price history
CREATE TABLE price_history (
    article_id TEXT REFERENCES articles(article_id),
    sale_date DATE NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    sample_count INT DEFAULT 1,
    PRIMARY KEY (article_id, sale_date)
);

-- Raw sales data (can be truncated/rolled up)
CREATE TABLE sales_raw (
    id BIGSERIAL PRIMARY KEY,
    article_id TEXT NOT NULL,
    site_id TEXT,
    site_name TEXT,
    category TEXT,
    sale_date DATE NOT NULL,
    fiscal_year INT,
    fiscal_week INT,
    movement_type TEXT,
    cost DECIMAL(12,2),
    qty DECIMAL(12,2),
    ingested_at TIMESTAMP DEFAULT NOW()
);

-- Search log (already exists)
-- upload_log (already exists)
```

### 5.2 Indexes

```sql
CREATE INDEX idx_sales_article ON sales_raw(article_id);
CREATE INDEX idx_sales_date ON sales_raw(sale_date);
CREATE INDEX idx_sales_category ON sales_raw(category);
CREATE INDEX idx_articles_popularity ON articles(popularity_score DESC);
CREATE INDEX idx_price_history_article ON price_history(article_id);
```

---

## Phase 6: Implementation Order

| # | Task | Priority | Depends On |
|---|------|----------|------------|
| 1 | Extension captures batchedDataV2 → POST to API | HIGH | auto_filters.py |
| 2 | API `/api/ingest/batched` endpoint | HIGH | #1 |
| 3 | Parse batchedDataV2 → populate `articles`, `sales_raw` | HIGH | #2 |
| 4 | Compute `popularity_score` nightly job | HIGH | #3 |
| 5 | Compute `price_history` nightly job | MEDIUM | #3 |
| 6 | `/api/search` endpoint with popularity ordering | HIGH | #4 |
| 7 | Web API scrape for text search fallback | MEDIUM | #6 |
| 8 | Client sync-at-midnight workflow | MEDIUM | #6 |
| 9 | Client search integration (local + remote merge) | MEDIUM | #6, #8 |

---

## Open Questions

1. **Year-to-date or all-time?** How far back do we ingest from Data Studio?
2. **BWS inclusion?** Currently filtering DM only. Include BWS for broader catalog?
3. **Price history retention?** Keep all or only recent (12 months)?
4. **Popularity recency decay rate?** Need to tune the weights based on actual data.
5. **Scraping legality?** DM website scraping for text search — check ToS.

---

## Phase 7: Sync Timing — Finding the Price Change Window

### 7.1 What We Know

From batchedDataV2 response timestamps:

```
dataTimestamp:  2026-06-26 01:32:01 UTC  (BigQuery snapshot time)
BQ creationTime: 2026-06-26 01:32:01 UTC
BQ endTime:      2026-06-26 01:32:02 UTC  (<1s, cache hit)
```

Data Studio UI shows "Data Last Updated: 26/06/2026 01:06:22" (likely AEST = 15:06 UTC previous day).

**The data pipeline refreshes around 1:00-1:30 AM** (timezone TBD — could be UTC or AEST).

### 7.2 The Problem

If DM updates prices at, say, 3:00 AM AEST and we sync at midnight, we miss:
- New sale prices that just went live
- Products that entered/exited promotion
- New products added overnight

Syncing too early = stale data for the first day of each sale period.

### 7.3 Discovery Strategy

**Price Change Monitor** — a lightweight script that runs hourly for 1 week:

```
For each hour (0-23):
  1. Pull batchedDataV2 for 10 high-volume products
  2. Compare prices to previous hour
  3. Record the hour where prices change
```

This gives us the **actual DM price update window**, independent of BigQuery refresh times.

Expected result: prices change at a consistent hour (e.g., 3-4 AM AEST). That's our sync trigger.

### 7.4 Candidate Sync Windows

| Window | Rationale |
|--------|-----------|
| **3:00 AM AEST** | Common retail price update time (end of previous business day) |
| **4:00 AM AEST** | Woolworths group (owner of DM) typically updates systems |
| **5:00 AM AEST** | Safe bet — prices definitely updated, data likely in BigQuery |

### 7.5 Implementation

**Script**: `dev/price_monitor.py` (runs on API server)

```bash
# One-time setup: extract top 50 from batchedDataV2
python dev/extract_top50.py

# Init tracking
python dev/price_monitor.py --setup

# Run hourly (add to crontab on API server)
0 * * * * cd /path/to/MY-dans-api && python dev/price_monitor.py >> logs/price_monitor.log 2>&1

# After 3 days, analyze:
python dev/price_monitor.py --analyze
```

Uses the official DM API (`Ocp-Apim-Subscription-Key` from `DM_API_KEY` env var).
Checks 50 popular products every hour, logs price changes.
After ~72 hours, the histogram reveals the exact price-change window.

Once we know the window, schedule the full sync **30 minutes after** the detected update time. This ensures:
- Prices are fresh for the new day
- BigQuery has ingested the new data
- Clients syncing at 7 AM get yesterday's final prices + today's new ones

### 7.6 Fallback: Progressive Sync

If the exact window can't be determined:
- Sync at **4:00 AM AEST** (best guess for Woolworths group)
- If no price changes detected vs yesterday, retry at 5:00 AM, then 6:00 AM
- First sync that finds changes → full sync, cancel retries
