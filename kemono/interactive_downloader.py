#!/usr/bin/env python3
"""
Интерактивный загрузчик контента Kemono.cr
Запрашивает URL автора и скачивает все медиафайлы из всех постов
"""

import re
import os
import json
import time
from urllib.parse import urlparse
from pathlib import Path
from typing import Optional, Tuple
from kemono_parser import KemonoParser, Artist, Post


def validate_kemono_url(url: str) -> Tuple[bool, Optional[str], Optional[str], Optional[str]]:
    """
    Проверяет корректность URL Kemono.cr
    Возвращает: (is_valid, service, user_id, error_message)
    """
    if not url or not isinstance(url, str):
        return False, None, None, "URL не может быть пустым"

    # Убираем лишние пробелы
    url = url.strip()

    # Проверяем базовый формат URL
    if not url.startswith(('http://', 'https://')):
        url = 'https://' + url

    try:
        parsed = urlparse(url)
        if parsed.netloc not in ['kemono.cr', 'www.kemono.cr']:
            return False, None, None, "URL должен быть с сайта kemono.cr"

        # Разбираем путь: /service/user/user_id
        path_parts = parsed.path.strip('/').split('/')
        if len(path_parts) < 3:
            return False, None, None, "Неверный формат URL. Ожидается: /service/user/user_id"

        service = path_parts[0]
        user_part = path_parts[1]
        user_id = path_parts[2]

        if user_part != 'user':
            return False, None, None, "Неверный формат URL. Ожидается: /service/user/user_id"

        if not user_id:
            return False, None, None, "Не найден ID пользователя в URL"

        return True, service, user_id, None

    except Exception as e:
        return False, None, None, f"Ошибка при разборе URL: {str(e)}"


def create_artist_from_url(url: str) -> Optional[Artist]:
    """Создает объект Artist из URL"""
    is_valid, service, user_id, error = validate_kemono_url(url)

    if not is_valid:
        print(f"❌ Ошибка: {error}")
        return None

    # Создаем Artist
    artist = Artist(
        id=user_id,
        service=service,
        name=f"User_{user_id}",  # Временно, имя будет обновлено при парсинге
        indexed="",
        updated="",
        url=url
    )

    return artist


def get_all_artist_posts(parser: KemonoParser, artist: Artist) -> list[Post]:
    """Получает все посты автора без лимита"""
    all_posts = []
    offset = 0
    batch_size = 50  # Максимальный размер батча

    print(f"\n🔍 Поиск всех постов автора {artist.name} ({artist.service})...")

    while True:
        print(f"   Получаем посты с offset {offset}...")

        # Получаем батч постов
        posts_batch = parser.get_artist_posts(artist, offset=offset, limit=batch_size)

        if not posts_batch:
            print("   Больше постов не найдено")
            break

        all_posts.extend(posts_batch)
        print(f"   Найдено {len(posts_batch)} новых постов (всего: {len(all_posts)})")

        # Если получили меньше чем batch_size, значит это последний батч
        if len(posts_batch) < batch_size:
            break

        offset += batch_size

        # Небольшая пауза между запросами
        time.sleep(1)

    return all_posts


