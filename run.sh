#!/bin/bash

if [[ "$#" -ne 2 ]]; then
      echo "Usage: $0 <neon_repo_path> <commit_range>"
          exit 1
fi

neon_repo=$1
commit_range=$2

results_prefix="./results/oltp_read_only_8thr_2m"

for commit_hash in $(git -C $neon_repo rev-list --reverse $commit_range); do
  commit_date=$(TZ=UTC0 git -C $neon_repo show -s --date=format-local:'%Y%m%d-%H%M%S' --format=%cd $commit_hash)
  echo "Running benchmark for commit ${commit_hash} with date ${commit_date}..."

  need_test=false
  for i in $(seq 1 3); do
    fn="${results_prefix}/${commit_date}_${commit_hash}_${i}.out"
    if [ ! -f $fn ]; then
      need_test=true
      break
    fi
  done

  if [ "$need_test" = false ]; then
    echo "Commit ${commit_hash} already tested"
    continue
  fi


  pushd $neon_repo
  git checkout $commit_hash
  cargo build --release --bin pageserver
  popd


  for i in $(seq 1 3); do
    fn="${results_prefix}/${commit_date}_${commit_hash}_${i}.out"
    if [ -f $fn ]; then
      echo "Commit's ${commit_hash} iteration ${i} already tested"
      continue
    fi

    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches

    "${neon_repo}/target/release/pageserver" -D /data/ &
    ps_process=$!

    ./warmup.sh

    ./sysbench.sh $fn

    kill -9 $ps_process
    wait $ps_process
  done

done

if git status results/ | grep -q Untracked ; then
  ./plot.r
  git add results results.md tps.svg latency.svg
  git commit -m "add results till $(git -C $neon_repo rev-parse --short HEAD)"
fi
