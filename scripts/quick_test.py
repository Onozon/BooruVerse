#!/usr/bin/env python3
"""
Быстрый тест интерактивного загрузчика с автоматическим вводом
"""

import sys
from io import StringIO

def test_interactive_downloader():
    """Тестируем интерактивный загрузчик с автоматическими ответами"""

    print("🧪 Тестируем интерактивный загрузчик...")
    print("=" * 50)

    # Monkey patch input function
    original_input = __builtins__['input']

    inputs = [
        "https://kemono.cr/fanbox/user/3065392",  # URL автора
        "1",  # Количество постов для тестирования
        "y"   # Подтверждение скачивания
    ]
    input_index = 0

    def mock_input(prompt=""):
        global input_index
        if input_index < len(inputs):
            result = inputs[input_index]
            print(f"{prompt}{result}")  # Эхо ввода
            input_index += 1
            return result
        else:
            return original_input(prompt)

    try:
        __builtins__['input'] = mock_input

        # Импортируем и запускаем main функцию
        from interactive_downloader import main
        main()

    except Exception as e:
        print(f"❌ Ошибка при тестировании: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # Восстанавливаем оригинальную функцию
        __builtins__['input'] = original_input

if __name__ == "__main__":
    test_interactive_downloader()
