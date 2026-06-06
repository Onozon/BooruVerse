#!/usr/bin/env python3
"""
Тест новой логики поиска без GUI
"""

from kemono_parser import KemonoParser

def test_artists_search():
    """Тест поиска авторов с правильными URL"""
    print("🧪 Тест поиска авторов с новой логикой")

    parser = KemonoParser(use_selenium=False)

    # Тест разных URL для поиска
    test_urls = [
        "https://kemono.cr/artists",  # Поиск
        "https://kemono.cr/artists/updated",  # Недавние
        "https://kemono.cr/artists/random"  # Случайный
    ]

    for url in test_urls:
        print(f"\n🔍 Тест поиска по URL: {url}")
        try:
            artists = parser.search_artists_http("abmayo", limit=10, search_url=url)
            print(f"✅ Найдено {len(artists)} авторов")

            if artists:
                for i, artist in enumerate(artists[:3]):
                    print(f"  {i+1}. {artist.name} ({artist.service})")

        except Exception as e:
            print(f"❌ Ошибка: {e}")

def test_posts_search():
    """Тест поиска постов"""
    print("\n📄 Тест поиска постов с новой логикой")

    parser = KemonoParser(use_selenium=False)

    # Тест разных URL для поиска постов
    test_urls = [
        "https://kemono.cr/posts",  # Поиск
        "https://kemono.cr/posts/popular",  # Популярные
        "https://kemono.cr/posts/tags"  # Тэги
    ]

    for url in test_urls:
        print(f"\n🔍 Тест поиска постов по URL: {url}")
        try:
            posts = parser.search_posts("abmayo", limit=10, search_url=url)
            print(f"✅ Найдено {len(posts)} постов")

            if posts:
                for i, post in enumerate(posts[:3]):
                    print(f"  {i+1}. {post.title} ({post.service}/{post.user})")

        except Exception as e:
            print(f"❌ Ошибка: {e}")

def test_state_management():
    """Тест управления состоянием поиска"""
    print("\n⚙️ Тест управления состоянием поиска")

    # Имитируем логику GUI
    current_search_type = "artists"
    current_search_url = "https://kemono.cr/artists"

    print(f"Начальное состояние: {current_search_type} -> {current_search_url}")

    # Имитируем нажатие кнопки "Недавние"
    current_search_type = "artists"
    current_search_url = "https://kemono.cr/artists/updated"
    print(f"После нажатия 'Недавние': {current_search_type} -> {current_search_url}")

    # Имитируем нажатие кнопки "Популярные" (Posts)
    current_search_type = "posts"
    current_search_url = "https://kemono.cr/posts/popular"
    print(f"После нажатия 'Популярные': {current_search_type} -> {current_search_url}")

    # Имитируем поиск
    if current_search_type == "artists":
        print("Будет выполнен поиск авторов")
    elif current_search_type == "posts":
        print("Будет выполнен поиск постов")

def main():
    """Основная функция тестирования"""
    print("🚀 Тест новой логики поиска Kemono.cr")
    print("="*60)

    test_state_management()
    test_artists_search()
    test_posts_search()

    print("\n" + "="*60)
    print("✅ Все тесты завершены")

if __name__ == "__main__":
    main()

