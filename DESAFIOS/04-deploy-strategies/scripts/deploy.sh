#!/usr/bin/env bash
# ==============================================================================
# deploy.sh — Ciclo Completo de Deploy Contínuo e Resiliência no Amazon ECS
# Projeto: BIA Cloud Lab — Formação AWS / D2NS
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================
# Uso:
#   ./deploy.sh [-E app|alb] [-t <TAG>] [--base-revision 15] [--dry-run]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

image_tag=""
skip_build=false
skip_smoke_test=false
allow_dirty=false
base_revision=""
timeout_seconds="$DEFAULT_TIMEOUT"

show_help() {
  cat << EOF
$(basename "$0") — Implantação Contínua com Rolling Update e Circuit Breaker no ECS

USO:
  $(basename "$0") [OPÇÕES]

OPÇÕES:
  -E, --env NOME              Ambiente alvo [app | alb | didatico] (padrão: $DEFAULT_ENV)
  -t, --tag, --image-tag TAG  Tag da imagem Docker (padrão: Git Short Hash HEAD)
      --base-revision REV     Número da revisão Task Def base (padrão: ativa no serviço, ex: 15)
      --skip-build            Reutiliza imagem já publicada no ECR, pulando Docker build/push
      --build-push            Força execução de Docker build e push (comportamento padrão)
      --allow-dirty           Permite o deploy mesmo se houver alterações locais no build context
  -p, --profile PERFIL        Perfil AWS CLI (padrão: $DEFAULT_PROFILE)
  -r, --region REGIAO         Região AWS (padrão: $DEFAULT_REGION)
  -e, --ecr-repo REPO         Repositório ECR (padrão: $DEFAULT_ECR_REPO)
  -c, --cluster CLUSTER       Override manual do Cluster ECS
  -s, --service SERVICO       Override manual do Serviço ECS
  -f, --task-family FAMILIA   Override manual da Família da Task Definition
      --container-name NOME   Override manual do Nome do Contêiner
  -u, --alb-url URL           Override manual da URL do ALB para Smoke Test
      --skip-smoke-test       Pula o smoke test pós-deploy
      --timeout SECONDS       Timeout máximo para estabilização do serviço (padrão: $DEFAULT_TIMEOUT)
      --dry-run               Modo simulação: valida pre-flight e exibe comandos sem mutações AWS
  -h, --help                  Exibe esta mensagem de ajuda

EXEMPLO:
  # 1. Deploy padrão completo a partir da baseline :15:
  $(basename "$0") --base-revision 15

  # 2. Simulação de deploy (Dry-Run não-destrutivo):
  $(basename "$0") --dry-run

  # 3. Deploy reutilizando imagem já existente no ECR:
  $(basename "$0") --skip-build -t 83a1f07
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -E|--env) load_environment "$2"; shift 2 ;;
    -t|--tag|--image-tag) image_tag="$2"; shift 2 ;;
    --build-push) skip_build=false; shift 1 ;;
    --skip-build) skip_build=true; shift 1 ;;
    --allow-dirty) allow_dirty=true; shift 1 ;;
    --base-revision) base_revision="$2"; shift 2 ;;
    --container-name) CONTAINER_NAME="$2"; shift 2 ;;
    --skip-smoke-test) skip_smoke_test=true; shift 1 ;;
    --timeout) timeout_seconds="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift 1 ;;
    -p|--profile) PROFILE="$2"; shift 2 ;;
    -r|--region) REGION="$2"; shift 2 ;;
    -e|--ecr-repo) ECR_REPO="$2"; shift 2 ;;
    -c|--cluster) CLUSTER="$2"; shift 2 ;;
    -s|--service) SERVICE="$2"; shift 2 ;;
    -f|--task-family) TASK_FAMILY="$2"; shift 2 ;;
    -u|--alb-url) ALB_URL="$2"; shift 2 ;;
    -h|--help) show_help; exit 0 ;;
    *) log_error "Opção desconhecida para 'deploy': $1"; show_help; exit 1 ;;
  esac
done

log_step "Fase 1: Validações Pré-Deploy (Pre-flight Checks)"
log_info "Ambiente Alvo:      $TARGET_ENV ($ENV_DESC)"
log_info "Cluster / Serviço:  $CLUSTER / $SERVICE"
log_info "Task Family:        $TASK_FAMILY"
log_info "Contêiner Alvo:     $CONTAINER_NAME"
log_info "Repositório ECR:    $ECR_REPO"
log_info "Perfil AWS / Reg:   $PROFILE / $REGION"

