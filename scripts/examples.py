#!/usr/bin/env python3
"""
Примеры использования Kemono Parser
"""

import json
import os
import sys
from pathlib import Path
from kemono_parser import KemonoParser, Artist


def load_config():
    """Загрузка конфигурации"""
    config_path = Path(__file__).parent / "config.json"
    if config_path.exists():
        with open(config_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}


def example_basic_usage():
    """Базовый пример использования"""
    print("=== Базовый пример использования ===")

    parser = KemonoParser()

    try:
        # Получаем список авторов
        print("Получаем список авторов...")
        artists = parser.get_artists_list(limit=5)

        if not artists:
            print("Не удалось получить список авторов")
            return

        print(f"Найдено {len(artists)} авторов:")
        for i, artist in enumerate(artists, 1):
            print(f"{i}. {artist.name} ({artist.service}) - {artist.url}")

        # Выбираем первого автора
        artist = artists[0]
        print(f"\nПарсим посты автора: {artist.name}")

        # Получаем посты автора
        posts = parser.get_artist_posts(artist, limit=3)

        print(f"Найдено {len(posts)} постов:")
        for i, post in enumerate(posts, 1):
            print(f"{i}. {post.title} (ID: {post.id})")
            print(f"   Дата: {post.published}")
            print(f"   Вложений: {len(post.attachments)}")
            print(f"   Файлов: {len(post.files)}")
            print()

        # Скачиваем контент первого поста
        if posts:
            post = posts[0]
            print(f"Скачиваем контент поста: {post.title}")

            downloaded = parser.download_post_content(post)
            print(f"Скачано файлов: {downloaded}")

    except Exception as e:
        print(f"Ошибка: {e}")
    finally:
        parser.close()


def example_service_specific():
    """Пример парсинга конкретного сервиса"""
    print("\n=== Парсинг конкретного сервиса ===")

    config = load_config()
    services = config.get('services', ['patreon'])

    parser = KemonoParser()

    try:
        for service in services[:3]:  # Первые 3 сервиса
            print(f"\nПарсим {service}...")
            artists = parser.get_artists_list(service=service, limit=3)

            print(f"Найдено {len(artists)} авторов на {service}:")
            for artist in artists:
                print(f"- {artist.name} (ID: {artist.id})")

    except Exception as e:
        print(f"Ошибка: {e}")
    finally:
        parser.close()


def example_download_artist():
    """Пример скачивания всех постов автора"""
    print("\n=== Скачивание всех постов автора ===")

    # Пример URL автора (замените на реальный)
    artist_url = "https://kemono.cr/patreon/user/123456"  # Замените на реальный URL

    parser = KemonoParser()

    try:
        # Создаем объект Artist из URL
        url_parts = artist_url.strip('/').split('/')
        if len(url_parts) >= 4:
            service = url_parts[-3]
            user_id = url_parts[-1]

            artist = Artist(
                id=user_id,
                service=service,
                name=f"User_{user_id}",
                indexed="",
                updated="",
                url=artist_url
            )

            print(f"Парсим автора: {artist.name} ({artist.service})")

            # Получаем все посты автора
            posts = []
            offset = 0
            batch_size = 10

            while True:
                batch = parser.get_artist_posts(artist, offset=offset, limit=batch_size)
                if not batch:
                    break
                posts.extend(batch)
                offset += batch_size
                print(f"Получено постов: {len(posts)}")

                if len(posts) >= 50:  # Ограничение для примера
                    break

            print(f"\nВсего постов: {len(posts)}")

            # Скачиваем контент всех постов
            download_dir = "downloads"
            total_downloaded = 0

            for i, post in enumerate(posts, 1):
                print(f"Скачиваем пост {i}/{len(posts)}: {post.title}")
                downloaded = parser.download_post_content(post, download_dir)
                total_downloaded += downloaded

            print(f"\nВсего скачано файлов: {total_downloaded}")

    except Exception as e:
        print(f"Ошибка: {e}")
    finally:
        parser.close()


