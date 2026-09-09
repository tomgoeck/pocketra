#!/bin/sh
# Baut und startet den Headless-Test des Simulationskerns (kein Godot nötig).
# SAN=1 sim/tests/run.sh baut zusätzlich mit Address-/UndefinedBehavior-Sanitizer (~3× Laufzeit).
set -e
cd "$(dirname "$0")/.."
mkdir -p ../build/simtest
SAN_FLAGS=""
OUT=../build/simtest/test_sim
if [ "${SAN:-0}" != "0" ]; then
    SAN_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g"
    OUT=../build/simtest/test_sim_san
    echo "Sanitizer aktiv (ASan + UBSan)"
fi
# shellcheck disable=SC2086
clang++ -std=c++17 -O2 -Wall -Wextra $SAN_FLAGS -Iinclude src/*/*.cpp tests/test_sim.cpp -o "$OUT"
UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1 "$OUT"
