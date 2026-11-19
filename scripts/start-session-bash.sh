#!/bin/bash
# Script: start-session-bash.sh
# Finalidade: Conexão interativa SSH-less à instância EC2 via AWS SSM Session Manager
# Referência: Formação AWS (Henrylle Maia) | Parametrização: BIA Cloud Lab (Danilo Lima)

set -e

# Configuração de perfil e região da AWS com suporte a variáveis de ambiente
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROFILE_ARGS=()
if [ -n "$AWS_PROFILE" ]; then
    PROFILE_ARGS=(--profile "$AWS_PROFILE")
fi
AWS_CMD=(aws --region "$REGION" "${PROFILE_ARGS[@]}")

# Validação fail-fast de pré-requisitos locais
if ! command -v aws >/dev/null 2>&1; then
    echo "> [ERRO] O utilitário 'aws' (AWS CLI) não foi encontrado no PATH." >&2
    exit 1
fi

# Função auxiliar para diagnóstico seguro de erros da AWS CLI
handle_aws_error() {
    local err_output="$1"
    local action_context="$2"

    if echo "$err_output" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
        echo "> [ERRO FATAL] Acesso negado (AccessDenied) ao $action_context." >&2
        echo "               A credencial AWS ativa não possui permissões necessárias." >&2
        exit 1
    elif echo "$err_output" | grep -qiE "ExpiredToken|InvalidClientTokenId|AuthFailure"; then
        echo "> [ERRO FATAL] Credenciais AWS inválidas ou expiradas ao $action_context." >&2
        exit 1
    fi
}

# Resolução do identificador da instância EC2
INSTANCE_ID="$1"
INSTANCE_NAME="${INSTANCE_NAME:-bia-dev}"

if [ -z "$INSTANCE_ID" ]; then
    # Tentar autodescobrir instância ativa com a tag Name configurada
    echo "==> Instance ID não informado como argumento. Buscando instância ativa com tag Name='$INSTANCE_NAME' na região $REGION..."
    if ! desc_raw=$("${AWS_CMD[@]}" ec2 describe-instances \
        --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>&1); then
        handle_aws_error "$desc_raw" "buscar instância ativa '$INSTANCE_NAME'"
        echo "> [AVISO] Falha ao consultar instâncias: $desc_raw" >&2
        INSTANCE_ID=""
    else
        INSTANCE_ID=$(echo "$desc_raw" | tr -d '\r\n')
    fi
fi

# Validação fail-fast se a instância foi localizada
if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo "> [ERRO] Nenhuma instância em execução foi encontrada com a tag Name='$INSTANCE_NAME' na região $REGION." >&2
    echo "         Uso manual: $0 <INSTANCE_ID>" >&2
    exit 1
fi

echo "==> Conectando na instância $INSTANCE_ID via AWS SSM Session Manager (região: $REGION)..."
"${AWS_CMD[@]}" ssm start-session \
    --target "$INSTANCE_ID" \
    --document-name AWS-StartInteractiveCommand \
    --parameters command="bash -l"
