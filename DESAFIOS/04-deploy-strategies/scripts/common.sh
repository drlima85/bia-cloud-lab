#!/usr/bin/env bash
# ==============================================================================
# common.sh — Módulo Compartilhado de Utilidades, Segurança e Ambientes ECS
# Projeto: BIA Cloud Lab — Formação AWS / D2NS
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================

set -euo pipefail

# Diretório base dos scripts
COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$COMMON_SCRIPT_DIR/deploy.conf"

# Carregamento opcional de variáveis de ambiente locais (.env)
if [[ -f "$COMMON_SCRIPT_DIR/../.env" ]]; then
  # shellcheck source=/dev/null
  set -a
  source "$COMMON_SCRIPT_DIR/../.env"
  set +a
elif [[ -f "$COMMON_SCRIPT_DIR/.env" ]]; then
  # shellcheck source=/dev/null
  set -a
  source "$COMMON_SCRIPT_DIR/.env"
  set +a
fi

# Carregamento do arquivo de configuração central
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# Constante de segurança mandatória: Conta AWS autorizada do laboratório
# Para segurança em repositórios públicos, NÃO há ID real hardcoded como fallback.
# Deve ser configurada via AUTHORIZED_ACCOUNT ou AWS_ACCOUNT_ID no ambiente ou em .env.
AUTHORIZED_ACCOUNT="${AUTHORIZED_ACCOUNT:-${AWS_ACCOUNT_ID:-}}"

# Configurações padrão com fallback seguro
DEFAULT_ENV="${DEFAULT_ENV:-app}"
DEFAULT_REGION="${AWS_REGION:-${DEFAULT_REGION:-us-east-2}}"
DEFAULT_PROFILE="${AWS_PROFILE:-${DEFAULT_PROFILE:-agy-aws-lab}}"
DEFAULT_ECR_REPO="${DEFAULT_ECR_REPO:-bia-cloud-lab}"
DEFAULT_TIMEOUT="${DEFAULT_TIMEOUT:-600}"

# Variáveis ativas globais
PROFILE="$DEFAULT_PROFILE"
REGION="$DEFAULT_REGION"
ECR_REPO="$DEFAULT_ECR_REPO"
DRY_RUN=false
TARGET_ENV="$DEFAULT_ENV"

# Cores e formatação para terminal
C_BLUE="\033[0;34m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[1;33m"
C_RED="\033[0;31m"
C_CYAN="\033[0;36m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

