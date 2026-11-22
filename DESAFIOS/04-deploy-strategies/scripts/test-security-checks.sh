#!/usr/bin/env bash
# ==============================================================================
# test-security-checks.sh — Testes Locais Automatizados de Segurança e Integridade
# Projeto: BIA Cloud Lab — Formação AWS / D2NS
# Trilha: Estratégias de Deploy & Resiliência (Desafio 02)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-ecs.sh"

# Conta AWS fictícia padrão para a suíte de testes de segurança
export AUTHORIZED_ACCOUNT="123456789012"
export AWS_ACCOUNT_ID="123456789012"

C_GREEN="\033[0;32m"
C_RED="\033[0;31m"
C_BLUE="\033[0;34m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

log_test() { echo -e "\n${C_BLUE}======================================================================${C_RESET}"; echo -e "${C_BOLD}TESTE: $*${C_RESET}"; echo -e "${C_BLUE}======================================================================${C_RESET}"; }
pass() { echo -e "${C_GREEN}[PASS]${C_RESET} $*"; }
fail() { echo -e "${C_RED}[FAIL]${C_RESET} $*"; exit 1; }

TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

# ------------------------------------------------------------------------------
# TESTE 1: Validação de Conta Não Autorizada no STS
# ------------------------------------------------------------------------------
log_test "1. Bloqueio por Conta AWS Não Autorizada (STS)"

MOCK_BIN1="$TEST_TMP/bin1"
mkdir -p "$MOCK_BIN1"
DOCKER_LOG1="$TEST_TMP/docker1.log"
AWS_MUTATION_LOG1="$TEST_TMP/aws_mut1.log"
rm -f "$DOCKER_LOG1" "$AWS_MUTATION_LOG1"

