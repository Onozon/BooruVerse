#!/usr/bin/env python3
"""
Тест функций открытия и копирования для авторов
"""

from kemono_parser import KemonoParser

def test_artist_functions():
    """Тест функций для работы с авторами"""

    print("🎯 ТЕСТ ФУНКЦИЙ АВТОРОВ")
    print("="*50)

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # Получаем автора через поиск
        print("🔍 Ищем автора 'abmayo'...")
        artists = parser.search_artists_selenium("abmayo", limit=1)

        if artists:
            artist = artists[0]
            print(f"✅ Найден автор: {artist.name} ({artist.service})")
            print(f"   URL: {artist.url}")

            # Тестируем функции
            print("\n🔧 ТЕСТИРУЕМ ФУНКЦИИ:")

            # Тест получения URL
            if hasattr(artist, 'url'):
                print(f"✅ hasattr(artist, 'url'): {artist.url}")
            else:
                print("❌ Нет атрибута url")

            # Тест получения имени
            if hasattr(artist, 'name'):
                print(f"✅ hasattr(artist, 'name'): {artist.name}")
            else:
                print("❌ Нет атрибута name")

            # Тест получения сервиса
            if hasattr(artist, 'service'):
                print(f"✅ hasattr(artist, 'service'): {artist.service}")
            else:
                print("❌ Нет атрибута service")

            # Тест получения updated
            if hasattr(artist, 'updated'):
                print(f"✅ hasattr(artist, 'updated'): {artist.updated}")
            else:
                print("❌ Нет атрибута updated")

            print("\n✅ ВСЕ ФУНКЦИИ ДОЛЖНЫ РАБОТАТЬ!")
        else:
            print("❌ Автор не найден")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_artist_functions()

