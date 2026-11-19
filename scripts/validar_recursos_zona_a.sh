#!/bin/bash
# Script: validar_recursos_zona_a.sh
# Finalidade: Auditoria pós-provisionamento da VPC, Subnet, Security Group e IAM Role
# Referência: Formação AWS (Henrylle Maia) | Parametrização: BIA Cloud Lab (Danilo Lima)

# Configuração de perfil e região da AWS com suporte a variáveis de ambiente
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROFILE_ARGS=()
if [ -n "$AWS_PROFILE" ]; then
    PROFILE_ARGS=(--profile "$AWS_PROFILE")
fi
AWS_CMD=(aws --region "$REGION" "${PROFILE_ARGS[@]}")

# Parametrização com valores padrão originais do laboratório
SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME:-bia-dev}"
ROLE_NAME="${ROLE_NAME:-role-acesso-ssm}"
PORT_TO_CHECK="${PORT_TO_CHECK:-3001}"
AVAILABILITY_ZONE="${AVAILABILITY_ZONE:-${REGION}a}"

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

echo "==> Iniciando validação de infraestrutura na região $REGION..."

# 1. Validação da VPC Default
if ! vpc_raw=$("${AWS_CMD[@]}" ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text 2>&1); then
    handle_aws_error "$vpc_raw" "consultar VPC default na região $REGION"
    echo "> [AVISO] Erro na consulta de VPC: $vpc_raw" >&2
    vpc_id=""
else
    vpc_id=$(echo "$vpc_raw" | tr -d '\r\n')
fi

if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
    echo "[OK] Tudo certo com a VPC: $vpc_id"
else
    echo ">[ERRO] Tenho um problema ao retornar a VPC default. Será se ela existe?"
fi

# 2. Validação da Subnet na Zona A
if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
    if ! subnet_raw=$("${AWS_CMD[@]}" ec2 describe-subnets --filters Name=vpc-id,Values="$vpc_id" Name=availabilityZone,Values="$AVAILABILITY_ZONE" --query "Subnets[0].SubnetId" --output text 2>&1); then
        handle_aws_error "$subnet_raw" "consultar Subnet na zona $AVAILABILITY_ZONE"
        echo "> [AVISO] Erro na consulta de Subnet: $subnet_raw" >&2
        subnet_id=""
    else
        subnet_id=$(echo "$subnet_raw" | tr -d '\r\n')
    fi
else
    subnet_id=""
fi

if [ -n "$subnet_id" ] && [ "$subnet_id" != "None" ]; then
    echo "[OK] Tudo certo com a Subnet na zona $AVAILABILITY_ZONE: $subnet_id"
else
    echo ">[ERRO] Tenho um problema ao retornar a subnet da zona a. Será se existe uma subnet na zona A?"
fi

# 3. Validação do Security Group
if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
    if ! sg_raw=$("${AWS_CMD[@]}" ec2 describe-security-groups --filters Name=vpc-id,Values="$vpc_id" Name=group-name,Values="$SECURITY_GROUP_NAME" --query "SecurityGroups[0].GroupId" --output text 2>&1); then
        handle_aws_error "$sg_raw" "consultar Security Group '$SECURITY_GROUP_NAME'"
        echo "> [AVISO] Erro na consulta do Security Group: $sg_raw" >&2
        security_group_id=""
    else
        security_group_id=$(echo "$sg_raw" | tr -d '\r\n')
    fi
else
    security_group_id=""
fi

if [ -n "$security_group_id" ] && [ "$security_group_id" != "None" ]; then
    echo "[OK] Security Group $SECURITY_GROUP_NAME foi criado: $security_group_id"
  
    # Validar inbound rule para o security group
    if ! inbound_rule=$("${AWS_CMD[@]}" ec2 describe-security-groups --group-ids "$security_group_id" --filters "Name=ip-permission.from-port,Values=$PORT_TO_CHECK" --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" --output text 2>&1); then
        handle_aws_error "$inbound_rule" "consultar regras de entrada do SG $security_group_id"
        inbound_rule=""
    fi

    if [ -n "$inbound_rule" ]; then
        echo " [OK] Regra de entrada está ok (porta $PORT_TO_CHECK)"
    else
        echo " >[ERRO] Regra de entrada para a porta $PORT_TO_CHECK não encontrada ou não está aberta para o mundo todo. Reveja a aula do Henrylle"
    fi

    # Validar outbound rule para o security group
    if ! outbound_rule=$("${AWS_CMD[@]}" ec2 describe-security-groups --group-ids "$security_group_id" --query "SecurityGroups[0].IpPermissionsEgress[?IpProtocol=='-1' && IpRanges[0].CidrIp=='0.0.0.0/0']" --output text 2>&1); then
        handle_aws_error "$outbound_rule" "consultar regras de saída do SG $security_group_id"
        outbound_rule=""
    fi
  
    if [ -n "$outbound_rule" ]; then
        echo " [OK] Regra de saída está correta"
    else
        echo " >[ERRO] Regra de saída para o mundo não encontrada. Reveja a aula do Henrylle"
    fi
else
    echo ">[ERRO] Não achei o security group $SECURITY_GROUP_NAME. Ele foi criado?"
fi

# 4. Validação da IAM Role para o SSM
if role_raw=$("${AWS_CMD[@]}" iam get-role --role-name "$ROLE_NAME" 2>&1); then
    echo "[OK] Tudo certo com a role '$ROLE_NAME'"
else
    handle_aws_error "$role_raw" "consultar a IAM Role '$ROLE_NAME'"
    if echo "$role_raw" | grep -qi "NoSuchEntity"; then
        echo ">[ERRO] A role '$ROLE_NAME' não existe"
    else
        echo ">[ERRO] Falha ao verificar a role '$ROLE_NAME': $role_raw"
    fi
fi
