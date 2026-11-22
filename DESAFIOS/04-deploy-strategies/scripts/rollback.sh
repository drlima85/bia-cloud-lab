#!/usr/bin/env bash
# ==============================================================================
# rollback.sh — Operação de Rollback Controlado e Imediato no Amazon ECS
# Projeto: BIA Cloud Lab — Formação AWS / D2NS
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================
# Uso:
#   ./rollback.sh -r <REVISAO> [-E app|alb] [--dry-run]
#   ./rollback.sh --list
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

target_revision=""
skip_smoke_test=false

show_help() {
  cat << EOF
$(basename "$0") — Reversão Direta de Task Definition no Amazon ECS

USO:
  $(basename "$0") -r <REVISAO> [OPÇÕES]
  $(basename "$0") --list [OPÇÕES]

OPÇÕES:
  -r, --revision NUM          Número da revisão alvo para reversão (ex: 15)
  -l, --list                  Lista as revisões recentes disponíveis no ECS
  -E, --env NOME              Ambiente alvo [app | alb | didatico] (padrão: $DEFAULT_ENV)
  -p, --profile PERFIL        Perfil AWS CLI (padrão: $DEFAULT_PROFILE)
  -region, --region REGIAO    Região AWS (padrão: $DEFAULT_REGION)
  -c, --cluster CLUSTER       Override manual do Cluster ECS
  -s, --service SERVICO       Override manual do Serviço ECS
  -f, --task-family FAMILIA   Override manual da Família da Task Definition
      --container-name NOME   Override manual do Nome do Contêiner
  -u, --alb-url URL           Override manual da URL do ALB para o Smoke Test
      --skip-smoke-test       Pula o smoke test pós-rollback
      --dry-run               Modo simulação: valida regras sem alterar a nuvem
  -h, --help                  Exibe esta mensagem de ajuda

EXEMPLO:
  # 1. Rollback direto e imediato para a revisão homologada 15:
  $(basename "$0") -r 15

  # 2. Simulação segura de rollback (Dry-Run):
  $(basename "$0") -r 15 --dry-run

  # 3. Listar revisões antes de decidir o rollback:
  $(basename "$0") --list
EOF
}

# Tratamento preliminar para opção --list
for arg in "$@"; do
  if [[ "$arg" == "-l" || "$arg" == "--list" || "$arg" == "--list-versions" ]]; then
    filtered_args=()
    for a in "$@"; do
      if [[ "$a" != "-l" && "$a" != "--list" && "$a" != "--list-versions" ]]; then
        filtered_args+=("$a")
      fi
    done
    exec "$SCRIPT_DIR/list-versions.sh" "${filtered_args[@]}"
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    -E|--env) load_environment "$2"; shift 2 ;;
    -r|--revision) target_revision="$2"; shift 2 ;;
    -p|--profile) PROFILE="$2"; shift 2 ;;
    -region|--region) REGION="$2"; shift 2 ;;
    -c|--cluster) CLUSTER="$2"; shift 2 ;;
    -s|--service) SERVICE="$2"; shift 2 ;;
    -f|--task-family) TASK_FAMILY="$2"; shift 2 ;;
    --container-name) CONTAINER_NAME="$2"; shift 2 ;;
    -u|--alb-url) ALB_URL="$2"; shift 2 ;;
    --skip-smoke-test) skip_smoke_test=true; shift 1 ;;
    --dry-run) DRY_RUN=true; shift 1 ;;
    -h|--help) show_help; exit 0 ;;
    *) log_error "Opção desconhecida para 'rollback': $1"; show_help; exit 1 ;;
  esac
done

log_step "Operação de Rollback Controlado no Amazon ECS"
log_info "Ambiente:      $TARGET_ENV ($ENV_DESC)"
log_info "Cluster / Svc: $CLUSTER / $SERVICE"
log_info "Task Family:   $TASK_FAMILY"
log_info "Perfil / Reg:  $PROFILE / $REGION"

AWS_CMD=(aws --profile "$PROFILE" --region "$REGION")

# Salvaguarda de Segurança Mandatória: Bloqueio estrito de rollback para a revisão 16
if [[ "$target_revision" == "16" && "$TASK_FAMILY" == "task-def-bia-cloud-app" ]]; then
  log_error "BLOQUEIO DE SEGURANÇA: A revisão :16 é a Task Definition contaminada com falha deliberada ('exit 1')."
  log_error "Rollback rejeitado para proteger a disponibilidade do serviço."
  exit 1
