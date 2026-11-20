#!/usr/bin/env bash
# ==============================================================================
# Script Parametrizado de Rollback no Amazon ECS — Projeto BIA
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================
# Uso:
#   ./rollback.sh -t <TAG_ANTERIOR> [OPTIONS]
# ==============================================================================

set -euo pipefail

DEFAULT_REGION="us-east-1"
DEFAULT_ECR_REPO="bia"
DEFAULT_CLUSTER="cluster-bia"
DEFAULT_SERVICE="service-bia"
DEFAULT_TASK_FAMILY="task-def-bia"

REGION="${AWS_REGION:-$DEFAULT_REGION}"
ECR_REPO="${ECR_REPO:-$DEFAULT_ECR_REPO}"
CLUSTER="${ECS_CLUSTER:-$DEFAULT_CLUSTER}"
SERVICE="${ECS_SERVICE:-$DEFAULT_SERVICE}"
TASK_FAMILY="${TASK_FAMILY:-$DEFAULT_TASK_FAMILY}"
TARGET_TAG="${TARGET_TAG:-}"

log_info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
log_warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

show_help() {
  cat << EOF
Uso: $(basename "$0") -t <TAG_DESTINO> [OPÇÕES]

Opções:
  -t, --tag TAG               Tag ou commit hash estável para rollback (obrigatório)
  -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
  -e, --ecr-repo REPO         Nome do repositório ECR (padrão: $DEFAULT_ECR_REPO)
  -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
  -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
  -f, --task-family FAMILY    Família da Task Definition (padrão: $DEFAULT_TASK_FAMILY)
  -l, --list-versions         Lista as últimas 10 versões disponíveis no ECR e sai
  -h, --help                  Exibe esta mensagem de ajuda

Exemplo:
  ./rollback.sh -t a1b2c3d -r us-east-1 -c cluster-bia -s service-bia
EOF
}

LIST_VERSIONS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag) TARGET_TAG="$2"; shift 2 ;;
    -r|--region) REGION="$2"; shift 2 ;;
    -e|--ecr-repo) ECR_REPO="$2"; shift 2 ;;
    -c|--cluster) CLUSTER="$2"; shift 2 ;;
    -s|--service) SERVICE="$2"; shift 2 ;;
    -f|--task-family) TASK_FAMILY="$2"; shift 2 ;;
    -l|--list-versions) LIST_VERSIONS=true; shift 1 ;;
    -h|--help) show_help; exit 0 ;;
    *) log_error "Opção desconhecida: $1"; show_help; exit 1 ;;
  esac
done

# Verificação de dependências
for cmd in aws jq; do
  if ! command -v "$cmd" &> /dev/null; then
    log_error "Dependência obrigatória '$cmd' não encontrada no PATH."
    exit 1
  fi
done

if [[ "$LIST_VERSIONS" == true ]]; then
  log_info "Listando as últimas versões disponíveis no repositório ECR '$ECR_REPO' ($REGION)..."
  aws ecr describe-images \
    --repository-name "$ECR_REPO" \
    --region "$REGION" \
    --query 'sort_by(imageDetails,&imagePushedAt)[-10:].[imageTags[0],imagePushedAt]' \
    --output table
  exit 0
fi

if [[ -z "$TARGET_TAG" ]]; then
  log_error "A tag para rollback é obrigatória. Use -t ou --tag, ou liste versões com -l."
  show_help
  exit 1
fi

log_info "Iniciando processo de rollback..."
log_info "Tag Alvo: $TARGET_TAG"
log_info "Cluster: $CLUSTER | Serviço: $SERVICE | Task Family: $TASK_FAMILY"

# Validar se a imagem alvo existe no ECR
log_info "Verificando se a imagem com tag '$TARGET_TAG' existe no ECR..."
if ! aws ecr describe-images \
  --repository-name "$ECR_REPO" \
  --region "$REGION" \
  --image-ids imageTag="$TARGET_TAG" > /dev/null 2>&1; then
  log_error "A imagem com tag '$TARGET_TAG' não foi encontrada no repositório '$ECR_REPO' ($REGION)."
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

# Obter a task definition atual
log_info "Obtendo Task Definition atual da família '$TASK_FAMILY'..."
CURRENT_TASK_DEF=$(aws ecs describe-task-definition \
  --region "$REGION" \
  --task-definition "$TASK_FAMILY" \
  --query 'taskDefinition' \
  --output json)

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "$CURRENT_TASK_DEF" > "$TEMP_DIR/current.json"

# Atualizar a imagem para a versão de rollback
TARGET_IMAGE="$ECR_URI:$TARGET_TAG"
log_info "Apontando imagem do contêiner para a versão estável anterior: $TARGET_IMAGE"

jq --arg image "$TARGET_IMAGE" '
  .containerDefinitions[0].image = $image |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
' "$TEMP_DIR/current.json" > "$TEMP_DIR/rollback.json"

# Registrar nova revisão
NEW_REVISION=$(aws ecs register-task-definition \
  --region "$REGION" \
  --cli-input-json "file://$TEMP_DIR/rollback.json" \
  --query 'taskDefinition.revision' \
  --output text)

log_success "Nova revisão de rollback criada: $TASK_FAMILY:$NEW_REVISION"

# Atualizar o serviço
log_info "Atualizando serviço ECS para a revisão de rollback..."
aws ecs update-service \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$TASK_FAMILY:$NEW_REVISION" > /dev/null

log_info "Aguardando convergência do serviço no cluster..."
aws ecs wait services-stable \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --services "$SERVICE"

log_success "Rollback concluído com sucesso!"
log_info "Serviço restaurado para versão: $TARGET_TAG ($TASK_FAMILY:$NEW_REVISION)"
