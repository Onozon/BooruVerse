#!/usr/bin/env python3
"""
Тестовый скрипт для проверки логики парсера
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from kemono_parser import KemonoParser
from interactive_downloader import create_artist_from_url

def test_parser_logic():
    """Тест логики парсера"""
    print("🧪 Тестируем логику парсера...")

    # Создаем парсер
    parser = KemonoParser(use_selenium=True, headless=True)
    print(f"✅ Парсер создан: {type(parser)}")

    # Создаем объект автора
    url = "https://kemono.cr/fanbox/user/6009237"
    artist = create_artist_from_url(url)
    print(f"✅ Автор создан: {artist.id if artist else 'None'}")

    if not artist:
        print("❌ Не удалось создать объект автора")
        return

    # Проверяем методы парсера
    print(f"📋 Доступные методы парсера: {[m for m in dir(parser) if 'post' in m.lower()]}")

    # Проверяем get_artist_posts_page
    try:
        print("🔍 Тестируем get_artist_posts_page...")
        page_posts = parser.get_artist_posts_page(artist, 1)
        print(f"✅ get_artist_posts_page вернул: {type(page_posts)}")

        if page_posts:
            if hasattr(page_posts, '__len__'):
                print(f"   Длина: {len(page_posts)}")
            else:
                print("   Это не последовательность")

            # Пробуем преобразовать в список
            try:
                posts_list = list(page_posts)
                print(f"   Преобразовано в список: {len(posts_list)} элементов")

                if posts_list:
                    first_post = posts_list[0]
                    print(f"   Первый пост: {type(first_post)}")
                    print(f"   ID первого поста: {getattr(first_post, 'id', 'no_id')}")
                    print(f"   Title первого поста: {getattr(first_post, 'title', 'no_title')[:50]}...")
            except Exception as e:
                print(f"   Ошибка преобразования: {e}")
        else:
            print("   Метод вернул None или пустое значение")

    except AttributeError as e:
        print(f"❌ Метод get_artist_posts_page не существует: {e}")

    except Exception as e:
        print(f"❌ Ошибка при вызове get_artist_posts_page: {e}")
        import traceback
        traceback.print_exc()

    # Проверяем get_all_artist_posts
    try:
        print("🔍 Тестируем get_all_artist_posts...")
        all_posts = parser.get_all_artist_posts(artist)
        print(f"✅ get_all_artist_posts вернул: {type(all_posts)}")

        if all_posts:
            if hasattr(all_posts, '__len__'):
                print(f"   Длина: {len(all_posts)}")
            else:
                print("   Это не последовательность")

            # Пробуем преобразовать в список
            try:
                posts_list = list(all_posts)
                print(f"   Преобразовано в список: {len(posts_list)} элементов")

                if posts_list:
                    first_post = posts_list[0]
                    print(f"   Первый пост: {type(first_post)}")
                    print(f"   ID первого поста: {getattr(first_post, 'id', 'no_id')}")
                    print(f"   Title первого поста: {getattr(first_post, 'title', 'no_title')[:50]}...")
            except Exception as e:
                print(f"   Ошибка преобразования: {e}")
        else:
            print("   Метод вернул None или пустое значение")

    except Exception as e:
        print(f"❌ Ошибка при вызове get_all_artist_posts: {e}")
        import traceback
        traceback.print_exc()

    print("🎉 Тест завершен!")

if __name__ == "__main__":
    test_parser_logic()