fi

# Caso a revisão não tenha sido fornecida na linha de comando
if [[ -z "$target_revision" ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    if [[ "$TARGET_ENV" == "app" ]]; then
      target_revision="15"
      log_info "[DRY-RUN] Nenhuma revisão informada. Utilizando revisão estável de referência mockada para app: :15"
    else
      target_revision="1"
      log_info "[DRY-RUN] Nenhuma revisão informada. Utilizando revisão simulada para $TARGET_ENV: :1"
    fi
  elif [[ -t 0 ]]; then
    log_warn "Nenhuma revisão informada via -r/--revision."
    echo "Consultando revisões recentes disponíveis..."
    "$SCRIPT_DIR/list-versions.sh" --limit 5
    read -r -p "Digite o número da revisão para rollback [ex: 15]: " target_revision
  fi
fi

if [[ -z "$target_revision" || ! "$target_revision" =~ ^[0-9]+$ ]]; then
  log_error "Revisão de rollback inválida ou não especificada. Use: $(basename "$0") rollback -r <NUM>"
  exit 1
fi

target_task_def="$TASK_FAMILY:$target_revision"
log_info "Revisão Alvo Selecionada para Rollback: ${C_BOLD}$target_task_def${C_RESET}"

caller_identity=""
caller_identity=$("${AWS_CMD[@]}" sts get-caller-identity --output json 2>/dev/null || true)

if [[ "$DRY_RUN" == true ]]; then
  if [[ -n "$caller_identity" ]]; then
    caller_acc=$(echo "$caller_identity" | jq -r '.Account // empty')
    if [[ -z "$AUTHORIZED_ACCOUNT" || "$caller_acc" == "$AUTHORIZED_ACCOUNT" ]]; then
      log_info "[DRY-RUN - VALIDAÇÃO READ-ONLY REAL NO ECS (SEM ALTERAÇÕES)]"
      desc_target=$("${AWS_CMD[@]}" ecs describe-task-definition --task-definition "$target_task_def" --output json 2>/dev/null || echo "")
      if [[ -n "$desc_target" ]]; then
        desc_family=$(echo "$desc_target" | jq -r '.taskDefinition.family // empty')
        desc_status=$(echo "$desc_target" | jq -r '.taskDefinition.status // empty')
        log_info "  - Task Def encontrada: $target_task_def"
        log_info "  - Família confirmada:  $desc_family (Esperado: $TASK_FAMILY)"
        log_info "  - Status confirmado:   $desc_status (Requer ACTIVE)"
        if [[ "$desc_family" != "$TASK_FAMILY" ]]; then
          log_error "FAMÍLIA INCOMPATÍVEL: A Task Definition '$target_task_def' pertence à família '$desc_family', mas o ambiente requer '$TASK_FAMILY'."
          exit 1
        fi
        if [[ "$desc_status" != "ACTIVE" ]]; then
          log_error "STATUS INVÁLIDO: A Task Definition '$target_task_def' está com status '$desc_status'. Apenas definições com status 'ACTIVE' podem ser associadas ao serviço."
          exit 1
        fi
      else
        log_warn "  - Task Def '$target_task_def' não encontrada na nuvem. Simulação prosseguirá em modo mock."
      fi
    else
      log_warn "[DRY-RUN SIMULADO - AMBIENTE OFFLINE / MOCK DIDÁTICO]"
      log_warn "AVISO: Conta STS '$caller_acc' difere da autorizada configurada '$AUTHORIZED_ACCOUNT'. Revisão alvo validada por mock local."
    fi
  else
    log_warn "[DRY-RUN SIMULADO - AMBIENTE OFFLINE / MOCK DIDÁTICO]"
    log_warn "AVISO: Sessão STS inativa. Revisão alvo validada por mock local."
  fi

  log_info "[DRY-RUN] Simulação de Execução de Rollback:"
  log_info "  1. NÃO executa build nem push Docker (conforme especificação do instrutor)."
  log_info "  2. NÃO registra nova Task Definition (aponta diretamente para a revisão homologada :$target_revision)."
  log_info "  3. Comando de reversão: aws ecs update-service --cluster $CLUSTER --service $SERVICE --task-definition $target_task_def"
  log_info "  4. Comando de estabilização: aws ecs wait services-stable --cluster $CLUSTER --services $SERVICE"
  log_info "  5. Smoke Test pós-rollback: $ALB_URL"
  log_success "[DRY-RUN] Simulação de Rollback concluída com sucesso. Nenhuma alteração foi realizada na nuvem."
  log_governance_dry_run_notice
  exit 0
fi

# Modo Real: Validação mandatória de identidade STS e conta autorizada
if [[ -z "$AUTHORIZED_ACCOUNT" ]]; then
  log_error "CONFIGURAÇÃO DE SEGURANÇA MANDATÓRIA: Nenhuma conta AWS autorizada foi definida."
  log_error "Para proteger sua conta contra operações acidentais em contas incorretas,"
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
if [[ "$account_id" != "$AUTHORIZED_ACCOUNT" ]]; then
  log_error "CONTA NÃO AUTORIZADA: A identidade STS atual pertence à conta '$account_id', mas a única conta autorizada configurada é '$AUTHORIZED_ACCOUNT'."
  exit 1
fi

# Validação de existência da Task Definition alvo
log_info "Validando se a Task Definition '$target_task_def' existe e está ativa no ECS..."
desc_target=$("${AWS_CMD[@]}" ecs describe-task-definition --task-definition "$target_task_def" --output json 2>/dev/null || echo "")
if [[ -z "$desc_target" ]]; then
  log_error "A Task Definition '$target_task_def' não foi encontrada no ECS ($REGION)."
  exit 1
fi

# Validação de Família
desc_family=$(echo "$desc_target" | jq -r '.taskDefinition.family // empty')
if [[ "$desc_family" != "$TASK_FAMILY" ]]; then
  log_error "FAMÍLIA INCOMPATÍVEL: A Task Definition '$target_task_def' pertence à família '$desc_family', mas o ambiente '$TARGET_ENV' requer '$TASK_FAMILY'."
  exit 1
fi

# Validação de Status ACTIVE
desc_status=$(echo "$desc_target" | jq -r '.taskDefinition.status // empty')
if [[ "$desc_status" != "ACTIVE" ]]; then
  log_error "STATUS INVÁLIDO: A Task Definition '$target_task_def' está com status '$desc_status'. Apenas Task Definitions com status 'ACTIVE' podem ser associadas ao serviço."
  exit 1
fi

# Salvaguarda: Inspeciona se a revisão alvo possui comando forçando exit 1
if echo "$desc_target" | jq -e '
  .taskDefinition.containerDefinitions[] |
  select(.command != null) |
  .command | tostring | contains("exit 1")
' >/dev/null 2>&1; then
  log_error "BLOQUEIO DE SEGURANÇA: A revisão alvo ($target_task_def) contém comando com terminação forçada ('exit 1')."
  log_error "Rollback cancelado para proteger o serviço."
  exit 1
fi

# Executar comutação direta do serviço ECS para a revisão selecionada (sem build, push ou nova task def)
log_info "Atualizando serviço '$SERVICE' diretamente para '$target_task_def'..."
"${AWS_CMD[@]}" ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$target_task_def" > /dev/null

log_info "Aguardando convergência do serviço no cluster (wait services-stable)..."
"${AWS_CMD[@]}" ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE"

log_success "Serviço comutado com sucesso para a revisão: $target_task_def"

# Smoke test pós-rollback
if [[ "$skip_smoke_test" == false ]]; then
  log_step "Execução do Smoke Test HTTP pós-Rollback no Endpoint do ALB"
  log_info "URL de validação: $ALB_URL"

  success_count=0
  for ((i=1; i<=3; i++)); do
    http_res=$(curl -s -w "%{http_code}|%{time_total}" -o "$TEMP_DIR/resp.txt" --max-time 5 "$ALB_URL" || echo "000|0")
    http_code=$(echo "$http_res" | cut -d'|' -f1)
    http_time=$(echo "$http_res" | cut -d'|' -f2)
    resp_body=$(cat "$TEMP_DIR/resp.txt" 2>/dev/null || echo "")

    if [[ "$http_code" == "200" ]]; then
      success_count=$((success_count + 1))
      log_info "  [Tentativa $i/3] HTTP $http_code (${http_time}s) - Payload: \"$resp_body\""
    else
      log_warn "  [Tentativa $i/3] HTTP $http_code (${http_time}s) - Resposta transitória inesperada..."
    fi
    sleep 2
  done

  if [[ "$success_count" -ge 2 ]]; then
    log_success "Smoke test aprovado pós-rollback!"
  else
    log_error "Smoke test pós-rollback reprovado ($success_count/3 sucessos)."
    exit 3
  fi
fi

log_success "Rollback concluído e homologado com sucesso para a revisão: $target_task_def"
