#!/bin/bash
# Script: lancar_ec2_zona_a.sh
# Finalidade: Provisionamento automatizado de instância EC2 para o ambiente BIA Dev
# Referência: Formação AWS (Henrylle Maia) | Adaptação e Parametrização: BIA Cloud Lab (Danilo Lima)

set -e

# Resolução dinâmica do diretório do script para localização de dependências relativas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validação fail-fast de pré-requisitos locais
if ! command -v aws >/dev/null 2>&1; then
    echo "> [ERRO] O utilitário 'aws' (AWS CLI) não foi encontrado no PATH." >&2
    exit 1
fi

# Configuração de perfil e região da AWS com suporte a variáveis de ambiente
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROFILE_ARGS=()
if [ -n "$AWS_PROFILE" ]; then
    PROFILE_ARGS=(--profile "$AWS_PROFILE")
fi
AWS_CMD=(aws --region "$REGION" "${PROFILE_ARGS[@]}")

# Validação de consistência regional da AMI
# AMI padrão do laboratório Formação AWS para us-east-1 (Amazon Linux 2023 x86_64)
DEFAULT_US_EAST_1_AMI="ami-02f3f602d23f1659d"

if [ "$REGION" = "us-east-1" ]; then
    AMI_ID="${AMI_ID:-$DEFAULT_US_EAST_1_AMI}"
else
    if [ -z "$AMI_ID" ]; then
        echo "> [ERRO] A região configurada é '$REGION' (diferente da região padrão 'us-east-1')." >&2
        echo "         Como as AMIs são regionais na AWS, é obrigatório definir a variável AMI_ID correspondente." >&2
        echo "         Exemplo: export AMI_ID=\"ami-xxxxxxxxxxxxxxxxx\" && $0" >&2
        exit 1
    fi
fi

# Parametrização com valores padrão originais do laboratório da Formação AWS
INSTANCE_NAME="${INSTANCE_NAME:-bia-dev}"
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-bia-dev}"
IAM_PROFILE_NAME="${IAM_PROFILE_NAME:-role-acesso-ssm}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
AVAILABILITY_ZONE="${AVAILABILITY_ZONE:-${REGION}a}"
USER_DATA_FILE="${USER_DATA_FILE:-$SCRIPT_DIR/user_data_ec2_zona_a.sh}"

# Validação do arquivo de User Data
if [ ! -f "$USER_DATA_FILE" ]; then
    echo "> [ERRO] Arquivo de User Data não encontrado: $USER_DATA_FILE" >&2
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

echo "==> Buscando VPC default na região $REGION..."
if ! vpc_output=$("${AWS_CMD[@]}" ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text 2>&1); then
    handle_aws_error "$vpc_output" "consultar VPCs na região $REGION"
    echo "> [ERRO] Falha ao consultar VPC default na região $REGION: $vpc_output" >&2
    exit 1
fi
vpc_id=$(echo "$vpc_output" | tr -d '\r\n')

if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ]; then
    echo "> [ERRO] VPC default não foi encontrada na região $REGION." >&2
    exit 1
fi
echo "    VPC ID: $vpc_id"

echo "==> Buscando Subnet na zona de disponibilidade $AVAILABILITY_ZONE..."
if ! subnet_output=$("${AWS_CMD[@]}" ec2 describe-subnets --filters Name=vpc-id,Values="$vpc_id" Name=availabilityZone,Values="$AVAILABILITY_ZONE" --query "Subnets[0].SubnetId" --output text 2>&1); then
    handle_aws_error "$subnet_output" "consultar Subnets na zona $AVAILABILITY_ZONE"
    echo "> [ERRO] Falha ao consultar Subnet na zona $AVAILABILITY_ZONE: $subnet_output" >&2
    exit 1
fi
subnet_id=$(echo "$subnet_output" | tr -d '\r\n')

if [ -z "$subnet_id" ] || [ "$subnet_id" = "None" ]; then
    echo "> [ERRO] Subnet na zona $AVAILABILITY_ZONE não foi encontrada para a VPC $vpc_id." >&2
    exit 1
fi
echo "    Subnet ID: $subnet_id"

echo "==> Buscando Security Group '$SECURITY_GROUP_NAME'..."
if ! sg_output=$("${AWS_CMD[@]}" ec2 describe-security-groups --filters Name=vpc-id,Values="$vpc_id" Name=group-name,Values="$SECURITY_GROUP_NAME" --query "SecurityGroups[0].GroupId" --output text 2>&1); then
    handle_aws_error "$sg_output" "consultar Security Group '$SECURITY_GROUP_NAME'"
    echo "> [ERRO] Falha ao consultar Security Group '$SECURITY_GROUP_NAME': $sg_output" >&2
    exit 1
fi
security_group_id=$(echo "$sg_output" | tr -d '\r\n')

if [ -z "$security_group_id" ] || [ "$security_group_id" = "None" ]; then
    echo ">[ERRO] Security group $SECURITY_GROUP_NAME não foi criado na VPC $vpc_id" >&2
    exit 1
fi
echo "    Security Group ID: $security_group_id"

echo "==> Verificando existência prévia de instâncias '$INSTANCE_NAME' na região $REGION..."
if ! existing_instances_output=$("${AWS_CMD[@]}" ec2 describe-instances \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[][InstanceId,State.Name]" \
    --output text 2>&1); then
    handle_aws_error "$existing_instances_output" "consultar instâncias existentes na região $REGION"
    echo "> [ERRO] Falha ao verificar instâncias existentes na região $REGION: $existing_instances_output" >&2
    exit 1
fi

existing_trimmed=$(echo "$existing_instances_output" | sed '/^[[:space:]]*$/d')

if [ -n "$existing_trimmed" ] && [ "$existing_trimmed" != "None" ]; then
    echo "> [AVISO] Já existe instância '$INSTANCE_NAME' registrada na região $REGION:" >&2
    while IFS=$'\t' read -r inst_id inst_state; do
        if [ -n "$inst_id" ]; then
            echo "          - Instância: $inst_id (Estado: $inst_state)" >&2
        fi
    done <<< "$existing_trimmed"
    echo "          Para evitar cobranças duplicadas de EC2, EBS e IPv4 público, o lançamento foi abortado." >&2
    exit 1
fi
echo "    Nenhuma instância '$INSTANCE_NAME' pré-existente encontrada. Prosseguindo."

echo "==> Lançando instância EC2 '$INSTANCE_NAME' ($INSTANCE_TYPE) com AMI $AMI_ID..."
"${AWS_CMD[@]}" ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$INSTANCE_TYPE" \
    --security-group-ids "$security_group_id" \
    --subnet-id "$subnet_id" \
    --associate-public-ip-address \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":15,"VolumeType":"gp2"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --iam-instance-profile "Name=$IAM_PROFILE_NAME" \
    --user-data "file://$USER_DATA_FILE"

echo "==> [SUCESSO] Comando de criação da instância enviado com êxito."
