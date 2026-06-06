#!/usr/bin/env python3
"""
Быстрый запуск Kemono Parser
Простой интерфейс для основных операций
"""

import argparse
import sys
from pathlib import Path
from kemono_parser import KemonoParser


def main():
    parser = argparse.ArgumentParser(description='Kemono.cr Parser - быстрая утилита')
    parser.add_argument('--url', help='URL автора для парсинга')
    parser.add_argument('--service', help='Сервис для парсинга (patreon, fanbox, etc.)')
    parser.add_argument('--limit', type=int, default=10, help='Лимит постов для скачивания')
    parser.add_argument('--download-dir', default='downloads', help='Директория для скачивания')
    parser.add_argument('--selenium', action='store_true', help='Использовать Selenium')
    parser.add_argument('--headless', action='store_true', default=True, help='Запускать браузер в фоновом режиме')
    parser.add_argument('--list-artists', action='store_true', help='Показать список авторов')

    args = parser.parse_args()

    # Создаем парсер
    kemono_parser = KemonoParser(
        use_selenium=args.selenium,
        headless=args.headless
    )

    try:
        if args.list_artists:
            # Показываем список авторов
            print("Получаем список авторов...")
            artists = kemono_parser.get_artists_list(
                service=args.service,
                limit=20
            )

            print(f"\nНайдено {len(artists)} авторов:")
            for i, artist in enumerate(artists, 1):
                print(f"{i:2d}. {artist.name} ({artist.service})")
                print(f"    URL: {artist.url}")
                print()

        elif args.url:
            # Парсим конкретного автора
            print(f"Парсим автора: {args.url}")

            # Создаем объект Artist из URL
            url_parts = args.url.strip('/').split('/')
            if len(url_parts) < 4 or 'kemono.cr' not in args.url:
                print("Неверный формат URL. Ожидается: https://kemono.cr/service/user/id")
                return

            service = url_parts[-3]
            user_id = url_parts[-1]

            from kemono_parser import Artist
            artist = Artist(
                id=user_id,
                service=service,
                name=f"User_{user_id}",
                indexed="",
                updated="",
                url=args.url
            )

            # Получаем посты
            print("Получаем посты...")
            posts = kemono_parser.get_artist_posts(artist, limit=args.limit)

            if not posts:
                print("Посты не найдены")
                return

            print(f"\nНайдено {len(posts)} постов:")

            total_files = 0
            for i, post in enumerate(posts, 1):
                print(f"\n{i}. {post.title}")
                print(f"   Дата: {post.published}")
                print(f"   Вложений: {len(post.attachments)}")
                print(f"   Файлов: {len(post.files)}")

                # Скачиваем контент
                print("   Скачиваем контент...")
                downloaded = kemono_parser.download_post_content(post, args.download_dir)
                total_files += downloaded
                print(f"   Скачано: {downloaded} файлов")

            print(f"\nВсего скачано файлов: {total_files}")

        else:
            # Интерактивный режим
            print("Kemono.cr Parser")
            print("==================")
            print()
            print("Использование:")
            print("  python quick_start.py --list-artists --service patreon")
            print("  python quick_start.py --url https://kemono.cr/patreon/user/123456")
            print("  python quick_start.py --list-artists")
            print()
            print("Доступные сервисы: patreon, fanbox, gumroad, subscribestar, dlsite, discord")
            print()
            print("Для просмотра всех опций: python quick_start.py --help")

    except KeyboardInterrupt:
        print("\nПрервано пользователем")
    except Exception as e:
        print(f"Ошибка: {e}")
        import traceback
        traceback.print_exc()
    finally:
        kemono_parser.close()


if __name__ == "__main__":
    main()
