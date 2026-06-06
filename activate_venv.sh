#!/bin/bash
# Скрипт для активации виртуального окружения
# Использование: source activate_venv.sh

# Переходим в папку проекта
cd "$(dirname "$0")"

# Активируем виртуальное окружение
source .venv/bin/activate

echo "✅ Виртуальное окружение активировано!"
echo "Для запуска основного приложения используйте:"
echo "python3 kemono_gui_v6.py"
echo ""
echo "Для деактивации введите: deactivate"

