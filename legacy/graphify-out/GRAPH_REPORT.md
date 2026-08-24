# Graph Report - legacy  (2026-08-23)

## Corpus Check
- 2 files · ~2,868 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 12 nodes · 19 edges · 4 communities (3 shown, 1 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `41e9274d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- geosat
- geosat.f
- tlmdec

## God Nodes (most connected - your core abstractions)
1. `geosat` - 8 edges
2. `rdfrm()` - 3 edges
3. `tlmdec()` - 3 edges
4. `hexval()` - 2 edges
5. `crcchk()` - 2 edges
6. `engcnv()` - 2 edges
7. `limchk()` - 2 edges
8. `timcnv()` - 2 edges
9. `orbprp()` - 2 edges
10. `report()` - 2 edges

## Surprising Connections (you probably didn't know these)
- `geosat` --calls--> `rdfrm()`  [EXTRACTED]
  legacy/src/geosat.f → legacy/src/geosat.f  _Bridges community 0 → community 1_
- `geosat` --calls--> `tlmdec()`  [EXTRACTED]
  legacy/src/geosat.f → legacy/src/geosat.f  _Bridges community 0 → community 2_

## Import Cycles
- None detected.

## Communities (4 total, 1 thin omitted)

### Community 0 - "geosat"
Cohesion: 0.40
Nodes (5): engcnv(), geosat, limchk(), orbprp(), report()

### Community 1 - "geosat.f"
Cohesion: 0.67
Nodes (3): hexval(), rdfrm(), timcnv()

## Knowledge Gaps
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `geosat` connect `geosat` to `geosat.f`, `tlmdec`?**
  _High betweenness centrality (0.191) - this node is a cross-community bridge._
- **Why does `rdfrm()` connect `geosat.f` to `geosat`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **Why does `tlmdec()` connect `tlmdec` to `geosat`, `geosat.f`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._