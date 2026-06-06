#!/usr/bin/env python3
"""
Быстрый тест поиска авторов
"""

from kemono_parser import KemonoParser

def test_artists_search():
    """Тест поиска авторов"""

    print("🎯 ТЕСТ ПОИСКА АВТОРОВ")
    print("="*50)

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        print("🔍 Ищем автора 'abmayo'...")

        artists = parser.search_artists_selenium("abmayo", limit=5, search_url="https://kemono.cr/artists")

        print(f"📄 Найдено авторов: {len(artists)}")

        if artists:
            print("✅ ПОИСК УСПЕШЕН!")
            for i, artist in enumerate(artists):
                print(f"  {i+1}. {artist.name} ({artist.service}) - ID: {artist.id}")
                print(f"     URL: {artist.url}")
        else:
            print("❌ Авторы не найдены")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_artists_search()

