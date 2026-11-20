#!/usr/bin/env bash
# ==============================================================================
# Script: package-eb-release.sh
# Finalidade: Geração parametrizada e sanitizada do pacote de entrega (.zip)
#             para implantação no AWS Elastic Beanstalk (Docker Compose).
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
OUTPUT_DIR="${OUTPUT_DIR:-.}"
BUNDLE_NAME="${BUNDLE_NAME:-}"
TMP_WORKSPACE=""

# Função de exibição de ajuda
mostrar_ajuda() {
    cat <<EOF
Uso: $(basename "$0") [OPÇÕES]

Gera o pacote de release (.zip) sanitizado para o AWS Elastic Beanstalk.
O bundle contém exclusivamente o manifesto declarativo 'docker-compose.yml',
sem expor senhas, credenciais em texto claro ou incluir arquivos '.env'.

Opções / Variáveis de Ambiente suportadas:
  --region REGION         Região AWS (padrão: us-east-1 ou \$AWS_REGION)
  --account-id ID         ID da conta AWS de 12 dígitos (padrão: \$AWS_ACCOUNT_ID ou via STS)
  --repo NOME             Nome do repositório ECR (padrão: bia ou \$ECR_REPO_NAME)
  --tag TAG               Tag da imagem da release (padrão: hash Git curta ou \$IMAGE_TAG)
  --profile PERFIL        Perfil de credenciais AWS CLI (padrão: \$AWS_PROFILE)
  --output-dir DIR        Diretório onde o .zip será salvo (padrão: diretório atual)
  --bundle-name NOME      Nome customizado do arquivo zip de saída
  -h, --help              Exibe esta mensagem de ajuda

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
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --bundle-name)
            BUNDLE_NAME="$2"
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
echo " [BIA LAB] Empacotamento de Release para o AWS Elastic Beanstalk"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# 2. Validação de Dependências e Pré-requisitos
# ------------------------------------------------------------------------------
for cmd in zip unzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[-] Erro: Utilitário obrigatório '$cmd' não está instalado ou não está no PATH." >&2
        exit 1
    fi
done

# Monta os argumentos de profile para o AWS CLI
AWS_CLI_ARGS=()
if [[ -n "$AWS_PROFILE" ]]; then
    AWS_CLI_ARGS+=(--profile "$AWS_PROFILE")
fi

# Validação defensiva do formato canônico de Região AWS (ex: us-east-1, sa-east-1)
if [[ ! "$AWS_REGION" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]]; then
    echo "[-] Erro: Região AWS inválida ('$AWS_REGION'). Formato canônico esperado: ex. us-east-1, sa-east-1." >&2
    exit 1
fi

# Validação defensiva do nome do repositório ECR
if [[ ! "$ECR_REPO_NAME" =~ ^[a-z0-9][a-z0-9._/-]{1,255}$ ]]; then
    echo "[-] Erro: Nome do repositório ECR inválido ('$ECR_REPO_NAME')." >&2
    echo "    Deve iniciar com letra minúscula ou dígito e conter entre 2 e 256 caracteres válidos." >&2
    exit 1
fi

# Resolução e Validação da Tag da Imagem
if [[ -z "$IMAGE_TAG" ]]; then
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        IMAGE_TAG=$(git rev-parse --short=7 HEAD)
        echo "[+] Tag obtida do commit Git: ${IMAGE_TAG}"
    else
        echo "[-] Erro: IMAGE_TAG não definida e não foi possível obter via Git." >&2
        echo "    Defina explicitamente IMAGE_TAG=<tag> para continuar." >&2
        exit 1
    fi
fi

# Validação defensiva da Tag da Imagem Docker
if [[ ! "$IMAGE_TAG" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]]; then
    echo "[-] Erro: Tag da imagem Docker inválida ('$IMAGE_TAG')." >&2
    echo "    Deve conter até 128 caracteres válidos (alfanuméricos, '.', '_', '-')." >&2
    exit 1
fi

# Resolução e Validação do Account ID
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    if command -v aws >/dev/null 2>&1; then
        echo "[+] Obtendo ID da conta AWS via STS..."
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text "${AWS_CLI_ARGS[@]}" 2>/dev/null || true)
    fi
fi

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    echo "[-] Erro: ID da conta AWS não definido." >&2
    echo "    Exporte AWS_ACCOUNT_ID=<12_digitos> ou configure credenciais válidas do AWS CLI." >&2
    exit 1
fi

