#!/usr/bin/env python3
"""
Диагностика URL изображений на kemono.cr
"""

from kemono_parser import KemonoParser

def debug_image_urls():
    """Проверяем URL изображений на странице поста"""
    print("🔍 Диагностика URL изображений")

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # Открываем страницу поста
        post_url = "https://kemono.cr/fanbox/post/9687940"
        print(f"📄 Открываем пост: {post_url}")

        html = parser._selenium_get(post_url)
        if not html:
            print("❌ Не удалось получить HTML")
            return

        print(f"📊 Размер HTML: {len(html)} символов")

        # Парсим HTML
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html, 'lxml')

        print("\n🔗 Найденные ссылки на изображения:")

        # Ищем все ссылки
        for link in soup.find_all('a', href=True):
            href = link['href']
            if any(ext in href.lower() for ext in ['.png', '.jpg', '.jpeg', '.gif', '.webp']):
                print(f"  📎 {href}")

        print("\n🖼️ Найденные img src:")

        # Ищем все img теги
        for img in soup.find_all('img', src=True):
            src = img['src']
            if any(ext in src.lower() for ext in ['.png', '.jpg', '.jpeg', '.gif', '.webp']):
                print(f"  🖼️ {src}")

        print("\n🔍 Ищем паттерны в URL...")

        # Ищем все URL с n1, n2, n3, n4.kemono.cr
        import re
        kemono_urls = re.findall(r'https://[n\d]+\.kemono\.cr[^"\s]+', html)
        print(f"📦 Найдено {len(kemono_urls)} URL с поддоменами kemono.cr:")

        for url in kemono_urls[:10]:  # Показываем первые 10
            if any(ext in url.lower() for ext in ['.png', '.jpg', '.jpeg', '.gif', '.webp']):
                print(f"  🌐 {url}")

        if len(kemono_urls) > 10:
            print(f"  ... и еще {len(kemono_urls) - 10} URL")

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()
    finally:
        parser.close()

if __name__ == "__main__":
    debug_image_urls()

