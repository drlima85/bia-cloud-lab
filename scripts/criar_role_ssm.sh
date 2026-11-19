#!/bin/bash
# Script: criar_role_ssm.sh
# Finalidade: Criação da IAM Role e Instance Profile para acesso via AWS Systems Manager (SSM)
# Referência: Formação AWS (Henrylle Maia) | Parametrização e Idempotência: BIA Cloud Lab (Danilo Lima)

set -e

# Resolução dinâmica do diretório do script para localização de arquivos de política
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validação fail-fast de pré-requisitos locais
if ! command -v aws >/dev/null 2>&1; then
    echo "> [ERRO] O utilitário 'aws' (AWS CLI) não foi encontrado no PATH." >&2
    exit 1
fi

# Configuração de perfil AWS com suporte a variáveis de ambiente
PROFILE_ARGS=()
if [ -n "$AWS_PROFILE" ]; then
    PROFILE_ARGS=(--profile "$AWS_PROFILE")
fi
AWS_CMD=(aws "${PROFILE_ARGS[@]}")

# Parametrização com valores padrão originais do laboratório
ROLE_NAME="${ROLE_NAME:-role-acesso-ssm}"
POLICY_NAME="${POLICY_NAME:-AmazonSSMManagedInstanceCore}"
TRUST_POLICY_FILE="${TRUST_POLICY_FILE:-$SCRIPT_DIR/ec2_principal.json}"

# Validação fail-fast do arquivo de Trust Policy
if [ ! -f "$TRUST_POLICY_FILE" ]; then
    echo "> [ERRO] Arquivo de Trust Policy não encontrado: $TRUST_POLICY_FILE" >&2
    exit 1
fi

# Função auxiliar para diagnóstico seguro de erros da AWS CLI
handle_aws_error() {
    local err_output="$1"
    local action_context="$2"

    if echo "$err_output" | grep -qiE "AccessDenied|UnauthorizedOperation"; then
        echo "> [ERRO FATAL] Acesso negado (AccessDenied) ao $action_context." >&2
        echo "               A credencial AWS ativa não possui permissões IAM necessárias." >&2
        exit 1
    elif echo "$err_output" | grep -qiE "ExpiredToken|InvalidClientTokenId|AuthFailure"; then
        echo "> [ERRO FATAL] Credenciais AWS inválidas ou expiradas ao $action_context." >&2
        exit 1
    fi
}

echo "==> Verificando existência da IAM Role '$ROLE_NAME'..."
role_check_output=$("${AWS_CMD[@]}" iam get-role --role-name "$ROLE_NAME" 2>&1) && role_exists=true || role_exists=false

if [ "$role_exists" = "true" ]; then
    echo "    IAM Role '$ROLE_NAME' já existe."
else
    handle_aws_error "$role_check_output" "consultar a IAM Role '$ROLE_NAME'"
    if echo "$role_check_output" | grep -qi "NoSuchEntity"; then
        echo "==> Criando a IAM Role '$ROLE_NAME'..."
        if ! create_role_err=$("${AWS_CMD[@]}" iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document "file://$TRUST_POLICY_FILE" 2>&1); then
            handle_aws_error "$create_role_err" "criar a IAM Role '$ROLE_NAME'"
            echo "> [ERRO] Falha ao criar a IAM Role '$ROLE_NAME': $create_role_err" >&2
            exit 1
        fi
        echo "    IAM Role '$ROLE_NAME' criada com sucesso."
    else
        echo "> [ERRO] Falha inesperada ao verificar a IAM Role '$ROLE_NAME': $role_check_output" >&2
        exit 1
    fi
fi

echo "==> Verificando existência do Instance Profile '$ROLE_NAME'..."
profile_check_output=$("${AWS_CMD[@]}" iam get-instance-profile --instance-profile-name "$ROLE_NAME" 2>&1) && profile_exists=true || profile_exists=false

if [ "$profile_exists" = "true" ]; then
    echo "    Instance Profile '$ROLE_NAME' já existe."
else
    handle_aws_error "$profile_check_output" "consultar o Instance Profile '$ROLE_NAME'"
    if echo "$profile_check_output" | grep -qi "NoSuchEntity"; then
        echo "==> Criando o Instance Profile '$ROLE_NAME'..."
        if ! create_profile_err=$("${AWS_CMD[@]}" iam create-instance-profile \
            --instance-profile-name "$ROLE_NAME" 2>&1); then
            handle_aws_error "$create_profile_err" "criar o Instance Profile '$ROLE_NAME'"
            echo "> [ERRO] Falha ao criar o Instance Profile '$ROLE_NAME': $create_profile_err" >&2
            exit 1
        fi
        echo "    Instance Profile '$ROLE_NAME' criado com sucesso."
    else
        echo "> [ERRO] Falha inesperada ao verificar o Instance Profile '$ROLE_NAME': $profile_check_output" >&2
        exit 1
    fi
fi

echo "==> Verificando associação da Role ao Instance Profile..."
role_attached=$("${AWS_CMD[@]}" iam get-instance-profile --instance-profile-name "$ROLE_NAME" \
    --query "InstanceProfile.Roles[?RoleName=='$ROLE_NAME'].RoleName" --output text 2>&1) || true

if [ "$role_attached" = "$ROLE_NAME" ]; then
    echo "    Role '$ROLE_NAME' já está vinculada ao Instance Profile."
else
    echo "==> Vinculando a Role ao Instance Profile..."
    if ! add_role_err=$("${AWS_CMD[@]}" iam add-role-to-instance-profile \
        --instance-profile-name "$ROLE_NAME" \
        --role-name "$ROLE_NAME" 2>&1); then
        handle_aws_error "$add_role_err" "vincular a Role ao Instance Profile"
        if echo "$add_role_err" | grep -qi "LimitExceeded"; then
            echo "> [ERRO] Limite de roles por instance profile atingido: $add_role_err" >&2
            exit 1
        else
            echo "> [ERRO] Falha ao vincular Role ao Instance Profile: $add_role_err" >&2
            exit 1
        fi
    fi
    echo "    Role vinculada ao Instance Profile com sucesso."
fi

echo "==> Verificando política gerenciada '$POLICY_NAME' na role '$ROLE_NAME'..."
policy_attached=$("${AWS_CMD[@]}" iam list-attached-role-policies --role-name "$ROLE_NAME" \
    --query "AttachedPolicies[?PolicyName=='$POLICY_NAME'].PolicyName" --output text 2>&1) || true

if [ "$policy_attached" = "$POLICY_NAME" ]; then
    echo "    Managed policy '$POLICY_NAME' já está anexada à role."
else
    echo "==> Anexando a managed policy '$POLICY_NAME'..."
    if ! attach_err=$("${AWS_CMD[@]}" iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/$POLICY_NAME" 2>&1); then
        handle_aws_error "$attach_err" "anexar a política '$POLICY_NAME' à role '$ROLE_NAME'"
        echo "> [ERRO] Falha ao anexar política à role: $attach_err" >&2
        exit 1
    fi
    echo "    Managed policy anexada com sucesso."
fi

echo "==> [SUCESSO] Role e Instance Profile '$ROLE_NAME' validados e prontos para uso."
