#!/usr/bin/env python3
"""
Простой тест сериализации постов без GUI
"""

import sys
import os
import json
from pathlib import Path
from datetime import datetime

def serialize_post(post):
    """Преобразовать объект поста в сериализуемый словарь"""
    try:
        # Получаем основные атрибуты поста
        post_dict = {
            'id': getattr(post, 'id', ''),
            'title': getattr(post, 'title', ''),
            'content': getattr(post, 'content', ''),
            'published': getattr(post, 'published', None),
            'date': getattr(post, 'date', None),
            'service': getattr(post, 'service', ''),
            'user': getattr(post, 'user', ''),
            'added': getattr(post, 'added', None),
            'edited': getattr(post, 'edited', None),
            'url': getattr(post, 'url', ''),
            'post_type': getattr(post, 'post_type', ''),
            'embed': getattr(post, 'embed', {}),
            'file': getattr(post, 'file', {}),
            'attachments': getattr(post, 'attachments', []),
            'files': getattr(post, 'files', []),
            'links': getattr(post, 'links', []),
            'shared_file': getattr(post, 'shared_file', False)
        }

        # Преобразуем даты в строки для JSON сериализации
        for date_field in ['published', 'date', 'added', 'edited']:
            if post_dict[date_field] is not None:
                if hasattr(post_dict[date_field], 'isoformat'):
                    post_dict[date_field] = post_dict[date_field].isoformat()
                elif isinstance(post_dict[date_field], str):
                    # Уже строка, оставляем как есть
                    pass
                else:
                    # Другие типы преобразуем в строку
                    post_dict[date_field] = str(post_dict[date_field])

        return post_dict
    except Exception as e:
        print(f"❌ Ошибка сериализации поста {getattr(post, 'id', 'unknown')}: {e}")
        return None

def save_posts_cache(posts_data, artist_id="test_artist", cache_dir="cache"):
    """Сохранить кэш постов артиста"""
    try:
        cache_path = Path(cache_dir) / "posts_metadata" / f"{artist_id}_posts.json"
        cache_path.parent.mkdir(parents=True, exist_ok=True)

        # Сериализуем посты
        serialized_posts = []
        for post in posts_data:
            serialized_post = serialize_post(post)
            if serialized_post:
                serialized_posts.append(serialized_post)

        cache_data = {
            'artist_id': artist_id,
            'posts': serialized_posts,
            'is_complete': True,
            'last_updated': datetime.now().isoformat(),
            'version': 'v3'
        }

        with open(cache_path, 'w', encoding='utf-8') as f:
            json.dump(cache_data, f, ensure_ascii=False, indent=2)

        print(f"💾 Кэш постов сохранен: {artist_id} ({len(serialized_posts)} постов)")
        return True
    except Exception as e:
        print(f"❌ Ошибка сохранения кэша постов: {e}")
        import traceback
        traceback.print_exc()
        return False

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

def test_serialization():
    """Тест сериализации постов"""
    print("🧪 Тестируем сериализацию постов...")

    # Создаем тестовый пост
    test_post = MockPost()

    # Тестируем сериализацию
    serialized = serialize_post(test_post)
    print(f"✅ Сериализованный пост: {serialized}")

    # Тестируем сохранение в кэш
    success = save_posts_cache([test_post], "6009237")
    print(f"💾 Сохранение в кэш: {'✅ Успешно' if success else '❌ Ошибка'}")

    # Проверяем файл
    cache_path = Path("cache/posts_metadata/6009237_posts.json")
    if cache_path.exists():
        print(f"📁 Файл кэша создан: {cache_path}")

        # Читаем содержимое
        with open(cache_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        print(f"📊 Данные в кэше: {len(data.get('posts', []))} постов")
        print(f"🔖 Версия кэша: {data.get('version', 'unknown')}")
        print(f"✅ Полный кэш: {data.get('is_complete', False)}")

        if data.get('posts'):
            first_post = data['posts'][0]
            print(f"   Первый пост ID: {first_post.get('id', 'N/A')}")
            print(f"   Первый пост title: {first_post.get('title', 'N/A')}")
    else:
        print("❌ Файл кэша не найден")

    print("\n🎉 Тест завершен!")

if __name__ == "__main__":
    test_serialization()
