# Replay the current-engine campaign

Run these commands from the repository root with the pinned Ruby and root bundle.
Set `BUNDLE_PATH` to a writable installed gem directory. Every output must be new.
Setup and oracle runs are additional to the measured samples.

The engine revision and dependency lockfiles are explicit. Published driver hashes
identify the measured source at the commits linked in [REPORT.md](REPORT.md).
The current driver includes a replay-only correction: it adds corpus dependencies
before the first Bundler install. This preserves retained lock entries and permits
frozen Bundler. The timed commands and bootstrap code are unchanged. New replay
metadata records the corrected driver's hash; the original campaign hashes remain
unchanged. Use the current Taskfile mapping below rather than the historical task
name recorded in controller logs.

## dense-msgpack

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus dense --modes lines --cases full,warm --serializer msgpack --repetitions 3 --profiles 1 --output tmp/issue20-replay-dense-msgpack --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/dense-msgpack/metadata.json
```

## dense-sqlite

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus dense --modes lines --cases full,warm --backend sqlite --repetitions 3 --profiles 1 --output tmp/issue20-replay-dense-sqlite --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/dense-sqlite/metadata.json
```

## dense

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus dense --cases full,warm,input_fault --repetitions 3 --profiles 1 --output tmp/issue20-replay-dense --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/dense/metadata.json
```

## eager

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus eager --cases full,warm,input_fault --repetitions 3 --profiles 1 --output tmp/issue20-replay-eager --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/eager/metadata.json
```

## large-workers-4

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus large --modes dependency --cases parallel_full --workers 4 --repetitions 3 --profiles 1 --output tmp/issue20-replay-large-workers-4 --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/large-workers-4/metadata.json
```

## large

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus large --cases plain,coverage_control,full,warm,input_fault --repetitions 3 --profiles 1 --output tmp/issue20-replay-large --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/large/metadata.json
```

## sparse

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus sparse --cases full,warm,input_fault --repetitions 3 --profiles 1 --output tmp/issue20-replay-sparse --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/sparse/metadata.json
```

## startup-dry

```sh
task benchmark:evidence:startup -- --modes lines --cases unwrapped_plain --repetitions 3 --profiles 0 --output tmp/issue20-replay-startup-dry --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/startup-dry/metadata.json
```

## startup-large-dry

```sh
task benchmark:evidence:startup -- --fixtures ruby --corpus large --modes dependency --cases unwrapped_plain --repetitions 3 --profiles 0 --output tmp/issue20-replay-startup-large-dry --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/startup-large-dry/metadata.json
```

## startup

```sh
task benchmark:evidence:memory -- --modes lines --cases plain,unwrapped_plain --repetitions 3 --profiles 0 --output tmp/issue20-replay-startup --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/startup/metadata.json
```

## stock

```sh
task benchmark:evidence:memory -- --repetitions 3 --profiles 1 --output tmp/issue20-replay-stock --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/stock/metadata.json
```

## timing-dense

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus dense --cases full,warm --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-dense --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-dense/metadata.json
```

## timing-eager

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus eager --cases full,warm --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-eager --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-eager/metadata.json
```

## timing-large-workers-4

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus large --modes dependency --cases parallel_full --workers 4 --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-large-workers-4 --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-large-workers-4/metadata.json
```

## timing-large

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus large --cases full,warm --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-large --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-large/metadata.json
```

## timing-probe

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus large --modes lines --cases full,warm --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-probe --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-probe/metadata.json
```

## timing-sparse

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus sparse --cases full,warm --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-sparse --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-sparse/metadata.json
```

## timing-stock

```sh
task benchmark:evidence:current -- --cases full,warm --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-stock --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-stock/metadata.json
```

## timing-workers-1

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus sparse --modes dependency --cases parallel_full --workers 1 --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-workers-1 --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-workers-1/metadata.json
```

## timing-workers-2

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus sparse --modes dependency --cases parallel_full --workers 2 --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-workers-2 --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-workers-2/metadata.json
```

## timing-workers-4

```sh
task benchmark:evidence:current -- --fixtures ruby --corpus sparse --modes dependency --cases parallel_full --workers 4 --repetitions 0 --profiles 1 --output tmp/issue20-replay-timing-workers-4 --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/timing-workers-4/metadata.json
```

## workers-1

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus sparse --modes dependency --cases parallel_full --workers 1 --repetitions 3 --profiles 1 --output tmp/issue20-replay-workers-1 --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/workers-1/metadata.json
```

## workers-2

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus sparse --modes dependency --cases parallel_full --workers 2 --repetitions 3 --profiles 1 --output tmp/issue20-replay-workers-2 --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/workers-2/metadata.json
```

## workers-4

```sh
task benchmark:evidence:memory -- --fixtures ruby --corpus sparse --modes dependency --cases parallel_full --workers 4 --repetitions 3 --profiles 1 --output tmp/issue20-replay-workers-4 --revision e225fbf240f9828e922aa48f8fd59632dfeab4b0 --lockfiles benchmark/results/2026-11-04-issue-20/workers-4/metadata.json
```

## Runtime comparison

Replace the installed Ruby binary paths when replaying on another host.

```sh
task benchmark:evidence:runtime -- --rubies /home/sebastian/.local/share/rv/rubies/ruby-3.3.10/bin/ruby,/home/sebastian/.local/share/rv/rubies/ruby-3.4.12/bin/ruby,/home/sebastian/.local/share/rv/rubies/ruby-4.0.9/bin/ruby --output tmp/issue20-replay-runtime.json
```
