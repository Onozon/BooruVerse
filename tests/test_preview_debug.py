#!/usr/bin/env python3
"""
Тест для отладки проблемы с превью постов
"""

from kemono_parser import KemonoParser
from interactive_downloader import create_artist_from_url

def test_post_thumbnails():
    """Тест наличия превью у постов"""

    print("🧪 ТЕСТ ПРЕВЬЮ ПОСТОВ")
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

        # Получаем посты автора
        print("\n📥 Загружаем посты автора...")
        posts = parser.get_artist_posts(artist, offset=0, limit=5)

        if not posts:
            print("❌ Посты не найдены")
            return

        print(f"✅ Найдено {len(posts)} постов")

        # Анализируем превью каждого поста
        for i, post in enumerate(posts):
            print(f"\n📋 ПОСТ {i+1}: {post.title[:40]}...")
            print(f"   ID: {post.id}")
            print(f"   URL: {post.url}")

            # Проверяем поля превью
            thumbnail = getattr(post, 'thumbnail', None)
            attachments = getattr(post, 'attachments', [])
            files = getattr(post, 'files', [])

            print(f"   Thumbnail: {'✅' if thumbnail else '❌'} {thumbnail}")
            print(f"   Attachments: {len(attachments)} элементов")
            print(f"   Files: {len(files)} элементов")

            # Показываем первые 3 attachments если они есть
            if attachments:
                print("   Attachments:")
                for j, att in enumerate(attachments[:3]):
                    if isinstance(att, dict):
                        print(f"     {j+1}. {att.get('name', 'unnamed')} -> {att.get('url', 'no url')}")
                    else:
                        print(f"     {j+1}. {att}")

            # Показываем первые 3 files если они есть
            if files:
                print("   Files:")
                for j, file_item in enumerate(files[:3]):
                    if isinstance(file_item, dict):
                        print(f"     {j+1}. {file_item.get('name', 'unnamed')} -> {file_item.get('url', 'no url')}")
                    else:
                        print(f"     {j+1}. {file_item}")

            # Имитируем логику поиска превью из GUI
            found_preview = None

            if thumbnail:
                found_preview = thumbnail
                print(f"   ✅ Используем thumbnail: {thumbnail}")
            else:
                # Ищем в attachments
                for attachment in attachments:
                    if isinstance(attachment, dict) and attachment.get('url'):
                        file_url = attachment.get('url')
                        if file_url and any(file_url.lower().endswith(ext) for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']):
                            found_preview = file_url
                            print(f"   ✅ Найдено превью в attachments: {file_url}")
                            break

                # Если не нашли в attachments, ищем в files
                if not found_preview:
                    for file_item in files:
                        if isinstance(file_item, dict) and file_item.get('url'):
                            file_url = file_item.get('url')
                            if file_url and any(file_url.lower().endswith(ext) for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']):
                                found_preview = file_url
                                print(f"   ✅ Найдено превью в files: {file_url}")
                                break

            if found_preview:
                print(f"   🎯 ИТОГО: превью будет загружено из {found_preview}")
            else:
                print("   ❌ Превью не найдено - будет показано пустое изображение")

    except Exception as e:
        print(f"❌ Ошибка тестирования: {e}")
        import traceback
        traceback.print_exc()

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_post_thumbnails()

