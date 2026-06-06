#!/usr/bin/env python3
"""
Тест GUI превью - имитация создания карточек постов
"""

from kemono_parser import KemonoParser
from interactive_downloader import create_artist_from_url

def get_post_attr(post, attr_name, default=None):
    """Имитация метода get_post_attr из GUI"""
    if hasattr(post, attr_name):
        value = getattr(post, attr_name)
        return value if value is not None else default
    elif isinstance(post, dict):
        return post.get(attr_name, default)
    else:
        return default

def test_gui_preview_creation():
    """Тест имитации создания превью в GUI"""

    print("🧪 ТЕСТ ИМИТАЦИИ GUI ПРЕВЬЮ")
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
        posts = parser.get_artist_posts(artist, offset=0, limit=3)

        if not posts:
            print("❌ Посты не найдены")
            return

        print(f"✅ Найдено {len(posts)} постов")

        # Имитируем создание карточек постов (как в GUI)
        print("\n🎨 ИМИТАЦИЯ СОЗДАНИЯ КАРТОЧЕК ПОСТОВ:")
        print("-"*50)

        for i, post in enumerate(posts):
            print(f"\n📋 Создание карточки для поста {i+1}")

            # Имитируем логику из create_post_card
            post_thumbnail = get_post_attr(post, 'thumbnail')
            post_id = get_post_attr(post, 'id', 'unknown')
            print(f"🎯 [CREATE_POST_CARD] Создание карточки для поста {post_id}")

            if post_thumbnail:
                print(f"🖼️ [ФОНОВАЯ ЗАГРУЗКА] Начинаем загрузку превью для поста {post_id}: {post_thumbnail}")
                print("   ✅ Функция load_post_thumbnail_async будет вызвана с thumbnail")
            else:
                print(f"⚠️ [CREATE_POST_CARD] У поста {post_id} нет превью, проверяем attachments и files...")
                attachments = get_post_attr(post, 'attachments', [])
                files = get_post_attr(post, 'files', [])

                if attachments or files:
                    print(f"🔍 [CREATE_POST_CARD] Пост {post_id} имеет {len(attachments)} attachments и {len(files)} files - запускаем поиск превью")
                    print("   ✅ Функция load_post_thumbnail_async будет вызвана для поиска превью")
                else:
                    print(f"❌ [CREATE_POST_CARD] Пост {post_id} не имеет превью, attachments или files")
                    print("   ❌ Превью не будет загружено")

            print(f"   📊 РЕЗУЛЬТАТ: {'✅ Превью будет отображено' if post_thumbnail or attachments or files else '❌ Превью не будет'}")

    except Exception as e:
        print(f"❌ Ошибка тестирования: {e}")
        import traceback
        traceback.print_exc()

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_gui_preview_creation()

