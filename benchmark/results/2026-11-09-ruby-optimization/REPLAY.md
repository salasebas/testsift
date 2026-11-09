# Replay the Ruby optimization comparison

Run from a checkout of this branch with Docker available. Use a fresh output path
for every replay.

```sh
LOCK=benchmark/results/2026-11-04-issue-20/stock/metadata.json
run() { task benchmark:evidence:docker -- task benchmark:evidence:current -- "$@"; }

for rev in 7d95a29 e225fbf bb26fc3; do
  run --revision $rev --fixtures ruby --corpus large --modes lines \
    --cases full,warm,input_fault --repetitions 3 --profiles 1 --output tmp/replay/large-$rev
done

for rev in 7d95a29 e225fbf; do
  run --revision $rev --fixtures rails --lockfiles $LOCK --modes lines,branches \
    --cases full,warm,changed_input,fault --repetitions 3 --profiles 1 --output tmp/replay/rails-$rev
  run --revision $rev --fixtures ruby --corpus sparse --modes lines,branches --workers 2 \
    --cases full,warm,input_fault,parallel_full --repetitions 3 --profiles 1 --output tmp/replay/sparse-$rev
  run --revision $rev --fixtures ruby --corpus eager --modes lines \
    --cases full,warm --repetitions 3 --profiles 1 --output tmp/replay/eager-$rev
done

for pass in 7d95a29:a e225fbf:b 7d95a29:c e225fbf:d; do
  run --revision ${pass%%:*} --fixtures rails --lockfiles $LOCK --modes lines \
    --cases full,warm --repetitions 5 --profiles 0 --output tmp/replay/rails-confirm-${pass%%:*}-${pass##*:}
done
```

The runtime study runs on the host with each interpreter's default gem paths:

```sh
R=~/.local/share/rv/rubies
ruby benchmark/evidence/runtime.rb \
  --rubies $R/ruby-3.3.10/bin/ruby,$R/ruby-3.4.12/bin/ruby,$R/ruby-4.0.9/bin/ruby,$R/ruby-4.1.0-preview1/bin/ruby \
  --output tmp/replay/runtime-macos.json
```
