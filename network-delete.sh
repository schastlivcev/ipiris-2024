#!/bin/bash
set -e # Завершение выполнения скрипта при первой ошибке

# Проверка количества аргументов
if [ "$#" -lt 1 ]; then
  echo "Использование: $0 <NETWORK_NAME> [SUBNET_NAME1 SUBNET_NAME2 ...]"
  exit 1
fi

NETWORK_NAME="$1"
shift  # Сдвиг аргументов на 1 (удаление названия сети, новым $1 становится $2 и т.д.)

# Получение идентификатора сети по имени
NETWORK_ID=$(yc vpc network get --name "$NETWORK_NAME" --format json 2>/dev/null | jq -r '.id')
if [ -z "$NETWORK_ID" ]; then
  echo "Ошибка: Сеть с именем '$NETWORK_NAME' не найдена!"
  exit 1
fi

echo "Сеть найдена: $NETWORK_NAME (ID: $NETWORK_ID)"

# Получение списка всех подсетей в сети, если конкретные не указаны
if [ "$#" -eq 0 ]; then
  echo "Ищем все подсети в сети $NETWORK_NAME..."
  SUBNET_NAMES=$(yc vpc subnet list --format json | jq -r --arg network_id "$NETWORK_ID" '.[] | select(.network_id == $network_id) | .name')
else
  SUBNET_NAMES="$@"
fi

# Проверка, есть ли подсети для удаления
if [ -z "$SUBNET_NAMES" ]; then
  echo "Подсети в сети $NETWORK_NAME не найдены."
else
  # Цикл удаления указанных (или найденных) подсетей
  for SUBNET in $SUBNET_NAMES; do
    echo "Обрабатываем подсеть: $SUBNET"

    # Получение идентификатора подсети
    SUBNET_ID=$(yc vpc subnet get --name "$SUBNET" --format json 2>/dev/null | jq -r '.id')
    if [ -z "$SUBNET_ID" ]; then
      echo "Ошибка: Подсеть '$SUBNET' не найдена!"
      continue
    fi

    echo "Подсеть найдена: $SUBNET (ID: $SUBNET_ID)"

    # Поиск всех виртуальных машин подсети
    INSTANCE_IDS=$(yc compute instance list --format json | jq -r --arg subnet_id "$SUBNET_ID" '.[] | select(.network_interfaces[0].subnet_id == $subnet_id) | .id')
    if [ -n "$INSTANCE_IDS" ]; then
      echo "Найдены виртуальные машины в подсети $SUBNET:"
      echo "$INSTANCE_IDS"

      # Удаление принадлежащих виртуальных машин
      for INSTANCE_ID in $INSTANCE_IDS; do
        echo "Удаляем виртуальную машину: $INSTANCE_ID"
        yc compute instance delete --id "$INSTANCE_ID" || echo "Ошибка при удалении виртуальной машины $INSTANCE_ID"
      done
    else
      echo "В подсети $SUBNET нет виртуальных машин."
    fi

    # Удаление самой подсеть
    echo "Удаляем подсеть: $SUBNET"
    yc vpc subnet delete --name "$SUBNET" || echo "Ошибка при удалении подсети $SUBNET"
  done
fi

# Проверка наличия подсетей в сети
REMAINING_SUBNETS=$(yc vpc subnet list --format json | jq -r --arg network_id "$NETWORK_ID" '.[] | select(.network_id == $network_id) | .name')
if [ -n "$REMAINING_SUBNETS" ]; then
  echo "Ошибка: В сети $NETWORK_NAME остались подсети, которые не удалось удалить:"
  echo "$REMAINING_SUBNETS"
  exit 1
fi

# Удаление сети
echo "Удаляем сеть: $NETWORK_NAME"
yc vpc network delete --name "$NETWORK_NAME"

echo "Сеть $NETWORK_NAME и её подсети успешно удалены!"