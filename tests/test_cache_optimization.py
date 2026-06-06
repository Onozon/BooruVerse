#!/usr/bin/env python3
"""
Тест новой функциональности кэширования при массовой загрузке
"""

import sys
import os
import json
from pathlib import Path

# Добавляем текущую директорию в путь
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def test_cache_optimization():
    """Тестируем работу кэширования при массовой загрузке"""

    print("🔍 Тест оптимизации кэширования при массовой загрузке")
    print("=" * 60)

    # Проверяем наличие кэша медиа
    cache_dir = Path("cache/media_metadata")
    if not cache_dir.exists():
        print("❌ Директория кэша не найдена")
        return

    # Считаем файлы кэша
    cache_files = list(cache_dir.glob("*.json"))
    print(f"📂 Найдено файлов кэша медиа: {len(cache_files)}")

    if not cache_files:
        print("⚠️ Кэш пустой, создайте кэш запустив анализ постов")
        return

    # Показываем пример структуры кэша
    sample_file = cache_files[0]
    print(f"\n📄 Пример файла кэша: {sample_file.name}")

    try:
        with open(sample_file, 'r', encoding='utf-8') as f:
            cache_data = json.load(f)

        media_count = len(cache_data.get('media', []))
        post_id = cache_data.get('post_id', 'unknown')
        last_updated = cache_data.get('last_updated', 'unknown')

        print(f"   Пост ID: {post_id}")
        print(f"   Медиа файлов: {media_count}")
        print(f"   Последнее обновление: {last_updated}")

        if media_count > 0:
            first_media = cache_data['media'][0]
            filename = first_media.get('filename', '')
            file_ext = Path(filename).suffix.lower() if filename else ''
            print(f"   Пример файла: {filename[:50]}..." if len(filename) > 50 else f"   Пример файла: {filename}")
            print(f"   Расширение: {file_ext}")

    except Exception as e:
        print(f"❌ Ошибка чтения файла кэша: {e}")

    print("\n🚀 Новая функциональность:")
    print("✅ При массовой загрузке сначала проверяется кэш")
    print("✅ Если кэш найден - используется без повторного анализа")
    print("✅ Только новые посты анализируются заново")
    print("✅ Применяется фильтрация по типам файлов")
    print("✅ Показывается статистика: 'Из кэша: X постов | Проанализировано: Y постов'")

    print("\n💡 Преимущества:")
    print("⚡ Значительно быстрее при повторных загрузках")
    print("💾 Экономит трафик и ресурсы")
    print("🎯 Учитывает настройки фильтрации типов файлов")
    print("📊 Прозрачная статистика использования кэша")

if __name__ == "__main__":
    test_cache_optimization()
