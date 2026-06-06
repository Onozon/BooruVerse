#!/usr/bin/env python3
"""
Отладка получения превью постов на главной странице
"""

from kemono_parser import KemonoParser
from interactive_downloader import create_artist_from_url

def debug_post_thumbnails():
    """Отладка превью постов на главной странице"""
    print("🔍 Отладка превью постов на главной странице")

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # Получаем страницу с постами
        url = "https://kemono.cr/fanbox/user/3065392"
        artist = create_artist_from_url(url)

        # Открываем главную страницу автора
        html = parser._selenium_get(url)
        if not html:
            print("❌ Не удалось получить HTML главной страницы")
            return

        print(f"📊 Размер HTML главной страницы: {len(html)} символов")

        # Парсим HTML
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html, 'lxml')

        # Ищем посты
        post_articles = soup.find_all('article', class_='post-card')
        print(f"📄 Найдено постов: {len(post_articles)}")

        # Анализируем первый пост
        if post_articles:
            post = post_articles[0]
            print(f"\n📋 Анализ первого поста:")

            # Получаем ID поста
            post_id = None
            if post.get('data-id'):
                post_id = post['data-id']
            else:
                link = post.find('a', href=lambda x: x and '/post/' in x)
                if link:
                    href = link['href']
                    post_id = href.split('/')[-1]

            print(f"   ID поста: {post_id}")

            # Ищем все изображения в посте
            img_tags = post.find_all('img')
            print(f"   Найдено изображений: {len(img_tags)}")

            for i, img in enumerate(img_tags, 1):
                src = img.get('src')
                if src:
                    print(f"   🖼️  {i}: {src}")

                    # Проверяем атрибуты изображения
                    alt = img.get('alt', '')
                    title = img.get('title', '')
                    if alt or title:
                        print(f"       Alt/Title: {alt or title}")

            # Ищем другие элементы с изображениями
            print("\n🔍 Ищем другие элементы с изображениями:")

            # Ищем все элементы с background-image
            all_divs = post.find_all('div', style=lambda x: x and 'background-image' in x.lower())
            for div in all_divs:
                style = div.get('style', '')
                if 'background-image' in style:
                    print(f"   🎨 Background-image: {style}")

            # Ищем ссылки с изображениями
            all_links = post.find_all('a')
            for link in all_links:
                href = link.get('href', '')
                if href and ('img.kemono.cr' in href or 'thumbnail' in href):
                    print(f"   🔗 Link with image: {href}")

        # Ищем все thumbnail изображения на странице
        print("\n🌐 Все thumbnail изображения на странице:")
        thumbnail_imgs = soup.find_all('img', src=lambda x: x and 'thumbnail' in x.lower())
        for i, img in enumerate(thumbnail_imgs[:10], 1):  # Первые 10
            src = img.get('src', '')
            print(f"   {i}: {src}")

            # Проверяем, в каком элементе находится изображение
            parent = img.parent
            if parent:
                print(f"      Parent: {parent.name} {parent.get('class', [])}")

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()
    finally:
        parser.close()

if __name__ == "__main__":
    debug_post_thumbnails()
