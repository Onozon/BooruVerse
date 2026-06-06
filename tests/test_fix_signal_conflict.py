#!/usr/bin/env python3
"""
Тест для проверки исправления конфликта имен сигнала и переменной
"""

def test_signal_conflict_fix():
    """Проверяем исправление конфликта имен"""
    print("🧪 Проверяем исправление конфликта имен...")

    # Импортируем нужные модули
    import sys
    import os
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))

    # Проверяем код на наличие исправлений
    with open('kemono_gui_v2.py', 'r', encoding='utf-8') as f:
        content = f.read()

    # Проверяем наличие сигнала
    if 'full_image_loaded = pyqtSignal(object)' in content:
        print("✅ Сигнал full_image_loaded найден")
    else:
        print("❌ Сигнал full_image_loaded не найден")
        return False

    # Проверяем правильное имя переменной состояния
    if 'self.is_full_image_loaded = False' in content:
        print("✅ Переменная состояния переименована в is_full_image_loaded")
    else:
        print("❌ Переменная состояния не переименована")
        return False

    # Проверяем отсутствие конфликта
    if 'self.full_image_loaded = False' in content:
        print("❌ Всё ещё есть конфликт имен: self.full_image_loaded = False")
        return False
    else:
        print("✅ Конфликт имен устранён")

    # Проверяем правильное использование переменной состояния
    if 'self.is_full_image_loaded = True' in content:
        print("✅ Правильное использование переменной состояния")
    else:
        print("❌ Неправильное использование переменной состояния")
        return False

    # Проверяем подключение сигнала
    if 'self.full_image_loaded.connect(self.display_full_image)' in content:
        print("✅ Сигнал правильно подключен")
    else:
        print("❌ Сигнал не подключен")
        return False

    print("\n🎉 Конфликт имен устранён!")
    print("📋 Исправления:")
    print("   📡 Сигнал full_image_loaded сохранён")
    print("   🔄 Переменная состояния переименована в is_full_image_loaded")
    print("   🚫 Конфликт имен устранён")
    print("   🔗 Сигнал правильно подключен к слоту")

    return True

if __name__ == "__main__":
    success = test_signal_conflict_fix()
    print("\n🚀 Готово к тестированию!" if success else "\n❌ Нужно исправить")
    sys.exit(0 if success else 1)

