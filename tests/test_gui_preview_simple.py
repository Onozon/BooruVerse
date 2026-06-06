#!/usr/bin/env python3
"""
Простой тест GUI превью - запуск GUI с имитацией загрузки постов
"""

import sys
import os
from PyQt6.QtWidgets import QApplication
from PyQt6.QtCore import QTimer

# Добавляем текущую директорию в путь
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from kemono_gui_v5 import KemonoGUI
from kemono_parser import KemonoParser
from interactive_downloader import create_artist_from_url

def test_gui_preview_simple():
    """Запуск GUI с тестовой загрузкой постов"""

    print("🧪 ПРОСТОЙ ТЕСТ GUI ПРЕВЬЮ")
    print("="*50)

    app = QApplication(sys.argv)

    try:
        # Создаем GUI
        gui = KemonoGUI()

        def load_test_posts():
            """Функция для загрузки тестовых постов"""
            print("🔄 Начинаем загрузку тестовых постов...")

            try:
                # Имитируем загрузку постов (как будто пользователь ввел URL и нажал "Загрузить посты")
                from kemono_parser import KemonoParser
                from interactive_downloader import create_artist_from_url

                # Создаем парсер
                parser = KemonoParser(use_selenium=True, headless=True)

                # Создаем объект автора
                url = 'https://kemono.cr/fanbox/user/17332140'
                artist = create_artist_from_url(url)

                if artist:
                    print(f"✅ Создан объект автора: {artist.name}")

                    # Получаем посты
                    posts = parser.get_artist_posts(artist, offset=0, limit=2)
                    print(f"📊 Загружено {len(posts)} постов")

                    # Имитируем успешную загрузку постов
                    gui.all_posts = posts
                    gui.on_posts_loaded(posts)

                    print("✅ Посты переданы в GUI для отображения")
                else:
                    print("❌ Не удалось создать объект автора")

                if parser.driver:
                    parser.driver.quit()

            except Exception as e:
                print(f"❌ Ошибка загрузки постов: {e}")
                import traceback
                traceback.print_exc()

        # Запускаем загрузку постов через 2 секунды
        QTimer.singleShot(2000, load_test_posts)

        # Запускаем GUI
        print("🚀 Запуск GUI...")
        gui.show()

        # Выходим через 10 секунд
        QTimer.singleShot(10000, app.quit)

        app.exec()

        print("✅ Тест завершен")

    except Exception as e:
        print(f"❌ Ошибка тестирования: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_gui_preview_simple()

