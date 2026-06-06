#!/usr/bin/env python3
"""
Тест поиска авторов на странице Kemono.cr
"""

from kemono_parser import KemonoParser

def test_search_artists():
    """Тест поиска авторов"""
    print("🚀 Тестируем поиск авторов на Kemono.cr")

    # Создаем парсер с Selenium
    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # Тестируем поиск
        query = "abmayo"  # Популярный автор
        print(f"🔍 Ищем: {query}")

        artists = parser.search_artists_on_page(query, limit=10)

        print(f"✅ Найдено {len(artists)} авторов:")

        for i, artist in enumerate(artists, 1):
            print(f"{i}. {artist.name} ({artist.service}) - ID: {artist.id}")
            print(f"   URL: {artist.url}")

        if not artists:
            print("❌ Авторы не найдены")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

    finally:
        # Закрываем браузер
        if hasattr(parser, 'driver') and parser.driver:
            parser.driver.quit()
            print("🔌 Браузер закрыт")

if __name__ == "__main__":
    test_search_artists()

