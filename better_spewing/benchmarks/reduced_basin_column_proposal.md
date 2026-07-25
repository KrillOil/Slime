# Reduced Basin-Column Model Proposal

Status: unimplemented Package 2C decision proposal. This document does not
authorize G2, Package 3A, or production-room migration.

## Creator decision requested

Choose exactly one:

1. **Approve a Package 2D design checkpoint** for the reduced basin-column
   authority below, after which implementation and schema reconciliation may be
   commissioned separately.
2. **Reject the reduction and pause the upgrade** at Package 2C while retaining
   the accepted G1 rollback surface.

Approval is required because this replaces the canonical per-cell settled-flow
model. Package 2C does not implement it.

## Proposed authority and schema

- Keep AIRBORNE packet authority, stable packet IDs, swept collision, drain
  records, the ownership ledger, 60 Hz tick order, and immutable room/tuning
  hashes unchanged.
- Replace the full row-major settled-cell volume array with authored basin
  records in stable basin ID order. Each record contains:
  `basin_id:u32`, immutable horizontal bounds, floor profile hash, capacity in
  quanta, current conserved volume, and ordered column surface heights.
- Use one column per 15 authored pixels inside a basin. Columns are local to the
  basin; no room-wide empty grid is serialized.
- Canonical state stores the ordered basin volumes/columns, a deduplicated FIFO
  of active basin IDs, membership bits, stable counters, and the next scheduled
  column cursor. Unused tail bits remain zero.
- Bump the complete-state schema version. Encode all integers little-endian with
  explicit counts and fixed-width records. Include basin-definition and derived
  basin-coverage hashes in immutable inputs.
- Room occupancy remains the collision/LOS authority. A separate immutable
  authored basin-coverage encoding maps each eligible near-side contact pixel
  to either one stable basin ID/column or the no-basin sentinel.

## Deposition and flow

- Deposition first performs the existing near-side contact and solid exclusion.
  The immutable basin-coverage map then selects a basin column.
- AIRBORNE→SETTLED transfer remains atomic and limited by basin capacity.
  Partial volume stays on the same packet ID at the impact position and retries
  next tick. No eligible basin or no capacity leaves the packet conserved and
  stationary.
- Each active basin processes a bounded number of columns in stable basin ID
  and rotating canonical cursor order.
- Within a basin, apply snapshot/delta fall-to-floor and lateral height
  equalization only between adjacent authored columns. No transfer crosses
  basin boundaries and no upward-pressure rule is introduced.
- Stable basins sleep after the tuning-controlled processed-tick threshold.
  Deposition or suction wakes the destination basin and its adjacent columns.
- SETTLED ledger volume must equal the sum of every basin column at every
  intermediate phase.

## Player, immersion, hazard, and suction interfaces

- Player sampling asks basin authority for conserved volume intersecting the
  existing deterministic player sample points. It returns the same integer
  submerged numerator/denominator interface expected by later immersion work.
- Hazard coverage queries the immutable basin span plus current column surface
  height. Hazard state itself remains separately serialized and stable-ID
  ordered.
- Suction LOS continues to use the shared occupancy traversal. Eligible settled
  candidates are returned in `(distance, basin_id, column_index)` order.
  Reservation debits the selected basin column atomically into SUCTION; return
  or recovery reverses ownership without loss.
- These interfaces are declarations only; player interaction, hazards, and
  suction remain deferred to their canonical packages.

## Conservation, replay, and migration effects

- Ledger categories and ownership transitions do not change. Basin columns are
  a different SETTLED representation, not a new category.
- Replay headers gain the basin-definition and basin-coverage hashes. Old state
  schema and replay versions reject explicitly; no silent conversion occurs.
- Deterministic migration tooling must rebuild authored basin bytes, coverage,
  initial basin state, occupancy, tuning, and replay fixtures together.
- Rooms 1–4 require explicit shallow basin rectangles/column profiles. Areas not
  authored as basins cannot accept settled goo. Existing room geometry must not
  be silently inferred into basins.

## Performance hypothesis and budgets

The measured 15 px full grid has 2,304 settled cells and still reports Web core
simulation p95 156.2 ms. The proposed normal-room target is at most 8 basins,
128 total columns, 32 active columns per tick, and 64 adjacent-pair evaluations
per tick. The stress target is at most 16 basins, 256 total columns, 128 active
columns, and 256 adjacent pairs.

The hypothesis is that removing room-wide array copies/scans and limiting
deposition/flow to authored columns reduces work by more than one order of
magnitude. Acceptance budgets remain unchanged: normal simulation p95 ≤2 ms;
stress p95 ≤4 ms, p99 ≤6 ms, max ≤8 ms; whole-frame p95 ≤16.67 ms; zero
gameplay-affecting dropped ticks, divergence, or ledger/category error.

## Validation plan

1. Lock basin-definition, coverage, state-schema, tuning, and replay byte/hash
   fixtures across three fresh processes.
2. Prove deposition exclusion, partial retry, saturation, stable basin/column
   ordering, conservation, and no cross-basin transfer.
3. Prove snapshot/delta equalization, sleep/wake timing, budget deferral, and
   checkpoint resume determinism.
4. Prove immersion, hazard-depth, and suction-candidate query interfaces against
   hand-authored basin fixtures without implementing their later mechanics.
5. Run 100 emission→deposit→suction/recovery model cycles with zero ledger error.
6. Repeat the exact Package 2C desktop and installed-Chrome 10+120-second
   measurements with raw core/full-runner/hash/frame samples.
7. Rerun every P1A–P2C and legacy suite and independently verify G1 recovery.

## Rollback

- Develop only on a new post-approval checkpoint branch/commit.
- Preserve `checkpoint/primordial-slime-spew-g1`, the baseline tag, and recovery
  ZIP unchanged.
- Keep the current full-grid implementation and fixtures reachable at the
  Package 2C checkpoint.
- If basin validation or performance fails, abandon the new commits without
  rewriting history and restore from the Package 2C parent or G1 tag.