def example_selenium_usage():
    """Пример использования с Selenium"""
    print("\n=== Использование с Selenium ===")

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        print("Используем Selenium для парсинга...")

        # Получаем список авторов с Selenium
        artists = parser.get_artists_list(limit=3)

        if artists:
            artist = artists[0]
            print(f"Автор: {artist.name}")

            # Получаем посты
            posts = parser.get_artist_posts(artist, limit=2)

            print(f"Найдено постов: {len(posts)}")
            for post in posts:
                print(f"- {post.title}")

    except Exception as e:
        print(f"Ошибка: {e}")
    finally:
        parser.close()


def example_search_and_download():
    """Пример поиска и скачивания конкретного контента"""
    print("\n=== Поиск и скачивание контента ===")

    parser = KemonoParser()

    try:
        # Получаем список авторов
        artists = parser.get_artists_list(limit=10)

        # Ищем авторов с определенными ключевыми словами
        keywords = ["art", "artist", "draw", "illustration"]
        matching_artists = []

        for artist in artists:
            artist_name_lower = artist.name.lower()
            if any(keyword in artist_name_lower for keyword in keywords):
                matching_artists.append(artist)

        print(f"Найдено {len(matching_artists)} подходящих авторов")

        # Скачиваем контент от первых 2 подходящих авторов
        for artist in matching_artists[:2]:
            print(f"\nОбрабатываем автора: {artist.name}")

            posts = parser.get_artist_posts(artist, limit=5)

            for post in posts:
                # Скачиваем только посты с изображениями
                if post.attachments:
                    print(f"Скачиваем пост с изображениями: {post.title}")
                    downloaded = parser.download_post_content(post)
                    print(f"Скачано: {downloaded} файлов")

    except Exception as e:
        print(f"Ошибка: {e}")
    finally:
        parser.close()


def example_batch_download():
    """Пример пакетного скачивания"""
    print("\n=== Пакетное скачивание ===")

    # Список URL авторов для скачивания
    artist_urls = [
        # Добавьте реальные URL авторов
        # "https://kemono.cr/patreon/user/123456",
        # "https://kemono.cr/fanbox/user/789012",
    ]

    if not artist_urls:
        print("Добавьте URL авторов в список artist_urls")
        return

    parser = KemonoParser()
    download_dir = "batch_downloads"

    try:
        for url in artist_urls:
            print(f"\nОбрабатываем: {url}")

            # Создаем объект Artist
            url_parts = url.strip('/').split('/')
            service = url_parts[-3]
            user_id = url_parts[-1]

            artist = Artist(
                id=user_id,
                service=service,
                name=f"User_{user_id}",
                indexed="",
                updated="",
                url=url
            )

            # Получаем и скачиваем посты
            posts = parser.get_artist_posts(artist, limit=10)

            for post in posts:
                parser.download_post_content(post, download_dir)

            print(f"Завершено для {url}")

    except Exception as e:
        print(f"Ошибка: {e}")
    finally:
        parser.close()


def main():
    """Главная функция"""
    print("Kemono.cr Parser - Примеры использования")
    print("=" * 50)

    # Проверяем наличие зависимостей
    try:
        import requests
        import beautifulsoup4
    except ImportError as e:
        print(f"Ошибка импорта: {e}")
        print("Установите зависимости: pip install -r requirements.txt")
        return

    # Запускаем примеры
    examples = [
        ("Базовое использование", example_basic_usage),
        ("Парсинг конкретного сервиса", example_service_specific),
        ("Использование с Selenium", example_selenium_usage),
        ("Поиск и скачивание", example_search_and_download),
        ("Пакетное скачивание", example_batch_download),
        ("Скачивание всех постов автора", example_download_artist),
    ]

    print("Выберите пример для запуска:")
    for i, (name, _) in enumerate(examples, 1):
        print(f"{i}. {name}")

    print("\n0. Запустить все примеры")

    try:
        choice = input("\nВаш выбор (или Enter для выхода): ").strip()

        if not choice:
            return

        if choice == "0":
            # Запускаем все примеры
            for name, example_func in examples:
                try:
                    example_func()
                except Exception as e:
                    print(f"Ошибка в примере '{name}': {e}")
                print("-" * 50)
        else:
            choice_idx = int(choice) - 1
            if 0 <= choice_idx < len(examples):
                examples[choice_idx][1]()
            else:
                print("Неверный выбор")

    except KeyboardInterrupt:
        print("\nПрервано пользователем")
    except Exception as e:
        print(f"Ошибка: {e}")


if __name__ == "__main__":
    main()
