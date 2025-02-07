#!/bin/bash

# Функция генерация случайного 4-значного числа с неповторяющимися цифрами
generate_number() {
    digits=(${shuf -i 0-9 -n 10}) # Строка из перемешанных цифр 0-9
    echo "${digits[0]}${digits[1]}${digits[2]}${digits[3]}"
}

# Функция подсчета быков и коров
count_bulls_and_cows() {
    local guess=$1 # Введенное число
    local bulls=0
    local cows=0

    # Проход по каждой цифре
    for i in {0..3}; do
        if [[ ${guess:$i:1} == ${secret:$i:1} ]]; then
            ((bulls++))
        elif [[ $secret == *${guess:$i:1}* ]]; then
            ((cows++))
        fi
    done
    echo "$bulls $cows"
}

# Функция проверки корректности ввода
validate_input() {
    local input=$1
    
    # 1. Состоит из 4 цифр
    # 2. Все цифры уникальны (grep, sort, uniq, wc -l)
    if [[ $input =~ ^[0-9]{4}$ ]] && [[ $(echo "$input" | grep -o . | sort | uniq | wc -l) -eq 4 ]]; then
        return 0
    fi
    return 1
}

# Обработка сигнала SIGINT (Ctrl+C)
trap 'echo -e "\nЧтобы выйти, введите q или Q."' SIGINT

# Начало игры
secret=$(generate_number)   # Загадывание числа
turn=0                      # Счетчик ходов
declare -a history          # Массив истории ходов

# Вывод правил
echo "********************************************************************************"
echo "* Я загадал 4-значное число с неповторяющимися цифрами. На каждом ходу делайте *"
echo "* попытку отгадать загаданное число. Попытка - это 4-значное число с           *"
echo "* неповторяющимися цифрами.                                                    *"
echo "********************************************************************************"

# Игровой цикл
while true; do
    # Читаем ввод
    read -p "Попытка $((turn + 1)): " guess
    
    # Выход, если "q" или "Q"
    if [[ $guess == "q" || $guess == "Q" ]]; then
        echo "Выход из игры. Загаданное число: $secret"
        exit 1 # Ненулевой статус
    fi
    
    # Проверка некорректности ввода в ином случае
    if ! validate_input "$guess"; then
        echo "Ошибка! Введите 4-значное число с неповторяющимися цифрами."
        continue
    fi
    
    # Увеличиваем счетчик ходов
    ((turn++))

    # Подсчет быков и коров
    read bulls cows < <(count_bulls_and_cows "$guess")
    echo "Коров - $cows, Быков - $bulls"
    
    # Добавление хода в историю
    history+=("$turn. $guess (Коров - $cows, Быков - $bulls)")
    
    echo -e "\nИстория ходов:"
    printf "%s\n" "${history[@]}"
    
    # Проверка победы, если быков 4
    if [[ $bulls -eq 4 ]]; then
        echo "Поздравляю! Вы угадали число: $secret"
        exit 0 # Нулевой статус
    fi
done
