# Ruby Coverage and Rust: implementation and reuse assessment

Research date: 2026-11-04. Measured source baseline (imported upstream):
`f13851f7b3393aaafa7c7df088c1605747f07ce5`. Fork PR base:
`03173c22b32b0accaccf37a5e662487b3bc79c50`. The Coverage adapter and loaded-file
tracker source at the fork base matches the imported baseline.
This document addresses the Coverage portion of issue #3. It contains source-based
engineering conclusions, not measured speedups or an implementation proposal already
validated by benchmarks.

## Decision

Keep each Ruby implementation's Coverage collector. First measure and reduce repeated
snapshot production; then prototype a narrow, optional Rust snapshot consumer if Ruby
comparison and allocation remain material. Do not port MRI's collector merely to change
its implementation language: its hot counters already execute in native C. Do not
require a custom Ruby build for the normal gem.

An existing Rust project, [Supercov](https://github.com/supercorp-ai/supercov/tree/b1aafa07ce6be3a8697d1a5a7697e5ecb19b014d),
is relevant, but it uses Ruby Coverage and Ruby probes alongside Rust source analysis.
It is not a compatible Rust implementation of MRI Coverage. Its probe planning and
transport are useful reference designs; adopting its whole runtime would change the
measurement model and supported interpreter surface.

## What MRI actually does

The benchmark runtime is MRI **3.3.10**, whose exact release revision is
[`343ea050023cfc0374fdea6fdf625b2f57b716a4`](https://github.com/ruby/ruby/tree/343ea050023cfc0374fdea6fdf625b2f57b716a4).
The installed runtime reports that revision. Its
[Coverage extension](https://github.com/ruby/ruby/blob/343ea050023cfc0374fdea6fdf625b2f57b716a4/ext/coverage/coverage.c)
duplicates line arrays and builds every tracked file's result. With branch mode, each peek
recreates nested hashes and six-element branch keys. With method mode, each peek calls
`rb_objspace_each_objects(method_coverage_i, ...)` to scan object-space slots for method
entries. These release-specific costs matter even if TestSift ultimately uses only lines:
another owner such as SimpleCov may have enabled additional modes.

For comparison, the inspected development MRI revision is
[`1f77afb8e8dc3b48acb3528a393f86d6d468e3f0`](https://github.com/ruby/ruby/tree/1f77afb8e8dc3b48acb3528a393f86d6d468e3f0).
This is a development-branch snapshot, not evidence that every supported release has
identical internals. Its [Coverage extension](https://github.com/ruby/ruby/blob/1f77afb8e8dc3b48acb3528a393f86d6d468e3f0/ext/coverage/coverage.c)
and [VM callbacks](https://github.com/ruby/ruby/blob/1f77afb8e8dc3b48acb3528a393f86d6d468e3f0/thread.c)
separate three costs:

1. **Compilation/instrumentation:** Ruby associates coverage metadata with instruction
   sequences. Starting collection after code was loaded does not retroactively instrument
   that code. Replacing a result formatter cannot change this cost.
2. **Execution:** `update_line_coverage` updates a Ruby immediate-integer counter in an
   internal array. `update_branch_coverage` uses a program-counter-to-branch index and
   updates its counter. These callbacks are C, not Ruby loops. Moving them to Rust still
   leaves event dispatch, instrumentation, and memory access unless the design changes.
3. **Observation:** `rb_coverage_peek_result` enumerates the complete tracked-file hash.
   It duplicates and freezes line arrays and constructs the result hash; requested branch
   and method modes build their output too. The inspected head caches structural templates
   for branches and methods, avoiding the release's branch-key reconstruction and whole
   object-space method scan, but still makes output copies and fills counters.

Both [3.3.10 `array.c`](https://github.com/ruby/ruby/blob/343ea050023cfc0374fdea6fdf625b2f57b716a4/array.c#L2692)
and [development `array.c`](https://github.com/ruby/ruby/blob/1f77afb8e8dc3b48acb3528a393f86d6d468e3f0/array.c#L2932)
implement this C `rb_ary_dup` entry point as `rb_ary_new2(len)` followed by `ary_memcpy`
and setting the length. Thus this path eagerly copies the array's VALUE slots; it does
not merely share the line buffer. Integer/nil elements are immediate values, so this is
not a deep copy of separately allocated counter objects. Do not confuse this entry point
with other Ruby Array duplication/sharing paths. Benchmark the release actually deployed;
development optimizations are not evidence of reduced 3.3.10 costs.

`peek_result` does not clear or stop collection. The current implementation takes no
filter arguments: filtering the returned hash by project root cannot prevent MRI from
producing results for gems first. A Ruby consumer that only needs file names nevertheless
pays for result production when it calls `peek_result.keys`. An extension that calls the
same public Ruby method inherits this cost. These statements follow the source above,
not a claim about Rust's relative performance.

There is an active upstream discussion,
[Feature #22250: `only:` for `peek_result`](https://redmine.ruby-lang.org/issues/22250),
about avoiding unused coverage modes for per-test attribution. Treat it as a proposal,
not an available API: the inspected source still registers a zero-argument method.
Follow this direction before maintaining a competing runtime patch. Selecting modes
would not itself filter files or return a dirty-file delta.

### Modes are semantic choices

[The Ruby 3.4 Coverage contract](https://docs.ruby-lang.org/en/3.4/Coverage.html)
defines ordinary lines as execution counts indexed by line, branches as nested maps,
and oneshot lines as executed line numbers. Ordinary `lines` and `oneshot_lines`
cannot run together. Methods and branches have their own result shapes and ownership
metadata; `eval` is an additional capability whose availability must be checked on each
supported version.

Oneshot is not an interchangeable optimization for per-example deltas. MRI's callback
removes the line event flag after its first observation. If example A and example B both
execute the same line, a run-wide oneshot first hit alone cannot establish B's dependency.
Clearing results must not be assumed to rearm it; see
[Bug #19715](https://bugs.ruby-lang.org/issues/19715). Resetting/recompiling between
examples changes execution and cannot be slipped in as an optimization. Counts preserve
repeat execution across examples; their delta semantics need to remain intact.

Coverage is process-global, not per-thread. Snapshot subtraction across example boundaries
can include other threads' execution. Rust neither creates missing attribution information
nor fixes parallel-example ambiguity. Preserve the project's conservative selection rules
and test explicit concurrency ownership rather than promising precise attribution.

### Public and internal boundaries

A normal extension can call Ruby's public Coverage methods and process their Ruby values.
The inspected [`internal/coverage.h`](https://github.com/ruby/ruby/blob/1f77afb8e8dc3b48acb3528a393f86d6d468e3f0/internal/coverage.h)
declares `rb_get_coverages` and other helpers inside a symbol-export section. In 3.3.10,
the declaration instead lives in
[`internal/thread.h`](https://github.com/ruby/ruby/blob/343ea050023cfc0374fdea6fdf625b2f57b716a4/internal/thread.h#L40),
outside that header's explicit export block; the newer header does not exist there.
The [3.3.10 implementation](https://github.com/ruby/ruby/blob/343ea050023cfc0374fdea6fdf625b2f57b716a4/thread.c#L5714)
returns the VM's internal coverage VALUE. On this installed Linux build,
`nm -D /home/sebastian/.local/share/rv/rubies/ruby-3.3.10/bin/ruby` reports exported
`T rb_get_coverages` and `T rb_set_coverages` symbols. That checks actual availability on
one build, not every distributor's shared-library/export configuration. Therefore it
would be inaccurate to say there are no exported native entry points. They are explicitly
**internal** APIs, however; export visibility is not an ABI or layout stability guarantee.
The hidden arrays, coverage indexes, method entries, instruction-sequence structures, and
VM event machinery are implementation details.

An extension might read these internals on a pinned MRI build without literally forking
MRI. Shipping that approach across 3.1–4.0 requires individual source/ABI validation and
packaging work; headers or symbols may differ. A stable selective snapshot or dirty-file
feed needs an upstream API or a maintained runtime patch. Replacing callbacks and compiler
instrumentation requires substantially deeper MRI integration. Copying `coverage.c` alone
is insufficient: it depends on VM-owned metadata and callbacks in other translation units.
MRI source licensing must follow its
[COPYING](https://github.com/ruby/ruby/blob/1f77afb8e8dc3b48acb3528a393f86d6d468e3f0/COPYING)
terms, including retained notices and the applicable Ruby/BSD licensing choices.

## Practical migration inventory

The baseline's `lib/testsift/tracker/coverage_adapter.rb` normalizes snapshots,
filters paths, unions before/after keys, compares line arrays, and creates changed-file
inputs. `loaded_files_tracker.rb` also obtains coverage file names; installation and final
reporting have other observation needs. These are separate from VM collection.

| Work | Rust feasibility | What remains / preferred first step |
| --- | --- | --- |
| Deduplicate identical-boundary peeks | Ruby orchestration first | Prove equivalent boundary timing and filter ownership; share one observation where valid. |
| Root-prefix filtering and mode normalization | Easy native loop | Public `peek_result` has already materialized excluded entries. Preserve encodings and user filter callbacks. |
| Union file keys and compare counters | Good bounded prototype | Keep previous counters in Rust-owned memory; handle new/missing files, nil entries, length changes and equal arrays exactly. |
| Retain snapshot state and file IDs | Useful with batching | Avoid round trips and temporary Ruby Sets; define reset/fork lifecycle and bounded memory. |
| Discover newly tracked files | Limited through public API | A Rust consumer of `peek_result.keys` cannot remove MRI's snapshot production; an upstream file-list API could. |
| Branch/method output conversion | Possible consumer optimization | Do not discard SimpleCov-owned branch/method output or fabricate nil/zero semantics. |
| Final report merging and serialization | Independent native batch candidate | Preserve the existing serialized contract; not evidence that per-example collection becomes faster. |
| File hashing for changed-file inputs | Batch candidate outside Coverage itself | Measure I/O versus hashing; reuse existing digest behavior and exact bytes/algorithm. |
| Native counter updates | Already native | A C-to-Rust translation is not a demonstrated algorithmic improvement. |
| Selective/dirty-file snapshot from VM | Largest structural opportunity, higher risk | Needs supported API or version-specific internals; patch the owning runtime rather than pretending bindings supply it. |
| Compile-time probes or custom Ruby VM | Technically possible, different product scope | Must prove instrumentation semantics and loader compatibility; no automatic equivalence to Coverage. |

A minimal seam is one batched `observe(snapshot)` operation per required boundary,
returning changed file IDs. Register paths once, hold primitive counters and nil masks
inside Rust, and construct Ruby Inputs only for changed files. Keep arbitrary Ruby filter
callbacks in Ruby unless their semantics can be preserved. This eliminates repeated Ruby
comparison/object construction, not MRI snapshot creation. Do not serialize each snapshot
to JSON merely to cross an in-process boundary. Benchmark direct GVL-held traversal against
copying to Rust-owned buffers and releasing the GVL: copying and crossing the boundary may
cost more than the comparison saved.

## Existing projects and fork targets

### Alternatives to per-example full Coverage snapshots

These mechanisms can collect overlapping file sets, but they answer different questions.
For arbitrary executable Ruby, none can be substituted solely because it finds the same
files in a simple method-call fixture. A safe replacement must demonstrate the required
dependency set, including conservative handling of observations it cannot attribute.

| Mechanism | Useful observation | Soundness and cost tradeoff |
| --- | --- | --- |
| `TracePoint(:line)` with `path` | Files executing Ruby statements during each example, including statements outside methods | Avoids full accumulated-counter snapshots but delivers an event for executed lines, potentially far more work in hot loops. A native callback may reduce Ruby callback cost, not event frequency. Track a per-example file set, preserve background-thread policy, and verify blocks, eval paths, hooks, JIT and interpreter behavior. It does not reproduce branch/method reports. |
| `TracePoint(:call, :b_call, :class)` | Ruby method/block entry and class/module body entry | Fewer events can be attractive, but top-level expressions and constant-only data dependencies can occur without the chosen events; class reopening and generated methods complicate attribution. An event subset is not a complete arbitrary-Ruby execution collector. |
| `$LOADED_FEATURES` differences plus `require`/`load` hooks | Newly required features and explicitly observed loads | Finds loader relationships and boot/shared dependencies cheaply relative to line snapshots, but an already-required file can execute in many later examples without appearing again. `load` re-executes rather than populating the require cache in the same way; eval need not be a filesystem feature. Associate boot-loaded files conservatively or retain execution observation. |
| `Method#source_location` / `UnboundMethod#source_location` | Ruby method definition filename and line | Useful for known invoked methods; enumerating definitions does not prove invocation. Native methods return nil; dynamically generated/eval definitions can have synthetic locations. Top-level code and ordinary constant reads are not method calls. |
| `Module#const_source_location` | A constant's definition location, including a class/module constant binding | Helps declaration/source indexing, not general execution tracing. A class can be reopened in multiple files; one constant binding location does not enumerate all contributing implementations. Definition location does not establish which example read the constant. |
| Static Ruby parsing plus explicit probes | Source obligations and execution evidence inserted at selected positions | Can avoid full snapshots and obtain richer events, but introduces a loader/compiler integration and must preserve arbitrary Ruby semantics. Supercov below is a concrete implementation to inspect, not proof of transparent compatibility. |

The event and path contracts above come from the
[Ruby 3.3 TracePoint documentation](https://docs.ruby-lang.org/en/3.3/TracePoint.html).
The method and constant distinctions follow the
[Method source-location contract](https://docs.ruby-lang.org/en/3.3/Method.html#method-i-source_location)
and [Module constant-source-location contract](https://docs.ruby-lang.org/en/3.3/Module.html#method-i-const_source_location).
The [Kernel loader contract](https://docs.ruby-lang.org/en/3.3/Kernel.html#method-i-require)
describes require's loaded-feature behavior and distinguishes load. The completeness and
cost judgments in the table are engineering inferences from those contracts, not measured
comparisons. Ordinary Coverage has its own gaps for nonexecuting constant dependencies;
these alternatives must be judged against the complete dependency model, not treated as
ways to infer reads they do not observe.

For TestSift, a practical experiment is **file-set TracePoint versus counter deltas**, with
the same conservative boot/shared-file handling and report compatibility. It is separate
from a Rust port: first establish correct event coverage, then measure Ruby and native
callback implementations. A loader-only or method-only approach is no-go as a universal
replacement unless the product deliberately restricts its supported Ruby behavior.

### A public native TracePoint backend is a distinct viable candidate

**Yes, in principle:** an optional MRI Rust extension can subscribe to public line events
and accumulate per-example file IDs without calling `Coverage.peek_result` or reading
private Coverage arrays. This is a different collector backend, not a port of Coverage.
In a dependency-only mode it could avoid global Coverage snapshots altogether. When a user
requests cumulative coverage output or SimpleCov already owns Coverage, leave stdlib
Coverage running separately and obtain its required reports at the existing reporting
boundaries. That coexistence pays both collectors' execution overhead; avoiding snapshots
does not establish a net improvement. Existing report defaults must not silently disappear.

One final global Coverage result does not recover per-example line deltas or historical
counts for skipped examples. A file-only prototype needs an explicit dependency-only
report contract, or must retain the existing line-delta adapter when those outputs are
requested. Eliminating every per-example snapshot while preserving all historical line
outputs requires a collector that provides that additional evidence.

The public header declares `rb_tracepoint_new`, `rb_tracepoint_enable/disable`,
`rb_tracearg_from_tracepoint` and `rb_tracearg_path`. Declaration/signature presence was
checked at these exact release revisions:

| Release inspected | Source revision and public header |
| --- | --- |
| 3.1.0 | [`fb4df44d1670e9d25aef6b235a7281199a177edb`](https://github.com/ruby/ruby/blob/fb4df44d1670e9d25aef6b235a7281199a177edb/include/ruby/debug.h) |
| 3.2.0 | [`a528908271c678360d2d8ca232c178e7cdd340b4`](https://github.com/ruby/ruby/blob/a528908271c678360d2d8ca232c178e7cdd340b4/include/ruby/debug.h) |
| 3.3.10 | [`343ea050023cfc0374fdea6fdf625b2f57b716a4`](https://github.com/ruby/ruby/blob/343ea050023cfc0374fdea6fdf625b2f57b716a4/include/ruby/debug.h#L423) |
| 3.4.0 | [`f45010833071b953744658842369e3496dfacb48`](https://github.com/ruby/ruby/blob/f45010833071b953744658842369e3496dfacb48/include/ruby/debug.h) |
| 4.0.0 | [`553f1675f3a9cece340b90f374a4245dccac2272`](https://github.com/ruby/ruby/blob/553f1675f3a9cece340b90f374a4245dccac2272/include/ruby/debug.h) |

The installed 3.3.10 executable exports all six functions above, verified with `nm -D`.
This is public C API source compatibility evidence across the supported MRI families,
not a promise that one binary supports every Ruby ABI, patch release, platform or binding
version. Build and test against each supported Ruby. The pinned
[rb-sys wrapper](https://github.com/oxidize-rb/rb-sys/blob/7ade413d4472453c24d0741af53c728f5902cb38/crates/rb-sys-build/src/bindings/wrapper.h)
includes `ruby/debug.h`; rb-sys can generate this surface, while Magnus can expose lifecycle
methods and typed state. No custom VM header/layout is needed. A binding compile/link smoke
test remains necessary; no extension has been built by this research.

Keep the first prototype deliberately small:

1. Create a retained TracePoint for normal `RUBY_EVENT_LINE` events, passing `Qnil` for the
   target-thread parameter. The 3.3.10 header labels that parameter unsupported; the
   implementation has an explicitly untested non-nil branch. Do not base thread ownership
   on that branch.
2. At each callback, obtain the ephemeral trace argument and path through public functions.
   Intern exact path bytes plus encoding policy into Rust-owned IDs; do not canonicalize,
   hash files, invoke arbitrary filters or perform filesystem I/O for every line. Return
   candidate IDs in one batch and apply existing Ruby path/filter/digest rules outside the
   callback. Cache only with a sound path identity strategy.
3. Use a per-file `last_seen_epoch` and append an ID only on its first hit in the current
   epoch. This bounds result storage to unique files while callbacks still occur for every
   executed line. Define epoch rollover explicitly. Keep enabled tracing stable during the
   run and change attribution epochs at example boundaries; repeated enable/disable can
   perturb JIT state.
4. Maintain a separate boot/shared collection before examples and conservative attribution
   for execution outside an owned example. Preserve require/load, data-file and declared
   dependency observers. A line collector cannot discover a constant's defining file merely
   because an example reads that already-created constant.

The 3.3.10 [implementation of trace arguments](https://github.com/ruby/ruby/blob/343ea050023cfc0374fdea6fdf625b2f57b716a4/vm_trace.c#L856)
returns current event state and resolves paths lazily. Never retain its pointer after the
callback. Treat nil and synthetic/eval paths explicitly. Copy path bytes before their
Ruby storage can move; never keep unrooted VALUEs or string-buffer pointers in Rust maps.
Retain the TracePoint and typed owner through marked Ruby references, account for compaction,
and disable/unregister before freeing the callback's `void *data`. A pointer to a moved Rust
object is equally unsafe; use stable owned storage with an explicit lifecycle.

Normal events allow Ruby APIs according to the public header, unlike internal allocation
events. The callback must remain on the Ruby execution thread under the appropriate VM
locking discipline; do not release the GVL while touching trace values. Avoid Ruby calls
that can raise across unprotected Rust frames: use reviewed binding protection or a tiny
C boundary where necessary. Prevent Rust panics crossing C ABI boundaries. Marking an
extension thread/ractor-safe is a separate proof obligation, not a performance switch.
Do not assume a single process-global epoch is correct with parallel examples, fibers or
background threads. Serial RSpec with process workers is the first bounded target;
ambiguous work must conservatively invalidate selection or fall back, not vanish.

JIT behavior is a material risk even with a cheap callback. In 3.3.10,
[`update_global_event_hook`](https://github.com/ruby/ruby/blob/343ea050023cfc0374fdea6fdf625b2f57b716a4/vm_trace.c#L131)
can invalidate YJIT/RJIT code on first instruction-sequence events. Its
[YJIT invalidation implementation](https://github.com/ruby/ruby/blob/343ea050023cfc0374fdea6fdf625b2f57b716a4/yjit/src/invariants.rs#L460)
routes execution back through tracing-aware execution. Native Rust callbacks do not bypass
that mechanism. Measure JIT-on and JIT-off total suite behavior; do not infer tracing costs
from callback body timing alone.

Unlike load-time source rewriting, line TracePoint needs no `load_iseq` hook. That reduces
loader integration surface but does not prove equivalence for preloaded code, Bootsnap,
eval, refinements or all interpreter event implementations. Include these in correctness
fixtures. On fork, reset/rebind owner state, epochs and IDs coherently in the child; never
share a parent worker's active example or rely on inherited Rust locks/background threads.
JRuby requires a different adapter and must retain the existing Ruby path. TruffleRuby's
C-extension compatibility is not proof that this callback/GC/thread model is supported;
keep it disabled there until independently validated.

The archived
[coverband_ext callback](https://github.com/danmayer/coverband_ext/blob/ec1b660b87d1b2f1f02eddcd00051e00285dc11b/ext/coverband_ext/coverband_ext.c#L60)
is historical evidence that native line-hook file collection is practical: it deliberately
uses older thread event hooks for Ruby 1.9 compatibility. It is not evidence for modern Rust
soundness or a maintained per-example backend. Prefer a new narrow public-API backend with
modern binding/lifecycle support over resurrecting its old private headers and assumptions.

**Bounded recommendation:** approve research/prototyping of this public native line-file
backend alongside batched snapshot comparison. Accept it only after (a) differential
dependency fixtures cover repeated shared-file execution, top-level code, hooks, lazy loads,
eval, constant/boot dependencies and failure paths; (b) SimpleCov branch/method reports stay
unchanged; (c) compile/link and lifecycle tests pass on MRI 3.1–4.0, including GC stress,
compaction, fork and JIT; (d) unsupported engines keep working; and (e) repeated end-to-end
benchmarks beat the improved stock backend within an agreed budget. Tests of deliberately
ambiguous concurrency must prove conservative behavior. No implementation or measured
speedup is claimed here. Do not make this the sole collector until those gates pass.

### Candidate assessment

Repository metadata and source revisions below were fetched with `gh api` on the research
date. Recent metadata is evidence of activity, not proof of reliability or compatibility.

| Project / inspected revision | License and status | Reuse decision |
| --- | --- | --- |
| [Magnus](https://github.com/matsadler/magnus/tree/d2a154c212397fbf29511aca37cabd67f8084c2e), `d2a154c…` | MIT; repository updated 2026-11-01; docs show 0.9.3 | Established Ruby/Rust extension bindings; suitable prototype foundation, not a coverage collector. |
| [rb-sys](https://github.com/oxidize-rb/rb-sys/tree/7ade413d4472453c24d0741af53c728f5902cb38), `7ade413…` | Apache-2.0 per repository metadata; updated 2026-09-23 | Low-level bindings/build tooling. Its stable-API machinery does not stabilize MRI's private Coverage structures. Check individual crate licensing before distribution. |
| [Supercov](https://github.com/supercorp-ai/supercov/tree/b1aafa07ce6be3a8697d1a5a7697e5ecb19b014d), `b1aafa0…` | MIT; updated 2026-10-30 | Concrete Rust/Ruby research target. Ruby support starts at 3.3, with fuller measurement at 3.4, outside TestSift's complete 3.1+ surface. Not a drop-in collector. |
| [SimpleCov](https://github.com/simplecov-ruby/simplecov/tree/a4529a4988cd27f9e391ed19a20c5202c62bfde0), `a4529a4…` | MIT; updated 2026-11-04 | Integration partner and reference for mode ownership and report semantics; not a Rust replacement for VM instrumentation. |
| [Coverband](https://github.com/danmayer/coverband/tree/2fd22d8a30cf3ea8a18153c3e99f8b0906bcf924), `2fd22d8…` | MIT; updated 2026-11-01 | Production coverage reference; its production sampling goals are not per-example dependency equivalence. |
| [coverband_ext](https://github.com/danmayer/coverband_ext/tree/ec1b660b87d1b2f1f02eddcd00051e00285dc11b), `ec1b660…` | MIT; archived, last push 2016-08-13; README explicitly deprecated | Historical C extension, not Rust. Reject as modern maintained fork foundation; README targets old Rubies and says modern Coverband does not need it. |
| [DeepCover](https://github.com/deep-cover/deep-cover/tree/b546819732ddb8a13aae135c012fc9c17ad00190), `b546819…` | MIT; last push 2022-02-19; README says minimal maintenance and missing Ruby 3.x syntax support | Source instrumentation alternative with intentionally different coverage semantics. Reject as reliable replacement across the supported matrix. |
| [Artichoke](https://github.com/artichoke/artichoke/tree/dbeb76f881d1729a08a3e970cf57c205dcbfc03a), `dbeb76f…` | MIT; updated 2026-11-03 | Rust/Ruby runtime, not a Coverage component injectable into MRI; replacing users' runtime is outside this optimization. |

Supercov deserves specific consideration. Its pinned
[`ruby_instrumenter.rs`](https://github.com/supercorp-ai/supercov/blob/b1aafa07ce6be3a8697d1a5a7697e5ecb19b014d/crates/supercov-engine/src/ruby_instrumenter.rs)
uses Ruby Prism to plan source probes. Its
[`supercov_runtime.rb`](https://github.com/supercorp-ai/supercov/blob/b1aafa07ce6be3a8697d1a5a7697e5ecb19b014d/runtime/ruby/supercov_runtime.rb)
starts stdlib Coverage, installs a `RubyVM::InstructionSequence.load_iseq` hook,
inserts probes, and writes evidence consumed by Rust. It explicitly deals with loader,
Ractor, refinement and uninstrumentable-source constraints. This is useful architecture to
study, but adopting it would require proving Bootsnap/load-hook coexistence, eval behavior,
source locations, branch semantics and every-example attribution. Source comments describe
performance observations from that project; they are not TestSift measurements and are not
used as speedup estimates here. License-compatible extraction of a small independently
needed component is preferable to maintaining a whole fork.

Other Rust coverage tools such as
[grcov](https://github.com/mozilla/grcov) process compiler-generated coverage artifacts.
They can help report aggregation, but they do not observe execution of Ruby source inside
MRI. LLVM coverage of MRI itself measures the interpreter's native code, not the Ruby
application's line dependencies.

[rbspy](https://github.com/rbspy/rbspy/tree/01bd053ef51d164243411c28d98eb4ac7c224cd3)
is a relevant maintained Rust tool: repository metadata reports MIT, not archived, and a
2026-11-04 push; its pinned Cargo manifest declares version 0.55.0 and MIT. Its
[README](https://github.com/rbspy/rbspy/blob/01bd053ef51d164243411c28d98eb4ac7c224cd3/README.md)
explicitly describes sampling running Ruby processes and warns that the Rust library API
is not stable. Reuse it for diagnostic profiling or study its
[stack-reading implementation](https://github.com/rbspy/rbspy/blob/01bd053ef51d164243411c28d98eb4ac7c224cd3/src/core/ruby_spy.rs),
not as the dependency collector: a method/file can execute entirely between samples, so
absence from sampled stacks cannot establish absence of an example dependency. Higher
sample frequency reduces that risk without eliminating it. Forking its sampling core
therefore does not meet no-false-negative selection; an exact event backend would replace
the central observation mechanism. Prefer the narrower public TracePoint prototype for
that requirement. No rbspy profiling was run during this research.

## Compatibility and reliability gates

The repository's stated surface is MRI 3.1, 3.2, 3.3, 3.4 and 4.0; JRuby 9.4 is gated;
TruffleRuby and Ruby head are best effort. Do not replace that policy with whatever versions
a candidate's current README supports.

- **MRI:** start with public Ruby values through Magnus/rb-sys. Test each supported Ruby
  ABI, operating-system/architecture target, GC compaction and JIT configuration. Private
  internals require a separate explicit support decision, not a silent fallback guess.
- **JRuby:** [JRuby is a JVM implementation](https://www.jruby.org/). MRI private pointers
  and instruction sequences do not exist there. Keep the Ruby Coverage adapter. A portable
  Rust computation core would need an independently validated JNI/FFI/process transport;
  a Magnus MRI extension is not that adapter.
- **TruffleRuby:** [its project](https://github.com/truffleruby/truffleruby) supports many
  C extensions, but that does not establish compatibility with an MRI-private extension.
  Preserve the pure Ruby path and validate public-API native support separately.

The [Magnus safety contract](https://docs.rs/magnus/0.9.3/magnus/) warns that Ruby objects
kept in Rust heap containers can escape Ruby GC's reach. Use owned primitive data or
properly marked Ruby typed data. Ruby APIs require the appropriate Ruby thread and GVL;
release the GVL only after copying the required values to Rust-owned memory. Keep all
Ruby API calls out of background Rust threads. Bound allocations, handle integer conversion
explicitly, prevent panics unwinding across FFI, and test interruption/error propagation.
A process crash cannot gracefully degrade after the fact, so safe boundaries matter more
than catching Ruby exceptions around the entry point.

Forked RSpec workers must not inherit stale parent snapshot IDs, locked Rust mutexes or
background-thread state. Never clear/stop Coverage owned by SimpleCov. On unsupported
platforms, installation/load failure, or recoverable backend failure, retain working Ruby
behavior and conservative test selection. Validate non-UTF-8 paths, nil counters, newly
loaded files, skipped examples, hooks, eval, multiple examples sharing a line, and
concurrent/background execution. These are semantic requirements, not optional benchmark
cases.

## Go / no-go experiment

1. Profile representative Rails and Ruby fixtures with separate timers/allocation samples
   for `peek_result`, filtering, counter comparison, hashing and final serialization.
   Record Ruby version, modes, file/line counts, examples, warm/cold state and repetitions.
2. Share redundant snapshots only where the observed boundary is identical. Verify the
   existing dependency/report output before introducing native code.
3. Prototype public-snapshot batched comparison. Compare total suite time, allocations,
   retained memory and boundary latency against the improved Ruby implementation. Include
   tiny suites where FFI/copy overhead dominates and large suites with many untouched files.
4. Proceed only if end-to-end improvement survives repeated measurements and the complete
   supported fallback matrix preserves output and failure behavior. Set a concrete minimum
   acceptable improvement from the project's actual benchmark budget before implementation;
   this research does not invent that number.
5. If snapshot production dominates, stop the consumer rewrite as the primary solution.
   Evaluate an upstream selective snapshot/file-list/delta API. Keep an MRI-internal proof
   of concept isolated until version support and maintenance ownership are explicit.
6. Reject a collector rewrite or project fork unless it demonstrates exact required
   attribution, supported syntax/loaders/engines, maintained licensing, reproducible
   packaging and a measured advantage over stock Coverage. A Rust label is not evidence.

## Search scope and limits

GitHub CLI repository searches (limit 30 each) included `ruby coverage language:Rust`,
`ruby coverage native`, `coverage ruby extension`, `coverage rust ruby`, plus targeted
`deep-cover` and `coverband_ext` searches. Web searches covered official Ruby Coverage docs,
Ruby's issue tracker, Ruby/Rust coverage collectors, Magnus, rb-sys and TruffleRuby. The
Rust-language query returned Supercov and a mutation-testing project, not an established
standalone MRI-compatible Rust collector. Several keyword searches returned no repositories;
that only describes those searches, not the whole ecosystem. Private/unindexed projects,
nonmatching descriptions and newer code can be missed. No exhaustive crate audit, native
prototype, supported-version source matrix or performance experiment was performed.

All project decisions above distinguish inspected source, maintainer claims and engineering
inference. Before adopting a candidate, repeat metadata/license checks and audit the exact
selected release and transitive licenses; branch revisions are reproducibility anchors,
not promises of long-term support.
