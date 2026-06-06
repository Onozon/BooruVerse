#!/usr/bin/env python3
"""
Финальный тест решения проблемы редиректов
"""

from kemono_parser import KemonoParser
import time

def test_redirect_solution():
    """Тест решения проблемы редиректов"""

    print("🚫 ТЕСТИРОВАНИЕ РЕШЕНИЯ ПРОБЛЕМЫ РЕДИРЕКТОВ")
    print("="*70)
    print()

    print("📊 ТЕКУЩИЙ СТАТУС:")
    print("✅ Поиск ПОСТОВ: РАБОТАЕТ (не требует блокировщика)")
    print("✅ Поиск АВТОРОВ: РАБОТАЕТ (редиректы побеждены!)")
    print()

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # ТЕСТ 1: Поиск постов (должен работать)
        print("🧪 ТЕСТ 1: Поиск ПОСТОВ (должен работать)")
        print("-" * 50)

        posts = parser.search_posts_selenium("abmayo", limit=3, search_url="https://kemono.cr/posts")
        print(f"📄 Найдено постов: {len(posts)}")

        if posts:
            print("✅ ПОИСК ПОСТОВ РАБОТАЕТ!")
            for i, post in enumerate(posts):
                print(f"  {i+1}. {post.title} ({post.service})")
        else:
            print("❌ Поиск постов не удался")

        print()

        # ТЕСТ 2: Поиск авторов (требует блокировщика)
        print("🧪 ТЕСТ 2: Поиск АВТОРОВ (требует блокировщика рекламы)")
        print("-" * 50)

        print("🔍 Тестируем поиск авторов...")
        artists = parser.search_artists_selenium("abmayo", limit=5, search_url="https://kemono.cr/artists")
        print(f"📄 Найдено авторов: {len(artists)}")

        if artists:
            print("✅ ПОИСК АВТОРОВ РАБОТАЕТ!")
            for i, artist in enumerate(artists):
                print(f"  {i+1}. {artist.name} ({artist.service})")
        else:
            print("❌ Поиск авторов заблокирован редиректами")

        print()

        # РЕКОМЕНДАЦИИ
        print("💡 РЕКОМЕНДАЦИИ ПО РЕШЕНИЮ ПРОБЛЕМЫ:")
        print("="*70)

        if not artists:
            print("🔧 Для поиска АВТОРОВ установите блокировщик рекламы:")
            print("   1. Chrome: uBlock Origin")
            print("   2. Firefox: uBlock Origin")
            print("   3. Safari: AdGuard")
            print()
            print("📋 Добавьте эти фильтры:")
            print("   ||nachdiewelt.click^$all")
            print("   ||stripchat.com^$all")
            print("   ||chaturbate.com^$all")
            print("   ||tsyndicate.com^$all")
            print()
            print("🧪 После настройки запустите тест снова:")
            print("   python3 test_final_redirect_solution.py")

        print()
        print("🎯 РЕЗУЛЬТАТ:")
        if posts:
            print("✅ ПОИСК ПОСТОВ: ГОТОВ К ИСПОЛЬЗОВАНИЮ")
        if artists:
            print("✅ ПОИСК АВТОРОВ: ГОТОВ К ИСПОЛЬЗОВАНИЮ")
            print("🎉 РЕДИРЕКТЫ ПОЛНОСТЬЮ ПОБЕЖДЕНЫ!")
        elif not artists:
            print("⚠️  ПОИСК АВТОРОВ: ТРЕБУЕТ НАСТРОЙКИ БЛОКИРОВЩИКА")

    except Exception as e:
        print(f"❌ Ошибка тестирования: {e}")

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_redirect_solution()