def count_media_files(posts: list[Post]) -> Tuple[int, int, int]:
    """Подсчитывает общее количество медиафайлов"""
    total_images = 0
    total_videos = 0
    total_files = 0

    for post in posts:
        for attachment in post.attachments:
            url = attachment.get('url', '').lower()
            if any(ext in url for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']):
                total_images += 1
            elif any(ext in url for ext in ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv']):
                total_videos += 1

        for file_info in post.files:
            url = file_info.get('url', '').lower()
            if any(ext in url for ext in ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv']):
                total_videos += 1
            else:
                total_files += 1

    return total_images, total_videos, total_files


def create_safe_filename(name: str, max_length: int = 100) -> str:
    """Создает безопасное имя файла/папки"""
    # Убираем недопустимые символы
    safe_name = re.sub(r'[<>:"/\\|?*]', '_', name)
    # Убираем множественные пробелы и подчеркивания
    safe_name = re.sub(r'[_\s]+', '_', safe_name)
    # Обрезаем до максимальной длины
    if len(safe_name) > max_length:
        safe_name = safe_name[:max_length].rstrip('_')
    # Убираем подчеркивания в начале и конце
    safe_name = safe_name.strip('_')

    # Если имя пустое, возвращаем дефолтное
    if not safe_name:
        safe_name = "untitled"

    return safe_name


def download_all_media(parser: KemonoParser, artist: Artist, posts: list[Post]) -> dict:
    """Скачивает все медиафайлы из постов автора"""
    print(f"\n📁 Создаю структуру папок в: downloads/")

    total_downloaded = 0
    total_skipped = 0
    downloaded_by_post = {}
    errors = []

    for i, post in enumerate(posts, 1):
        print(f"\n📄 [{i}/{len(posts)}] Обработка поста: {post.title}")

        post_downloaded = 0
        post_skipped = 0

        # Используем download_post_content из парсера для загрузки медиафайлов с полной страницы поста
        print(f"   🔍 Загружаю медиафайлы с страницы поста...")
        try:
            # Передаем базовую папку downloads, парсер сам создаст правильную структуру
            downloaded = parser.download_post_content(post, "downloads", artist)
            post_downloaded = downloaded
            if downloaded > 0:
                print(f"   ✅ Скачано файлов: {downloaded}")
            else:
                print(f"   ⚠️  Медиафайлы не найдены на странице поста")
        except Exception as e:
            print(f"   ❌ Ошибка при загрузке медиафайлов: {e}")
            errors.append(f"Ошибка загрузки поста {post.id}: {e}")


        downloaded_by_post[post.id] = {
            'title': post.title,
            'downloaded': post_downloaded,
            'skipped': post_skipped,
            'total': post_downloaded + post_skipped
        }

        total_downloaded += post_downloaded
        total_skipped += post_skipped

        print(f"   📊 Пост завершен: {post_downloaded} скачано, {post_skipped} пропущено")

    return {
        'total_downloaded': total_downloaded,
        'total_skipped': total_skipped,
        'downloaded_by_post': downloaded_by_post,
        'errors': errors,
        'artist_dir': f"downloads/{artist.service}_{artist.name}_{artist.id}"
    }


def save_download_report(report: dict, artist: Artist):
    """Сохраняет отчет о скачивании в JSON файл"""
    report_file = Path(report['artist_dir']) / "download_report.json"

    report_data = {
        'artist': {
            'id': artist.id,
            'name': artist.name,
            'service': artist.service,
            'url': artist.url
        },
        'download_stats': {
            'total_downloaded': report['total_downloaded'],
            'total_skipped': report['total_skipped'],
            'total_posts_processed': len(report['downloaded_by_post'])
        },
        'posts': report['downloaded_by_post'],
        'errors': report['errors'],
        'download_date': time.strftime('%Y-%m-%d %H:%M:%S')
    }

    try:
        with open(report_file, 'w', encoding='utf-8') as f:
            json.dump(report_data, f, ensure_ascii=False, indent=2)
        print(f"\n📄 Отчет сохранен: {report_file}")
    except Exception as e:
        print(f"❌ Не удалось сохранить отчет: {e}")


def main():
    """Главная функция интерактивного загрузчика"""
    print("🎨 Kemono.cr Интерактивный Загрузчик Медиафайлов")
    print("=" * 60)
    print("Этот скрипт скачает ВСЕ медиафайлы из ВСЕХ постов указанного автора")
    print("Файлы будут организованы в папки: downloads/автор/пост/файлы")
    print()

    # Запрашиваем URL автора
    while True:
        url = input("🔗 Введите URL автора (например: https://kemono.cr/fanbox/user/3065392): ").strip()

        if not url:
            print("❌ URL не может быть пустым. Попробуйте снова.")
            continue

        # Валидируем URL
        artist = create_artist_from_url(url)
        if artist:
            break

    print(f"\n✅ URL распознан:")
    print(f"   Сервис: {artist.service}")
    print(f"   ID автора: {artist.id}")
    print(f"   Полный URL: {artist.url}")

    # Подтверждение
    confirm = input(f"\n🚀 Начать скачивание всех медиафайлов автора {artist.service}/{artist.id}? (y/n): ").lower()
    if confirm not in ['y', 'yes', 'да', 'д']:
        print("❌ Скачивание отменено.")
        return

    # Создаем парсер с Selenium (нужен для JS-тяжелых страниц)
    print("\n🔧 Инициализация парсера с Selenium...")
    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # Получаем все посты автора
        posts = get_all_artist_posts(parser, artist)

        if not posts:
            print("❌ Не найдено ни одного поста у этого автора.")
            return

        print(f"\n📊 Найдено {len(posts)} постов")

        # Подсчитываем медиафайлы (предварительная оценка)
        images, videos, files = count_media_files(posts)
        print(f"   🖼️  Изображений в превью: {images}")
        print(f"   🎬 Видео в превью: {videos}")
        print(f"   📁 Других файлов в превью: {files}")

        if images + videos + files == 0:
            print("   📝 Медиафайлы могут быть найдены на страницах постов")

        # Финальное подтверждение
        # Предлагаем ограничить количество постов для тестирования
        if len(posts) > 5:
            limit_input = input(f"\n📊 Найдено {len(posts)} постов. Сколько скачать для тестирования? (1-5, или 'all' для всех): ").strip()
            if limit_input.lower() != 'all':
                try:
                    limit = int(limit_input)
                    posts = posts[:limit]
                    print(f"📋 Ограничено до {len(posts)} постов для тестирования")
                except ValueError:
                    print("❌ Неверный ввод, скачиваем все посты")

        confirm = input(f"\n🚀 Скачать медиафайлы из {len(posts)} постов? (y/n): ").lower()
        if confirm not in ['y', 'yes', 'да', 'д']:
            print("❌ Скачивание отменено.")
            return

        # Начинаем скачивание
        print("\n⬇️  Начинаю скачивание...")
        start_time = time.time()

        report = download_all_media(parser, artist, posts)

        end_time = time.time()
        duration = end_time - start_time

        # Выводим итоговую статистику
        print("\n🎉 Скачивание завершено!")
        print(f"   ⏱️  Время выполнения: {duration:.1f} секунд")
        print(f"   📊 Скачано файлов: {report['total_downloaded']}")
        print(f"   ⏭️  Пропущено (уже существуют): {report['total_skipped']}")
        print(f"   📁 Папка с файлами: {report['artist_dir']}")

        if report['errors']:
            print(f"   ⚠️  Ошибок: {len(report['errors'])}")
            print("   Подробности в файле download_report.json")

        # Сохраняем отчет
        save_download_report(report, artist)

        print("\n📋 Для повторного запуска используйте:")
        print(f"   python {__file__}")

    except KeyboardInterrupt:
        print("\n\n❌ Скачивание прервано пользователем.")
    except Exception as e:
        print(f"\n❌ Критическая ошибка: {e}")
        import traceback
        traceback.print_exc()
    finally:
        parser.close()


if __name__ == "__main__":
    main()
