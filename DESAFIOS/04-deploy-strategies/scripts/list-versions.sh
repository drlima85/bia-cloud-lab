#!/usr/bin/env bash
# ==============================================================================
# list-versions.sh — Listagem Real de Revisões da Task Definition no Amazon ECS
# Projeto: BIA Cloud Lab — Formação AWS / D2NS
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================
# Uso:
#   ./list-versions.sh [-E app|alb] [--limit 10] [--dry-run]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

limit=10

show_help() {
  cat << EOF
$(basename "$0") — Listagem de Revisões da Task Definition no Amazon ECS

USO:
  $(basename "$0") [OPÇÕES]

OPÇÕES:
  -E, --env NOME             Ambiente alvo [app | alb | didatico] (padrão: $DEFAULT_ENV)
  -p, --profile PERFIL       Perfil AWS CLI (padrão: $DEFAULT_PROFILE)
  -r, --region REGIAO        Região AWS (padrão: $DEFAULT_REGION)
  -c, --cluster CLUSTER      Override manual do Cluster ECS
  -s, --service SERVICO      Override manual do Serviço ECS
  -f, --task-family FAMILIA  Override manual da Família da Task Definition
      --container-name NOME  Override manual do Nome do Contêiner
      --limit NUM            Número máximo de revisões a listar (padrão: 10)
      --dry-run              Modo simulação: exibe consulta ou mock offline seguro
  -h, --help                 Exibe esta mensagem de ajuda

EXEMPLO:
  $(basename "$0")
  $(basename "$0") -E alb --limit 5
  $(basename "$0") --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -E|--env) load_environment "$2"; shift 2 ;;
    -p|--profile) PROFILE="$2"; shift 2 ;;
    -r|--region) REGION="$2"; shift 2 ;;
    -c|--cluster) CLUSTER="$2"; shift 2 ;;
    -s|--service) SERVICE="$2"; shift 2 ;;
    -f|--task-family) TASK_FAMILY="$2"; shift 2 ;;
    --container-name) CONTAINER_NAME="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    -l|--list) shift 1 ;;
    --dry-run) DRY_RUN=true; shift 1 ;;
    -h|--help) show_help; exit 0 ;;
    *) log_error "Opção desconhecida: $1"; show_help; exit 1 ;;
  esac
done

log_step "Listagem de Revisões da Task Definition no ECS"
log_info "Ambiente:      $TARGET_ENV ($ENV_DESC)"
log_info "Cluster / Svc: $CLUSTER / $SERVICE"
log_info "Task Family:   $TASK_FAMILY"
log_info "Perfil / Reg:  $PROFILE / $REGION"

AWS_CMD=(aws --profile "$PROFILE" --region "$REGION")

caller_identity=""
caller_identity=$("${AWS_CMD[@]}" sts get-caller-identity --output json 2>/dev/null || true)