cat << EOF > "$MOCK_BIN1/aws"
#!/usr/bin/env bash
if [[ "\$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "999888777666", "Arn": "arn:aws:iam::999888777666:user/hacker"}'
  exit 0
elif [[ "\$*" == *"register-task-definition"* || "\$*" == *"update-service"* ]]; then
  echo "AWS MUTATION CALLED: \$*" >> "$AWS_MUTATION_LOG1"
fi
exit 0
EOF
chmod +x "$MOCK_BIN1/aws"

cat << EOF > "$MOCK_BIN1/docker"
#!/usr/bin/env bash
if [[ "\$*" == *"build"* || "\$*" == *"push"* ]]; then
  echo "DOCKER INVOKED: \$*" >> "$DOCKER_LOG1"
fi
exit 0
EOF
chmod +x "$MOCK_BIN1/docker"

exit_code1=0
output1=$(PATH="$MOCK_BIN1:$PATH" "$DEPLOY_SCRIPT" deploy --skip-build 2>&1) || exit_code1=$?

if [[ "$exit_code1" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para conta não autorizada."
else
  fail "Código de saída incorreto: esperado 1, obtido $exit_code1."
fi

if echo "$output1" | grep -q "CONTA NÃO AUTORIZADA"; then
  pass "Deploy bloqueado com sucesso com mensagem de conta não autorizada (999888777666)."
else
  fail "Deveria ter bloqueado com mensagem de conta não autorizada. Saída:\n$output1"
fi

if [[ -f "$AWS_MUTATION_LOG1" ]]; then
  fail "MUTAÇÃO AWS FOI CHAMADA INDEVIDAMENTE: $(cat "$AWS_MUTATION_LOG1")"
else
  pass "Zero mutações AWS chamadas durante o bloqueio."
fi

if [[ -f "$DOCKER_LOG1" ]]; then
  fail "DOCKER BUILD/PUSH FOI CHAMADO INDEVIDAMENTE: $(cat "$DOCKER_LOG1")"
else
  pass "Zero chamadas Docker build/push durante o bloqueio."
fi

# ------------------------------------------------------------------------------
# TESTE 2: Falha em describe-task-definition bloqueia ANTES do Docker Build
# ------------------------------------------------------------------------------
log_test "2. Falha em describe-task-definition Bloqueia Antes de Build/Push"

MOCK_BIN2="$TEST_TMP/bin2"
mkdir -p "$MOCK_BIN2"
DOCKER_LOG2="$TEST_TMP/docker2.log"
AWS_MUTATION_LOG2="$TEST_TMP/aws_mut2.log"
rm -f "$DOCKER_LOG2" "$AWS_MUTATION_LOG2"

cat << EOF > "$MOCK_BIN2/aws"
#!/usr/bin/env bash
if [[ "\$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "\$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "\$*" == *"ecs describe-services"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15"
  exit 0
elif [[ "\$*" == *"ecs describe-task-definition"* ]]; then
  echo "An error occurred (ClientException) when calling DescribeTaskDefinition: Service unavailable" >&2
  exit 1
elif [[ "\$*" == *"register-task-definition"* || "\$*" == *"update-service"* ]]; then
  echo "AWS MUTATION CALLED: \$*" >> "$AWS_MUTATION_LOG2"
fi
exit 0
EOF
chmod +x "$MOCK_BIN2/aws"

cat << EOF > "$MOCK_BIN2/docker"
#!/usr/bin/env bash
if [[ "\$*" == *"build"* || "\$*" == *"push"* ]]; then
  echo "DOCKER INVOKED: \$*" >> "$DOCKER_LOG2"
fi
exit 0
EOF
chmod +x "$MOCK_BIN2/docker"

exit_code2=0
output2=$(PATH="$MOCK_BIN2:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty 2>&1) || exit_code2=$?

if [[ "$exit_code2" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para falha no describe."
else
  fail "Código de saída incorreto: esperado 1, obtido $exit_code2."
fi

if echo "$output2" | grep -q "FALHA CRÍTICA: Falha ao executar 'ecs describe-task-definition'"; then
  pass "Deploy bloqueado com código de erro antes do build."
else
  fail "Não detectou mensagem esperada de bloqueio. Saída:\n$output2"
fi

if [[ -f "$AWS_MUTATION_LOG2" ]]; then
  fail "MUTAÇÃO AWS FOI CHAMADA INDEVIDAMENTE: $(cat "$AWS_MUTATION_LOG2")"
else
  pass "Zero mutações AWS chamadas durante o bloqueio."
fi

if [[ -f "$DOCKER_LOG2" ]]; then
  fail "Docker build/push FOI invocado indevidamente após falha no describe! Log:\n$(cat "$DOCKER_LOG2")"
else
  pass "Docker build/push NUNCA foram chamados após falha no describe-task-definition."
fi

# ------------------------------------------------------------------------------
# TESTE 3: Revisão 15 Real é Consultada e Preservada sem Mocks
# ------------------------------------------------------------------------------
log_test "3. Revisão 15 Real é Consultada e Propriedades Preservadas Integralmente"

MOCK_BIN3="$TEST_TMP/bin3"
mkdir -p "$MOCK_BIN3"
export DESCRIBE_CALLED_LOG="$TEST_TMP/describe_called.log"
export CAPTURED_JSON="$TEST_TMP/registered_task_def.json"
rm -f "$DESCRIBE_CALLED_LOG" "$CAPTURED_JSON"

cat << 'EOF' > "$MOCK_BIN3/aws"
#!/usr/bin/env bash
if [[ "$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "$*" == *"ecs describe-services"* && "$*" == *"--query services[0].taskDefinition"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15"
  exit 0
elif [[ "$*" == *"ecs describe-task-definition"* ]]; then
  echo "DESCRIBE CALLED FOR: $*" >> "${DESCRIBE_CALLED_LOG:-/tmp/desc_called.log}"
  cat << 'JSON'
  {
    "family": "task-def-bia-cloud-app",
    "revision": 15,
    "taskDefinitionArn": "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15",
    "status": "ACTIVE",
    "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
    "networkMode": "awsvpc",
    "cpu": "1024",
    "memory": "1024",
    "requiresCompatibilities": ["EC2"],
    "compatibilities": ["EC2"],
    "registeredAt": 1732123456.789,
    "registeredBy": "arn:aws:iam::123456789012:user/AGY-AWS-LAB",
    "placementConstraints": [
      {"type": "memberOf", "expression": "attribute:ecs.os-type == linux"}
    ],
    "containerDefinitions": [
      {
        "name": "bia-cloud-app",
        "image": "123456789012.dkr.ecr.us-east-2.amazonaws.com/bia-cloud-lab:elasticache-v2",
        "essential": true,
        "portMappings": [{"containerPort": 8080, "hostPort": 8080, "protocol": "tcp"}],
        "environment": [
          {"name": "NODE_ENV", "value": "production"},
          {"name": "CUSTOM_PROD_VAR", "value": "SECRET_REAL_15_CONFIRMED"}
        ],
        "secrets": [
          {"name": "DB_PASSWORD", "valueFrom": "arn:aws:ssm:us-east-2:123456789012:parameter/bia/db_password"}
        ]
      }
    ]
  }
JSON
  exit 0
elif [[ "$*" == *"ecs register-task-definition"* ]]; then
  for arg in "$@"; do
    if [[ "$arg" == file://* ]]; then
      cp "${arg#file://}" "${CAPTURED_JSON:-/tmp/captured.json}"
    fi
  done
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:17"
  exit 0
elif [[ "$*" == *"ecs update-service"* ]]; then
  echo '{"service":{"deployments":[{"id":"ecs-dep-test","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:17"}]}}'
  exit 0
elif [[ "$*" == *"ecs describe-services"* ]]; then
  echo '{"desiredCount":1,"runningCount":1,"deployments":[{"status":"PRIMARY","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:17","rolloutState":"COMPLETED"}]}'
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN3/aws"

cat << 'EOF' > "$MOCK_BIN3/docker"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN3/docker"

exit_code3=0
output3=$(PATH="$MOCK_BIN3:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty --skip-build -t 83a1f07 --skip-smoke-test 2>&1) || exit_code3=$?

if [[ "$exit_code3" -eq 0 ]]; then
  pass "Deploy concluído com código 0 em cenário válido."
else
  fail "Deploy falhou inesperadamente com código $exit_code3. Saída:\n$output3"
fi

if [[ ! -f "$DESCRIBE_CALLED_LOG" ]]; then
  fail "describe-task-definition NÃO foi chamado para a revisão 15! Saída:\n$output3"
else
  pass "describe-task-definition chamado com sucesso para a revisão :15 real."
fi

if [[ ! -f "$CAPTURED_JSON" ]]; then
  fail "O JSON registrado não foi capturado. Saída:\n$output3"
fi

# Validações estritas no manifesto capturado enviado ao register-task-definition
has_prod_var=$(jq -r '.containerDefinitions[0].environment[] | select(.name=="CUSTOM_PROD_VAR") | .value' "$CAPTURED_JSON")
if [[ "$has_prod_var" == "SECRET_REAL_15_CONFIRMED" ]]; then
  pass "Variável exclusiva da Revisão 15 preservada com sucesso (não sobrescrita por mock)."
else
  fail "Variável de ambiente da Revisão 15 foi perdida! JSON capturado:\n$(cat "$CAPTURED_JSON")"
fi

has_secret=$(jq -r '.containerDefinitions[0].secrets[] | select(.name=="DB_PASSWORD") | .valueFrom' "$CAPTURED_JSON")
if [[ "$has_secret" == *"arn:aws:ssm"* ]]; then
  pass "Segredos SSM da Revisão 15 preservados com sucesso."
else
  fail "Segredos SSM da Revisão 15 foram perdidos!"
fi

placement_count=$(jq '.placementConstraints | length' "$CAPTURED_JSON")
if [[ "$placement_count" -gt 0 ]]; then
  pass "placementConstraints preservado integralmente."
else
  fail "placementConstraints foi removido indevidamente!"
fi

has_readonly_arn=$(jq 'has("taskDefinitionArn")' "$CAPTURED_JSON")
has_readonly_status=$(jq 'has("status")' "$CAPTURED_JSON")
has_readonly_compat=$(jq 'has("compatibilities")' "$CAPTURED_JSON")
if [[ "$has_readonly_arn" == "false" && "$has_readonly_status" == "false" && "$has_readonly_compat" == "false" ]]; then
  pass "Metadados somente-leitura da AWS (taskDefinitionArn, status, compatibilities) expurgados corretamente."
else
  fail "Metadados somente-leitura permaneceram no JSON de registro!"
fi

# ------------------------------------------------------------------------------
# TESTE 4: Contêiner Ausente na Task Def Base Bloqueia ANTES do Build
# ------------------------------------------------------------------------------
log_test "4. Contêiner Ausente Bloqueia Deploy Antes de Build/Push"

MOCK_BIN4="$TEST_TMP/bin4"
mkdir -p "$MOCK_BIN4"
DOCKER_LOG4="$TEST_TMP/docker4.log"
AWS_MUTATION_LOG4="$TEST_TMP/aws_mut4.log"
rm -f "$DOCKER_LOG4" "$AWS_MUTATION_LOG4"

cat << EOF > "$MOCK_BIN4/aws"
#!/usr/bin/env bash
if [[ "\$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "\$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "\$*" == *"ecs describe-services"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15"
  exit 0
elif [[ "\$*" == *"ecs describe-task-definition"* ]]; then
  cat << 'JSON'
  {
    "family": "task-def-bia-cloud-app",
    "status": "ACTIVE",
    "containerDefinitions": [
      {"name": "bia-cloud-app", "image": "img:v1"}
    ]
  }
JSON
  exit 0
elif [[ "\$*" == *"register-task-definition"* || "\$*" == *"update-service"* ]]; then
  echo "AWS MUTATION CALLED: \$*" >> "$AWS_MUTATION_LOG4"
fi
exit 0
EOF
chmod +x "$MOCK_BIN4/aws"

cat << EOF > "$MOCK_BIN4/docker"
#!/usr/bin/env bash
if [[ "\$*" == *"build"* || "\$*" == *"push"* ]]; then
  echo "DOCKER INVOKED: \$*" >> "$DOCKER_LOG4"
fi
exit 0
EOF
chmod +x "$MOCK_BIN4/docker"

exit_code4=0
output4=$(PATH="$MOCK_BIN4:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty --container-name container_inexistente 2>&1) || exit_code4=$?

if [[ "$exit_code4" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para contêiner inexistente."
else
  fail "Código de saída incorreto: esperado 1, obtido $exit_code4."
fi

if echo "$output4" | grep -q "CONTÊINER NÃO ENCONTRADO: O contêiner 'container_inexistente' não existe"; then
  pass "Bloqueio correto com mensagem de contêiner inexistente."
else
  fail "Não bloqueou para contêiner inexistente. Saída:\n$output4"
fi

if [[ -f "$AWS_MUTATION_LOG4" ]]; then
  fail "MUTAÇÃO AWS FOI CHAMADA INDEVIDAMENTE: $(cat "$AWS_MUTATION_LOG4")"
else
  pass "Zero mutações AWS chamadas durante o bloqueio."
fi

if [[ -f "$DOCKER_LOG4" ]]; then
  fail "Docker build/push FOI invocado antes de validar o contêiner!"
else
  pass "Docker build/push NUNCA foram chamados para contêiner inexistente."
fi

# ------------------------------------------------------------------------------
# TESTE 5: Ambiguidade de Contêiner Bloqueia ANTES do Build
# ------------------------------------------------------------------------------
log_test "5. Ambiguidade de Contêiner (>1) Bloqueia Deploy Antes de Build/Push"

MOCK_BIN5="$TEST_TMP/bin5"
mkdir -p "$MOCK_BIN5"
DOCKER_LOG5="$TEST_TMP/docker5.log"
AWS_MUTATION_LOG5="$TEST_TMP/aws_mut5.log"
rm -f "$DOCKER_LOG5" "$AWS_MUTATION_LOG5"

cat << EOF > "$MOCK_BIN5/aws"
#!/usr/bin/env bash
if [[ "\$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "\$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "\$*" == *"ecs describe-services"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15"
  exit 0
elif [[ "\$*" == *"ecs describe-task-definition"* ]]; then
  cat << 'JSON'
  {
    "family": "task-def-bia-cloud-app",
    "status": "ACTIVE",
    "containerDefinitions": [
      {"name": "bia-cloud-app", "image": "img1:v1"},
      {"name": "bia-cloud-app", "image": "img2:v2"}
    ]
  }
JSON
  exit 0
elif [[ "\$*" == *"register-task-definition"* || "\$*" == *"update-service"* ]]; then
  echo "AWS MUTATION CALLED: \$*" >> "$AWS_MUTATION_LOG5"
fi
exit 0
EOF
chmod +x "$MOCK_BIN5/aws"

cat << EOF > "$MOCK_BIN5/docker"
#!/usr/bin/env bash
if [[ "\$*" == *"build"* || "\$*" == *"push"* ]]; then
  echo "DOCKER INVOKED: \$*" >> "$DOCKER_LOG5"
fi
exit 0
EOF
chmod +x "$MOCK_BIN5/docker"

exit_code5=0
output5=$(PATH="$MOCK_BIN5:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty 2>&1) || exit_code5=$?

if [[ "$exit_code5" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para ambiguidade de contêineres."
else
  fail "Código de saída incorreto: esperado 1, obtido $exit_code5."
fi

if echo "$output5" | grep -q "AMBIGUIDADE DE CONTÊINER: Foram encontrados 2 contêineres"; then
  pass "Bloqueio correto para contêineres duplicados (ambiguidade)."
else
  fail "Não bloqueou para contêineres duplicados. Saída:\n$output5"
fi

if [[ -f "$AWS_MUTATION_LOG5" ]]; then
  fail "MUTAÇÃO AWS FOI CHAMADA INDEVIDAMENTE: $(cat "$AWS_MUTATION_LOG5")"
else
  pass "Zero mutações AWS chamadas durante o bloqueio."
fi

if [[ -f "$DOCKER_LOG5" ]]; then
  fail "Docker build/push FOI invocado antes de detectar ambiguidade!"
else
  pass "Docker build/push NUNCA foram chamados para contêineres ambíguos."
fi

# ------------------------------------------------------------------------------
# TESTE 6: Família Incompatível Bloqueia ANTES do Build
# ------------------------------------------------------------------------------
log_test "6. Família Incompatível Bloqueia Deploy Antes de Build/Push"

MOCK_BIN6="$TEST_TMP/bin6"
mkdir -p "$MOCK_BIN6"
DOCKER_LOG6="$TEST_TMP/docker6.log"
AWS_MUTATION_LOG6="$TEST_TMP/aws_mut6.log"
rm -f "$DOCKER_LOG6" "$AWS_MUTATION_LOG6"

cat << EOF > "$MOCK_BIN6/aws"
#!/usr/bin/env bash
if [[ "\$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "\$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "\$*" == *"ecs describe-services"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-ERRADA:15"
  exit 0
elif [[ "\$*" == *"ecs describe-task-definition"* ]]; then
  cat << 'JSON'
  {
    "family": "task-def-ERRADA",
    "status": "ACTIVE",
    "containerDefinitions": [
      {"name": "bia-cloud-app", "image": "img1:v1"}
    ]
  }
JSON
  exit 0
elif [[ "\$*" == *"register-task-definition"* || "\$*" == *"update-service"* ]]; then
  echo "AWS MUTATION CALLED: \$*" >> "$AWS_MUTATION_LOG6"
fi
exit 0
EOF
chmod +x "$MOCK_BIN6/aws"

cat << EOF > "$MOCK_BIN6/docker"
#!/usr/bin/env bash
if [[ "\$*" == *"build"* || "\$*" == *"push"* ]]; then
  echo "DOCKER INVOKED: \$*" >> "$DOCKER_LOG6"
fi
exit 0
EOF
chmod +x "$MOCK_BIN6/docker"

exit_code6=0
output6=$(PATH="$MOCK_BIN6:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty 2>&1) || exit_code6=$?

if [[ "$exit_code6" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para família incompatível."
else
  fail "Código de saída incorreto: esperado 1, obtido $exit_code6."
fi

if echo "$output6" | grep -q "FAMÍLIA INCOMPATÍVEL: A Task Definition base pertence à família 'task-def-ERRADA'"; then
  pass "Bloqueio correto para família de Task Definition divergente."
else
  fail "Não bloqueou para família divergente. Saída:\n$output6"
fi

if [[ -f "$AWS_MUTATION_LOG6" ]]; then
  fail "MUTAÇÃO AWS FOI CHAMADA INDEVIDAMENTE: $(cat "$AWS_MUTATION_LOG6")"
else
  pass "Zero mutações AWS chamadas durante o bloqueio."
fi

if [[ -f "$DOCKER_LOG6" ]]; then
  fail "Docker build/push FOI invocado antes de validar a família!"
else
  pass "Docker build/push NUNCA foram chamados para família divergente."
fi

# ------------------------------------------------------------------------------
# TESTE 7: Task Definition Base INACTIVE Bloqueia ANTES de Build/Push
# ------------------------------------------------------------------------------
log_test "7. Task Definition Base com Status INACTIVE Bloqueia Antes de Build/Push"

MOCK_BIN7="$TEST_TMP/bin7"
mkdir -p "$MOCK_BIN7"
DOCKER_LOG7="$TEST_TMP/docker7.log"
AWS_MUTATION_LOG7="$TEST_TMP/aws_mut7.log"
rm -f "$DOCKER_LOG7" "$AWS_MUTATION_LOG7"

cat << EOF > "$MOCK_BIN7/aws"
#!/usr/bin/env bash
if [[ "\$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "\$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "\$*" == *"ecs describe-services"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:14"
  exit 0
elif [[ "\$*" == *"ecs describe-task-definition"* ]]; then
  cat << 'JSON'
  {
    "family": "task-def-bia-cloud-app",
    "status": "INACTIVE",
    "containerDefinitions": [
      {"name": "bia-cloud-app", "image": "img1:v1"}
    ]
  }
JSON
  exit 0
elif [[ "\$*" == *"register-task-definition"* || "\$*" == *"update-service"* ]]; then
  echo "AWS MUTATION CALLED: \$*" >> "$AWS_MUTATION_LOG7"
fi
exit 0
EOF
chmod +x "$MOCK_BIN7/aws"

cat << EOF > "$MOCK_BIN7/docker"
#!/usr/bin/env bash
if [[ "\$*" == *"build"* || "\$*" == *"push"* ]]; then
  echo "DOCKER INVOKED: \$*" >> "$DOCKER_LOG7"
fi
exit 0
EOF
chmod +x "$MOCK_BIN7/docker"

exit_code7=0
output7=$(PATH="$MOCK_BIN7:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty --base-revision 14 2>&1) || exit_code7=$?

if [[ "$exit_code7" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para Task Definition com status INACTIVE."
else
  fail "Código de saída incorreto: esperado 1, obtido $exit_code7."
fi

if echo "$output7" | grep -q "STATUS INVÁLIDO: A Task Definition base '.*' está com status 'INACTIVE'"; then
  pass "Bloqueio correto para Task Definition inativa."
else
  fail "Não bloqueou para status INACTIVE. Saída:\n$output7"
fi

if [[ -f "$AWS_MUTATION_LOG7" ]]; then
  fail "MUTAÇÃO AWS FOI CHAMADA INDEVIDAMENTE: $(cat "$AWS_MUTATION_LOG7")"
else
  pass "Zero mutações AWS chamadas durante o bloqueio."
fi

if [[ -f "$DOCKER_LOG7" ]]; then
  fail "Docker build/push FOI invocado indevidamente!"
else
  pass "Docker build/push NUNCA foram chamados para Task Def inativa."
fi

# ------------------------------------------------------------------------------
# TESTE 8: Bloqueio Rígido da Revisão 16 Defeituosa ('exit 1')
# ------------------------------------------------------------------------------
log_test "8. Bloqueio Rígido da Revisão Defeituosa :16 ('exit 1')"

MOCK_BIN8="$TEST_TMP/bin8"
mkdir -p "$MOCK_BIN8"
DOCKER_LOG8="$TEST_TMP/docker8.log"
AWS_MUTATION_LOG8="$TEST_TMP/aws_mut8.log"
rm -f "$DOCKER_LOG8" "$AWS_MUTATION_LOG8"

cat << EOF > "$MOCK_BIN8/aws"
#!/usr/bin/env bash
if [[ "\$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "\$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "\$*" == *"register-task-definition"* || "\$*" == *"update-service"* ]]; then
  echo "AWS MUTATION CALLED: \$*" >> "$AWS_MUTATION_LOG8"
fi
exit 0
EOF
chmod +x "$MOCK_BIN8/aws"

cat << EOF > "$MOCK_BIN8/docker"
#!/usr/bin/env bash
if [[ "\$*" == *"build"* || "\$*" == *"push"* ]]; then
  echo "DOCKER INVOKED: \$*" >> "$DOCKER_LOG8"
fi
exit 0
EOF
chmod +x "$MOCK_BIN8/docker"

exit_code8=0
output8=$(PATH="$MOCK_BIN8:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty --base-revision 16 2>&1) || exit_code8=$?

if [[ "$exit_code8" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para bloqueio da Revisão :16."
else
  fail "Código de saída incorreto: esperado 1, obtido $exit_code8."
fi

if echo "$output8" | grep -q "BLOQUEIO DE SEGURANÇA: A revisão :16 é a Task Definition contaminada"; then
  pass "Bloqueio correto com mensagem de segurança da Revisão :16."
else
  fail "Não bloqueou a Revisão :16. Saída:\n$output8"
fi

if [[ -f "$AWS_MUTATION_LOG8" ]]; then
  fail "MUTAÇÃO AWS FOI CHAMADA INDEVIDAMENTE: $(cat "$AWS_MUTATION_LOG8")"
else
  pass "Zero mutações AWS chamadas durante o bloqueio."
fi

if [[ -f "$DOCKER_LOG8" ]]; then
  fail "Docker build/push FOI invocado indevidamente!"
else
  pass "Docker build/push NUNCA foram chamados para Revisão :16."
fi

# ------------------------------------------------------------------------------
# TESTE 9: Rollout com desiredCount=0 Bloqueia Homologação
# ------------------------------------------------------------------------------
log_test "9. Rollout com desiredCount=0 Bloqueia Homologação com Erro"

MOCK_BIN9="$TEST_TMP/bin9"
mkdir -p "$MOCK_BIN9"

cat << 'EOF' > "$MOCK_BIN9/aws"
#!/usr/bin/env bash
if [[ "$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "$*" == *"ecs describe-services"* && "$*" == *"--query services[0].taskDefinition"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15"
  exit 0
elif [[ "$*" == *"ecs describe-task-definition"* ]]; then
  cat << 'JSON'
  {
    "family": "task-def-bia-cloud-app",
    "status": "ACTIVE",
    "containerDefinitions": [
      {"name": "bia-cloud-app", "image": "123456789012.dkr.ecr.us-east-2.amazonaws.com/bia-cloud-lab:elasticache-v2"}
    ]
  }
JSON
  exit 0
elif [[ "$*" == *"ecs register-task-definition"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:18"
  exit 0
elif [[ "$*" == *"ecs update-service"* ]]; then
  echo '{"service":{"deployments":[{"id":"ecs-dep-test","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:18"}]}}'
  exit 0
elif [[ "$*" == *"ecs describe-services"* ]]; then
  # Serviço com desiredCount=0 e runningCount=0, rollout COMPLETED
  echo '{"desiredCount":0,"runningCount":0,"deployments":[{"status":"PRIMARY","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:18","rolloutState":"COMPLETED"}]}'
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN9/aws"

cat << 'EOF' > "$MOCK_BIN9/docker"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN9/docker"

exit_code9=0
output9=$(PATH="$MOCK_BIN9:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty --skip-build -t 83a1f07 --skip-smoke-test 2>&1) || exit_code9=$?

if [[ "$exit_code9" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para bloqueio de desiredCount=0."
else
  fail "Código de saída incorreto: esperado 1, obtido $exit_code9."
fi

if echo "$output9" | grep -q "ROLLOUT NÃO HOMOLOGADO: O serviço '.*' possui desiredCount=0"; then
  pass "Bloqueio correto impedindo homologação com 0 tarefas desejadas."
else
  fail "Não bloqueou para desiredCount=0. Saída:\n$output9"
fi

# ------------------------------------------------------------------------------
# TESTE 10: Disparo do Circuit Breaker Confirma Estado Read-Only e Sai com Código 2
# ------------------------------------------------------------------------------
log_test "10. Disparo de Circuit Breaker (rolloutState=FAILED) com Diagnóstico Read-Only"

MOCK_BIN10="$TEST_TMP/bin10"
mkdir -p "$MOCK_BIN10"

cat << 'EOF' > "$MOCK_BIN10/aws"
#!/usr/bin/env bash
if [[ "$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "$*" == *"ecs describe-services"* && "$*" == *"--query services[0].taskDefinition"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15"
  exit 0
elif [[ "$*" == *"ecs describe-task-definition"* ]]; then
  cat << 'JSON'
  {
    "family": "task-def-bia-cloud-app",
    "status": "ACTIVE",
    "containerDefinitions": [
      {"name": "bia-cloud-app", "image": "123456789012.dkr.ecr.us-east-2.amazonaws.com/bia-cloud-lab:elasticache-v2"}
    ]
  }
JSON
  exit 0
elif [[ "$*" == *"ecs register-task-definition"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:19"
  exit 0
elif [[ "$*" == *"ecs update-service"* ]]; then
  echo '{"service":{"deployments":[{"id":"ecs-dep-test","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:19"}]}}'
  exit 0
elif [[ "$*" == *"ecs describe-services"* ]]; then
  # Simula Circuit Breaker disparado: rolloutState=FAILED na nova revisão, e PRIMARY revertida para a :15
  cat << 'JSON'
  {
    "desiredCount": 1,
    "runningCount": 1,
    "deployments": [
      {
        "status": "PRIMARY",
        "taskDefinition": "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15",
        "rolloutState": "COMPLETED"
      },
      {
        "status": "ACTIVE",
        "taskDefinition": "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:19",
        "rolloutState": "FAILED",
        "rolloutStateReason": "Circuit breaker triggered: Task failed container health checks"
      }
    ]
  }
JSON
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN10/aws"

cat << 'EOF' > "$MOCK_BIN10/docker"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN10/docker"

exit_code10=0
output10=$(PATH="$MOCK_BIN10:$PATH" "$DEPLOY_SCRIPT" deploy --allow-dirty --skip-build -t 83a1f07 --skip-smoke-test 2>&1) || exit_code10=$?

if [[ "$exit_code10" -eq 2 ]]; then
  pass "Código de saída 2 confirmado para disparo do Circuit Breaker."
else
  fail "Código de saída incorreto: esperado 2, obtido $exit_code10."
fi

if echo "$output10" | grep -q "CONFIRMAÇÃO READ-ONLY: O ECS restaurou com sucesso a Task Definition estável como PRIMARY"; then
  pass "Diagnóstico read-only confirmou restauração da Task Definition estável."
else
  fail "Não confirmou diagnóstico read-only. Saída:\n$output10"
fi

# ------------------------------------------------------------------------------
# TESTE 11: Dry-Run Offline no Ambiente ALB Exibe Mocks Claramente Simulados
# ------------------------------------------------------------------------------
log_test "11. Dry-Run Offline no Ambiente ALB Exibe Mocks Claramente Simulados"

MOCK_BIN11="$TEST_TMP/bin11"
mkdir -p "$MOCK_BIN11"

cat << 'EOF' > "$MOCK_BIN11/aws"
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCK_BIN11/aws"

output11=$(PATH="$MOCK_BIN11:$PATH" "$DEPLOY_SCRIPT" list -E alb --dry-run 2>&1)

if echo "$output11" | grep -q ":SIM-2" && echo "$output11" | grep -q ":SIM-1"; then
  pass "Registros simulados :SIM-2 e :SIM-1 exibidos para o ambiente ALB."
else
  fail "Não exibiu registros simulados para ALB. Saída:\n$output11"
fi

if echo "$output11" | grep -q ":16" || echo "$output11" | grep -q ":15"; then
  fail "Revisões fixas do ambiente APP (:16 / :15) foram indevidamente vazadas no ambiente ALB! Saída:\n$output11"
else
  pass "Nenhuma revisão fixa do ambiente APP (:16 / :15) foi vazada no ambiente ALB."
fi

# ------------------------------------------------------------------------------
# TESTE 12: Execução Direta do Script Especializado list-versions.sh
# ------------------------------------------------------------------------------
log_test "12. Execução Direta do Script Especializado list-versions.sh"

exit_code12=0
output12=$(PATH="$MOCK_BIN11:$PATH" "$SCRIPT_DIR/list-versions.sh" --dry-run 2>&1) || exit_code12=$?

if [[ "$exit_code12" -eq 0 ]]; then
  pass "Script list-versions.sh executou com código 0 em modo dry-run."
else
  fail "list-versions.sh falhou com código $exit_code12. Saída:\n$output12"
fi

if echo "$output12" | grep -q "REVISÃO" && echo "$output12" | grep -q "SITUAÇÃO NO SERVIÇO"; then
  pass "Cabeçalho da tabela de revisões validado com sucesso."
else
  fail "Tabela formatada não encontrada na saída. Saída:\n$output12"
fi

# ------------------------------------------------------------------------------
# TESTE 13: Execução Direta do Script Especializado rollback.sh
# ------------------------------------------------------------------------------
log_test "13. Execução Direta do Script Especializado rollback.sh"

# 13.1 Bloqueio da Revisão :16 no rollback direto
exit_code13_fail=0
output13_fail=$("$SCRIPT_DIR/rollback.sh" -r 16 2>&1) || exit_code13_fail=$?

if [[ "$exit_code13_fail" -eq 1 ]]; then
  pass "Código de saída 1 confirmado para bloqueio da Revisão :16 no rollback.sh direto."
else
  fail "rollback.sh permitiu a revisão 16! Código obtido: $exit_code13_fail."
fi

if echo "$output13_fail" | grep -q "BLOQUEIO DE SEGURANÇA: A revisão :16 é a Task Definition contaminada"; then
  pass "Mensagem de segurança contra contaminação confirmada no rollback.sh."
else
  fail "Mensagem de segurança ausente no rollback.sh. Saída:\n$output13_fail"
fi

# 13.2 Execução segura de rollback.sh em modo dry-run
exit_code13_ok=0
output13_ok=$(PATH="$MOCK_BIN11:$PATH" "$SCRIPT_DIR/rollback.sh" -r 15 --dry-run 2>&1) || exit_code13_ok=$?

if [[ "$exit_code13_ok" -eq 0 ]]; then
  pass "rollback.sh executou com código 0 para revisão 15 em dry-run."
else
  fail "rollback.sh dry-run falhou com código $exit_code13_ok. Saída:\n$output13_ok"
fi

# ------------------------------------------------------------------------------
# TESTE 14: Execução Direta do Script Especializado deploy.sh
# ------------------------------------------------------------------------------
log_test "14. Execução Direta do Script Especializado deploy.sh"

exit_code14=0
output14=$(PATH="$MOCK_BIN11:$PATH" "$SCRIPT_DIR/deploy.sh" --dry-run --base-revision 15 --allow-dirty 2>&1) || exit_code14=$?

if [[ "$exit_code14" -eq 0 ]]; then
  pass "Script deploy.sh direto executou com sucesso (código 0) em dry-run."
else
  fail "deploy.sh falhou em dry-run com código $exit_code14. Saída:\n$output14"
fi

if echo "$output14" | grep -q "Simulação completa de Deploy concluída com sucesso"; then
  pass "Mensagem de sucesso da simulação confirmada no deploy.sh direto."
else
  fail "Simulação do deploy.sh direto não reportou conclusão. Saída:\n$output14"
fi

# ------------------------------------------------------------------------------
# TESTE 15: Fachada de Compatibilidade deploy-ecs.sh
# ------------------------------------------------------------------------------
log_test "15. Fachada de Compatibilidade deploy-ecs.sh (Delegação Transparente)"

# 15.1 Delegação para list
exit_code15_list=0
output15_list=$(PATH="$MOCK_BIN11:$PATH" "$DEPLOY_SCRIPT" list --dry-run 2>&1) || exit_code15_list=$?
if [[ "$exit_code15_list" -eq 0 ]] && echo "$output15_list" | grep -q "REVISÃO"; then
  pass "Fachada deploy-ecs.sh delegou corretamente para 'list'."
else
  fail "Falha na delegação da fachada para list."
fi

# 15.2 Delegação para rollback com bloqueio da :16
exit_code15_rb=0
output15_rb=$("$DEPLOY_SCRIPT" rollback -r 16 2>&1) || exit_code15_rb=$?
if [[ "$exit_code15_rb" -eq 1 ]] && echo "$output15_rb" | grep -q "BLOQUEIO DE SEGURANÇA"; then
  pass "Fachada deploy-ecs.sh delegou corretamente para 'rollback' com preservação do bloqueio da :16."
else
  fail "Falha na delegação da fachada para rollback."
fi

# 15.3 Delegação para deploy
exit_code15_dep=0
output15_dep=$(PATH="$MOCK_BIN11:$PATH" "$DEPLOY_SCRIPT" deploy --dry-run --base-revision 15 --allow-dirty 2>&1) || exit_code15_dep=$?
if [[ "$exit_code15_dep" -eq 0 ]] && echo "$output15_dep" | grep -q "Simulação completa de Deploy"; then
  pass "Fachada deploy-ecs.sh delegou corretamente para 'deploy'."
else
  fail "Falha na delegação da fachada para deploy."
fi

# ------------------------------------------------------------------------------
# TESTE 16: Falha Persistente no Smoke Test Dispara Rollback e Código 3
# ------------------------------------------------------------------------------
log_test "16. Falha Persistente no Smoke Test Dispara Rollback para a Baseline e Código 3"

MOCK_BIN16="$TEST_TMP/bin16"
mkdir -p "$MOCK_BIN16"
ROLLBACK_LOG16="$TEST_TMP/rollback_call_16.log"
rm -f "$ROLLBACK_LOG16"

cat << 'EOF' > "$MOCK_BIN16/aws"
#!/usr/bin/env bash
if [[ "$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "$*" == *"ecs describe-services"* && "$*" == *"--query services[0].taskDefinition"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:15"
  exit 0
elif [[ "$*" == *"ecs describe-task-definition"* ]]; then
  cat << 'JSON'
  {
    "family": "task-def-bia-cloud-app",
    "status": "ACTIVE",
    "containerDefinitions": [
      {"name": "bia-cloud-app", "image": "123456789012.dkr.ecr.us-east-2.amazonaws.com/bia-cloud-lab:base"}
    ]
  }
JSON
  exit 0
elif [[ "$*" == *"ecs register-task-definition"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:19"
  exit 0
elif [[ "$*" == *"ecs update-service"* ]]; then
  if [[ "$*" == *"task-def-bia-cloud-app:15"* ]]; then
    echo "EMERGENCY_ROLLBACK_CALLED_TO_15: $*" >> "${ROLLBACK_LOG_FILE:-/tmp/rollback_called.log}"
  fi
  echo '{"service":{"deployments":[{"id":"dep16","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:19"}]}}'
  exit 0
elif [[ "$*" == *"ecs describe-services"* ]]; then
  echo '{"desiredCount":1,"runningCount":1,"deployments":[{"status":"PRIMARY","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:19","rolloutState":"COMPLETED"}]}'
  exit 0
elif [[ "$*" == *"ecs wait services-stable"* ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN16/aws"

cat << 'EOF' > "$MOCK_BIN16/docker"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN16/docker"

# Mock do curl retornando HTTP 500 (Falha de aplicação)
cat << 'EOF' > "$MOCK_BIN16/curl"
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$prev_arg" == "-o" ]]; then
    echo '{"error":"Internal Server Error"}' > "$arg"
  fi
  prev_arg="$arg"
done
echo "500|0.05"
exit 0
EOF
chmod +x "$MOCK_BIN16/curl"

exit_code16=0
output16=$(ROLLBACK_LOG_FILE="$ROLLBACK_LOG16" PATH="$MOCK_BIN16:$PATH" "$SCRIPT_DIR/deploy.sh" --allow-dirty --skip-build -t test16 2>&1) || exit_code16=$?

if [[ "$exit_code16" -eq 3 ]]; then
  pass "Código de saída 3 confirmado para falha persistente no Smoke Test."
else
  fail "Código de saída incorreto para falha no smoke test: esperado 3, obtido $exit_code16. Saída:\n$output16"
fi

if [[ -f "$ROLLBACK_LOG16" ]] && grep -q "task-def-bia-cloud-app:15" "$ROLLBACK_LOG16"; then
  pass "Rollback de emergência foi acionado com sucesso para a baseline :15 de partida."
else
  fail "Rollback de emergência NÃO foi chamado para a baseline! Saída:\n$output16"
fi

# ------------------------------------------------------------------------------
# TESTE 17: Smoke Test Tolera Falha Transitória e Conclui com Código 0
# ------------------------------------------------------------------------------
log_test "17. Smoke Test Tolera Falha Transitória de Warmup e Conclui com Código 0"

MOCK_BIN17="$TEST_TMP/bin17"
mkdir -p "$MOCK_BIN17"
CURL_COUNTER_FILE="$TEST_TMP/curl_attempt.count"
ROLLBACK_LOG17="$TEST_TMP/rollback_call_17.log"
rm -f "$CURL_COUNTER_FILE" "$ROLLBACK_LOG17"
echo "0" > "$CURL_COUNTER_FILE"

cp "$MOCK_BIN16/aws" "$MOCK_BIN17/aws"
cp "$MOCK_BIN16/docker" "$MOCK_BIN17/docker"

# Mock do curl com 1 falha transitória (502) na primeira tentativa e sucesso (200) nas demais
cat << EOF > "$MOCK_BIN17/curl"
#!/usr/bin/env bash
cnt=\$(cat "$CURL_COUNTER_FILE" 2>/dev/null || echo "0")
cnt=\$((cnt + 1))
echo "\$cnt" > "$CURL_COUNTER_FILE"

for arg in "\$@"; do
  if [[ "\$prev_arg" == "-o" ]]; then
    if [[ "\$cnt" -eq 1 ]]; then
      echo '{"error":"Bad Gateway Warmup"}' > "\$arg"
    else
      echo '{"status":"ok","versao":"4.2.0"}' > "\$arg"
    fi
  fi
  prev_arg="\$arg"
done

if [[ "\$cnt" -eq 1 ]]; then
  echo "502|0.08"
else
  echo "200|0.02"
fi
exit 0
EOF
chmod +x "$MOCK_BIN17/curl"

exit_code17=0
output17=$(ROLLBACK_LOG_FILE="$ROLLBACK_LOG17" PATH="$MOCK_BIN17:$PATH" "$SCRIPT_DIR/deploy.sh" --allow-dirty --skip-build -t test17 2>&1) || exit_code17=$?

if [[ "$exit_code17" -eq 0 ]]; then
  pass "Deploy concluído com código 0 com tolerância a falha transitória."
else
  fail "Deploy falhou indevidamente com código $exit_code17. Saída:\n$output17"
fi

if echo "$output17" | grep -q "Smoke test aprovado com resiliência"; then
  pass "Log confirmou aprovação resiliente com 1 falha transitória tolerada."
else
  fail "Mensagem de resiliência ausente. Saída:\n$output17"
fi

if [[ -f "$ROLLBACK_LOG17" ]]; then
  fail "Rollback de emergência foi acionado indevidamente para falha transitória!"
else
  pass "Nenhum rollback foi acionado para oscilação transitória resolvida."
fi

# ------------------------------------------------------------------------------
# TESTE 18: Rollback com Baseline Alternativa (:17) Não Fica Preso à :15
# ------------------------------------------------------------------------------
log_test "18. Rollback Dinâmico com Baseline Alternativa (:17) Não Fica Preso à :15"

MOCK_BIN18="$TEST_TMP/bin18"
mkdir -p "$MOCK_BIN18"
ROLLBACK_LOG18="$TEST_TMP/rollback_call_18.log"
rm -f "$ROLLBACK_LOG18"

cat << 'EOF' > "$MOCK_BIN18/aws"
#!/usr/bin/env bash
if [[ "$*" == *"sts get-caller-identity"* ]]; then
  echo '{"Account": "123456789012", "Arn": "arn:aws:iam::123456789012:user/AGY-AWS-LAB"}'
  exit 0
elif [[ "$*" == *"ecr describe-repositories"* ]]; then
  exit 0
elif [[ "$*" == *"ecs describe-services"* && "$*" == *"--query services[0].taskDefinition"* ]]; then
  # Serviço em execução na revisão 17 (não na 15)
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:17"
  exit 0
elif [[ "$*" == *"ecs describe-task-definition"* ]]; then
  cat << 'JSON'
  {
    "family": "task-def-bia-cloud-app",
    "revision": 17,
    "status": "ACTIVE",
    "containerDefinitions": [
      {"name": "bia-cloud-app", "image": "123456789012.dkr.ecr.us-east-2.amazonaws.com/bia-cloud-lab:83a1f07"}
    ]
  }
JSON
  exit 0
elif [[ "$*" == *"ecs register-task-definition"* ]]; then
  echo "arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:20"
  exit 0
elif [[ "$*" == *"ecs update-service"* ]]; then
  if [[ "$*" == *"task-def-bia-cloud-app:17"* ]]; then
    echo "EMERGENCY_ROLLBACK_CALLED_TO_17: $*" >> "${ROLLBACK_LOG_FILE:-/tmp/rollback_called.log}"
  elif [[ "$*" == *"task-def-bia-cloud-app:15"* ]]; then
    echo "ERROR_WRONGLY_CALLED_TO_15: $*" >> "${ROLLBACK_LOG_FILE:-/tmp/rollback_called.log}"
  fi
  echo '{"service":{"deployments":[{"id":"dep18","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:20"}]}}'
  exit 0
elif [[ "$*" == *"ecs describe-services"* ]]; then
  echo '{"desiredCount":1,"runningCount":1,"deployments":[{"status":"PRIMARY","taskDefinition":"arn:aws:ecs:us-east-2:123456789012:task-definition/task-def-bia-cloud-app:20","rolloutState":"COMPLETED"}]}'
  exit 0
elif [[ "$*" == *"ecs wait services-stable"* ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN18/aws"

cp "$MOCK_BIN16/docker" "$MOCK_BIN18/docker"
cp "$MOCK_BIN16/curl" "$MOCK_BIN18/curl"

exit_code18=0
output18=$(ROLLBACK_LOG_FILE="$ROLLBACK_LOG18" PATH="$MOCK_BIN18:$PATH" "$SCRIPT_DIR/deploy.sh" --allow-dirty --skip-build -t test18 2>&1) || exit_code18=$?

if [[ "$exit_code18" -eq 3 ]]; then
  pass "Código de saída 3 confirmado para falha no Smoke Test com baseline :17."
else
  fail "Código de saída incorreto: esperado 3, obtido $exit_code18. Saída:\n$output18"
fi

if [[ -f "$ROLLBACK_LOG18" ]] && grep -q "EMERGENCY_ROLLBACK_CALLED_TO_17" "$ROLLBACK_LOG18"; then
  pass "Rollback de emergência foi acionado com sucesso para a baseline :17 (revisão de partida)."
else
  fail "Rollback de emergência NÃO foi direcionado para :17! Log:\n$(cat "$ROLLBACK_LOG18" 2>/dev/null || echo 'arquivo ausente')"
fi

if [[ -f "$ROLLBACK_LOG18" ]] && grep -q "ERROR_WRONGLY_CALLED_TO_15" "$ROLLBACK_LOG18"; then
  fail "ERRO DE SEGURANÇA: Rollback foi forçado indevidamente para :15 em vez da versão ativa :17!"
else
  pass "Nenhum rollback indevido para :15 ocorreu: a versão ativa :17 foi rigorosamente respeitada."
fi

echo -e "\n${C_GREEN}${C_BOLD}======================================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}TODOS OS 18 TESTES DE SEGURANÇA E INTEGRAÇÃO FORAM APROVADOS COM SUCESSO!${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}======================================================================${C_RESET}"
