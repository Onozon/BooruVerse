#!/usr/bin/env python3
"""
Тест полного потока загрузки превью постов
"""

from pathlib import Path
import hashlib

def get_post_attr(post, attr_name, default=None):
    """Имитация метода get_post_attr из GUI"""
    if hasattr(post, attr_name):
        value = getattr(post, attr_name)
        return value if value is not None else default
    elif isinstance(post, dict):
        return post.get(attr_name, default)
    else:
        return default

def get_cached_preview_path(url, preview_type="post"):
    """Имитация метода get_cached_preview_path"""
    if not url or not isinstance(url, str) or not url.strip():
        return None

    # Вычисляем путь как в GUI
    filename = hashlib.md5(url.encode()).hexdigest() + ".png"

    # Директория cache
    cache_dir = Path("cache")
    if preview_type == "post":
        target_dir = cache_dir / "post_thumbnails"
    else:
        target_dir = cache_dir / "media_previews"

    cache_path = target_dir / filename

    if cache_path.exists() and cache_path.stat().st_size > 0:
        return str(cache_path)

    return None

def simulate_load_post_thumbnail_async(post, thumbnail_label):
    """Имитация функции load_post_thumbnail_async"""
    def load_thumbnail():
        try:
            post_id = get_post_attr(post, 'id', 'unknown')
            print(f"🔄 [ПРЕВЬЮ] Начинаем обработку превью для поста {post_id}")
            print(f"🔍 [ПРЕВЬЮ] thumbnail_label: {thumbnail_label}")

            # Проверяем, что thumbnail_label все еще существует
            if thumbnail_label is None or not hasattr(thumbnail_label, 'setPixmap'):
                print("❌ [ПРЕВЬЮ] thumbnail_label не существует или не имеет setPixmap")
                return

            print("✅ [ПРЕВЬЮ] thumbnail_label валиден, продолжаем...")
            post_thumbnail = get_post_attr(post, 'thumbnail')

            if post_thumbnail:
                print(f"🖼️ [ПРЕВЬЮ] Найден thumbnail, проверяем кэш: {post_thumbnail}")
                # Сначала проверяем кэш
                cached_path = get_cached_preview_path(post_thumbnail, preview_type="post")
                print(f"📁 [ПРЕВЬЮ] Кэш путь: {cached_path}")

                if cached_path:
                    print(f"✅ [ПРЕВЬЮ] Найдено в кэше: {cached_path}")
                    # Имитируем загрузку из кэша
                    print("✅ [ПРЕВЬЮ] Имитируем создание QPixmap из кэша")
                    print("📡 [ПРЕВЬЮ] Имитируем отправку сигнала обновления из кэша")
                else:
                    print("📥 [ПРЕВЬЮ] Не найдено в кэше, имитируем загрузку из интернета")
                    print("📁 [ПРЕВЬЮ] Имитируем успешную загрузку")
                    print("✅ [ПРЕВЬЮ] Имитируем создание QPixmap")
                    print("📡 [ПРЕВЬЮ] Имитируем отправку сигнала обновления")
            else:
                print(f"⚠️ [ПРЕВЬЮ] У поста {post_id} нет превью, проверяем attachments и files...")
                attachments = get_post_attr(post, 'attachments', [])
                files = get_post_attr(post, 'files', [])

                if attachments or files:
                    print(f"🔍 [ПРЕВЬЮ] Пост {post_id} имеет {len(attachments)} attachments и {len(files)} files")
                    print("📥 [ПРЕВЬЮ] Имитируем поиск превью в attachments/files")
                else:
                    print(f"❌ [ПРЕВЬЮ] Пост {post_id} не имеет превью, attachments или files")

        except Exception as e:
            print(f"❌ [ПРЕВЬЮ] Ошибка в load_thumbnail: {e}")

    # Имитируем запуск в потоке
    print("🧵 [ПРЕВЬЮ] Имитируем запуск в отдельном потоке")
    load_thumbnail()

class MockPost:
    def __init__(self):
        self.id = '10486318'
        self.title = '【全体公開／PSD】3939 HAPPY BIRTHDAY!!!'
        self.thumbnail = 'https://img.kemono.cr/thumbnail/data/55/0d/550dc4e4cac7fc3512cfa9414d21f8f1d4e26a0a8745e9380b89aba950557f9b.jpg'
        self.attachments = []
        self.files = []

class MockLabel:
    def __init__(self):
        self.pixmap_set = False

    def setPixmap(self, pixmap):
        self.pixmap_set = True
        print(f"✅ [LABEL] Pixmap установлен: {pixmap}")

    def __str__(self):
        return f"MockLabel(pixmap_set={self.pixmap_set})"

def test_preview_flow():
    """Тест полного потока превью"""

    print("🧪 ТЕСТ ПОЛНОГО ПОТОКА ПРЕВЬЮ")
    print("="*50)

    # Создаем mock пост и label
    post = MockPost()
    label = MockLabel()

    print(f"📋 Пост: {post.title}")
    print(f"🖼️ Thumbnail: {post.thumbnail}")
    print(f"🏷️ Label: {label}")

    # Имитируем вызов функции
    print("\n🚀 Запуск load_post_thumbnail_async...")
    simulate_load_post_thumbnail_async(post, label)

    print("\n✅ Имитация завершена")
    print(f"🏷️ Финальное состояние label: {label}")

if __name__ == "__main__":
    test_preview_flow()
