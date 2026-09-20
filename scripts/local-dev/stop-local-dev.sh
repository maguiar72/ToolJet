#!/usr/bin/env bash
# Encerra PostgREST, backend e frontend iniciados por start-local-dev.sh.
pkill -f "[w]ebpack serve|[n]pm start" 2>/dev/null || true
pkill -f "[n]est start|[s]tart:dev" 2>/dev/null || true
pkill -x postgrest 2>/dev/null || true
echo "Serviços do ToolJet encerrados."
