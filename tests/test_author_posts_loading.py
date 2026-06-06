#!/usr/bin/env python3
"""
Тест загрузки постов автора после исправлений
"""

from kemono_parser import KemonoParser
from interactive_downloader import create_artist_from_url

def test_author_posts_loading():
    """Тест загрузки постов автора"""

    print("🧪 ТЕСТ ЗАГРУЗКИ ПОСТОВ АВТОРА")
    print("="*50)

    # Создаем парсер
    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # Создаем объект автора
        url = 'https://kemono.cr/fanbox/user/17332140'
        artist = create_artist_from_url(url)

        if not artist:
            print("❌ Не удалось создать объект автора")
            return

        print(f"✅ Создан объект автора: {artist.name} ({artist.service})")
        print(f"   URL: {artist.url}")

        # Имитируем логику из GUI
        print("\n🔄 Имитация логики GUI...")

        # Шаг 1: Проверяем кэш (имитируем отсутствие кэша)
        cached_data = None  # Имитируем отсутствие кэша
        print("📁 Кэш: отсутствует (имитация)")

        if cached_data:
            print("✅ Кэш найден, используем его")
        else:
            print("📄 Кэша нет, выполняем полный анализ")

            # Шаг 2: Получаем посты (имитируем первую страницу)
            print("📥 Загружаем первую страницу постов...")
            page = 1
            offset = (page - 1) * 50
            page_posts = parser.get_artist_posts(artist, offset=offset, limit=50)

            print(f"📊 Результаты:")
            print(f"   Страница: {page}")
            print(f"   Offset: {offset}")
            print(f"   Найдено постов: {len(page_posts)}")

            if page_posts:
                print("✅ ПОСТЫ НАЙДЕНЫ!")
                print("   Первые 3 поста:")
                for i, post in enumerate(page_posts[:3]):
                    print(f"     {i+1}. {post.title[:40]}...")
                    print(f"        ID: {post.id}")
                    print(f"        URL: {post.url}")

                # Проверяем, что посты имеют все необходимые поля
                sample_post = page_posts[0]
                print("\n🔍 Проверка полей поста:")
                print(f"   ID: {'✅' if sample_post.id else '❌'}")
                print(f"   Title: {'✅' if sample_post.title else '❌'}")
                print(f"   Author: {'✅' if sample_post.author else '❌'}")
                print(f"   Service: {'✅' if sample_post.service else '❌'}")
                print(f"   URL: {'✅' if sample_post.url else '❌'}")
            else:
                print("❌ ПОСТЫ НЕ НАЙДЕНЫ!")
                print("   Возможные причины:")
                print("   - Автор не имеет постов")
                print("   - Проблема с парсингом HTML")
                print("   - Ошибка в селекторах")

    except Exception as e:
        print(f"❌ Ошибка тестирования: {e}")
        import traceback
        traceback.print_exc()

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_author_posts_loading()