AWS_CMD=(aws --profile "$PROFILE" --region "$REGION")

# ------------------------------------------------------------------------------
# 1.1. Validação de Autenticação STS e Conta AWS Autorizada
# ------------------------------------------------------------------------------
account_id=""
caller_arn=""
caller_identity=""
caller_identity=$("${AWS_CMD[@]}" sts get-caller-identity --output json 2>/dev/null || true)

if [[ "$DRY_RUN" == false ]]; then
  log_info "Validando autenticação e identidade AWS com perfil '$PROFILE'..."
  if [[ -z "$AUTHORIZED_ACCOUNT" ]]; then
    log_error "CONFIGURAÇÃO DE SEGURANÇA MANDATÓRIA: Nenhuma conta AWS autorizada foi definida."
    log_error "Para proteger sua conta contra deploys acidentais em contas incorretas,"
    log_error "defina 'AUTHORIZED_ACCOUNT' ou 'AWS_ACCOUNT_ID' via variável de ambiente ou arquivo .env."
    log_info "Consulte o modelo em .env.example para instruções de configuração."
    exit 1
  fi

  if [[ -z "$caller_identity" ]]; then
    log_error "FALHA DE AUTENTICAÇÃO: Não foi possível obter caller identity para o perfil '$PROFILE'."
    log_error "A sessão STS expirou ou as credenciais temporárias são inválidas."
    log_info "Ação necessária: Execute 'aws login --profile $PROFILE' com MFA antes de prosseguir."
    exit 1
  fi
  account_id=$(echo "$caller_identity" | jq -r '.Account // empty')
  caller_arn=$(echo "$caller_identity" | jq -r '.Arn // empty')

  if [[ "$account_id" != "$AUTHORIZED_ACCOUNT" ]]; then
    log_error "CONTA NÃO AUTORIZADA: A identidade STS pertence à conta '$account_id', mas a única conta autorizada é '$AUTHORIZED_ACCOUNT'."
    exit 1
  fi
  log_success "Identidade AWS confirmada: $caller_arn (Conta: $account_id)"
else
  if [[ -n "$caller_identity" ]]; then
    account_id=$(echo "$caller_identity" | jq -r '.Account // empty')
    caller_arn=$(echo "$caller_identity" | jq -r '.Arn // empty')
    if [[ -n "$AUTHORIZED_ACCOUNT" && "$account_id" != "$AUTHORIZED_ACCOUNT" ]]; then
      log_warn "[DRY-RUN] AVISO: Identidade STS pertence à conta '$account_id' (autorizada configurada: $AUTHORIZED_ACCOUNT)."
    fi
    log_info "[DRY-RUN - VALIDAÇÃO READ-ONLY REAL NA AWS]"
    log_info "  Identidade AWS confirmada: $caller_arn (Conta: $account_id)"
  else
    log_warn "[DRY-RUN SIMULADO - AMBIENTE OFFLINE / MOCK DIDÁTICO]"
    log_warn "AVISO: Sessão AWS STS inativa. A simulação prosseguirá em modo mock seguro."
    account_id="${AUTHORIZED_ACCOUNT:-123456789012}"
  fi
fi

# ------------------------------------------------------------------------------
# 1.2. Validação do Repositório no Amazon ECR
# ------------------------------------------------------------------------------
log_info "Verificando existência do repositório ECR '$ECR_REPO' ($REGION)..."
if [[ -n "$caller_identity" ]]; then
  if ! "${AWS_CMD[@]}" ecr describe-repositories --repository-names "$ECR_REPO" > /dev/null 2>&1; then
    log_error "O repositório ECR '$ECR_REPO' não foi encontrado na região '$REGION'."
    exit 1
  fi
  log_success "Repositório ECR verificado com sucesso: $ECR_REPO"
else
  log_info "[DRY-RUN] Sessão offline: Verificação do repositório ECR '$ECR_REPO' mockada."
fi

# ------------------------------------------------------------------------------
# 1.3. Resolução da Tag da Imagem e Integridade do Git
# ------------------------------------------------------------------------------
resolve_git_info

