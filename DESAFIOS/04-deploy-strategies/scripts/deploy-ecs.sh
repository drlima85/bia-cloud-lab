#!/usr/bin/env bash
# ==============================================================================
# deploy-ecs.sh — CLI Unificada e Fachada de Compatibilidade no Amazon ECS
# Projeto: BIA Cloud Lab — Formação AWS / D2NS
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================
# Este script atua como ponto de entrada unificado, delegando para os scripts
# especializados da arquitetura modular:
#   - deploy            -> scripts/deploy.sh
#   - rollback          -> scripts/rollback.sh
#   - list              -> scripts/list-versions.sh
#   - check-availability-> scripts/check-availability.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat << EOF
deploy-ecs.sh — CLI Unificada de Deploy e Resiliência no Amazon ECS

USO:
  $(basename "$0") <COMANDO> [OPÇÕES]

COMANDOS DISPONÍVEIS:
  deploy              Compila imagem Docker, publica no ECR e atualiza o serviço ECS (padrão)
  rollback            Reverte o serviço diretamente para uma revisão anterior da Task Def
  list                Lista as revisões reais da Task Definition no ECS com registeredAt e ativa
  check-availability  Monitora a disponibilidade e latência contínua do endpoint ALB
  help                Exibe esta mensagem de ajuda

Para ajuda específica de cada comando:
  $(basename "$0") deploy --help
  $(basename "$0") rollback --help
  $(basename "$0") list --help
  $(basename "$0") check-availability --help
EOF
}

MAIN_COMMAND="deploy"
if [[ $# -gt 0 ]]; then
  case "$1" in
    deploy) MAIN_COMMAND="deploy"; shift 1 ;;
    rollback) MAIN_COMMAND="rollback"; shift 1 ;;
    list|list-versions) MAIN_COMMAND="list"; shift 1 ;;
    check-availability) MAIN_COMMAND="check-availability"; shift 1 ;;
    help|-h|--help) show_help; exit 0 ;;
    -*) MAIN_COMMAND="deploy" ;;
    *) echo "[ERROR] Comando inválido: $1" >&2; show_help; exit 1 ;;
  esac
fi

case "$MAIN_COMMAND" in
  deploy) exec "$SCRIPT_DIR/deploy.sh" "$@" ;;
  rollback) exec "$SCRIPT_DIR/rollback.sh" "$@" ;;
  list) exec "$SCRIPT_DIR/list-versions.sh" "$@" ;;
  check-availability) exec "$SCRIPT_DIR/check-availability.sh" "$@" ;;
  *) show_help; exit 1 ;;
esac
