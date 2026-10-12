# Analysis efficiency measurements

Tracks the experiments for [#2016](https://github.com/morluto/rea/issues/2016).
The production CLI/MCP contracts and defaults remain the compatibility baseline.
Downloaded artifacts, runtime copies, exported Evidence, transcripts and raw
measurements belong outside the checkout.

## Reproduce a measurement

Use the repository's pinned Node/npm and locked dependencies. Build each selected
revision, then copy its `dist/`, `bridge/`, `scripts/`, `skills/`, `package.json`
and `package-lock.json` to a separate runtime directory before editing production
sources. That copy needs the matching locked dependencies. The initial frozen
baseline is `42b0ed126df7d5b908ac369715378d5e519051b7`; this study does not
silently substitute a newer `main` or the previous Code Mode experiment.

The public artifacts and acquisition digests are in `corpus.json`. Supply their
actual local paths and an optional JSON object of explicit provider environment
settings. Do not add credentials to that file. Provider settings are inherited
by the child, but the report persists only the selected settings' digest. It
does not serialize the ambient environment.

```sh
export NODE_OPTIONS=--max-old-space-size=512
export UV_THREADPOOL_SIZE=1
export GOMAXPROCS=1
export GOMEMLIMIT=2GiB
python3 experiments/analysis-efficiency/resource-run.py -- \
  node experiments/analysis-efficiency/measure.mjs \
  --runtime-root /absolute/frozen-runtime \
  --revision 42b0ed126df7d5b908ac369715378d5e519051b7 \
  --artifact obsidian.asar --path /absolute/obsidian-1.14.4.asar \
  --providers /absolute/selected-providers.json \
  --output /absolute/new-measurement-directory
```

The wrapper requires Linux cgroup v2 and a working user systemd manager. It owns
a unique transient scope, restricts the whole process tree to one CPU, caps
memory at 4 GiB with no swap and 192 tasks, and samples memory/tasks/CPU every
100 ms. It stops its own scope above 3 GiB or below 4 GiB host available memory;
startup requires 8 GiB available. Cleanup failures retain the owned scope's
identity. Run heavy builds, providers and model trials serially. Sampled peaks
can miss short spikes; cgroup limit events are separately reported.

## What the numbers mean

`summary.json` records the selected artifact's before/after SHA-256, runtime
file-table digest, dispatcher and lockfile digests, runner source digest,
Node/SDK versions, catalog sizes, caller arguments and producer Evidence IDs.
`runtime-files.json` identifies the exact compiled files measured. Actual
provider settings and runtime files must stay fixed during a comparison.

Every tool call measures three intervals at the public SDK Transport boundary:

- Client work before `send`, including first-use schema preparation.
- Transport/server roundtrip, including framing, I/O, server work and client
  JSON parsing. This interval is **not** a Ghidra-only or provider-only timer.
- Client work after the parsed response reaches `onmessage`.

The SDK call's total excludes the runner's subsequent encoding and disk writes.
Result byte counts measure compact JSON of the parsed client result, not raw
wire bytes or tokens. Progress notifications retain their actual arrival times;
they do not imply more precise internal engine timings than the producer emits.
Scope CPU time and aggregate process-tree memory come from the wrapper's final
JSON line. Fresh processes have cold application caches; host page caches are
not globally flushed.

`--delivery summary` is an explicit candidate workflow, initially for artifact
inventory. It must be supported by the selected server's advertised schema.
The default `complete` runs the existing calls unchanged. Compare the same
analyst facts and complete source Evidence before crediting a smaller response.
Projection can reduce delivery bytes without reducing upstream analysis time.

Compare paired runs with the same runner source and provider settings:

```sh
node experiments/analysis-efficiency/compare.mjs \
  --left /absolute/complete-run --right /absolute/summary-run \
  --output /absolute/new-comparison.json
```

This checks all selected analyst facts, including inventory source IDs, exact
path records, manifest, counts, completeness, contradictions, coverage,
unexplored branches and limitations. It excludes only delivery observation IDs
and the named recovery-path description. Different settings, changed facts or
failed workflows make the comparator fail. Counts include extra view calls and
observed tool errors. Use repeated runs with alternating order before claiming
a distribution or a speedup; one pair is only one observation.

For a completed WASM result exceeding the MCP response budget, the runner keeps
the original error, exports retained Evidence through the public tool, and
authenticates the exact reported record using the selected runtime's parser.
The report names this recovery; it does not relabel the oversized inline reply
as successful delivery.

## Initial observations and exclusions

The frozen baseline has 2,326,609 bytes of complete catalog JSON, of which
494,207 bytes describe names, descriptions and input schemas. One Obsidian
trial spent about 21.9 s before the first request was sent, then about 0.77 s
in that request's transport/server roundtrip. Other cold runs differed
substantially. These single observations identify a measurement boundary;
they do not establish a speedup or a distribution.

The initial matrix exercised shipped Obsidian, NewPipe, ShareX, OpenWrt, SQLite
WASM and jq artifacts. SQLite produced a complete result larger than the
transport frame and requires an explicit recovery run. A first jq attempt hit
the SDK's default 60 s timeout because the experimental runner used a superseded
three-argument call signature. SDK 2.3.1 accepts request options as argument two;
the corrected jq run completed real Ghidra analysis in about 265 s. That earlier
driver timeout is excluded from REA regression claims. Provisional runs with
different runner source digests are not one paired statistical cohort.

No cross-session engine database cache, default analyzer changes, external
plugin loading, or broad plugin SDK is enabled by this experiment.

## Obsidian delivery checkpoint

The [recorded pairs](results/obsidian-20261012.json) compare frozen baseline
`42b0ed12` and candidate `f1106181` in complete → summary and summary → complete
order using the same runner source, bytes and provider settings. Both preserve
every selected fact and the atomic inventory Evidence ID.

| Measurement                                         |        Complete | Summary + exact path view |
| --------------------------------------------------- | --------------: | ------------------------: |
| Tool-result compact JSON, including lifecycle calls |   937,404 bytes |              16,322 bytes |
| Tool calls per question                             |               3 |                         4 |
| Complete catalog compact JSON                       | 2,326,609 bytes |           2,370,505 bytes |
| Workflow elapsed, first pair                        |         11.04 s |                   10.23 s |
| Workflow elapsed, second pair                       |         10.57 s |                   10.18 s |

Reply JSON falls by about 98.3%; catalog JSON grows by about 1.9%. The two elapsed
observations do not establish a statistical speedup. Inventory coverage and
upstream byte acquisition are unchanged. The candidate remains opt-in; existing
requests continue to deliver the complete inspection. Each run verifies the
selected artifact's before/after digest and reports no observed OOM or task
limit events. Source typing and projection improve selected delivery without
introducing an engine database cache or an external plugin protocol.
