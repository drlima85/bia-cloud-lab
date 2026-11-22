#!/usr/bin/env bash
# ==============================================================================
# deploy-pipeline.sh — Wrapper de Compatibilidade para a CLI Unificada deploy-ecs.sh
# Projeto: BIA Cloud Lab — Formação AWS / D2NS
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================
# Este script delega a execução diretamente para:
#   ./deploy-ecs.sh deploy "$@"
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/deploy-ecs.sh" deploy "$@"
