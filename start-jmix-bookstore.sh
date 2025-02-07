#!/bin/bash
set -e # Завершение выполнения скрипта при первой ошибке

# Функция вывода справки по использованию
usage() {
  echo "Использование: $0 -c <YC_CLOUD_NAME> -f <YC_FOLDER_NAME> \\"
  echo "              [-n <NETWORK_NAME=jmix-network>] \\"
  echo "              [-s <SUBNET_NAME=jmix-subnet>] \\"
  echo "              [-v <VM_NAME=jmix-bookstore-vm>] \\"
  echo "              [-u <VM_USER_NAME=ipiris>]"
  exit 1
}

# Парсинг аргументов
while getopts ":c:f:n:s:v:u:" opt; do
  case $opt in
    c) YC_CLOUD_NAME="$OPTARG" ;;
    f) YC_FOLDER_NAME="$OPTARG" ;;
    n) NETWORK_NAME="$OPTARG" ;;
    s) SUBNET_NAME="$OPTARG" ;;
    v) VM_NAME="$OPTARG" ;;
    u) USER_NAME="$OPTARG" ;;
    *) usage ;;
  esac
done

# Проверка наличия обязательных параметров
if [ -z "$YC_CLOUD_NAME" ] || [ -z "$YC_FOLDER_NAME" ]; then
  usage
fi

# Установка значений по умолчанию для опциональных параметров
NETWORK_NAME=${NETWORK_NAME:-"jmix-network"}
SUBNET_NAME=${SUBNET_NAME:-"jmix-subnet"}
VM_NAME=${VM_NAME:-"jmix-bookstore-vm"}
USER_NAME=${USER_NAME:-"ipiris"}

# Получение идентификатора облака по имени
YC_CLOUD_ID=$(yc resource-manager cloud list --format json | jq -r --arg name "$YC_CLOUD_NAME" '.[] | select(.name == $name) | .id')
if [ -z "$YC_CLOUD_ID" ]; then
  echo "Ошибка: Облако с именем '$YC_CLOUD_NAME' не найдено!"
  exit 1
fi

# Получение идентификатора каталога по имени
YC_FOLDER_ID=$(yc resource-manager folder list --cloud-id "$YC_CLOUD_ID" --format json | jq -r --arg name "$YC_FOLDER_NAME" '.[] | select(.name == $name) | .id')
if [ -z "$YC_FOLDER_ID" ]; then
  echo "Ошибка: Каталог с именем '$YC_FOLDER_NAME' не найден в облаке '$YC_CLOUD_NAME'!"
  exit 1
fi

echo "Используется облако: $YC_CLOUD_NAME (ID: $YC_CLOUD_ID)"
echo "Используется каталог: $YC_FOLDER_NAME (ID: $YC_FOLDER_ID)"

# Переменные для настройки виртуальной машины
ZONE="ru-central1-a"
IMAGE_ID="fd833ivvmqp6cuq7shpc" # Почему-то не видны ни IMAGE_FAMILY, ни IMAGE_NAME
PLATFORM="standard-v3" # Intel Ice Lake
SSH_KEY_NAME="jmix-ssh-key"
SSH_PRIVATE_KEY="$HOME/.ssh/${SSH_KEY_NAME}" # Путь до приватного SSH-ключа
SSH_PUBLIC_KEY="${SSH_PRIVATE_KEY}.pub" # Путь до публичного SSH-ключа
DOCKER_IMAGE="jmix/jmix-bookstore" # Docker-образ

# Авторизация в Yandex Cloud
yc config set cloud-id $YC_CLOUD_ID
yc config set folder-id $YC_FOLDER_ID

# Проверка существования сети
NETWORK_ID=$(yc vpc network get --name $NETWORK_NAME --format json 2>/dev/null | jq -r '.id')
if [ -z "$NETWORK_ID" ]; then
  echo "Создание облачной сети..."
  yc vpc network create --name $NETWORK_NAME
  NETWORK_ID=$(yc vpc network get --name $NETWORK_NAME --format json | jq -r '.id')
else
  echo "Используется существующая сеть: $NETWORK_NAME (ID: $NETWORK_ID)"
fi

# Проверка существования подсети
SUBNET_ID=$(yc vpc subnet get --name $SUBNET_NAME --format json 2>/dev/null | jq -r '.id')
if [ -z "$SUBNET_ID" ]; then
  echo "Создание облачной подсети..."
  yc vpc subnet create \
    --name $SUBNET_NAME \
    --zone $ZONE \
    --range 192.168.1.0/24 \
    --network-name $NETWORK_NAME
  SUBNET_ID=$(yc vpc subnet get --name $SUBNET_NAME --format json | jq -r '.id')
else
  echo "Используется существующая подсеть: $SUBNET_NAME (ID: $SUBNET_ID)"
fi

# Создание SSH-ключей
echo "Создание SSH-ключей..."
mkdir -p "$HOME/.ssh" # Создание директории, если ее нет
ssh-keygen -t rsa -b 2048 -f "$SSH_PRIVATE_KEY" -N ""

# Создание временной cloud-init конфигурации для установки нужного имени пользователя
# и передачи публичного ключа
# Использование параметра --ssh-keys привязывает ключ к пользователю 'yc-user' 
CLOUD_INIT_TEMP=$(mktemp)
cat <<EOF > "$CLOUD_INIT_TEMP"
#cloud-config

users:
  - name: $USER_NAME
    sudo: ['ALL=(ALL) NOPASSWD:ALL'] # sudo без пароля
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat $SSH_PUBLIC_KEY)

packages:
  - docker.io # Требование установки Docker

runcmd: # Запуск Docker-а и образа
  - systemctl start docker
  - systemctl enable docker
  - docker run -d -p 80:8080 $DOCKER_IMAGE
EOF

# Создание виртуальной машины
echo -e "\nСоздание виртуальной машины..."
yc compute instance create \
  --name $VM_NAME \
  --zone $ZONE \
  --platform $PLATFORM \
  --cores 2 \
  --memory 4 \
  --create-boot-disk image-id=$IMAGE_ID,size=20GB,type=network-ssd \
  --network-interface subnet-name=$SUBNET_NAME,nat-ip-version=ipv4 \
  --metadata-from-file user-data="$CLOUD_INIT_TEMP"

# Удаление временной cloud-init конфигурации
rm -f "$CLOUD_INIT_TEMP"

# Получение внешнего IP виртуальной машины
VM_IP=$(yc compute instance get --name $VM_NAME --format json | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')

# Вывод результатов
echo "Образ $DOCKER_IMAGE успешно запущен!"
echo "Подключение к виртуальной машине по SSH:"
echo "ssh -i $SSH_PRIVATE_KEY $USER_NAME@$VM_IP"
echo "Адрес для открытия веб-приложения:"
echo "http://$VM_IP"