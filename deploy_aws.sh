CADENA=$(aws ec2 describe-images --owners self --query 'Images[*].Name' --output text --no-verify-ssl)
mapfile -t VERSIONES < <(echo $CADENA | grep -o 'v[0-9.]\+')

ULTIMO_INDICE=$((${#VERSIONES[@]} - 1))
ULTIMA_VERSION=$(printf "%s\n" "${VERSIONES[@]}" | sort -Vr | head -n1)

echo "Última versión $ULTIMA_VERSION"


VERSION_SIN_V=$(echo $ULTIMA_VERSION | sed 's/^v//') 

echo "--- Extrayendo números con cut --- $VERSION_SIN_V"

NUMERO_MAYOR=$(echo $VERSION_SIN_V | cut -d . -f 1)
echo "Mayor (1): $NUMERO_MAYOR" 

NUMERO_MENOR=$(echo $VERSION_SIN_V | cut -d . -f 2)
echo "Menor (0): $NUMERO_MENOR" 

NUMERO_PARCHE=$(echo $VERSION_SIN_V | cut -d . -f 3)
echo "Parche (1): $NUMERO_PARCHE" 

NUEVO_NUMERO_MAYOR=$((NUMERO_MAYOR + 1))
NUEVA_VERSION="${NUEVO_NUMERO_MAYOR}.${NUMERO_MENOR}.${NUMERO_PARCHE}"
echo "La nueva versión es: $NUEVA_VERSION"

echo "--- Ejecutando Packer ---"
PACKER_OUTPUT=$(packer build -var="version=${NUEVA_VERSION}" packer_image_aws.pkr.hcl)
echo "${PACKER_OUTPUT}" 
AMI_ID=$(echo "$PACKER_OUTPUT" | grep 'AMIs were created:' -A 1 | grep -oP '(ami-[0-9a-fA-F]+)')

echo "--- Temino la creación de imagen AWS ---"
# Verificación del resultado
if [ -z "$AMI_ID" ]; then
    echo "ERROR: No se pudo extraer el ID de la AMI."
    exit 1
fi

echo "ID de la AMI : $AMI_ID"
AWS_REGION="us-east-1"
INSTANCE_TYPE="t2.micro"
KEY_NAME="avega-ubuntu"
SECURITY_GROUP_IDS="sg-07331bc93ce28c153"
SUBNET_ID="subnet-0644f10a78750bb59"
STACK_NAME="server-by-packer"
echo "--- Lanzando Instancia EC2 ---"
RUN_INSTANCES_OUTPUT=$(aws ec2 run-instances \
    --region "${AWS_REGION}" \
    --image-id "${AMI_ID}" \
    --count 1 \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${KEY_NAME}" \
    --security-group-ids "${SECURITY_GROUP_IDS}" \
    --subnet-id "${SUBNET_ID}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${STACK_NAME}}]" \
    --query 'Instances[0].InstanceId' \
    --output text --no-verify-ssl)


    export INSTANCE_ID="${RUN_INSTANCES_OUTPUT}"
echo "Instancia Lanzada. ID: ${INSTANCE_ID}"

# --- Esperar a que la Instancia Esté Lista ---
echo "Esperando a que la instancia '${INSTANCE_ID}' entre en estado 'running'..."
# El comando 'wait' es fundamental para asegurar que AWS ha terminado de arrancar la VM
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}" --region "${AWS_REGION}"

# --- Consultar y Mostrar la IP Pública ---
echo "--- Extrayendo Información de la Instancia ---"

PUBLIC_IP=$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text  --no-verify-ssl)

if [ -z "${PUBLIC_IP}" ]; then
    echo "ADVERTENCIA: La instancia no tiene una IP Pública asignada (puede estar en una subred privada)."
    echo "Puedes intentar buscar la IP Privada o el DNS Privado."
else
    echo "¡Despliegue Completado!"
    echo "--------------------------------------------------------"
    echo "NOMBRE (Tag): ${STACK_NAME}"
    echo "ID de Instancia: ${INSTANCE_ID}"
    echo "**IP PÚBLICA: ${PUBLIC_IP}**"
    echo "--------------------------------------------------------"
    echo "Puedes conectarte por SSH usando: ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
fi