if [[ -z "$caller_identity" ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    log_warn "[DRY-RUN SIMULADO - AMBIENTE OFFLINE / MOCK DIDÁTICO]"
    log_warn "AVISO: Sessão AWS STS inativa. Exibindo dados simulados de referência (mock). Nenhum dado foi confirmado na AWS."
    echo ""
    echo "==================================================================================================================="
    printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" "REVISÃO" "STATUS" "DATA REGISTRO(UTC)" "IMAGEM / TAG ECR" "SITUAÇÃO NO SERVIÇO"
    echo "==================================================================================================================="
    if [[ "$TARGET_ENV" == "app" ]]; then
      printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" ":16" "ACTIVE" "2026-11-20 18:45" "bia-cloud-lab:elasticache-v2 [Exit 1]" "⚠️ [FALHA INDUZIDA FASE 2]"
      printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" ":15" "ACTIVE" "2026-11-19 14:10" "bia-cloud-lab:elasticache-v2" "--> [ATIVA NO SERVIÇO]"
      printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" ":14" "INACTIVE" "2026-11-18 20:00" "bia-cloud-lab:rolling-purple-v1" ""
      printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" ":13" "INACTIVE" "2026-11-18 16:30" "bia-cloud-lab:4.2.0" ""
    else
      printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" ":SIM-2" "ACTIVE" "2026-11-20 12:00" "$ECR_REPO:simulated-v2" "--> [SIMULADA ATIVA NO SERVIÇO]"
      printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" ":SIM-1" "INACTIVE" "2026-11-19 10:00" "$ECR_REPO:simulated-v1" "[SIMULADA ANTERIOR]"
    fi
    echo "==================================================================================================================="
    log_governance_dry_run_notice
    exit 0
  else
    log_error "FALHA DE AUTENTICAÇÃO: Não foi possível obter caller identity para o perfil '$PROFILE'."
    log_error "A sessão STS expirou ou as credenciais temporárias são inválidas."
    log_info "Ação necessária: Execute 'aws login --profile $PROFILE' com MFA antes de prosseguir."
    exit 1
  fi
fi

# Validação estrita da conta AWS autorizada
caller_account=$(echo "$caller_identity" | jq -r '.Account // empty')
if [[ "$DRY_RUN" == false ]]; then
  if [[ -z "$AUTHORIZED_ACCOUNT" ]]; then
    log_error "CONFIGURAÇÃO DE SEGURANÇA MANDATÓRIA: Nenhuma conta AWS autorizada foi definida."
    log_error "Defina 'AUTHORIZED_ACCOUNT' ou 'AWS_ACCOUNT_ID' via variável de ambiente ou arquivo .env."
    exit 1
  fi
  if [[ "$caller_account" != "$AUTHORIZED_ACCOUNT" ]]; then
    log_error "CONTA NÃO AUTORIZADA: A identidade STS atual pertence à conta '$caller_account', mas a única conta autorizada configurada é '$AUTHORIZED_ACCOUNT'."
    exit 1
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  log_info "[DRY-RUN - CONSULTA READ-ONLY REAL NO ECS (SEM ALTERAÇÕES)]"
else
  log_info "[CONSULTA REAL - DADOS OBTIDOS DIRETAMENTE DO AMAZON ECS CONTROL PLANE]"
fi

# Obter a revisão ativa no serviço
ACTIVE_TASK_DEF_ARN=$("${AWS_CMD[@]}" ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query 'services[0].taskDefinition' \
  --output text 2>/dev/null || echo "")

ACTIVE_REVISION=""
if [[ -n "$ACTIVE_TASK_DEF_ARN" && "$ACTIVE_TASK_DEF_ARN" != "None" ]]; then
  ACTIVE_REVISION=$(echo "$ACTIVE_TASK_DEF_ARN" | awk -F':' '{print $NF}')
fi

# Obter lista de revisões da família
TASK_DEF_ARNS=$("${AWS_CMD[@]}" ecs list-task-definitions \
  --family-prefix "$TASK_FAMILY" \
  --sort DESC \
  --max-items "$limit" \
  --query 'taskDefinitionArns' \
  --output json 2>/dev/null || echo "[]")

count=$(echo "$TASK_DEF_ARNS" | jq '. | length')
if [[ "$count" -eq 0 ]]; then
  log_warn "Nenhuma Task Definition encontrada para a família '$TASK_FAMILY'."
  exit 0
fi

echo ""
echo "==================================================================================================================="
printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" "REVISÃO" "STATUS" "DATA REGISTRO(UTC)" "IMAGEM / TAG ECR" "SITUAÇÃO NO SERVIÇO"
echo "==================================================================================================================="

for arn in $(echo "$TASK_DEF_ARNS" | jq -r '.[]'); do
  rev=$(echo "$arn" | awk -F':' '{print $NF}')

  desc_json=$("${AWS_CMD[@]}" ecs describe-task-definition --task-definition "$arn" --output json 2>/dev/null || echo "{}")
  status=$(echo "$desc_json" | jq -r '.taskDefinition.status // "UNKNOWN"')
  raw_registered_at=$(echo "$desc_json" | jq -r '.taskDefinition.registeredAt // "N/A"')
  reg_date=$(format_registered_at "$raw_registered_at")
  image=$(echo "$desc_json" | jq -r '.taskDefinition.containerDefinitions[0].image // "N/A"' | awk -F'/' '{print $NF}')

  marker=""
  if [[ "$rev" == "$ACTIVE_REVISION" ]]; then
    marker="--> [ATIVA NO SERVIÇO]"
  elif [[ "$rev" == "16" && "$TASK_FAMILY" == "task-def-bia-cloud-app" ]]; then
    marker="⚠️ [FALHA INDUZIDA FASE 2]"
  fi

  printf "%-9s | %-8s | %-18s | %-45s | %-22s\n" ":$rev" "$status" "$reg_date" "$image" "$marker"
done
echo "==================================================================================================================="
echo ""

if [[ "$DRY_RUN" == true ]]; then
  log_governance_dry_run_notice
fi
