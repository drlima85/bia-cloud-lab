#!/usr/bin/env bash
# ==============================================================================
# Script: build-and-push-ecr.sh
# Finalidade: Compilação da imagem Docker multi-stage da aplicação BIA e envio
#             (push) para o Amazon ECR com parametrização dinâmica e segura.
# Trilha: AWS Elastic Beanstalk (Desafio 01 - eb-docker-deploy)
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. Configuração de Variáveis e Parâmetros com Fallbacks Seguros
# ------------------------------------------------------------------------------
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
AWS_PROFILE="${AWS_PROFILE:-}"
ECR_REPO_NAME="${ECR_REPO_NAME:-bia}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
DOCKER_BUILD_DIR="${DOCKER_BUILD_DIR:-}"

# Função de exibição de ajuda
mostrar_ajuda() {
    cat <<EOF
Uso: $(basename "$0") [OPÇÕES]

Compila a imagem Docker da BIA e envia para o Amazon ECR de forma parametrizada.

Opções / Variáveis de Ambiente suportadas:
  --region REGION       Região AWS (padrão: us-east-1 ou \$AWS_REGION)
  --account-id ID       ID da conta AWS de 12 dígitos (padrão: \$AWS_ACCOUNT_ID ou obtido via STS)
  --repo NOME           Nome do repositório ECR (padrão: bia ou \$ECR_REPO_NAME)
  --tag TAG             Tag da imagem Docker (padrão: hash Git curta ou \$IMAGE_TAG)
  --profile PERFIL      Perfil de credenciais AWS CLI (padrão: \$AWS_PROFILE)
  --dir CAMINHO         Diretório raiz da aplicação onde reside o Dockerfile
  -h, --help            Exibe esta mensagem de ajuda

Exemplo de uso:
  AWS_REGION=us-east-1 AWS_PROFILE=formacaoaws $(basename "$0")
EOF
    exit 0
}

# Tratamento de argumentos posicionais / flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --account-id)
            AWS_ACCOUNT_ID="$2"
            shift 2
            ;;
        --repo)
            ECR_REPO_NAME="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --dir)
            DOCKER_BUILD_DIR="$2"
            shift 2
            ;;
        -h|--help)
            mostrar_ajuda
            ;;
        *)
            echo "[-] Parâmetro desconhecido: $1" >&2
            mostrar_ajuda
            ;;
    esac
done

