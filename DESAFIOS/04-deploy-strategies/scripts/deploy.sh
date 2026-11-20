#!/usr/bin/env bash
# ==============================================================================
# Script Parametrizado de Deploy no Amazon ECS — Projeto BIA
# Trilha: Estratégias de Deploy & Resiliência (Desafio 01)
# ==============================================================================
# Uso:
#   ./deploy.sh [OPTIONS]
#
# Variáveis de ambiente ou parâmetros:
#   AWS_REGION, ECR_REPO, ECS_CLUSTER, ECS_SERVICE, TASK_FAMILY, IMAGE_TAG
# ==============================================================================

set -euo pipefail

# Configurações padrão
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
TAG=""

log_info()    { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
log_warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }

show_help() {
  cat << EOF
Uso: $(basename "$0") [OPÇÕES]

Opções:
  -r, --region REGION         Região AWS (padrão: $DEFAULT_REGION)
  -e, --ecr-repo REPO         Nome do repositório ECR (padrão: $DEFAULT_ECR_REPO)
  -c, --cluster CLUSTER       Nome do cluster ECS (padrão: $DEFAULT_CLUSTER)
  -s, --service SERVICE       Nome do serviço ECS (padrão: $DEFAULT_SERVICE)
  -f, --task-family FAMILY    Família da Task Definition (padrão: $DEFAULT_TASK_FAMILY)
  -t, --tag TAG               Tag da imagem (padrão: commit hash git de 7 caracteres)
  -h, --help                  Exibe esta mensagem de ajuda

Exemplo:
  ./deploy.sh -r us-east-1 -c cluster-bia -s service-bia -t v1.0.0
EOF
}

# Parsing de argumentos
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) REGION="$2"; shift 2 ;;
    -e|--ecr-repo) ECR_REPO="$2"; shift 2 ;;
    -c|--cluster) CLUSTER="$2"; shift 2 ;;
    -s|--service) SERVICE="$2"; shift 2 ;;
    -f|--task-family) TASK_FAMILY="$2"; shift 2 ;;
    -t|--tag) TAG="$2"; shift 2 ;;
    -h|--help) show_help; exit 0 ;;
    *) log_error "Opção desconhecida: $1"; show_help; exit 1 ;;
  esac
done

# Validação defensiva de formato
if [[ ! "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
  log_error "Região AWS inválida: '$REGION'. Formato esperado: xx-xxxx-x (ex: us-east-1)"
  exit 1
fi

if [[ ! "$ECR_REPO" =~ ^[a-z0-9][a-z0-9._/-]{1,255}$ ]]; then
  log_error "Nome de repositório ECR inválido: '$ECR_REPO'"
  exit 1
fi

# Obtenção de tag caso não fornecida
if [[ -z "$TAG" ]]; then
  if git rev-parse --git-dir > /dev/null 2>&1; then
    TAG=$(git rev-parse --short=7 HEAD)
    log_info "Tag não especificada. Utilizando Git commit hash: $TAG"
  else
    log_error "Tag não especificada e diretório não é repositório Git. Use -t ou --tag."
    exit 1
  fi
fi

# Verificação de dependências
for cmd in aws jq; do
  if ! command -v "$cmd" &> /dev/null; then
    log_error "Dependência obrigatória '$cmd' não encontrada no PATH."
    exit 1
  fi
done

log_info "Iniciando processo de deploy parametrizado..."
log_info "Região: $REGION | Cluster: $CLUSTER | Serviço: $SERVICE"
log_info "Repositório: $ECR_REPO | Task Family: $TASK_FAMILY | Tag: $TAG"

# Obter Account ID dinamicamente
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$ECR_REPO"

# Obter a task definition atual
log_info "Obtendo última revisão de Task Definition para família '$TASK_FAMILY'..."
CURRENT_TASK_DEF=$(aws ecs describe-task-definition \
  --region "$REGION" \
  --task-definition "$TASK_FAMILY" \
  --query 'taskDefinition' \
  --output json)

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "$CURRENT_TASK_DEF" > "$TEMP_DIR/current.json"

# Atualizar a imagem no container principal e remover campos não editáveis
NEW_IMAGE="$ECR_URI:$TAG"
log_info "Atualizando imagem do contêiner para: $NEW_IMAGE"

jq --arg image "$NEW_IMAGE" '
  .containerDefinitions[0].image = $image |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)
' "$TEMP_DIR/current.json" > "$TEMP_DIR/new.json"

# Registrar nova revisão de Task Definition
log_info "Registrando nova revisão da Task Definition no ECS..."
NEW_REVISION=$(aws ecs register-task-definition \
  --region "$REGION" \
  --cli-input-json "file://$TEMP_DIR/new.json" \
  --query 'taskDefinition.revision' \
  --output text)

log_success "Nova revisão registrada com sucesso: $TASK_FAMILY:$NEW_REVISION"

# Atualizar o serviço ECS
log_info "Atualizando serviço ECS '$SERVICE' para revisão '$TASK_FAMILY:$NEW_REVISION'..."
aws ecs update-service \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$TASK_FAMILY:$NEW_REVISION" > /dev/null

log_info "Aguardando estabilização do serviço (wait services-stable)..."
aws ecs wait services-stable \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --services "$SERVICE"

log_success "Deploy concluído com sucesso e serviço estabilizado!"
log_info "Versão ativa: $TAG (Revisão: $TASK_FAMILY:$NEW_REVISION)"
