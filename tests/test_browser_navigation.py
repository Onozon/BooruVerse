#!/usr/bin/env python3
"""
Тест навигации браузерной вкладки
"""

from kemono_parser import KemonoParser

def test_artists_pages():
    """Тест страниц авторов"""

    print("🎯 ТЕСТ СТРАНИЦ АВТОРОВ")
    print("="*50)

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        pages = {
            "main": "https://kemono.cr/artists",
            "updated": "https://kemono.cr/artists/updated",
            "random": "https://kemono.cr/artists/random"
        }

        for page_type, url in pages.items():
            print(f"\n🔍 Тестируем страницу '{page_type}': {url}")

            try:
                artists = parser.get_artists_page(url, limit=5)

                print(f"📄 Найдено авторов: {len(artists)}")
                if artists:
                    print("✅ СТРАНИЦА РАБОТАЕТ!")
                    for i, artist in enumerate(artists[:3]):  # Показываем первые 3
                        print(f"  {i+1}. {artist.name} ({artist.service}) - ID: {artist.id}")
                else:
                    print("⚠️  Авторы не найдены")

            except Exception as e:
                print(f"❌ Ошибка: {e}")

    except Exception as e:
        print(f"❌ Общая ошибка: {e}")

    finally:
        if parser.driver:
            parser.driver.quit()

def test_posts_pages():
    """Тест страниц постов"""

    print("\n🎯 ТЕСТ СТРАНИЦ ПОСТОВ")
    print("="*50)

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        pages = {
            "main": "https://kemono.cr/posts",
            "popular": "https://kemono.cr/posts/popular",
            "tags": "https://kemono.cr/posts/tags",
            "random": "https://kemono.cr/posts/random"
        }

        for page_type, url in pages.items():
            print(f"\n🔍 Тестируем страницу '{page_type}': {url}")

            try:
                posts = parser.get_posts_page(url, limit=5)

                print(f"📄 Найдено постов: {len(posts)}")
                if posts:
                    print("✅ СТРАНИЦА РАБОТАЕТ!")
                    for i, post in enumerate(posts[:3]):  # Показываем первые 3
                        print(f"  {i+1}. {post.title} - Автор: {post.author}")
                        print(f"      URL: {post.url}")
                else:
                    print("⚠️  Посты не найдены")

            except Exception as e:
                print(f"❌ Ошибка: {e}")

    except Exception as e:
        print(f"❌ Общая ошибка: {e}")

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_artists_pages()
    test_posts_pages()

