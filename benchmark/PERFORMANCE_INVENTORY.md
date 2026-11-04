# TestSift optimization and Rust inventory

This inventory covers the imported implementation at
`f13851f7b3393aaafa7c7df088c1605747f07ce5`. It separates changes to the amount of work
from changes to the language doing that work. The experiment and raw measurements
are documented in [the issue #3 report](ISSUE_3_RESULTS.md). Collector implementations,
licenses, maintenance evidence, and pinned primary sources are in
[the Coverage and Rust assessment](COVERAGE_RUST_RESEARCH.md).

The inventory includes costs that the supplied fixtures do not exercise. An
unmeasured candidate is not evidence of a bottleneck, and this document promises
no speedup for it. The supplied workloads cannot bound costs for every application.

## Optimize snapshot production first

The adapter takes a Coverage snapshot before and after every example. Loaded-file
tracking takes another snapshot to obtain its keys. Its file-count fast path runs
after that snapshot already exists. The Coverage implementation creates results
for the complete instrumented Ruby process before TestSift filters the project.
Enabling branch collection therefore increases dependency-recorder cost even when
the consumer uses only lines or file names.

Reusing the adapter's already-created result removes an unnecessary producer call.
A Rust function that receives the same three complete Ruby snapshots cannot remove
that producer cost. A filtered or dirty-file collector interface could remove more,
but it changes the collection boundary and needs VM support or a separate collector.
Do not equate this with rewriting the selector.

## Collection and example boundaries

| Cost and owner | Existing work | Rust opportunity and limit | Next check |
| --- | --- | --- | --- |
| VM coverage counters, MRI `thread.c` and `ext/coverage/coverage.c` | Native callbacks maintain line and branch counters. | A language port alone keeps event and memory-access costs. A new event representation might help but requires a collector design. | Compare ordinary execution with matched Coverage collection, independently of snapshot requests. |
| Global snapshot production, `Coverage.peek_result` | Copies line arrays and builds requested coverage modes for tracked files. | Calling the public method from Rust retains this work. Avoid unused files or modes at the producer, or consume stable dirty-file data if an API becomes available. | Measure snapshots with actual Coverage at several file and branch counts and supported Ruby versions. |
| Loaded-file snapshot, `LoadedFilesTracker#stop_example` | Creates a full result only to get its keys, then checks the tracked-file count. | No Rust is needed to reuse an existing result. A file-enumeration collector API would avoid counters entirely. | Compare the bootstrap sharing variant, snapshot call counts, fault oracles, and dynamically loaded files. |
| Root and filter normalization, `CoverageAdapter#peek_normalized` | Iterates every returned file twice per example, then applies project filters. | A native scan can reduce Ruby dispatch and allocation. Filtering before snapshot construction has a larger possible saving. | Separate `coverage_normalize` from `coverage_snapshot`; preserve Ruby filter matching semantics. |
| Dependency delta, `CoverageAdapter#compute_diff` | Unions path keys and scans line arrays to the first difference. | A good batched Rust candidate after producer costs fall. Ruby `VALUE` access and result materialization remain under the GVL. | Compare one batch per example with the Ruby implementation, including conversion and output construction. |
| Line-report delta, `Engine#record_coverage_delta` | Revisits the same arrays and stores positive line-count differences. | Fuse dependency detection and optional line deltas in one pass. This can be done in Ruby before porting the pass. | Verify nil slots, new files, differing array lengths, counts above one, and current report compatibility. |
| Dependency-only mode | The imported engine records line-report deltas even when only dependency selection is needed. | Separating requested outputs can remove work before native acceleration. | Add an explicit product contract in the collection/report separation work; use this benchmark's ablation as a lower bound. |
| Coverage modes and lifecycle | SimpleCov can own collection, and reports can require branches. | Rust cannot silently disable another tool's modes, reset global counters, or use oneshot counts as repeated-example counts. | Check coexistence, startup order, eval, repeated execution, workers, and interpreter fallback before adoption. |

## Attribution, filesystem, and selection

| Cost and owner | Existing work | Rust opportunity and limit | Next check |
| --- | --- | --- | --- |
| Loaded inputs, `LoadedFilesTracker#loaded_set_inputs` | Builds a fresh Set from all cached loaded inputs for each example. | Immutable shared sets, load epochs, or native ID sets may avoid repeated copying. They must preserve the dependencies of code that was loaded earlier. | Measure allocations as the number of project-loaded files and examples grows. |
| Input unions, `Engine#example_finished` | Combines coverage, loaded files, I/O, Rails, declared globs, and metadata through several temporary Sets. | A batched accumulator or native integer-ID set can remove intermediates. | Keep every input kind and duplicate-path behavior; compare peak memory and total allocations. |
| File attribution, `Engine#attribute_to_example` | Rechecks filters, derives relative paths, and rewrites file metadata while traversing every attributed input. | Reuse per-run path metadata and filter decisions. Native path IDs can reduce object traffic. | Bound the repeated work without assuming files cannot change during the suite. |
| Conservative transitive dependencies | A loaded file can become a dependency of many later examples. | Faster sets do not improve the selected-test ratio. A more precise collection model may reduce both graph size and test execution. | Check proposed skips against full runs with source, constants, lazy loads, helpers, and metaprogramming mutations. |
| Stat freshness, `Tracker::FileDigest.compute` | Every call stats the file, constructs a nanosecond key, and checks a process-local digest cache. | Batch syscalls and reuse freshness checks where a run boundary permits. Rust does not make the filesystem syscall disappear. | Count stat calls and separate `filesystem_stat` from the remaining digest-cache bookkeeping. |
| Content hashing, `Digest::SHA256.file` | SHA256 is already native and cached by mtime and size. | Batch file I/O may help at scale. Rewriting SHA256 in Rust is not itself a demonstrated improvement. | Compare many small files, changed bytes, deleted files, and same-size changes; preserve stored digest compatibility. |
| New-file discovery, `NewFileDetector` | Walks configured directories and globs, filters known paths, and hashes new inputs. | A native walker or persistent watcher can help large trees. Watchers introduce missed-event and restart recovery requirements. | Measure large repositories with a small change set; keep deletion, symlink, and unreadable-file behavior. |
| Declared globs and `tracks:` metadata | Resolve globs and merge declared inputs; declared-glob walks are already memoized. | Batch glob matches and intern resolved paths. Avoid porting the already-cached steady-state call. | Measure many distinct declarations and matched paths, separately from the cached call. |
| Graph registration and inverse index, `DependencyGraph` | Copies paths into Sets, invalidates an inverse index on registration, and rebuilds it lazily. | Native compact IDs, bitmaps, and adjacency lists are plausible. They offer little whole-run value when the graph is a small fraction of runtime. | Use actual large dependency graphs and include rebuilding, reverse-index queries, and output conversion. |
| Warm graph reconstruction, `Engine#seed_graph_from_previous` and `#graph_from_previous` | Reconstructs graph objects from cached path sets for state and selection. | Reuse one canonical graph or deserialize directly to a native model. | Profile warm runs with 10k or more examples before introducing another graph representation. |
| Status and invalidator selection, `Tracker::Filter` | Gives precedence to whole-suite invalidation and always-run statuses, then adds changed dependents. | A small pure Rust selector is easy to specify, but crossing the boundary can cost more than this logic. | Require exact selected-ID and reason parity for failed, flaky, pending, interrupted, new, and changed examples. |
| Example identity, `Example.from` | Builds metadata and hashes stable JSON identity fields with native MD5. | Batch stable identity construction only if discovery profiles justify it. | Keep rename and unnamed-example identity contracts and cached-history behavior. |
| ENV matching and snapshots | Expands tracked names and globs and stores digested values. | Native glob matching or compact key sets may help unusually large environments. | Measure wildcard-heavy metadata; do not collect undeclared sensitive ENV values. |
| I/O hooks and Rails notifications | Normalize observed paths, route events, deduplicate inputs, and hash files. Rails adds templates, translations, and optional schema inputs. | Keep framework hooks in Ruby; a native accumulator could consume normalized events in batches. | Separate hook rejection, recorded I/O, templates, SQL, I18n, and per-example bucket cost on representative applications. |

## Persistence, finalization, and process costs

| Cost and owner | Existing work | Rust opportunity and limit | Next check |
| --- | --- | --- | --- |
| Cache manifest and lazy load, `JsonBackend#load_graph` and `#read_field` | Reads requested fields on demand; parses JSON, interns strings, and reconstructs sets and symbolized metadata. | The JSON parser is already native. A Rust parser helps only if it avoids the second object-model walk or keeps the model native. | Split native parsing, Ruby decoding/interning, disk reads, and model construction on actual populated caches. |
| Snapshot building, `Engine#build_snapshot` | Projects forward and reverse graphs, metadata, statuses, per-example coverage, and histories to persistent structures. | Serialize a native model directly rather than exporting and reimporting large Ruby hashes. | Measure snapshot construction separately from encoding and writing. Preserve all schema fields. |
| Cache encoding and storage backends | JSON is native; optional MessagePack and SQLite already provide native implementations. | Reuse existing backends before adding another format. A Rust backend can remove Ruby graph materialization, not automatically improve the underlying C codecs. | Repeat actual fixture runs with each backend and serializer once persistence is material; include load, save, bytes, and corrupt-cache recovery. |
| Line coverage carry-forward and export | Merges skipped-example historical line counts, applies filters, and writes JSON. | Batch sparse line-count accumulation or avoid it when no line report is requested. | Preserve the distinction between current-run observations and historical coverage; avoid a faster misleading report. |
| Terminal, JSON, and HTML reports | Build payloads, paths, dependency views, and HTML data after finalization. | Shared prepared payloads or a native serializer can reduce repeated traversal. The browser UI and report semantics remain separate. | Attribute payload construction, JSON encoding, file writes, and embedded HTML data independently at large report sizes. |
| Worker merge, `RSpec::ParallelTests` | Waits for peers, loads snapshots, merges them, writes the final cache and coverage, emits reports, and purges worker directories. | Native merging can help large worker outputs. Startup, peer waits, disk contention, and scheduling require process-level changes. | Include the elected worker's complete exit and verify the merged cache, not just summed RSpec output. |
| Remote cache, `RemoteCache` | Finds ancestry candidates, transfers archives or Redis fields, validates, extracts, and applies retention. | Native compression and validation can help CPU-bound archives. Network RTT and transferred bytes need transport or cache-layout changes. | These fixtures do not configure remote storage. Measure actual S3, Redis, and local-filesystem restores separately before ranking this cost. |
| Ruby, Bundler, RSpec, and Rails boot | Loads gems and the framework, discovers examples, builds RSpec metadata, and initializes the application. | A native selector does not remove framework startup. Preloading can amortize it, with process isolation and stale-state tradeoffs. | Compare cold processes with an explicitly separate preload/fork experiment; never present preload time as complete cold execution. |
| Selection before runner boot | The existing adapter loads the runner and discovers examples before it can return an empty selection. | A Rust CLI could avoid Ruby/Bundler/Rails startup for a verified empty run. This requires a complete runner manifest and configuration/input contract; it is not a language-only port. Arbitrary Ruby DSLs and dynamically generated examples require the existing discovery path. | Prototype only with explicit manifest guarantees. Changes to example discovery, CLI filters, config, ENV, or unknown inputs must force runner discovery; measure total savings and fallback correctness. |
| Garbage collection | Reclaims temporary coverage snapshots, strings, Sets, and report structures. | Reduce allocations first. A native-owned model can reduce Ruby heap pressure, but its memory must be counted separately. | Compare object allocations, GC time, process RSS, and native heap measurements. Do not treat fewer Ruby objects as lower total memory by definition. |
| Runtime version and JIT | Changes collector implementation, object allocation, interpreter execution, and compilation overhead. | An interpreter upgrade may remove work without a TestSift native extension. Rust would still need support for every promised engine. | Run the same real-Coverage workload with installed Ruby releases. A snapshot microbenchmark alone does not establish application compatibility or JIT benefit. |

## Set a native prototype gate

Start with a Ruby reference and a stable boundary that accepts a batch of observations
and returns changed file IDs plus optional line deltas. Keep the existing collectors,
RSpec lifecycle hooks, Rails callbacks, and reporting contracts outside the first
native implementation. A typed, interpreter-independent graph model can follow only
when its measured cost justifies it.

Proceed with a native consumer when all these conditions hold:

- After reducing unnecessary snapshots, its target still consumes at least 10% of
  the complete instrumented run or dominates peak memory on a representative large
  project. The supplied tiny Ruby graph is not sufficient evidence.
- Conversion, FFI, allocation, initialization, and native execution together save at
  least 10% of end-to-end median wall time, without a worse p95 or peak process memory.
  A faster isolated loop does not pass this gate.
- Differential runs produce exactly the same selected IDs and reasons, line deltas,
  cache fields, and failure-oracle results. Cover dynamic loads, constants, filters,
  file deletion, ENV changes, retries, pending statuses, and worker merges.
- Native failure falls back to the existing Ruby path and never fails the user's
  suite. MRI, JRuby, and best-effort interpreter behavior remain explicit.
- The build and release matrix is maintainable. A required custom MRI build or an
  unversioned private VM structure is a no-go for the default gem.

A different collector has a separate gate. It must first explain how it observes
arbitrary executed Ruby dependencies, preserve coexistence with coverage reporting,
and show no omitted oracle failures. Only then compare its total time and memory.
Changing to cheaper evidence with weaker dependency semantics is a product decision,
not an optimization validated by a fast benchmark.

These thresholds are proposed decision criteria, not changes to the repository's
existing benchmark limits. The baseline and limits remain unchanged by this work.
