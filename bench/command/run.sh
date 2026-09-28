#!/bin/sh
# Command-mode benchmark on this Mac: ./run.sh [case ids] [voices] [--asr=… --prompt --ac=512 --cases=…] (see main.swift).
# Needs Apple Intelligence on; Whisper modes need `brew install whisper-cpp` and models in ~/.cache/whisper.
set -e
cd "$(dirname "$0")"
mkdir -p .build
swiftc -O -o .build/bench main.swift ../../ios/App/CommandWriter.swift ../../ios/App/SpokenSymbols.swift ../../ios/App/ShellVocabulary.swift ../../ios/App/Cleaner.swift
.build/bench "$PWD" "$@"