if [[ ! "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
    echo "[-] Erro: O ID da conta AWS informado ('$AWS_ACCOUNT_ID') é inválido. Esperados 12 dígitos." >&2
    exit 1
fi

# Configuração do nome do bundle
if [[ -z "$BUNDLE_NAME" ]]; then
    BUNDLE_NAME="bia-versao-${IMAGE_TAG}.zip"
fi

# Resolução do diretório de saída
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR_ABS=$(cd "$OUTPUT_DIR" && pwd)
TARGET_ZIP="${OUTPUT_DIR_ABS}/${BUNDLE_NAME}"

# ------------------------------------------------------------------------------
# 3. Proteção contra Sobrescrita Acidental de Artefatos Existentes
# ------------------------------------------------------------------------------
if [[ -e "$TARGET_ZIP" ]]; then
    echo "[-] Erro: O arquivo de entrega já existe em: ${TARGET_ZIP}" >&2
    echo "    Para evitar perda ou sobrescrita acidental de versões existentes, o empacotamento foi interrompido." >&2
    echo "    Ações recomendadas:" >&2
    echo "      1. Mova ou renomeie o arquivo existente se desejar mantê-lo." >&2
    echo "      2. Especifique um nome alternativo via --bundle-name <novo_nome>.zip." >&2
    exit 1
fi

ECR_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${IMAGE_TAG}"

echo "------------------------------------------------------------------------------"
echo " Região AWS:       ${AWS_REGION}"
echo " Conta AWS:        ${AWS_ACCOUNT_ID}"
echo " Repositório ECR:  ${ECR_REPO_NAME}"
echo " Tag da Versão:    ${IMAGE_TAG}"
echo " Imagem Alvo:      ${ECR_IMAGE_URI}"
echo " Arquivo de Saída: ${TARGET_ZIP}"
echo "------------------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 4. Workspace Temporário Isolado com Limpeza Defensiva
# ------------------------------------------------------------------------------
TMP_WORKSPACE=$(mktemp -d -t bia-eb-bundle-XXXXXX)

limpar_workspace_temporario() {
    local exit_code=$?
    if [[ -n "${TMP_WORKSPACE:-}" && -d "${TMP_WORKSPACE}" ]]; then
        # Validação defensiva rigorosa: apenas remove caminhos temporários seguros
        case "${TMP_WORKSPACE}" in
            /tmp/bia-eb-bundle-*|/var/tmp/bia-eb-bundle-*)
                rm -rf "${TMP_WORKSPACE}"
                ;;
            *)
                echo "[!] Alerta de Segurança: Caminho temporário fora do padrão esperado não removido: ${TMP_WORKSPACE}" >&2
                ;;
        esac
    fi
    exit "$exit_code"
}
trap limpar_workspace_temporario EXIT INT TERM

# ------------------------------------------------------------------------------
# 5. Geração do Manifesto Docker Compose Sanitizado
# ------------------------------------------------------------------------------
# As variáveis sensíveis de banco de dados (DB_PWD, DB_HOST) NUNCA são gravadas com
# valores em texto claro neste arquivo. Elas permanecem referenciadas literalmente
# como variáveis de ambiente (${DB_PWD}, ${DB_HOST}) que o Elastic Beanstalk
# injeta em tempo de execução via Environment properties.
echo "[+] Gerando manifesto declarativo docker-compose.yml sanitizado..."

cat <<EOF > "${TMP_WORKSPACE}/docker-compose.yml"
# ==============================================================================
# Manifesto Declarativo de Execução - AWS Elastic Beanstalk
# Versão: ${IMAGE_TAG}
# Plataforma: Docker running on 64bit Amazon Linux 2023 (ou AL2)
# ==============================================================================
services:
  server:
    image: ${ECR_IMAGE_URI}
    container_name: bia
    restart: always
    ports:
      - "80:8080"
    environment:
      DB_USER: \${DB_USER:-postgres}
      DB_PWD: \${DB_PWD}
      DB_PORT: \${DB_PORT:-5432}
      DB_HOST: \${DB_HOST}
EOF

# ------------------------------------------------------------------------------
# 6. Compactação do Pacote de Release (.zip)
# ------------------------------------------------------------------------------
echo "[+] Empacotando artefato de release em '${TARGET_ZIP}'..."
(
    cd "$TMP_WORKSPACE"
    zip -q -9 "$TARGET_ZIP" docker-compose.yml
)

# ------------------------------------------------------------------------------
# 7. Auditoria Aprofundada do Pacote Gerado (Nomes e Conteúdo)
# ------------------------------------------------------------------------------
echo "[+] Auditando estrutura e arquivos do pacote ZIP..."
ZIP_CONTENTS=$(unzip -l "$TARGET_ZIP")
echo "$ZIP_CONTENTS"

# Validação 7.1: Exclusividade de arquivos no pacote
if echo "$ZIP_CONTENTS" | grep -Ei '(\.env|\.pem|\.key|credentials|secret)' >/dev/null 2>&1; then
    echo "[-] ERRO CRÍTICO: O bundle gerado contém arquivos confidenciais inesperados!" >&2
    rm -f "$TARGET_ZIP"
    exit 1
fi

echo "[+] Auditando conteúdo interno do manifesto para resolução em runtime..."
MANIFEST_CONTENT=$(unzip -p "$TARGET_ZIP" docker-compose.yml)

# Validação 7.2: Garantir que as variáveis de runtime foram preservadas literalmente
for var in 'DB_HOST: ${DB_HOST}' 'DB_PWD: ${DB_PWD}' 'DB_USER: ${DB_USER:-postgres}' 'DB_PORT: ${DB_PORT:-5432}'; do
    if ! echo "$MANIFEST_CONTENT" | grep -F "$var" >/dev/null 2>&1; then
        echo "[-] ERRO CRÍTICO: A cláusula esperada '$var' não foi encontrada literalmente no manifesto gerado!" >&2
        rm -f "$TARGET_ZIP"
        exit 1
    fi
done

echo "[✓] Auditoria concluída: referências de variáveis literais preservadas para runtime."

FILE_SIZE=$(du -h "$TARGET_ZIP" | cut -f1)

echo "------------------------------------------------------------------------------"
echo "[✓] Pacote de release gerado com sucesso!"
echo "    Arquivo:  ${TARGET_ZIP}"
echo "    Tamanho:  ${FILE_SIZE}"
echo ""
echo "    Próximos passos para deploy manual ou via EB CLI:"
echo "    1. Configure as Environment Properties no ambiente Elastic Beanstalk:"
echo "       DB_HOST, DB_USER, DB_PWD, DB_PORT"
echo "    2. Realize o upload do bundle via Console Web ou utilize o comando oficial:"
echo "       eb deploy (ou aws elasticbeanstalk create-application-version)"
echo "=============================================================================="