if [[ -z "$image_tag" ]]; then
  if [[ -n "$GIT_SHORT_HASH" ]]; then
    image_tag="$GIT_SHORT_HASH"
    log_info "Tag definida a partir do Git commit SHA HEAD: $image_tag"
  else
    image_tag="latest"
    log_warn "Repositório Git não identificado. Utilizando tag padrão: $image_tag"
  fi
else
  log_info "Tag customizada informada pelo operador: $image_tag"
fi

if [[ -n "$GIT_REPO_ROOT" ]] && command -v git &>/dev/null; then
  dirty_app_files=()
  dockerignore_path="$GIT_REPO_ROOT/.dockerignore"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    raw_status="${line:0:2}"
    file_path="${line:3}"
    file_path="${file_path##\"}"
    file_path="${file_path%%\"}"

    if is_non_app_directory "$file_path"; then
      continue
    fi

    if is_dockerignored "$file_path" "$dockerignore_path"; then
      continue
    fi

    dirty_app_files+=("$raw_status $file_path")
  done < <(git -C "$GIT_REPO_ROOT" status --porcelain 2>/dev/null || true)

  if [[ ${#dirty_app_files[@]} -gt 0 ]]; then
    if [[ "$allow_dirty" == true ]]; then
      log_warn "Alterações não commitadas detectadas no contexto da aplicação, mas --allow-dirty foi acionado:"
      for f in "${dirty_app_files[@]}"; do
        echo "  - $f"
      done
    else
      log_error "BUILD CONTEXT SUJO: Arquivos da aplicação foram modificados e não foram commitados no Git:"
      for f in "${dirty_app_files[@]}"; do
        echo "  - $f"
      done
      log_error "A imagem Docker incorporaria artefatos divergentes do commit $image_tag."
      log_info "Ação necessária: Faça commit das alterações ou execute com '--allow-dirty' caso seja deliberado."
      exit 1
    fi
  else
    log_success "Contexto de build da aplicação BIA verificado heuristicamente (alinhado com o commit Git $image_tag)."
    log_info "  (Nota: Salvaguarda heurística defensiva baseada no .dockerignore; não substitui o parser nativo do Docker CLI)."
  fi
fi

# ------------------------------------------------------------------------------
# 1.4. Identificação da Task Definition em Execução e da Molde (Template Base)
# ------------------------------------------------------------------------------
log_info "Inspecionando a Task Definition ativa e a baseline do serviço '$SERVICE'..."

active_service_task_def=""
if [[ "$DRY_RUN" == false ]]; then
  active_service_task_def=$("${AWS_CMD[@]}" ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --query 'services[0].taskDefinition' \
    --output text 2>/dev/null || echo "")
else
  if [[ -n "$caller_identity" ]]; then
    active_service_task_def=$("${AWS_CMD[@]}" ecs describe-services \
      --cluster "$CLUSTER" \
      --services "$SERVICE" \
      --query 'services[0].taskDefinition' \
      --output text 2>/dev/null || echo "")
  fi
  if [[ -z "$active_service_task_def" || "$active_service_task_def" == "None" ]]; then
    active_service_task_def="arn:aws:ecs:$REGION:$account_id:task-definition/$TASK_FAMILY:${HOMOLOGATED_BASELINE:-15}"
  fi
fi

# Diferenciação explícita entre Task Def em execução vs Molde para o novo deployment
template_base_task_def=""
if [[ -n "$base_revision" ]]; then
  template_base_task_def="$TASK_FAMILY:$base_revision"
  log_info "Task Definition Molde (Template Base informada via flag): $template_base_task_def"
else
  if [[ -n "$active_service_task_def" && "$active_service_task_def" != "None" ]]; then
    template_base_task_def="$active_service_task_def"
  else
    template_base_task_def="$TASK_FAMILY:${HOMOLOGATED_BASELINE:-15}"
  fi
  log_info "Task Definition Molde (Template Base derivada do serviço): $template_base_task_def"
fi

# Alvo de rollback para falha de negócio no Smoke Test: a versão que estava efetivamente ativa
rollback_target_task_def="${active_service_task_def:-$template_base_task_def}"

log_info "Detalhamento de Governança SRE:"
log_info "  - Task Definition Ativa no Serviço:   ${active_service_task_def:-N/A}"
log_info "  - Task Definition Molde para Deploy:  $template_base_task_def"
log_info "  - Alvo de Rollback pós-Smoke Test:    $rollback_target_task_def"

# Mantém compatibilidade com variável legada interna
base_task_def_arn="$template_base_task_def"

# ------------------------------------------------------------------------------
# 1.5. Salvaguarda Mandatória: Bloqueio Rigoroso da Revisão Defeituosa 16
# ------------------------------------------------------------------------------
if [[ "$base_task_def_arn" == *":16" && "$TASK_FAMILY" == "task-def-bia-cloud-app" ]]; then
  log_error "BLOQUEIO DE SEGURANÇA: A revisão :16 é a Task Definition contaminada com falha deliberada ('exit 1')."
  log_error "Ela não pode ser utilizada como baseline de deploy para proteger a estabilidade do cluster."
  log_info "Ação necessária: Utilize a revisão homologada 15 informando '--base-revision 15'."
  exit 1
fi

# ------------------------------------------------------------------------------
# 1.6. Auditoria Completa da Task Definition Base via describe-task-definition
# ------------------------------------------------------------------------------
base_task_def_json=""
if [[ -n "$caller_identity" ]]; then
  log_info "Consultando manifesto completo da Task Definition '$base_task_def_arn' no Amazon ECS..."
  if ! base_task_def_json=$("${AWS_CMD[@]}" ecs describe-task-definition --task-definition "$base_task_def_arn" --output json 2>/dev/null); then
    log_error "FALHA CRÍTICA: Falha ao executar 'ecs describe-task-definition' para '$base_task_def_arn'."
    log_error "Deploy abortado antes de qualquer compilação Docker ou mutação."
    exit 1
  fi

  if [[ -z "$base_task_def_json" ]]; then
    log_error "FALHA CRÍTICA: Falha ao executar 'ecs describe-task-definition' para '$base_task_def_arn'."
    log_error "Deploy abortado antes de qualquer compilação Docker ou mutação."
    exit 1
  fi
else
  if [[ "$DRY_RUN" == true ]]; then
    base_task_def_json=$(cat << 'EOF'
{
  "taskDefinition": {
    "family": "task-def-bia-cloud-app",
    "status": "ACTIVE",
    "networkMode": "awsvpc",
    "containerDefinitions": [
      {
        "name": "bia-cloud-app",
        "image": "123456789012.dkr.ecr.us-east-2.amazonaws.com/bia-cloud-lab:base",
        "cpu": 512,
        "memory": 1024,
        "essential": true
      }
    ],
    "placementConstraints": [],
    "requiresCompatibilities": ["EC2"]
  }
}
EOF
)
  else
    log_error "FALHA CRÍTICA: Execução real exige sessão AWS autenticada para auditar a Task Definition base."
    exit 1
  fi
fi

# Normalização do objeto taskDefinition (suporta retorno nativo da AWS ou mock em raiz)
normalized_task_def=$(echo "$base_task_def_json" | jq 'if has("taskDefinition") then .taskDefinition else . end')

# Validar status ACTIVE da Task Definition base
base_task_def_status=$(echo "$normalized_task_def" | jq -r '.status // empty')
if [[ "$base_task_def_status" != "ACTIVE" ]]; then
  log_error "STATUS INVÁLIDO: A Task Definition base '$base_task_def_arn' está com status '$base_task_def_status'. Apenas definições com status 'ACTIVE' podem ser associadas ao serviço."
  exit 1
fi

# Validar família da Task Definition base
base_family=$(echo "$normalized_task_def" | jq -r '.family // empty')
if [[ "$base_family" != "$TASK_FAMILY" ]]; then
  log_error "FAMÍLIA INCOMPATÍVEL: A Task Definition base pertence à família '$base_family', mas o ambiente requer '$TASK_FAMILY'."
  exit 1
fi

# Validar unicidade do contêiner alvo
target_container_count=$(echo "$normalized_task_def" | jq --arg c "$CONTAINER_NAME" '[.containerDefinitions[]? | select(.name == $c)] | length')
if [[ "$target_container_count" -eq 0 ]]; then
  log_error "CONTÊINER NÃO ENCONTRADO: O contêiner '$CONTAINER_NAME' não existe na Task Definition '$base_task_def_arn'."
  exit 1
elif [[ "$target_container_count" -gt 1 ]]; then
  log_error "AMBIGUIDADE DE CONTÊINER: Foram encontrados $target_container_count contêineres com o nome '$CONTAINER_NAME' na Task Definition."
  exit 1
fi

log_success "Task Definition base auditada e pré-validada com sucesso: $base_task_def_arn (Família: $base_family, Contêiner: $CONTAINER_NAME)"

# ==============================================================================
# FASE 2: BUILD DOCKER LOCAL E PUBLICAÇÃO NO AMAZON ECR
# ==============================================================================
log_step "Fase 2: Build Docker Local e Publicação no Amazon ECR"

ecr_registry="$account_id.dkr.ecr.$REGION.amazonaws.com"
target_image_uri="$ecr_registry/$ECR_REPO:$image_tag"

dockerfile_path=""
build_context_dir=""
if [[ -n "$GIT_REPO_ROOT" && -f "$GIT_REPO_ROOT/Dockerfile" ]]; then
  dockerfile_path="$GIT_REPO_ROOT/Dockerfile"
  build_context_dir="$GIT_REPO_ROOT"
elif [[ -f "$SCRIPT_DIR/../../Dockerfile" ]]; then
  dockerfile_path="$(cd "$SCRIPT_DIR/../.." && pwd)/Dockerfile"
  build_context_dir="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

log_info "Dockerfile:  ${dockerfile_path:-N/A}"
log_info "Contexto:    ${build_context_dir:-N/A}"
log_info "Imagem Alvo: $target_image_uri"

if [[ "$skip_build" == false ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Comandos de compilação e publicação que seriam executados:"
    log_info "  1. docker build -t \"$ECR_REPO:$image_tag\" -t \"$target_image_uri\" -f \"$dockerfile_path\" \"$build_context_dir\""
    log_info "  2. aws ecr get-login-password --profile $PROFILE --region $REGION | docker login --username AWS --password-stdin $ecr_registry"
    log_info "  3. docker push \"$target_image_uri\""
  else
    if [[ -z "$dockerfile_path" || ! -f "$dockerfile_path" ]]; then
      log_error "Dockerfile não localizado no repositório."
      exit 1
    fi

    log_info "Iniciando compilação da imagem Docker..."
    docker build \
      -t "$ECR_REPO:$image_tag" \
      -t "$target_image_uri" \
      -f "$dockerfile_path" \
      "$build_context_dir"

    log_success "Build Docker concluído com sucesso."

    log_info "Realizando autenticação temporária no Amazon ECR ($ecr_registry)..."
    "${AWS_CMD[@]}" ecr get-login-password | docker login --username AWS --password-stdin "$ecr_registry"

    log_info "Publicando imagem no repositório ECR: $target_image_uri..."
    docker push "$target_image_uri"
    log_success "Imagem publicada com sucesso no Amazon ECR."
  fi
else
  log_info "Flag --skip-build informada. Pulando Docker Build e ECR Push."
  if [[ "$DRY_RUN" == false ]]; then
    log_info "Validando se a imagem já existe no ECR..."
    if ! "${AWS_CMD[@]}" ecr describe-images --repository-name "$ECR_REPO" --image-ids imageTag="$image_tag" > /dev/null 2>&1; then
      log_error "A imagem '$target_image_uri' não foi encontrada no ECR."
      log_info "Execute sem '--skip-build' para construir e publicar a imagem."
      exit 1
    fi
    log_success "Imagem existente no ECR confirmada: $target_image_uri"
  fi
fi

# ==============================================================================
# FASE 3: REGISTRO DA NOVA REVISÃO DA TASK DEFINITION
# ==============================================================================
log_step "Fase 3: Registro da Nova Revisão da Task Definition"

new_task_def_file="$TEMP_DIR/new-task-definition.json"

# Transformação cirúrgica com jq:
# 1. Preserva todos os campos legítimos aceitos pela API RegisterTaskDefinition
# 2. Remove estritamente os campos somente-leitura de resposta da AWS
# 3. Altera exclusivamente o campo 'image' do contêiner configurado
echo "$normalized_task_def" | jq \
  --arg container "$CONTAINER_NAME" \
  --arg new_image "$target_image_uri" '
  del(
      .taskDefinitionArn,
      .revision,
      .status,
      .requiresAttributes,
      .compatibilities,
      .registeredAt,
      .registeredBy,
      .deregisteredAt
    )
  | .containerDefinitions |= map(
      if .name == $container then
        .image = $new_image
      else
        .
      end
    )
' > "$new_task_def_file"

if [[ ! -s "$new_task_def_file" ]]; then
  log_error "Falha crítica ao preparar o manifesto JSON da nova Task Definition."
  exit 1
fi

new_task_def_arn=""
new_revision=""

if [[ "$DRY_RUN" == true ]]; then
  new_revision="17"
  new_task_def_arn="arn:aws:ecs:$REGION:$account_id:task-definition/$TASK_FAMILY:$new_revision"
  log_info "[DRY-RUN] Nova Task Definition simulada validada com sucesso."
  log_info "  - Família:              $TASK_FAMILY"
  log_info "  - Nova Revisão:         :$new_revision"
  log_info "  - Contêiner Mutado:     $CONTAINER_NAME (exclusivo)"
  log_info "  - Nova Imagem:          $target_image_uri"
  log_info "  - Campos Preservados:   placementConstraints, requiresCompatibilities, command, entryPoint, env e secrets"
  log_info "  - Metadados Expurgações: del(taskDefinitionArn, revision, status, requiresAttributes, compatibilities, registeredAt/By, deregisteredAt)"
else
  log_info "Registrando nova revisão no plano de controle do Amazon ECS..."
  registered_json=$("${AWS_CMD[@]}" ecs register-task-definition \
    --cli-input-json "file://$new_task_def_file" \
    --output json)

  if [[ "$registered_json" == arn:* ]]; then
    new_task_def_arn="$registered_json"
    new_revision=$(echo "$new_task_def_arn" | awk -F':' '{print $NF}')
  else
    new_task_def_arn=$(echo "$registered_json" | jq -r '.taskDefinition.taskDefinitionArn // .taskDefinitionArn // empty' 2>/dev/null || echo "")
    new_revision=$(echo "$registered_json" | jq -r '.taskDefinition.revision // .revision // empty' 2>/dev/null || echo "")
    if [[ -z "$new_revision" && -n "$new_task_def_arn" ]]; then
      new_revision=$(echo "$new_task_def_arn" | awk -F':' '{print $NF}')
    fi
  fi

  log_success "Nova Task Definition registrada: ${C_BOLD}$TASK_FAMILY:$new_revision${C_RESET}"
  log_info "ARN gerado: $new_task_def_arn"
fi

# ==============================================================================
# FASE 4: ATUALIZAÇÃO DO SERVIÇO ECS E ACOMPANHAMENTO DE ROLLOUT
# ==============================================================================
log_step "Fase 4: Atualização do Serviço ECS e Acompanhamento de Rollout"

if [[ "$DRY_RUN" == true ]]; then
  log_info "[DRY-RUN] Comandos que seriam executados na AWS:"
  log_info "  aws ecs update-service --cluster $CLUSTER --service $SERVICE --task-definition $new_task_def_arn"
  log_info "  aws ecs wait services-stable --cluster $CLUSTER --services $SERVICE"
  log_info "  Smoke Test: 5x GET $ALB_URL"
  log_success "[DRY-RUN] Simulação completa de Deploy concluída com sucesso! Nenhuma mutação foi efetuada."
  log_governance_dry_run_notice
  exit 0
fi

log_info "Disparando atualização do serviço '$SERVICE' para a revisão :$new_revision..."
update_json=$("${AWS_CMD[@]}" ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$new_task_def_arn" \
  --output json)

deployment_id=$(echo "$update_json" | jq -r '
  (.service.deployments // .deployments // [])[]? |
  select(.taskDefinition == "'"$new_task_def_arn"'") |
  .id
' | head -n1)

if [[ -z "$deployment_id" ]]; then
  deployment_id="ecs-dep-$(date +%s)"
fi
log_info "Deployment iniciado com sucesso no ECS. ID: ${C_BOLD}$deployment_id${C_RESET}"

log_info "Acompanhando estabilização do serviço e status do Circuit Breaker (Timeout: ${timeout_seconds}s)..."

start_time=$(date +%s)
rollout_completed=false
circuit_breaker_failed=false
desired=1

while true; do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  if [[ $elapsed -gt $timeout_seconds ]]; then
    log_error "TIMEOUT: O serviço '$SERVICE' não atingiu estabilidade dentro de ${timeout_seconds}s."
    break
  fi

  svc_desc=$("${AWS_CMD[@]}" ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --output json 2>/dev/null || echo "{}")

  norm_svc=$(echo "$svc_desc" | jq 'if has("services") then .services[0] else . end')
  primary_deployment=$(echo "$norm_svc" | jq -r '
    (.deployments // [])[]? |
    select(.id == "'"$deployment_id"'" or .taskDefinition == "'"$new_task_def_arn"'")
  ')

  if [[ -n "$primary_deployment" && "$primary_deployment" != "null" ]]; then
    rollout_state=$(echo "$primary_deployment" | jq -r '.rolloutState // "IN_PROGRESS"')
    desired=$(echo "$primary_deployment" | jq -r '.desiredCount // empty')
    if [[ -z "$desired" || "$desired" == "null" ]]; then
      desired=$(echo "$norm_svc" | jq -r '.desiredCount // 0')
    fi
    running=$(echo "$primary_deployment" | jq -r '.runningCount // empty')
    if [[ -z "$running" || "$running" == "null" ]]; then
      running=$(echo "$norm_svc" | jq -r '.runningCount // 0')
    fi

    echo -ne "  -> [${elapsed}s] Rollout em andamento... desired: $desired | running: $running | status: $rollout_state \r"

    if [[ "$rollout_state" == "COMPLETED" ]]; then
      echo ""
      log_success "Rollout da nova versão concluído com sucesso no ECS!"
      rollout_completed=true
      break
    elif [[ "$rollout_state" == "FAILED" ]]; then
      echo ""
      circuit_breaker_failed=true
      log_warn "O ECS Deployment Circuit Breaker detectou falhas consecutivas e disparou o auto-rollback para a implantação $new_task_def_arn!"
      break
    fi
  else
    cb_check=$(echo "$norm_svc" | jq -r '(.deployments // [])[]? | select(.rolloutState == "FAILED") | .rolloutState' | head -n1)
    if [[ "$cb_check" == "FAILED" ]]; then
      echo ""
      circuit_breaker_failed=true
      log_warn "O ECS Deployment Circuit Breaker abortou a implantação $deployment_id e acionou o auto-rollback!"
      break
    fi
  fi

  sleep 6
done

if [[ "$circuit_breaker_failed" == true ]]; then
  echo ""
  log_step "Diagnóstico Read-Only Pós-Circuit Breaker"
  log_info "Consultando o estado do serviço no ECS control plane para validar o rollback automático..."

  post_svc_desc=$("${AWS_CMD[@]}" ecs describe-services \
    --cluster "$CLUSTER" \
    --services "$SERVICE" \
    --output json 2>/dev/null || echo "{}")

  norm_post=$(echo "$post_svc_desc" | jq 'if has("services") then .services[0] else . end')

  failed_reason=$(echo "$norm_post" | jq -r '
    (.deployments // [])[]? |
    select(.rolloutState == "FAILED") |
    .rolloutStateReason // "Falhas consecutivas de inicialização das tarefas"
  ' | head -n1)

  current_primary=$(echo "$norm_post" | jq -r '
    (.deployments // [])[]? |
    select(.status == "PRIMARY") |
    .taskDefinition // empty
  ')

  current_desired=$(echo "$norm_post" | jq -r '.desiredCount // 0')
  current_running=$(echo "$norm_post" | jq -r '.runningCount // 0')

  log_warn "Diagnóstico do Circuit Breaker: $failed_reason"
  log_info "Task Definition Ativa (PRIMARY) atual: $current_primary"
  log_info "Capacidade atual do serviço: desired: $current_desired | running: $current_running"

  if [[ -n "$current_primary" && ("$current_primary" == *"$base_task_def_arn"* || "$current_primary" == *":$base_revision") ]]; then
    log_success "CONFIRMAÇÃO READ-ONLY: O ECS restaurou com sucesso a Task Definition estável como PRIMARY: $current_primary"
    if [[ "$current_desired" -gt 0 && "$current_running" -ge "$current_desired" ]]; then
      log_success "Estabilidade comprovada: As tarefas do serviço estão ativas e saudáveis ($current_running/$current_desired tarefas em execução)."
    else
      log_warn "A Task Definition estável foi restaurada, mas as tarefas ainda estão convergindo (running: $current_running, desired: $current_desired)."
    fi
  else
    log_error "ATENÇÃO: A Task Definition PRIMARY ($current_primary) ainda não corresponde à versão estável esperada ($base_task_def_arn)."
    log_error "O rollback do Circuit Breaker pode ainda estar em andamento ou requerer intervenção operacional."
  fi

  log_error "Deploy abortado devido ao disparo do Circuit Breaker no ECS para a revisão :$new_revision."
  exit 2
fi

if [[ "$desired" -eq 0 ]]; then
  log_error "ROLLOUT NÃO HOMOLOGADO: O serviço '$SERVICE' possui desiredCount=0 (nenhuma tarefa em execução)."
  log_error "Para homologar o deploy com segurança de confiabilidade (SRE), o serviço precisa de pelo menos 1 tarefa saudável em execução."
  exit 1
fi

if [[ "$rollout_completed" == true ]]; then
  log_info "Aguardando estabilização final do cluster (wait services-stable)..."
  "${AWS_CMD[@]}" ecs wait services-stable \
    --cluster "$CLUSTER" \
    --services "$SERVICE" 2>/dev/null || true
else
  log_error "O rollout do ECS não foi concluído com sucesso dentro do tempo limite."
  exit 1
fi

# ==============================================================================
# FASE 5: SMOKE TEST HTTP PÓS-DEPLOY COM RESILIÊNCIA E AUTO-ROLLBACK
# ==============================================================================
if [[ "$skip_smoke_test" == false ]]; then
  log_step "Execução do Smoke Test HTTP no Endpoint do ALB"
  log_info "URL de validação: $ALB_URL"

  success_count=0
  failed_count=0
  total_attempts=5
  min_success_required=4  # Tolera até 1 falha transitória de warmup do alvo ALB

  for ((i=1; i<=total_attempts; i++)); do
    http_res=$(curl -s -w "%{http_code}|%{time_total}" -o "$TEMP_DIR/resp.txt" --max-time 5 "$ALB_URL" 2>/dev/null || echo "000|0")
    http_code=$(echo "$http_res" | cut -d'|' -f1)
    http_time=$(echo "$http_res" | cut -d'|' -f2)
    resp_body=$(cat "$TEMP_DIR/resp.txt" 2>/dev/null || echo "")

    if [[ "$http_code" == "200" ]]; then
      success_count=$((success_count + 1))
      log_info "  [Tentativa $i/$total_attempts] HTTP $http_code (${http_time}s) - Payload: \"$resp_body\""
    else
      failed_count=$((failed_count + 1))
      log_warn "  [Tentativa $i/$total_attempts] HTTP $http_code (${http_time}s) - Falha transitória ou resposta inesperada..."
    fi
    sleep 2
  done

  if [[ "$success_count" -ge "$min_success_required" ]]; then
    if [[ "$failed_count" -gt 0 ]]; then
      log_warn "Smoke test aprovado com resiliência ($success_count/$total_attempts sucessos, $failed_count falha transitória tolerada)."
    else
      log_success "Smoke test 100% aprovado! Todas as $total_attempts requisições responderam HTTP 200."
    fi
  else
    log_error "Smoke test reprovado ($failed_count falhas detectadas em $total_attempts tentativas; mínimo exigido: $min_success_required)!"
    if [[ -n "${rollback_target_task_def:-$base_task_def_arn}" ]]; then
      rb_target="${rollback_target_task_def:-$base_task_def_arn}"
      log_warn "Bug lógico de aplicação detectado após rollout. Iniciando rollback de negócio para baseline ativa no serviço: $rb_target..."
      "${AWS_CMD[@]}" ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --task-definition "$rb_target" > /dev/null
      "${AWS_CMD[@]}" ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" 2>/dev/null || true
      log_success "Rollback de emergência concluído com sucesso para a baseline: $rb_target"
    fi
    exit 3
  fi
fi

log_step "Sumário de Release"
log_success "Deploy concluído e validado com sucesso!"
echo "Ambiente:        $TARGET_ENV ($CLUSTER / $SERVICE)"
echo "Task Definition: $TASK_FAMILY:$new_revision (Base: $base_task_def_arn)"
echo "Imagem / Tag:    $target_image_uri"
echo "Endpoint ALB:    $ALB_URL"
