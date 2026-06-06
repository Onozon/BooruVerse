#!/usr/bin/env python3
"""
Тест GUI с найденными постами
"""

from kemono_parser import KemonoParser

def test_gui_with_posts():
    """Тест GUI с найденными постами"""

    print("🧪 Тестирование GUI с найденными постами")
    print("="*60)

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # Ищем посты
        posts = parser.search_posts_selenium("abmayo", limit=3, search_url="https://kemono.cr/posts")
        print(f"✅ Найдено {len(posts)} постов")

        # Проверяем атрибуты каждого поста
        for i, post in enumerate(posts):
            print(f"\n📝 Пост {i+1}:")
            print(f"   ID: {getattr(post, 'id', 'N/A')}")
            print(f"   Title: {getattr(post, 'title', 'N/A')}")
            print(f"   Author: {getattr(post, 'author', 'N/A')}")
            print(f"   Service: {getattr(post, 'service', 'N/A')}")
            print(f"   URL: {getattr(post, 'url', 'N/A')}")

            # Проверяем на наличие поля user
            if hasattr(post, 'user'):
                print(f"   ⚠️  Имеет поле user: {post.user}")
            else:
                print("   ✅ Нет поля user")

            # Проверяем на наличие поля author
            if hasattr(post, 'author'):
                print(f"   ✅ Имеет поле author: {post.author}")
            else:
                print("   ❌ Нет поля author")
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_gui_with_posts()
