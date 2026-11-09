# Replay the issue #21 comparison

Run from a checkout of this branch with Docker available. Each command builds the
pinned Linux image, installs Linux gems into the `testsift-evidence-bundle`
volume, and archives the named engine revision into a new output directory.
Use a fresh output path for every replay.

```sh
LOCK=benchmark/results/2026-11-04-issue-20/stock/metadata.json
run() { task benchmark:evidence:docker -- task benchmark:evidence:current -- "$@"; }

for rev in e225fbf fb36816 bb26fc3; do
  run --revision $rev --fixtures rails --lockfiles $LOCK --modes lines,branches \
    --cases full,warm,changed_input,fault --repetitions 3 --profiles 1 --output tmp/replay/rails-$rev
  run --revision $rev --fixtures ruby --corpus large --modes lines \
    --cases full,warm,input_fault --repetitions 3 --profiles 1 --output tmp/replay/large-$rev
done

for rev in e225fbf bb26fc3; do
  run --revision $rev --fixtures ruby --corpus sparse --modes lines,branches --workers 2 \
    --cases full,warm,input_fault,parallel_full --repetitions 3 --profiles 1 --output tmp/replay/sparse-$rev
done

for pass in bb26fc3:a e225fbf:b bb26fc3:c; do
  run --revision ${pass%%:*} --fixtures ruby --corpus large --modes lines \
    --cases warm,input_fault --repetitions 5 --profiles 0 --output tmp/replay/large-warm-${pass%%:*}-${pass##*:}
done
```

The published dataset names match these output names. `large-e225fbf-r2` is a
second run of the large baseline command. The first two Rails campaigns also
requested `parallel_full`; the driver excludes that cell for the Rails fixture,
so it produced no rows.

On macOS without Docker, replace `run` with
`task benchmark:evidence:current -- "$@"` to compare revisions natively. Native
macOS rows use BSD `time -l`, `getrusage`, and malloc-zone samples, and are not
comparable with Linux rows.