echo "=============================================================================="
echo " [BIA LAB] Compilação e Envio de Imagem para o Amazon ECR"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# 2. Validação de Dependências e Pré-requisitos do Sistema
# ------------------------------------------------------------------------------
for cmd in docker aws git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[-] Erro: Dependência obrigatória '$cmd' não está instalada ou não está no PATH." >&2
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    echo "[-] Erro: O daemon do Docker não está em execução ou o usuário não tem permissão." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Validações Defensivas de Região e Repositório ECR
# ------------------------------------------------------------------------------
# Validação do formato canônico de Região AWS (ex: us-east-1, sa-east-1, eu-west-1)
if [[ ! "$AWS_REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]]; then
    echo "[-] Erro: Região AWS inválida ('$AWS_REGION'). Formato canônico esperado: ex. us-east-1, sa-east-1." >&2
    exit 1
fi

# Validação do nome do repositório ECR (letras minúsculas, números, '.', '_', '-', '/', entre 2 e 256 caracteres)
if [[ ! "$ECR_REPO_NAME" =~ ^[a-z0-9][a-z0-9._/-]{1,255}$ ]]; then
    echo "[-] Erro: Nome do repositório ECR inválido ('$ECR_REPO_NAME')." >&2
    echo "    Deve iniciar com letra minúscula ou dígito e conter entre 2 e 256 caracteres válidos." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 4. Resolução e Validação da Tag da Imagem e Conta AWS
# ------------------------------------------------------------------------------
# Se a TAG não foi informada, extrai do commit Git atual
if [[ -z "$IMAGE_TAG" ]]; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        IMAGE_TAG=$(git rev-parse --short=7 HEAD)
        echo "[+] Tag de imagem obtida via commit Git: ${IMAGE_TAG}"
    else
        echo "[-] Erro: IMAGE_TAG não definida e o diretório atual não é um repositório Git." >&2
        echo "    Por favor, defina IMAGE_TAG=<versao> antes de executar o script." >&2
        exit 1
    fi
fi

# Validação defensiva do formato da Tag da Imagem Docker
# (Permite letras, números, '.', '_', '-', até 128 caracteres, iniciando com caractere alfanumérico ou underscore)
if [[ ! "$IMAGE_TAG" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]]; then
    echo "[-] Erro: Tag da imagem Docker inválida ('$IMAGE_TAG')." >&2
    echo "    Deve conter até 128 caracteres válidos (alfanuméricos, '.', '_', '-')." >&2
    exit 1
fi

# Monta os argumentos de profile para o AWS CLI
AWS_CLI_ARGS=()
if [[ -n "$AWS_PROFILE" ]]; then
    AWS_CLI_ARGS+=(--profile "$AWS_PROFILE")
fi

# Se o ID da conta não foi informado, obtém dinamicamente via STS
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    echo "[+] Obtendo ID da conta AWS dinamicamente via STS..."
    if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text "${AWS_CLI_ARGS[@]}" 2>/dev/null); then
        echo "[-] Erro: Não foi possível obter o ID da conta via AWS STS." >&2
        echo "    Verifique suas credenciais AWS ou exporte explicitamente AWS_ACCOUNT_ID=<12_digitos>." >&2
        exit 1
    fi
fi

# Validação estrita do formato do Account ID (12 dígitos numéricos)
if [[ ! "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    echo "[-] Erro: O ID da conta AWS informado ('$AWS_ACCOUNT_ID') é inválido. Esperados 12 dígitos." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# 5. Localização do Dockerfile
# ------------------------------------------------------------------------------
if [[ -z "$DOCKER_BUILD_DIR" ]]; then
    # Tenta localizar o Dockerfile subindo na árvore de diretórios
    CURRENT_SCAN_DIR="$(pwd)"
    while [[ "$CURRENT_SCAN_DIR" != "/" ]]; do
        if [[ -f "$CURRENT_SCAN_DIR/Dockerfile" ]]; then
            DOCKER_BUILD_DIR="$CURRENT_SCAN_DIR"
            break
        fi
        CURRENT_SCAN_DIR="$(dirname "$CURRENT_SCAN_DIR")"
    done
fi

if [[ -z "$DOCKER_BUILD_DIR" || ! -f "$DOCKER_BUILD_DIR/Dockerfile" ]]; then
    echo "[-] Erro: Dockerfile não localizado. Defina --dir <caminho_do_monorepo>." >&2
    exit 1
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_IMAGE_URI="${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"

echo "------------------------------------------------------------------------------"
echo " Região AWS:       ${AWS_REGION}"
echo " Conta AWS:        ${AWS_ACCOUNT_ID}"
echo " Repositório ECR:  ${ECR_REPO_NAME}"
echo " Tag da Imagem:    ${IMAGE_TAG}"
echo " URI Completa ECR: ${ECR_IMAGE_URI}"
echo " Contexto Docker:  ${DOCKER_BUILD_DIR}"
if [[ -n "$AWS_PROFILE" ]]; then
    echo " Perfil AWS CLI:   ${AWS_PROFILE}"
fi
echo "------------------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 6. Autenticação no Amazon ECR
# ------------------------------------------------------------------------------
echo "[+] Autenticando Docker no Amazon ECR (${ECR_REGISTRY})..."
aws ecr get-login-password --region "${AWS_REGION}" "${AWS_CLI_ARGS[@]}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# ------------------------------------------------------------------------------
# 7. Compilação da Imagem Docker
# ------------------------------------------------------------------------------
echo "[+] Compilando imagem Docker localmente (${ECR_REPO_NAME}:latest)..."
docker build -t "${ECR_REPO_NAME}:latest" -f "${DOCKER_BUILD_DIR}/Dockerfile" "${DOCKER_BUILD_DIR}"

# ------------------------------------------------------------------------------
# 8. Tag e Envio para o Amazon ECR
# ------------------------------------------------------------------------------
echo "[+] Aplicando tag para envio ao ECR (${ECR_IMAGE_URI})..."
docker tag "${ECR_REPO_NAME}:latest" "${ECR_IMAGE_URI}"

echo "[+] Enviando imagem para o Amazon ECR..."
docker push "${ECR_IMAGE_URI}"

echo "------------------------------------------------------------------------------"
echo "[✓] Imagem publicada com sucesso no Amazon ECR:"
echo "    ${ECR_IMAGE_URI}"
echo "=============================================================================="
