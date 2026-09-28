#!/bin/bash
# ./compare.sh <tag> [bench options]: builds, runs the 4 voices in parallel, prints each voice's scores.
cd "$(dirname "$0")"
mkdir -p .build
tag=$1; shift
swiftc -O -o .build/bench main.swift ../../ios/App/CommandWriter.swift ../../ios/App/SpokenSymbols.swift ../../ios/App/ShellVocabulary.swift ../../ios/App/Cleaner.swift
for v in Samantha Reed Aman Tara; do .build/bench "$PWD" "$@" $v > .build/cmp-$tag-$v.txt 2>&1 & done
wait
for v in Samantha Reed Aman Tara; do printf "%-24s %-9s %s\n" "$tag" $v "$(grep -E '^\+ spoken|^CommandWriter  ' .build/cmp-$tag-$v.txt | tr -s ' ' | tr '\n' ' ')"; done
