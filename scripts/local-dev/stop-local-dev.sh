#!/usr/bin/env bash
# Encerra PostgREST, backend e frontend iniciados por start-local-dev.sh.
pkill -f "webpack serve" 2>/dev/null || true
pkill -f "nest start" 2>/dev/null || true
pkill -x postgrest 2>/dev/null || true
echo "Serviços do ToolJet encerrados."