log_info()    { echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $*"; }
log_warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_error()   { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; }
log_step()    { echo -e "\n${C_CYAN}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }

# Diretório temporário seguro com limpeza automática
TEMP_DIR=$(mktemp -d)
common_cleanup() {
  rm -rf "$TEMP_DIR"
}
trap common_cleanup EXIT INT TERM

# ==============================================================================
# FUNÇÕES DE GOVERNANÇA E FORMATAÇÃO
# ==============================================================================

log_governance_dry_run_notice() {
  echo ""
  log_info "[NOTA DE GOVERNANÇA] A validação em modo --dry-run valida regras sintáticas, argumentos e templates locais, mas NÃO substitui a homologação empírica com recursos ativos na nuvem."
}

format_registered_at() {
  local raw="$1"
  if [[ -z "$raw" || "$raw" == "null" || "$raw" == "N/A" ]]; then
    echo "N/A"
  elif [[ "$raw" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    local sec="${raw%%.*}"
    date -u -d "@$sec" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$raw"
  else
    echo "$raw" | cut -d'.' -f1 | tr 'T' ' ' | cut -c 1-16
  fi
}

resolve_git_info() {
  export GIT_DISCOVERY_ACROSS_FILESYSTEM=1
  local cur_dir="$COMMON_SCRIPT_DIR"
  local found_root=""

  while [[ "$cur_dir" != "/" ]]; do
    if [[ -d "$cur_dir/.git" ]]; then
      found_root="$cur_dir"
      break
    fi
    cur_dir=$(dirname "$cur_dir")
  done

  GIT_REPO_ROOT="$found_root"
  if [[ -n "$found_root" ]] && command -v git &>/dev/null; then
    GIT_SHORT_HASH=$(git -C "$found_root" rev-parse --short=7 HEAD 2>/dev/null || echo "")
  elif command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
    GIT_SHORT_HASH=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "")
  else
    GIT_SHORT_HASH=""
  fi
}

is_dockerignored() {
  local filepath="$1"
  local d_file="$2"
  [[ ! -f "$d_file" ]] && return 1

  local basename_file
  basename_file="$(basename "$filepath")"

  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    pattern="${pattern%%#*}"
    pattern="$(echo "$pattern" | tr -d '\r' | xargs)"
    [[ -z "$pattern" ]] && continue

    local clean_pat="${pattern%/}"

    # Casamento direto de caminho, prefixo ou basename
    if [[ "$filepath" == $clean_pat || "$filepath" == $clean_pat/* || "$basename_file" == $clean_pat ]]; then
      return 0
    fi
    # Casamento em qualquer subdiretório
    if [[ "$filepath" == */$clean_pat/* || "$filepath" == */$clean_pat ]]; then
      return 0
    fi
  done < "$d_file"

  return 1
}

is_non_app_directory() {
  local filepath="$1"
  case "$filepath" in
    DESAFIOS/*|.agents/*|.kiro/*|.github/*|docs/*|n8n-lab/*|backups/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_environment() {
  local env_name="$1"
  case "$env_name" in
    app)
      TARGET_ENV="app"
      ENV_DESC="${ENV_APP_DESC:-Ambiente Principal BIA Cloud App (ALB + EC2)}"
      CLUSTER="${ENV_APP_CLUSTER:-cluster-bia-app}"
      SERVICE="${ENV_APP_SERVICE:-service-bia-cloud-app}"
      TASK_FAMILY="${ENV_APP_TASK_FAMILY:-task-def-bia-cloud-app}"
      CONTAINER_NAME="${ENV_APP_CONTAINER_NAME:-bia-cloud-app}"
      ALB_URL="${ENV_APP_ALB_URL:-http://localhost:8080/api/versao}"
      HOMOLOGATED_BASELINE="${ENV_APP_HOMOLOGATED_BASELINE:-15}"
      ;;
    alb)
      TARGET_ENV="alb"
      ENV_DESC="${ENV_ALB_DESC:-Ambiente Secundário BIA Cloud ALB}"
      CLUSTER="${ENV_ALB_CLUSTER:-cluster-bia-app}"
      SERVICE="${ENV_ALB_SERVICE:-service-bia-cloud-alb}"
      TASK_FAMILY="${ENV_ALB_TASK_FAMILY:-task-def-bia-cloud-alb}"
      CONTAINER_NAME="${ENV_ALB_CONTAINER_NAME:-bia-cloud-alb}"
      ALB_URL="${ENV_ALB_ALB_URL:-http://localhost:8080/}"
      HOMOLOGATED_BASELINE="${ENV_ALB_HOMOLOGATED_BASELINE:-1}"
      ;;
    didatico)
      TARGET_ENV="didatico"
      ENV_DESC="${ENV_DIDATICO_DESC:-Ambiente Didático Teórico Formação AWS}"
      CLUSTER="${ENV_DIDATICO_CLUSTER:-cluster-bia}"
      SERVICE="${ENV_DIDATICO_SERVICE:-service-bia}"
      TASK_FAMILY="${ENV_DIDATICO_TASK_FAMILY:-task-def-bia}"
      CONTAINER_NAME="${ENV_DIDATICO_CONTAINER_NAME:-bia}"
      ALB_URL="${ENV_DIDATICO_ALB_URL:-http://localhost:8080/api/versao}"
      HOMOLOGATED_BASELINE="${ENV_DIDATICO_HOMOLOGATED_BASELINE:-1}"
      ;;
    *)
      log_error "Ambiente inválido: '$env_name'."
      echo "Ambientes suportados:"
      echo "  - app      : Cluster cluster-bia-app / Service service-bia-cloud-app (Padrão)"
      echo "  - alb      : Cluster cluster-bia-app / Service service-bia-cloud-alb"
      echo "  - didatico : Cluster cluster-bia / Service service-bia (Teórico)"
      exit 1
      ;;
  esac
}

# Inicializa variáveis com o ambiente padrão
load_environment "$DEFAULT_ENV"
