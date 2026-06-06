#!/usr/bin/env python3
"""
Тест сериализации/десериализации постов для kemono_gui_v3.py
"""

import sys
import os
from pathlib import Path

# Добавляем текущую директорию в путь
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def test_post_serialization():
    """Тест сериализации и десериализации постов"""

    # Создаем простой объект поста для тестирования
    class MockPost:
        def __init__(self):
            self.id = "12345"
            self.title = "Test Post"
            self.content = "Test content"
            self.published = "2023-01-01T12:00:00Z"
            self.service = "fanbox"
            self.user = "testuser"
            self.attachments = [
                {"name": "image.jpg", "url": "https://example.com/image.jpg"}
            ]
            self.files = []
            self.links = []

    # Импортируем методы из kemono_gui_v3
    from kemono_gui_v3 import KemonoGUI

    # Создаем экземпляр GUI для тестирования
    gui = KemonoGUI()
    gui.cache_dir.mkdir(exist_ok=True)

    # Создаем тестовый пост
    test_post = MockPost()

    print("🧪 Тестируем сериализацию поста...")

    # Тестируем сериализацию
    serialized = gui.serialize_post(test_post)
    print(f"✅ Сериализованный пост: {serialized}")

    # Тестируем десериализацию
    deserialized = gui.deserialize_post(serialized)
    print(f"✅ Десериализованный пост: {deserialized}")

    # Тестируем сохранение в кэш
    success = gui.save_posts_cache("test_artist", [test_post], is_complete=True)
    print(f"💾 Сохранение в кэш: {'✅ Успешно' if success else '❌ Ошибка'}")

    # Тестируем загрузку из кэша
    loaded_data = gui.load_posts_cache("test_artist")
    if loaded_data:
        loaded_posts, is_complete = loaded_data
        print(f"📂 Загрузка из кэша: {len(loaded_posts)} постов, complete={is_complete}")
        if loaded_posts:
            print(f"   Первый пост ID: {loaded_posts[0].get('id', 'N/A')}")
            print(f"   Первый пост title: {loaded_posts[0].get('title', 'N/A')}")
    else:
        print("❌ Ошибка загрузки из кэша")

    print("\n🎉 Тест завершен!")

if __name__ == "__main__":
    test_post_serialization()
