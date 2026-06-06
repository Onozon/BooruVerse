#!/usr/bin/env python3
"""
Графический интерфейс для Kemono.cr Parser
Создан на основе tkinter с адаптивной разметкой
"""

import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import threading
import queue
import json
import os
import re
from pathlib import Path
from PIL import Image, ImageTk
import requests
from io import BytesIO
import time
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
from bs4 import BeautifulSoup

# Импорт нашего парсера
from kemono_parser import KemonoParser
from interactive_downloader import create_artist_from_url


class KemonoGUI:
    def __init__(self):
        """Инициализация GUI"""
        self.root = tk.Tk()
        self.root.title("🎨 Kemono.cr Parser - Графический интерфейс")
        self.root.geometry("1400x900")
        self.root.minsize(800, 600)
        
        # Данные приложения
        self.parser = None
        self.current_artist = None
        self.all_posts = []
        self.current_page = 0
        self.posts_per_page = 50  # Постов на страницу
        self.selected_post = None
        self.current_media = []

        # Управление памятью tkinter объектов
        self.photo_images = []  # Храним ссылки на PhotoImage объекты
        self.post_frames = []   # Храним ссылки на фреймы постов

        # История URL запросов
        self.url_history = []  # Список предыдущих URL
        self.history_file = "url_history.json"  # Файл для сохранения истории
        self.max_history_items = 20  # Максимум 20 элементов в истории
        
        # Состояние скачивания
        self.download_queue = queue.Queue()
        self.download_threads = []
        self.download_status = {}
        self.is_downloading = False
        
        # Система кэширования превью
        self.cache_dir = Path("cache")
        self.cache_dir.mkdir(exist_ok=True)

        # Создаем подпапки для разных типов превью
        self.post_thumbnails_dir = self.cache_dir / "post_thumbnails"
        self.media_previews_dir = self.cache_dir / "media_previews"
        self.post_thumbnails_dir.mkdir(exist_ok=True)
        self.media_previews_dir.mkdir(exist_ok=True)

        # Очищаем поврежденные файлы из кэша при запуске
        self.cleanup_corrupted_cache()

        # Система повторных попыток для неудачных превью
        self.failed_previews = set()
        self.retry_thread = None
        self.retry_active = False

        # Кэши для оптимизации
        self.preview_cache = {}  # URL -> cache_path
        self.url_validation_cache = {}  # URL -> bool (валидный ли URL)

        # GUI элементы
        self.setup_styles()
        self.create_widgets()
        self.setup_layout()
        
        # Загрузка сохраненного состояния
        self.load_download_state()
        self.load_url_history()

    def get_cached_preview_path(self, url):
        """Получить путь к кэшированному превью"""
        if url in self.preview_cache:
            return self.preview_cache[url]
        return None

    def cleanup_corrupted_cache(self):
        """Очистка поврежденных файлов из кэша"""
        print("🧹 Очищаем поврежденные файлы из кэша...")
        cleaned_count = 0

        for cache_dir in [self.post_thumbnails_dir, self.media_previews_dir]:
            if not os.path.exists(cache_dir):
                continue

            for filename in os.listdir(cache_dir):
                filepath = os.path.join(cache_dir, filename)
                try:
                    # Проверяем что файл не пустой
                    if os.path.getsize(filepath) == 0:
                        os.remove(filepath)
                        cleaned_count += 1
                        continue

                    # Проверяем что файл - корректное изображение
                    with Image.open(filepath) as img:
                        img.verify()

                except (OSError, IOError, Image.UnidentifiedImageError, RecursionError):
                    try:
                        os.remove(filepath)
                        cleaned_count += 1
                    except:
                        pass

        if cleaned_count > 0:
            print(f"🗑️ Удалено {cleaned_count} поврежденных файлов из кэша")

    def cache_preview(self, url, image_data, preview_type="media"):
        """Сохранить превью в кэш"""
        try:
            # Выбираем подпапку в зависимости от типа
            if preview_type == "post":
                target_dir = self.post_thumbnails_dir
            else:  # media
                target_dir = self.media_previews_dir

            # Создаем имя файла из URL
            import hashlib
            filename = hashlib.md5(url.encode()).hexdigest() + ".png"
            cache_path = target_dir / filename

            # Сохраняем изображение
            image_data.save(cache_path, "PNG")

            # Добавляем в кэш
            self.preview_cache[url] = str(cache_path)
            return str(cache_path)
        except Exception as e:
            print(f"Ошибка кэширования превью: {e}")
            return None

    def download_and_cache_preview(self, url, size=(100, 80), preview_type="media", max_retries=3):
        """Скачать и закешировать превью с повторными попытками"""
        from PIL import Image
        import requests
        from io import BytesIO
        import time

        # Проверяем кэш
        cached_path = self.get_cached_preview_path(url)
        if cached_path and Path(cached_path).exists():
            return cached_path

        # Повторные попытки скачивания
        for attempt in range(max_retries):
            try:
                # Скачиваем изображение
                response = requests.get(url, timeout=15, stream=True)
                if response.status_code != 200:
                    if attempt < max_retries - 1:  # Не последняя попытка
                        time.sleep(2 ** attempt)  # Экспоненциальная задержка
                        continue
                    return None

                # Читаем данные (ограничиваем для превью)
                image_data = BytesIO()
                downloaded = 0
                max_size = 500000 if preview_type == "post" else 200000

                for chunk in response.iter_content(chunk_size=8192):
                    if downloaded > max_size:
                        break
                    image_data.write(chunk)
                    downloaded += len(chunk)

                image_data.seek(0)

                # Проверяем и открываем изображение с обработкой ошибок
                try:
                    pil_image = Image.open(image_data)
                    # Проверяем что изображение корректное
                    pil_image.verify()
                    image_data.seek(0)  # Возвращаемся к началу после проверки
                    pil_image = Image.open(image_data)  # Открываем заново

                except (OSError, IOError, Image.UnidentifiedImageError, RecursionError) as img_error:
                    print(f"❌ Поврежденное изображение {url}: {img_error}")
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)
                        continue
                    return None

                # Изменяем размер
                pil_image.thumbnail(size, Image.Resampling.LANCZOS)

                # Кэшируем
                return self.cache_preview(url, pil_image, preview_type)

            except Exception as e:
                if attempt < max_retries - 1:  # Не последняя попытка
                    print(f"Попытка {attempt + 1} неудачна для {url}: {e}. Повтор через {2 ** attempt} сек...")
                    time.sleep(2 ** attempt)  # Экспоненциальная задержка
                else:
                    print(f"Все попытки исчерпаны для {url}: {e}")
                    return None

        return None

    def add_failed_preview(self, url, preview_type="media"):
        """Добавить URL в очередь повторных попыток"""
        self.failed_previews.add((url, preview_type))
        self.start_retry_process()

    def start_retry_process(self):
        """Запустить фоновый процесс повторных попыток"""
        if self.retry_active or not self.failed_previews:
            return

        self.retry_active = True

        def retry_worker():
            import time
            while self.failed_previews and self.retry_active:
                # Берем один URL для повторной попытки
                if not self.failed_previews:
                    break

                url, preview_type = self.failed_previews.pop()
                size = (150, 110) if preview_type == "post" else (100, 80)

                try:
                    cached_path = self.download_and_cache_preview(url, size=size, preview_type=preview_type, max_retries=2)
                    if cached_path:
                        print(f"✅ Успешно загружено превью после повторной попытки: {url}")

                        # Определяем тип обновления и вызываем соответствующий метод
                        if preview_type == "post":
                            # Найдем пост по URL превью
                            for post in self.all_posts:
                                if hasattr(post, 'thumbnail') and post.thumbnail == url:
                                    self.root.after(0, lambda: self.update_post_thumbnail(post, cached_path))
                                    break
                        else:
                            # Найдем медиафайл по URL превью
                            for media in self.current_media:
                                if media.get('thumbnail_url') == url:
                                    self.root.after(0, lambda: self.update_media_preview(media, cached_path))
                                    break
                    else:
                        # Если снова неудача, вернем в очередь для следующих попыток
                        self.failed_previews.add((url, preview_type))

                except Exception as e:
                    print(f"Повторная попытка неудачна для {url}: {e}")
                    self.failed_previews.add((url, preview_type))

                # Небольшая задержка между попытками
                time.sleep(5)

            self.retry_active = False
            print("Фоновый процесс повторных попыток завершен")

        # Запускаем в отдельном потоке
        import threading
        self.retry_thread = threading.Thread(target=retry_worker, daemon=True)
        self.retry_thread.start()

    def download_post_thumbnails(self, posts):
        """Скачать превью всех постов в фоновом режиме"""
        if not posts:
            return

        def download_thumbnails():
            """Фоновая загрузка превью постов"""
            try:
                for post in posts:
                    if hasattr(post, 'thumbnail') and post.thumbnail:
                        # Скачиваем превью поста
                        cached_path = self.download_and_cache_preview(
                            post.thumbnail,
                            size=(150, 110),
                            preview_type="post"
                        )
                        if not cached_path:
                            # Добавляем в очередь повторных попыток
                            self.add_failed_preview(post.thumbnail, "post")

                        # Небольшая задержка чтобы не перегружать сервер
                        import time
                        time.sleep(0.1)
                    else:
                        # Если превью нет, попробуем получить его из первого изображения поста
                        try:
                            # Открываем страницу поста для получения превью
                            post_url = f"https://kemono.cr/{post.service}/post/{post.id}"
                            parser = KemonoParser(use_selenium=True, headless=True)
                            html = parser._selenium_get(post_url)

                            if html:
                                from bs4 import BeautifulSoup
                                soup = BeautifulSoup(html, 'lxml')
                                img_tags = soup.find_all('img')

                                for img in img_tags[:3]:  # Проверяем первые 3 изображения
                                    src = img.get('src')
                                    if src and not src.startswith('data:') and 'static' not in src.lower():
                                        full_url = f"https://kemono.cr{src}" if src.startswith('/') else src
                                        # Скачиваем как превью поста
                                        cached_path = self.download_and_cache_preview(
                                            full_url,
                                            size=(150, 110),
                                            preview_type="post"
                                        )
                                        if not cached_path:
                                            # Добавляем в очередь повторных попыток
                                            self.add_failed_preview(full_url, "post")
                                        break

                            parser.close()
                            import time
                            time.sleep(0.2)  # Задержка между запросами

                        except Exception as e:
                            print(f"Ошибка получения превью для поста {post.id}: {e}")
            except Exception as e:
                print(f"Ошибка загрузки превью постов: {e}")

        # Запускаем в отдельном потоке
        import threading
        thread = threading.Thread(target=download_thumbnails, daemon=True)
        thread.start()

    def download_media_previews(self, media_urls):
        """Скачать превью всех медиафайлов поста"""
        if not media_urls:
            return

        def download_previews():
            """Фоновая загрузка превью медиа"""
            try:
                for media_url in media_urls:
                    # Скачиваем превью медиафайла
                    cached_path = self.download_and_cache_preview(
                        media_url,
                        size=(100, 80),
                        preview_type="media"
                    )
                    if not cached_path:
                        # Добавляем в очередь повторных попыток
                        self.add_failed_preview(media_url, "media")

                    # Небольшая задержка
                    import time
                    time.sleep(0.05)
            except Exception as e:
                print(f"Ошибка загрузки превью медиа: {e}")

        # Запускаем в отдельном потоке
        import threading
        thread = threading.Thread(target=download_previews, daemon=True)
        thread.start()

    def update_post_thumbnail(self, post, cached_path):
        """Обновить превью поста в GUI"""
        def update_gui():
            try:
                # Найдем виджет поста и обновим его превью
                for widget in self.posts_scrollable_frame.winfo_children():
                    # Ищем виджет, который содержит информацию о посте
                    if hasattr(widget, 'post_id') and widget.post_id == post.id:
                        # Ищем thumbnail_frame
                        for child in widget.winfo_children():
                            if isinstance(child, tk.Frame) and hasattr(child, '_is_thumbnail_frame'):
                                # Очищаем фрейм от старого содержимого
                                for grandchild in child.winfo_children():
                                    grandchild.destroy()

                                # Создаем новое изображение
                                from PIL import Image, ImageTk
                                try:
                                    # Проверяем что файл существует и не пустой
                                    if not os.path.exists(cached_path) or os.path.getsize(cached_path) == 0:
                                        print(f"❌ Файл превью не найден или пустой: {cached_path}")
                                        return

                                    pil_image = Image.open(cached_path)

                                    # Проверяем что изображение корректное
                                    pil_image.verify()
                                    pil_image.close()

                                    # Открываем заново после проверки
                                    pil_image = Image.open(cached_path)

                                except (OSError, IOError, Image.UnidentifiedImageError) as e:
                                    print(f"❌ Поврежденное изображение превью {cached_path}: {e}")
                                    # Удаляем поврежденный файл из кэша
                                    try:
                                        os.remove(cached_path)
                                    except:
                                        pass
                                    return
                                except RecursionError as e:
                                    print(f"❌ Recursion error при открытии превью {cached_path}: {e}")
                                    # Удаляем поврежденный файл из кэша
                                    try:
                                        os.remove(cached_path)
                                    except:
                                        pass
                                    return

                                # Убеждаемся, что изображение правильного размера
                                pil_image.thumbnail((150, 110), Image.Resampling.LANCZOS)

                                # Создаем PhotoImage
                                photo = ImageTk.PhotoImage(pil_image)

                                # Создаем label с изображением
                                thumbnail_label = tk.Label(child, image=photo, bg='white')

                                # КРИТИЧНО: сохраняем ссылку на изображение в нескольких местах
                                thumbnail_label.image = photo
                                child._photo_image = photo  # Сохраняем в родительском виджете
                                thumbnail_label._photo_ref = photo  # Дополнительная ссылка

                                # ДОПОЛНИТЕЛЬНО: сохраняем в глобальном списке для предотвращения garbage collection
                                self.photo_images.append(photo)

                                # Устанавливаем изображение и упаковываем
                                thumbnail_label.configure(image=photo)
                                thumbnail_label.pack(expand=True, fill=tk.BOTH)

                                # Принудительно обновляем виджет
                                child.update_idletasks()
                                widget.update_idletasks()
                                self.posts_scrollable_frame.update_idletasks()

                                print(f"✅ Обновлено превью для поста {post.id}")
                                break
            except Exception as e:
                print(f"❌ Ошибка обновления превью поста {post.id}: {e}")
                import traceback
                traceback.print_exc()

        # Запускаем обновление в главном потоке
        self.root.after(0, update_gui)

    def update_media_preview(self, media, cached_path):
        """Обновить превью медиафайла в GUI"""
        def update_gui():
            try:
                # Найдем виджет медиафайла и обновим его превью
                for widget in self.media_scrollable_frame.winfo_children():
                    # Ищем виджет, который содержит информацию о медиафайле
                    if hasattr(widget, 'media_url') and widget.media_url == media['url']:
                        # Ищем preview_frame
                        for child in widget.winfo_children():
                            if isinstance(child, tk.Frame) and hasattr(child, '_is_preview_frame'):
                                # Очищаем фрейм от старого содержимого
                                for grandchild in child.winfo_children():
                                    grandchild.destroy()

                                # Создаем новое изображение
                                from PIL import Image, ImageTk
                                try:
                                    # Проверяем что файл существует и не пустой
                                    if not os.path.exists(cached_path) or os.path.getsize(cached_path) == 0:
                                        print(f"❌ Файл превью медиа не найден или пустой: {cached_path}")
                                        return

                                    pil_image = Image.open(cached_path)

                                    # Проверяем что изображение корректное
                                    pil_image.verify()
                                    pil_image.close()

                                    # Открываем заново после проверки
                                    pil_image = Image.open(cached_path)

                                except (OSError, IOError, Image.UnidentifiedImageError) as e:
                                    print(f"❌ Поврежденное изображение превью медиа {cached_path}: {e}")
                                    # Удаляем поврежденный файл из кэша
                                    try:
                                        os.remove(cached_path)
                                    except:
                                        pass
                                    return
                                except RecursionError as e:
                                    print(f"❌ Recursion error при открытии превью медиа {cached_path}: {e}")
                                    # Удаляем поврежденный файл из кэша
                                    try:
                                        os.remove(cached_path)
                                    except:
                                        pass
                                    return

                                # Убеждаемся, что изображение правильного размера
                                pil_image.thumbnail((110, 90), Image.Resampling.LANCZOS)

                                # Создаем PhotoImage
                                photo = ImageTk.PhotoImage(pil_image)

                                # Создаем label с изображением
                                image_label = tk.Label(child, image=photo, bg='white')

                                # КРИТИЧНО: сохраняем ссылку на изображение в нескольких местах
                                image_label.image = photo
                                child._photo_image = photo  # Сохраняем в родительском виджете
                                image_label._photo_ref = photo  # Дополнительная ссылка

                                # ДОПОЛНИТЕЛЬНО: сохраняем в глобальном списке для предотвращения garbage collection
                                self.photo_images.append(photo)

                                # Устанавливаем изображение и упаковываем
                                image_label.configure(image=photo)
                                image_label.pack(expand=True, fill=tk.BOTH)

                                # Принудительно обновляем виджет
                                child.update_idletasks()
                                widget.update_idletasks()
                                self.media_scrollable_frame.update_idletasks()

                                print(f"✅ Обновлено превью медиа {media['filename']}")
                                break
            except Exception as e:
                print(f"❌ Ошибка обновления превью медиа {media.get('filename', 'unknown')}: {e}")
                import traceback
                traceback.print_exc()

        # Запускаем обновление в главном потоке
        self.root.after(0, update_gui)

    def setup_styles(self):
        """Настройка стилей интерфейса"""
        self.style = ttk.Style()
        
        # Настройка цветовой схемы
        self.colors = {
            'bg': '#f0f0f0',
            'fg': '#333333',
            'accent': '#4CAF50',
            'error': '#f44336',
            'warning': '#ff9800',
            'info': '#2196F3'
        }
        
        self.root.configure(bg=self.colors['bg'])
    
    def create_widgets(self):
        """Создание всех виджетов интерфейса"""
        
        # Главная рамка
        self.main_frame = ttk.Frame(self.root)
        self.main_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        # === ВЕРХНЯЯ ПАНЕЛЬ ===
        self.create_top_panel()
        
        # === ОСНОВНАЯ ОБЛАСТЬ ===
        self.create_main_area()
        
        # === НИЖНЯЯ ПАНЕЛЬ ===
        self.create_bottom_panel()
    
    def create_top_panel(self):
        """Создание верхней панели с полем URL и кнопками"""
        self.top_frame = ttk.Frame(self.main_frame)
        self.top_frame.pack(fill=tk.X, pady=(0, 10))
        
        # Поле ввода URL
        ttk.Label(self.top_frame, text="URL автора:").pack(side=tk.LEFT, padx=(0, 5))

        self.url_var = tk.StringVar()
        self.url_entry = ttk.Entry(
            self.top_frame,
            textvariable=self.url_var,
            width=50,
            font=('Arial', 10)
        )
        self.url_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 5))

        # Подсказка для URL (только при пустом поле)
        self.url_placeholder_active = True
        self.url_entry.insert(0, "https://kemono.cr/fanbox/user/3065392")
        self.url_entry.configure(foreground='gray')

        # Обработчики событий
        self.url_entry.bind('<FocusIn>', self.on_url_focus_in)
        self.url_entry.bind('<FocusOut>', self.on_url_focus_out)
        self.url_entry.bind('<KeyRelease>', self.on_url_change)

        # Кнопка истории URL
        self.history_btn = tk.Button(
            self.top_frame,
            text="📋",
            font=('Arial', 10),
            bg='#2196F3',
            fg='white',
            activebackground='#1976D2',
            activeforeground='white',
            relief=tk.RAISED,
            bd=2,
            padx=8,
            pady=4,
            cursor='hand2',
            command=self.show_history_menu
        )
        self.history_btn.pack(side=tk.LEFT, padx=(0, 10))
        self.history_btn.bind('<Button-1>', lambda e: self.show_history_menu())
        
        # Кнопка "Открыть" с улучшенной кликабельностью
        self.open_btn = ttk.Button(
            self.top_frame,
            text="Открыть",
            command=self.load_artist_posts
        )
        self.open_btn.pack(side=tk.LEFT, padx=(0, 10), ipady=8, ipadx=10)
        self.open_btn.bind('<Button-1>', lambda e: self.load_artist_posts())

        # Кнопка логов ошибок с улучшенной кликабельностью
        self.error_btn = ttk.Button(
            self.top_frame,
            text="⚠️ Ошибки",
            command=self.show_error_logs
        )
        self.error_btn.pack(side=tk.LEFT, padx=(0, 5), ipady=5, ipadx=5)
        self.error_btn.bind('<Button-1>', lambda e: self.show_error_logs())

        # Кнопка статуса загрузок с улучшенной кликабельностью
        self.status_btn = ttk.Button(
            self.top_frame,
            text="📊 Статус",
            command=self.show_download_status
        )
        self.status_btn.pack(side=tk.LEFT, padx=(0, 10), ipady=5, ipadx=5)
        self.status_btn.bind('<Button-1>', lambda e: self.show_download_status())
        
        # Мини прогресс-бар
        self.mini_progress = ttk.Progressbar(
            self.top_frame,
            length=100,
            mode='determinate'
        )
        self.mini_progress.pack(side=tk.LEFT, padx=(10, 0))

        # Статусное сообщение
        self.status_label = tk.Label(
            self.top_frame,
            text="Готов к работе",
            font=('Arial', 9),
            fg='#666666',
            anchor='w'
        )
        self.status_label.pack(side=tk.LEFT, padx=(10, 0))

    def update_status(self, message):
        """Обновление статусного сообщения"""
        self.root.after(0, lambda: self.status_label.configure(text=message))
    
    def create_main_area(self):
        """Создание основной области с панелями постов и медиафайлов"""
        self.paned_window = ttk.PanedWindow(self.main_frame, orient=tk.HORIZONTAL)
        self.paned_window.pack(fill=tk.BOTH, expand=True, pady=(0, 10))
        
        # === ЛЕВАЯ ПАНЕЛЬ - ПОСТЫ ===
        self.create_posts_panel()
        
        # === ПРАВАЯ ПАНЕЛЬ - МЕДИАФАЙЛЫ ===
        self.create_media_panel()
        
        # Добавляем панели в PanedWindow
        self.paned_window.add(self.posts_frame, weight=2)
        self.paned_window.add(self.media_frame, weight=3)
    
    def create_posts_panel(self):
        """Создание левой панели с постами"""
        self.posts_frame = ttk.LabelFrame(self.paned_window, text="📄 Посты", padding=10)

        # Пагинация
        self.pagination_frame = ttk.Frame(self.posts_frame)
        self.pagination_frame.pack(fill=tk.X, pady=(0, 10))

        self.prev_btn = ttk.Button(
            self.pagination_frame,
            text="◁ Назад",
            command=self.prev_page,
            state=tk.DISABLED
        )
        self.prev_btn.pack(side=tk.LEFT, padx=(0, 5), ipady=5, ipadx=8)
        self.prev_btn.bind('<Button-1>', lambda e: self.prev_page())

        self.page_label = ttk.Label(
            self.pagination_frame,
            text="1/1",
            font=('Arial', 10, 'bold')
        )
        self.page_label.pack(side=tk.LEFT, padx=15)

        self.next_btn = ttk.Button(
            self.pagination_frame,
            text="Вперед ▷",
            command=self.next_page,
            state=tk.DISABLED
        )
        self.next_btn.pack(side=tk.LEFT, ipady=5, ipadx=8)
        self.next_btn.bind('<Button-1>', lambda e: self.next_page())

        # Область прокрутки для постов
        self.posts_canvas = tk.Canvas(self.posts_frame, bg='white')
        self.posts_scrollbar = ttk.Scrollbar(
            self.posts_frame,
            orient="vertical",
            command=self.posts_canvas.yview
        )
        self.posts_scrollable_frame = ttk.Frame(self.posts_canvas)
        
        self.posts_scrollable_frame.bind(
            "<Configure>",
            lambda e: self.posts_canvas.configure(scrollregion=self.posts_canvas.bbox("all"))
        )
        
        self.posts_canvas.create_window((0, 0), window=self.posts_scrollable_frame, anchor="nw")
        self.posts_canvas.configure(yscrollcommand=self.posts_scrollbar.set)
        
        self.posts_canvas.pack(side="left", fill="both", expand=True)
        self.posts_scrollbar.pack(side="right", fill="y")
        
        # Связываем колесо мыши с прокруткой
        self.posts_canvas.bind("<MouseWheel>", self._on_mousewheel_posts)
    
    def create_media_panel(self):
        """Создание правой панели с медиафайлами"""
        self.media_frame = ttk.LabelFrame(self.paned_window, text="🖼️ Просмотр поста", padding=10)
        
        # Область прокрутки для медиафайлов
        self.media_canvas = tk.Canvas(self.media_frame, bg='white')
        self.media_scrollbar = ttk.Scrollbar(
            self.media_frame,
            orient="vertical",
            command=self.media_canvas.yview
        )
        self.media_scrollable_frame = ttk.Frame(self.media_canvas)
        
        self.media_scrollable_frame.bind(
            "<Configure>",
            lambda e: self.media_canvas.configure(scrollregion=self.media_canvas.bbox("all"))
        )
        
        self.media_canvas.create_window((0, 0), window=self.media_scrollable_frame, anchor="nw")
        self.media_canvas.configure(yscrollcommand=self.media_scrollbar.set)
        
        self.media_canvas.pack(side="left", fill="both", expand=True)
        self.media_scrollbar.pack(side="right", fill="y")
        
        # Связываем колесо мыши с прокруткой
        self.media_canvas.bind("<MouseWheel>", self._on_mousewheel_media)
    
    def create_bottom_panel(self):
        """Создание нижней панели с кнопками скачивания"""
        self.bottom_frame = ttk.Frame(self.main_frame)
        self.bottom_frame.pack(fill=tk.X)
        
        # Кнопки для постов (слева)
        self.posts_buttons_frame = ttk.Frame(self.bottom_frame)
        self.posts_buttons_frame.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        self.download_selected_posts_btn = ttk.Button(
            self.posts_buttons_frame,
            text="Скачать выбранные посты",
            command=self.download_selected_posts,
            state=tk.DISABLED
        )
        self.download_selected_posts_btn.pack(side=tk.LEFT, padx=(0, 10), ipady=8, ipadx=15)
        self.download_selected_posts_btn.bind('<Button-1>', lambda e: self.download_selected_posts())
        
        # Кнопки для медиафайлов (справа)
        self.media_buttons_frame = ttk.Frame(self.bottom_frame)
        self.media_buttons_frame.pack(side=tk.RIGHT)
        
        self.download_selected_media_btn = ttk.Button(
            self.media_buttons_frame,
            text="Скачать выбранные медиа",
            command=self.download_selected_media,
            state=tk.DISABLED
        )
        self.download_selected_media_btn.pack(side=tk.LEFT, padx=(0, 5), ipady=6, ipadx=10)
        self.download_selected_media_btn.bind('<Button-1>', lambda e: self.download_selected_media())

        self.download_all_media_btn = ttk.Button(
            self.media_buttons_frame,
            text="Скачать все медиа из поста",
            command=self.download_all_post_media,
            state=tk.DISABLED
        )
        self.download_all_media_btn.pack(side=tk.LEFT, padx=(0, 5), ipady=6, ipadx=10)
        self.download_all_media_btn.bind('<Button-1>', lambda e: self.download_all_post_media())

        self.download_page_posts_btn = ttk.Button(
            self.media_buttons_frame,
            text="Скачать все посты страницы",
            command=self.download_page_posts,
            state=tk.DISABLED
        )
        self.download_page_posts_btn.pack(side=tk.LEFT, padx=(0, 5), ipady=6, ipadx=10)
        self.download_page_posts_btn.bind('<Button-1>', lambda e: self.download_page_posts())

        self.download_all_posts_btn = ttk.Button(
            self.media_buttons_frame,
            text="Скачать все посты пользователя",
            command=self.download_all_posts,
            state=tk.DISABLED
        )
        self.download_all_posts_btn.pack(side=tk.LEFT, ipady=6, ipadx=10)
        self.download_all_posts_btn.bind('<Button-1>', lambda e: self.download_all_posts())
    
    def setup_layout(self):
        """Настройка адаптивной разметки"""
        # Конфигурация весов для адаптивности
        self.root.grid_rowconfigure(0, weight=1)
        self.root.grid_columnconfigure(0, weight=1)
        
        # Обработчик изменения размера окна
        self.root.bind('<Configure>', self.on_window_resize)
    
    def on_window_resize(self, event):
        """Обработчик изменения размера окна"""
        if event.widget == self.root:
            # Пересчитываем количество колонок для постов
            self.update_posts_layout()
    
    def _on_mousewheel_posts(self, event):
        """Обработчик прокрутки колесом мыши для постов"""
        self.posts_canvas.yview_scroll(int(-1*(event.delta/120)), "units")
    
    def _on_mousewheel_media(self, event):
        """Обработчик прокрутки колесом мыши для медиафайлов"""
        self.media_canvas.yview_scroll(int(-1*(event.delta/120)), "units")
    
    # === МЕТОДЫ РАБОТЫ С ПОСТАМИ ===
    
    def on_url_focus_in(self, event):
        """Обработчик получения фокуса полем URL"""
        if self.url_placeholder_active:
            self.url_entry.delete(0, tk.END)
            self.url_entry.configure(foreground='black')
            self.url_placeholder_active = False
    
    def on_url_focus_out(self, event):
        """Обработчик потери фокуса полем URL"""
        if not self.url_var.get().strip():
            self.url_entry.insert(0, "https://kemono.cr/fanbox/user/3065392")
            self.url_entry.configure(foreground='gray')
            self.url_placeholder_active = True
    
    def on_url_change(self, event):
        """Обработчик изменения URL"""
        if not self.url_placeholder_active:
            # Проверяем валидность URL
            url = self.url_var.get().strip()
            if 'kemono.cr' in url:
                self.url_entry.configure(foreground='black')
            else:
                self.url_entry.configure(foreground='red')

    
    def load_artist_posts(self):
        """Загрузка постов автора"""
        # Получаем URL, учитывая состояние подсказки
        url = "" if self.url_placeholder_active else self.url_var.get().strip()
        
        if not url or not 'kemono.cr' in url:
            messagebox.showerror("Ошибка", "Введите корректный URL автора с kemono.cr")
            return
        
        # Показываем индикатор загрузки
        self.open_btn.configure(state=tk.DISABLED, text="Загрузка...")
        self.mini_progress.configure(mode='indeterminate')
        self.mini_progress.start()
        
        # Запускаем загрузку в отдельном потоке
        thread = threading.Thread(target=self._load_posts_thread, args=(url,))
        thread.daemon = True
        thread.start()
    
    def _load_posts_thread(self, url):
        """Поток загрузки постов"""
        try:
            self.update_status("Поиск постов...")

            # Создаем парсер если его нет
            if not self.parser:
                self.parser = KemonoParser(use_selenium=True, headless=True)

            # Создаем объект автора
            self.current_artist = create_artist_from_url(url)
            if not self.current_artist:
                raise ValueError("Не удалось определить автора по URL")

            # Получаем все посты со всех страниц автора
            self.all_posts = self.parser.get_all_artist_posts(self.current_artist)
            
            # Обновляем GUI в главном потоке
            self.root.after(0, self._on_posts_loaded)
            
        except Exception as e:
            error_msg = str(e)
            self.root.after(0, lambda: self._on_posts_error(error_msg))
    
    def _on_posts_loaded(self):
        """Обработчик успешной загрузки постов"""
        self.mini_progress.stop()
        self.mini_progress.configure(mode='determinate', value=0)
        self.open_btn.configure(state=tk.NORMAL, text="Открыть")

        if not self.all_posts:
            self.update_status("Готов к работе")
            messagebox.showwarning("Предупреждение", "У этого автора не найдено постов")
            return

        # Обновляем статус
        self.update_status(f"Поиск постов ({len(self.all_posts)} найдено)")

        # Сохраняем URL в историю
        if hasattr(self, 'current_artist') and self.current_artist and self.current_artist.url:
            self.add_url_to_history(self.current_artist.url)

        # Сбрасываем на первую страницу
        self.current_page = 0

        # Обновляем отображение постов
        self.update_posts_display()

        # Активируем кнопки
        self.update_buttons_state()

        total_pages = (len(self.all_posts) + self.posts_per_page - 1) // self.posts_per_page
        print(f"📊 Загружено {len(self.all_posts)} постов ({total_pages} страниц по {self.posts_per_page} постов)")
        messagebox.showinfo("Успех", f"Загружено {len(self.all_posts)} постов ({total_pages} страниц). Превью загружаются по мере готовности...")
    
    def _on_posts_error(self, error_msg):
        """Обработчик ошибки загрузки постов"""
        self.mini_progress.stop()
        self.mini_progress.configure(mode='determinate', value=0)
        self.open_btn.configure(state=tk.NORMAL, text="Открыть")
        
        messagebox.showerror("Ошибка", f"Не удалось загрузить посты:\n{error_msg}")
    
    def update_posts_display(self):
        """Обновление отображения постов с пагинацией"""
        # Очищаем текущие виджеты и освобождаем память
        for widget in self.posts_scrollable_frame.winfo_children():
            widget.destroy()

        # Очищаем ссылки на старые объекты для освобождения памяти
        self.photo_images.clear()
        self.post_frames.clear()

        if not self.all_posts:
            return

        # Вычисляем диапазон постов для текущей страницы
        start_idx = self.current_page * self.posts_per_page
        end_idx = min(start_idx + self.posts_per_page, len(self.all_posts))
        current_posts = self.all_posts[start_idx:end_idx]

        # Вычисляем количество колонок (адаптивно, без ограничений)
        window_width = self.posts_canvas.winfo_width()
        if window_width <= 1:  # Окно еще не отрисовано
            window_width = 800  # Умолчание для широкого экрана

        post_width = 170  # Минимальная ширина одного поста
        cols = max(1, window_width // post_width)

        # Максимум колонок - не более чем постов на странице
        cols = min(cols, len(current_posts))

        print(f"📏 Окно шириной {window_width}px, карточка {post_width}px, колонок: {cols}")

        print(f"📋 Страница {self.current_page + 1}: показываем посты {start_idx + 1}-{end_idx} из {len(self.all_posts)} в {cols} колонках")

        # Создаем сетку для постов текущей страницы
        for i, post in enumerate(current_posts):
            row = i // cols
            col = i % cols

            self.create_post_widget(post, row, col)

        # Обновляем пагинацию
        total_pages = (len(self.all_posts) + self.posts_per_page - 1) // self.posts_per_page
        self.page_label.configure(text=f"{self.current_page + 1}/{total_pages}")

        self.prev_btn.configure(state=tk.NORMAL if self.current_page > 0 else tk.DISABLED)
        self.next_btn.configure(state=tk.NORMAL if self.current_page < total_pages - 1 else tk.DISABLED)
    
    def create_post_widget(self, post, row, col):
        """Создание виджета для одного поста"""
        # Выделяем текущий открытый пост и меняем дизайн карточек
        if hasattr(self, 'selected_post') and self.selected_post and self.selected_post.id == post.id:
            post_frame = tk.Frame(self.posts_scrollable_frame, bg='#E3F2FD', relief=tk.GROOVE, borderwidth=3)
            bg_color = '#E3F2FD'
        else:
            post_frame = tk.Frame(self.posts_scrollable_frame, bg='white', relief=tk.GROOVE, borderwidth=2)
            bg_color = 'white'

        post_frame.grid(row=row, column=col, padx=5, pady=5, sticky="nsew")
        
        # Чекбокс с увеличенной областью клика
        post_var = tk.BooleanVar()
        checkbox_frame = tk.Frame(post_frame, width=40, height=40, bg=bg_color)
        checkbox_frame.pack(anchor='nw', padx=8, pady=8)
        checkbox_frame.pack_propagate(False)

        checkbox = ttk.Checkbutton(
            checkbox_frame,
            variable=post_var,
            command=self.on_post_selection_changed
        )
        checkbox.pack(expand=True, fill=tk.BOTH)

        # Делаем весь фрейм кликабельным
        def toggle_checkbox(event):
            current_value = post_var.get()
            post_var.set(not current_value)
            self.on_post_selection_changed()

        # Привязываем клик ко всем элементам карточки
        def on_click_anywhere(event):
            # Определяем что делать в зависимости от того, куда кликнули
            clicked_widget = event.widget

            # Если кликнули на чекбокс или его дочерние элементы - переключаем чекбокс
            if clicked_widget == checkbox_frame or (hasattr(clicked_widget, 'winfo_parent') and str(clicked_widget.winfo_parent()) == str(checkbox_frame)):
                toggle_checkbox(event)
            else:
                # Иначе - открываем пост
                self.select_post(post)

        # Сохраняем переменную чекбокса
        if not hasattr(self, 'post_vars'):
            self.post_vars = {}
        self.post_vars[post.id] = post_var

        # Добавляем атрибут для идентификации поста
        post_frame.post_id = post.id

        # Миниатюра поста с увеличенным размером
        thumbnail_frame = tk.Frame(post_frame, width=160, height=120, bg=bg_color, relief=tk.FLAT)
        thumbnail_frame.pack(pady=8)
        thumbnail_frame.pack_propagate(False)

        # Добавляем идентификатор для thumbnail_frame
        thumbnail_frame._is_thumbnail_frame = True

        # Пытаемся загрузить превью поста
        if hasattr(post, 'thumbnail') and post.thumbnail:
            try:
                cached_path = self.get_cached_preview_path(post.thumbnail)
                if cached_path and Path(cached_path).exists():
                    # Превью уже скачано, показываем его
                    from PIL import Image, ImageTk
                    pil_image = Image.open(cached_path)
                    pil_image.thumbnail((150, 110), Image.Resampling.LANCZOS)
                    photo = ImageTk.PhotoImage(pil_image)
                    thumbnail_label = tk.Label(thumbnail_frame, image=photo, bg='white')

                    # КРИТИЧНО: сохраняем ссылку на изображение в нескольких местах
                    thumbnail_label.image = photo
                    thumbnail_frame._photo_image = photo  # Сохраняем в родительском виджете

                    thumbnail_label.pack(expand=True, fill=tk.BOTH)
                    print(f"✅ Показано существующее превью для поста {post.id}")
                else:
                    # Превью еще не скачано, показываем иконку и запускаем асинхронную загрузку
                    icon_label = tk.Label(thumbnail_frame, text="🖼️", font=('Arial', 48), bg='white')
                    icon_label.pack(expand=True)

                    # Запускаем асинхронную загрузку превью для этого поста
                    def load_thumbnail_async():
                        try:
                            cached_path = self.download_and_cache_preview(post.thumbnail, size=(150, 110), preview_type="post")
                            if cached_path:
                                # Обновляем превью в GUI в главном потоке
                                self.root.after(0, lambda: self.update_post_thumbnail(post, cached_path))
                            else:
                                # Добавляем в очередь повторных попыток
                                self.add_failed_preview(post.thumbnail, "post")
                        except Exception as e:
                            print(f"Ошибка загрузки превью для поста {post.id}: {e}")
                            self.add_failed_preview(post.thumbnail, "post")

                    # Запускаем в отдельном потоке
                    import threading
                    thread = threading.Thread(target=load_thumbnail_async, daemon=True)
                    thread.start()

            except Exception as e:
                # Если ошибка, показываем иконку
                print(f"Ошибка отображения превью для поста {post.id}: {e}")
                icon_label = tk.Label(thumbnail_frame, text="🖼️", font=('Arial', 48), bg=bg_color)
                icon_label.pack(expand=True)
        else:
            # Если нет превью, показываем иконку
            icon_label = tk.Label(thumbnail_frame, text="🖼️", font=('Arial', 48), bg=bg_color)
            icon_label.pack(expand=True)

        # Название поста
        title_label = tk.Label(
            post_frame,
            text=post.title[:30] + ("..." if len(post.title) > 30 else ""),
            wraplength=150,
            bg=bg_color
        )
        title_label.pack()

        # Информация о посте
        media_count = len(post.attachments) + len(post.files)
        info_text = f"{media_count} 📎"

        # Дата поста (если есть)
        if hasattr(post, 'published') and post.published:
            try:
                date_str = post.published[:10]  # YYYY-MM-DD
                info_text += f"  {date_str}"
            except:
                pass

        info_label = tk.Label(post_frame, text=info_text, font=('Arial', 8), bg=bg_color)
        info_label.pack()

        # Привязываем события после создания всех виджетов
        checkbox_frame.bind('<Button-1>', toggle_checkbox)
        post_frame.bind('<Button-1>', on_click_anywhere)
        thumbnail_frame.bind('<Button-1>', lambda e: self.select_post(post))
        title_label.bind('<Button-1>', lambda e: self.select_post(post))
        info_label.bind('<Button-1>', lambda e: self.select_post(post))

        # Клик по посту для просмотра медиафайлов
        # Делаем всю область поста кликабельной
        def on_post_click(event, post_obj=post):
            self.select_post(post_obj)
        
        def on_post_enter(event):
            post_frame.configure(relief=tk.GROOVE)
            
        def on_post_leave(event):
            post_frame.configure(relief=tk.RAISED)
        
        for widget in [post_frame, thumbnail_frame, title_label, info_label]:
            widget.bind("<Button-1>", on_post_click)
            widget.bind("<Enter>", on_post_enter)
            widget.bind("<Leave>", on_post_leave)
            widget.configure(cursor="hand2")
    
    def select_post(self, post):
        """Выбор поста для просмотра медиафайлов"""
        self.selected_post = post
        self.load_post_media(post)
    
    def load_post_media(self, post):
        """Загрузка медиафайлов поста"""
        # Сохраняем выбранный пост
        self.selected_post = post

        # Обновляем выделение постов
        self.update_posts_display()

        # Показываем индикатор загрузки в правой панели
        self.media_frame.configure(text="🖼️ Загрузка медиафайлов...")

        # Запускаем загрузку в отдельном потоке
        thread = threading.Thread(target=self._load_media_thread, args=(post,))
        thread.daemon = True
        thread.start()
    
    def _load_media_thread(self, post):
        """Поток загрузки медиафайлов поста"""
        try:
            self.update_status("Поиск медиа")

            # Получаем медиафайлы с полной страницы поста
            # Используем существующую логику из kemono_parser
            if not self.parser:
                self.parser = KemonoParser(use_selenium=True, headless=True)
            
            # Конструируем URL поста
            post_url = f"https://kemono.cr/{post.service}/post/{post.id}"
            
            # Получаем HTML страницы поста
            html = self.parser._selenium_get(post_url)
            if html:
                from bs4 import BeautifulSoup
                soup = BeautifulSoup(html, 'lxml')
                
                # Ищем все медиафайлы на странице
                media_links = set()
                
                # Список всех поддерживаемых расширений
                image_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.svg']
                video_extensions = ['.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv']
                archive_extensions = ['.zip', '.rar', '.7z', '.tar', '.gz', '.bz2']
                other_extensions = ['.pdf', '.doc', '.docx', '.txt', '.psd']
                all_extensions = image_extensions + video_extensions + archive_extensions + other_extensions
                
                # Ссылки на файлы
                for link in soup.find_all('a', href=True):
                    href = link['href']
                    if any(ext in href.lower() for ext in all_extensions):
                        # Пропускаем thumbnail-ы, иконки сайта и системные файлы
                        if any(x in href.lower() for x in ['thumb', 'preview', 'icon', 'thumbnail', 'static/menu', 'static/close', 'favicon']):
                            continue

                        # Фильтр для рекламных доменов
                        if any(domain in href.lower() for domain in ['go.tscprts.com', 'tscprts.com', 'googletagmanager.com', 'google-analytics.com', 'doubleclick.net']):
                            continue

                        # Фильтр для URL с подозрительными параметрами (рекламные ссылки)
                        from urllib.parse import urlparse, parse_qs
                        parsed = urlparse(href)
                        query_params = parse_qs(parsed.query)

                        # Пропускаем URL с большим количеством параметров или длинными значениями
                        if len(query_params) > 3 or any(len(str(v)) > 50 for v in query_params.values()):
                            continue

                        # Фильтр для URL с двойными слэшами
                        if '//' in href and href.count('//') > 1:
                            continue

                        if href.startswith('http'):
                            media_links.add(href)
                        elif href.startswith('/'):
                            media_links.add(f"https://kemono.cr{href}")

                # Изображения - для них нужно найти полную версию
                for img in soup.find_all('img', src=True):
                    src = img['src']
                    if any(ext in src.lower() for ext in image_extensions):
                        # Фильтры для рекламных и системных изображений
                        if any(x in src.lower() for x in ['static/menu', 'static/close', 'favicon']):
                            continue

                        # Фильтр для рекламных доменов
                        if any(domain in src.lower() for domain in ['go.tscprts.com', 'tscprts.com', 'googletagmanager.com', 'google-analytics.com', 'doubleclick.net']):
                            continue

                        # Фильтр для URL с подозрительными параметрами (рекламные баннеры)
                        from urllib.parse import urlparse, parse_qs
                        parsed = urlparse(src)
                        query_params = parse_qs(parsed.query)

                        # Пропускаем URL с большим количеством параметров или длинными значениями
                        if len(query_params) > 3 or any(len(str(v)) > 50 for v in query_params.values()):
                            continue

                        # Фильтр для URL с двойными слэшами
                        if '//' in src and src.count('//') > 1:
                            continue

                        # Если это thumbnail, преобразуем в полную версию
                        if 'thumbnail' in src.lower() and 'img.kemono.cr' in src:
                            # Преобразуем thumbnail URL в полный
                            # https://img.kemono.cr/thumbnail/data/... -> https://n2.kemono.cr/data/...
                            full_url = src.replace('https://img.kemono.cr/thumbnail', 'https://n2.kemono.cr')
                            if (full_url.startswith('http') and
                                '//' not in full_url[8:] and  # Проверяем отсутствие двойных слэшей
                                '/data/' in full_url):        # Проверяем наличие /data/ в пути
                                media_links.add(full_url)
                        elif (src.startswith('http') and
                              'kemono.cr' in src and
                              '//' not in src[8:] and        # Проверяем отсутствие двойных слэшей
                              '/data/' in src):              # Проверяем наличие /data/ в пути
                            # Обычное изображение с kemono.cr
                            media_links.add(src)
                
                # Быстрая валидация URL с кэшированием и параллельными запросами
                print(f"📊 Проверяем {len(media_links)} найденных URL...")
                import concurrent.futures
                import threading

                def validate_url(url):
                    """Валидация одного URL с кэшированием"""
                    # Проверяем кэш
                    if url in self.url_validation_cache:
                        return url if self.url_validation_cache[url] else None

                    try:
                        # Быстрая проверка HEAD запросом
                        response = requests.head(url, timeout=3, allow_redirects=True)
                        if response.status_code == 200:
                            content_type = response.headers.get('content-type', '').lower()
                            if 'image' in content_type:
                                self.url_validation_cache[url] = True
                                return url
                            else:
                                self.url_validation_cache[url] = False
                        else:
                            self.url_validation_cache[url] = False
                    except Exception:
                        self.url_validation_cache[url] = False

                    return None

                # Параллельная валидация
                valid_urls = []
                with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
                    futures = {executor.submit(validate_url, url): url for url in media_links}
                    for future in concurrent.futures.as_completed(futures):
                        result = future.result()
                        if result:
                            valid_urls.append(result)

                print(f"📊 Найдено {len(valid_urls)} валидных изображений после проверки")
                media_links = set(valid_urls)

                self.current_media = []
                for url in media_links:
                    filename = url.split('/')[-1].split('?')[0]
                    
                    # Определяем тип файла
                    file_type = 'other'
                    if any(ext in url.lower() for ext in image_extensions):
                        file_type = 'image'
                    elif any(ext in url.lower() for ext in video_extensions):
                        file_type = 'video'
                    elif any(ext in url.lower() for ext in archive_extensions):
                        file_type = 'archive'
                    
                    # Создаем thumbnail URL для превью из полной версии
                    import urllib.parse
                    parsed_url = urllib.parse.urlparse(url)

                    # Преобразуем полную версию в thumbnail
                    # https://n2.kemono.cr/data/... -> https://img.kemono.cr/thumbnail/data/...
                    if 'n' in parsed_url.netloc and 'kemono.cr' in parsed_url.netloc:
                        thumbnail_url = f"https://img.kemono.cr/thumbnail{parsed_url.path}"
                    else:
                        # Для других случаев используем оригинальный URL
                        thumbnail_url = url

                    self.current_media.append({
                        'url': url,  # Полный URL для скачивания
                        'thumbnail_url': thumbnail_url,  # URL превью для отображения
                        'filename': filename,
                        'type': file_type
                    })

            print(f"📋 Создано {len(self.current_media)} медиафайлов для отображения")

            # Обновляем GUI в главном потоке
            self.root.after(0, self._on_media_loaded)
            
        except Exception as e:
            error_msg = str(e)
            self.root.after(0, lambda: self._on_media_error(error_msg))
    
    def _on_media_loaded(self):
        """Обработчик успешной загрузки медиафайлов"""
        # Используем название поста вместо "Просмотр поста"
        post_title = self.selected_post.title[:30] + "..." if len(self.selected_post.title) > 30 else self.selected_post.title
        self.media_frame.configure(text=f"🖼️ {post_title} ({len(self.current_media)} файлов)")

        # Сбрасываем статус
        self.update_status("Готов к работе")

        # Создаем карточки медиафайлов (превью будут загружаться по мере готовности)
        self.update_media_display()
        self.update_buttons_state()
    
    def _on_media_error(self, error_msg):
        """Обработчик ошибки загрузки медиафайлов"""
        self.media_frame.configure(text="🖼️ Ошибка загрузки")
        print(f"Ошибка загрузки медиафайлов: {error_msg}")
    
    def update_media_display(self):
        """Обновление отображения медиафайлов"""
        # Очищаем текущие виджеты
        for widget in self.media_scrollable_frame.winfo_children():
            widget.destroy()
        
        if not self.current_media:
            no_media_label = ttk.Label(self.media_scrollable_frame, text="Медиафайлы не найдены")
            no_media_label.pack(pady=20)
            return
        
        # Вычисляем количество колонок
        window_width = self.media_canvas.winfo_width()
        if window_width <= 1:
            window_width = 600  # Увеличиваем размер по умолчанию

        media_width = 140  # Увеличиваем ширину карточки
        cols = max(1, window_width // media_width)

        print(f"📏 Медиа-окно шириной {window_width}px, карточка {media_width}px, колонок: {cols}")
        
        # Создаем сетку медиафайлов
        if not hasattr(self, 'media_vars'):
            self.media_vars = {}
        
        for i, media in enumerate(self.current_media):
            row = i // cols
            col = i % cols
            self.create_media_widget(media, row, col)
    
    def create_media_widget(self, media, row, col):
        """Создание виджета для одного медиафайла"""
        media_frame = tk.Frame(self.media_scrollable_frame, bg='white', relief=tk.GROOVE, borderwidth=2)
        media_frame.grid(row=row, column=col, padx=8, pady=8, sticky="nsew")

        # Чекбокс с увеличенной областью клика
        media_var = tk.BooleanVar()
        checkbox_frame = tk.Frame(media_frame, width=40, height=40, bg='white')
        checkbox_frame.pack(anchor='nw', padx=8, pady=8)
        checkbox_frame.pack_propagate(False)

        # Цвет фона для всех элементов
        bg_color = 'white'

        checkbox = ttk.Checkbutton(
            checkbox_frame,
            variable=media_var,
            command=self.on_media_selection_changed
        )
        checkbox.pack(expand=True, fill=tk.BOTH)

        # Делаем весь фрейм кликабельным
        def toggle_media_checkbox(event):
            current_value = media_var.get()
            media_var.set(not current_value)
            self.on_media_selection_changed()

        # Привязываем клик ко всем элементам карточки
        def on_media_click_anywhere(event):
            # Определяем что делать в зависимости от того, куда кликнули
            clicked_widget = event.widget

            # Если кликнули на чекбокс или его дочерние элементы - переключаем чекбокс
            if clicked_widget == checkbox_frame or (hasattr(clicked_widget, 'winfo_parent') and str(clicked_widget.winfo_parent()) == str(checkbox_frame)):
                toggle_media_checkbox(event)
            else:
                # Иначе - переключаем чекбокс медиафайла
                toggle_media_checkbox(event)

        # Сохраняем переменную чекбокса
        self.media_vars[media['url']] = media_var

        # Добавляем атрибут для идентификации медиафайла
        media_frame.media_url = media['url']

        # Превью медиафайла с увеличенным размером
        preview_frame = tk.Frame(media_frame, width=120, height=100, bg='white', relief=tk.FLAT)
        preview_frame.pack(pady=5)
        preview_frame.pack_propagate(False)

        # Добавляем идентификатор для preview_frame
        preview_frame._is_preview_frame = True
        
        # Пытаемся загрузить превью изображения
        try:
            if media['type'] == 'image':
                cached_path = self.get_cached_preview_path(media['thumbnail_url'])
                if cached_path and Path(cached_path).exists():
                    # Превью уже скачано, показываем его
                    from PIL import Image, ImageTk
                    pil_image = Image.open(cached_path)
                    pil_image.thumbnail((110, 90), Image.Resampling.LANCZOS)
                    photo = ImageTk.PhotoImage(pil_image)
                    image_label = tk.Label(preview_frame, image=photo, bg='white')

                    # КРИТИЧНО: сохраняем ссылку на изображение в нескольких местах
                    image_label.image = photo
                    preview_frame._photo_image = photo  # Сохраняем в родительском виджете

                    image_label.pack(expand=True, fill=tk.BOTH)
                    print(f"✅ Показано существующее превью медиа {media['filename']}")
                else:
                    # Превью еще не скачано, показываем иконку и запускаем асинхронную загрузку
                    icon_label = ttk.Label(preview_frame, text="🖼️", font=('Arial', 24))
                    icon_label.pack(expand=True)

                    # Запускаем асинхронную загрузку превью для этого медиафайла
                    def load_media_preview_async():
                        try:
                            cached_path = self.download_and_cache_preview(media['thumbnail_url'], size=(110, 90), preview_type="media")
                            if cached_path:
                                # Обновляем превью в GUI в главном потоке
                                self.root.after(0, lambda: self.update_media_preview(media, cached_path))
                            else:
                                # Добавляем в очередь повторных попыток
                                self.add_failed_preview(media['thumbnail_url'], "media")
                        except Exception as e:
                            print(f"Ошибка загрузки превью для медиа {media['filename']}: {e}")
                            self.add_failed_preview(media['thumbnail_url'], "media")

                    # Запускаем в отдельном потоке
                    import threading
                    thread = threading.Thread(target=load_media_preview_async, daemon=True)
                    thread.start()

            else:
                # Для не-изображений показываем иконку типа
                type_icons = {
                    'video': "🎬",
                    'archive': "📦",
                    'other': "📄"
                }
                type_icon = type_icons.get(media['type'], "📄")
                icon_label = tk.Label(preview_frame, text=type_icon, font=('Arial', 24), bg=bg_color)
                icon_label.pack(expand=True)
        except Exception as e:
            # Если не удалось загрузить превью, показываем иконку
            print(f"Ошибка отображения превью для медиа {media['filename']}: {e}")
            type_icons = {
                'image': "🖼️",
                'video': "🎬",
                'archive': "📦",
                'other': "📄"
            }
            type_icon = type_icons.get(media['type'], "📄")
            icon_label = tk.Label(preview_frame, text=type_icon, font=('Arial', 24), bg=bg_color)
            icon_label.pack(expand=True)

        # Название файла
        filename = media['filename'][:15] + ("..." if len(media['filename']) > 15 else "")
        name_label = tk.Label(media_frame, text=filename, font=('Arial', 8), bg=bg_color)
        name_label.pack()

        # Привязываем события после создания всех виджетов
        checkbox_frame.bind('<Button-1>', toggle_media_checkbox)
        media_frame.bind('<Button-1>', on_media_click_anywhere)
        preview_frame.bind('<Button-1>', toggle_media_checkbox)
        name_label.bind('<Button-1>', toggle_media_checkbox)

        # Добавляем эффекты при наведении
        def on_media_enter(event):
            media_frame.configure(relief=tk.GROOVE, borderwidth=3)

        def on_media_leave(event):
            media_frame.configure(relief=tk.GROOVE, borderwidth=2)

        media_frame.bind("<Enter>", on_media_enter)
        media_frame.bind("<Leave>", on_media_leave)
        media_frame.configure(cursor="hand2")
    
    def update_posts_layout(self):
        """Обновление разметки постов при изменении размера окна"""
        if hasattr(self, 'all_posts') and self.all_posts:
            self.update_posts_display()
    
    # === МЕТОДЫ ПАГИНАЦИИ ===

    def prev_page(self):
        """Переход на предыдущую страницу"""
        if self.current_page > 0:
            self.current_page -= 1
            self.update_posts_display()

    def next_page(self):
        """Переход на следующую страницу"""
        total_pages = (len(self.all_posts) + self.posts_per_page - 1) // self.posts_per_page
        if self.current_page < total_pages - 1:
            self.current_page += 1
            self.update_posts_display()

    # === МЕТОДЫ СКАЧИВАНИЯ ===
    
    def download_selected_posts(self):
        """Скачивание выбранных постов"""
        selected_posts = self.get_selected_posts()
        if not selected_posts:
            messagebox.showwarning("Предупреждение", "Выберите посты для скачивания")
            return
        
        self.start_download(selected_posts, "selected_posts")
    
    def download_selected_media(self):
        """Скачивание выбранных медиафайлов"""
        selected_media = self.get_selected_media()
        if not selected_media:
            messagebox.showwarning("Предупреждение", "Выберите медиафайлы для скачивания")
            return
        
        self.start_download(selected_media, "selected_media")
    
    def download_all_post_media(self):
        """Скачивание всех медиафайлов текущего поста"""
        if not self.current_media:
            messagebox.showwarning("Предупреждение", "Нет медиафайлов для скачивания")
            return
        
        self.start_download(self.current_media, "all_post_media")
    
    def download_page_posts(self):
        """Скачивание всех постов текущей страницы"""
        start_idx = self.current_page * self.posts_per_page
        end_idx = min(start_idx + self.posts_per_page, len(self.all_posts))
        page_posts = self.all_posts[start_idx:end_idx]

        if not page_posts:
            messagebox.showwarning("Предупреждение", "На текущей странице нет постов")
            return

        self.start_download(page_posts, "page_posts")
    
    def download_all_posts(self):
        """Скачивание всех постов пользователя"""
        if not self.all_posts:
            messagebox.showwarning("Предупреждение", "Нет постов для скачивания")
            return
        
        self.start_download(self.all_posts, "all_posts")
    
    def get_selected_posts(self):
        """Получение списка выбранных постов"""
        if not hasattr(self, 'post_vars'):
            return []

        selected = []
        # Проверяем посты только текущей страницы
        start_idx = self.current_page * self.posts_per_page
        end_idx = min(start_idx + self.posts_per_page, len(self.all_posts))
        current_posts = self.all_posts[start_idx:end_idx]

        for post in current_posts:
            if post.id in self.post_vars and self.post_vars[post.id].get():
                selected.append(post)

        return selected
    
    def get_selected_media(self):
        """Получение списка выбранных медиафайлов"""
        if not hasattr(self, 'media_vars'):
            return []
        
        selected = []
        for media in self.current_media:
            if media['url'] in self.media_vars and self.media_vars[media['url']].get():
                selected.append(media)
        
        return selected
    
    def start_download(self, items, download_type):
        """Запуск процесса скачивания"""
        if self.is_downloading:
            messagebox.showwarning("Предупреждение", "Скачивание уже выполняется")
            return
        
        if not items:
            messagebox.showwarning("Предупреждение", "Нет элементов для скачивания")
            return
        
        # Подтверждение скачивания
        result = messagebox.askyesno(
            "Подтверждение", 
            f"Начать скачивание?\nТип: {download_type}\nЭлементов: {len(items)}"
        )
        
        if not result:
            return
        
        # Запускаем скачивание в отдельном потоке
        self.is_downloading = True
        self.update_download_buttons_state(False)
        
        thread = threading.Thread(
            target=self._download_thread, 
            args=(items, download_type)
        )
        thread.daemon = True
        thread.start()
    
    def _download_thread(self, items, download_type):
        """Поток скачивания"""
        try:
            if download_type in ["selected_posts", "page_posts", "all_posts"]:
                self._download_posts(items)
            elif download_type in ["selected_media", "all_post_media"]:
                self._download_media_files(items)
            
            # Уведомление об успешном завершении
            self.root.after(0, lambda: messagebox.showinfo(
                "Успех", 
                f"Скачивание завершено!\nТип: {download_type}\nЭлементов: {len(items)}"
            ))
            
        except Exception as e:
            error_message = f"Ошибка при скачивании: {str(e)}"
            self.root.after(0, lambda: messagebox.showerror(
                "Ошибка",
                error_message
            ))
        finally:
            self.is_downloading = False
            self.root.after(0, lambda: self.update_download_buttons_state(True))
    
    def collect_all_media_from_posts(self, posts):
        """Собирает все медиа URL из выбранных постов с многопоточным анализом"""
        if not self.parser:
            self.parser = KemonoParser(use_selenium=True, headless=True)

        all_media_info = []
        analyzed_count = 0

        print(f"\n🔍 Собираю медиафайлы из {len(posts)} постов...")

        # Обновляем статус
        self.update_status(f"Анализ постов (0/{len(posts)})")

        # Разделяем посты на батчи для многопоточной обработки
        batch_size = 10  # 10 потоков для анализа (увеличено для большей скорости)
        post_batches = [posts[i:i + batch_size] for i in range(0, len(posts), batch_size)]

        for batch_idx, batch in enumerate(post_batches):
            print(f"📦 Обрабатываю батч {batch_idx + 1}/{len(post_batches)} ({len(batch)} постов)...")

            # Многопоточная обработка батча
            from concurrent.futures import ThreadPoolExecutor, as_completed
            from queue import Queue
            import threading

            # Очередь для результатов
            results_queue = Queue()
            batch_results = []

            def analyze_post_worker(post):
                """Работает в отдельном потоке для анализа одного поста"""
                try:
                    # Собираем медиа из attachments и files (быстрый способ)
                    post_media = []

                    # Создаем путь к папке поста
                    safe_title = re.sub(r'[<>:"/\\|?*]', '_', post.title[:50])
                    author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
                    post_dir = Path("downloads") / author_name / safe_title

                    for attachment in post.attachments:
                        filename = attachment['name']
                        url = attachment['url']
                        if self.parser._is_valid_media_url(url):
                            filepath = post_dir / filename
                            post_media.append({
                                'url': url,
                                'filename': filename,
                                'filepath': str(filepath),
                                'post_title': post.title,
                                'post_id': post.id
                            })

                    for file_info in post.files:
                        filename = file_info['name']
                        url = file_info['url']
                        if self.parser._is_valid_media_url(url):
                            filepath = post_dir / filename
                            post_media.append({
                                'url': url,
                                'filename': filename,
                                'filepath': str(filepath),
                                'post_title': post.title,
                                'post_id': post.id
                            })

                    # Если вложений мало или их нет, анализируем полную страницу поста
                    if len(post_media) == 0:
                        # Используем основной парсер, но аккуратно
                        post_media_urls = self._analyze_post_for_media_safe(post)
                        for url_info in post_media_urls:
                            if self.parser._is_valid_media_url(url_info['url']):
                                filepath = post_dir / url_info['filename']
                                post_media.append({
                                    'url': url_info['url'],
                                    'filename': url_info['filename'],
                                    'filepath': str(filepath),
                                    'post_title': post.title,
                                    'post_id': post.id
                                })

                    # Отправляем результат в очередь
                    results_queue.put((post, post_media, None))

                except Exception as e:
                    # Отправляем ошибку в очередь
                    results_queue.put((post, [], str(e)))

            # Запускаем потоки для анализа постов
            threads = []
            for post in batch:
                thread = threading.Thread(target=analyze_post_worker, args=(post,))
                thread.daemon = True
                threads.append(thread)
                thread.start()

            # Ждем завершения всех потоков и собираем результаты
            for thread in threads:
                thread.join()

            # Обрабатываем результаты из очереди
            while not results_queue.empty():
                post, post_media, error = results_queue.get()

                if error:
                    print(f"   ❌ Ошибка при анализе поста {post.id}: {error}")
                else:
                    print(f"   📊 Пост '{post.title[:30]}...' - найдено {len(post_media)} медиафайлов")

                batch_results.append(post_media)
                analyzed_count += 1

                # Обновляем статус каждые 2 поста
                if analyzed_count % 2 == 0:
                    self.update_status(f"Анализ постов ({analyzed_count}/{len(posts)})")

            # Собираем результаты батча
            for post_media in batch_results:
                all_media_info.extend(post_media)

        # Финальное обновление статуса
        self.update_status(f"Анализ постов ({len(posts)}/{len(posts)})")

        print(f"\n📊 Всего собрано медиафайлов: {len(all_media_info)}")
        return all_media_info


    def _analyze_post_for_media_safe(self, post):
        """Анализирует пост и собирает медиа URL в многопоточном режиме"""
        media_urls = []

        try:
            # Создаем временный парсер только для этого поста
            temp_parser = KemonoParser(use_selenium=True, headless=True)

            try:
                # Используем логику из download_post_content, но только для сбора URL
                post_url = f"{temp_parser.base_url}/{post.service}/post/{post.id}"

                html = temp_parser._selenium_get(post_url)
                if not html:
                    return media_urls

                soup = BeautifulSoup(html, 'lxml')

                # Ищем все ссылки на медиафайлы
                media_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.svg',
                                   '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv',
                                   '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2',
                                   '.pdf', '.doc', '.docx', '.txt', '.psd']

                media_links = soup.find_all('a', href=lambda x: x and any(ext in x.lower() for ext in media_extensions))
                img_tags = soup.find_all('img', src=lambda x: x and any(ext in x.lower() for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']))

                all_media_urls = set()

                # Добавляем ссылки из <a> тегов
                for link in media_links:
                    try:
                        url = link['href']
                        if not url.startswith('http'):
                            from urllib.parse import urljoin
                            url = urljoin(temp_parser.base_url, url)
                        all_media_urls.add(url)
                    except:
                        continue

                # Добавляем ссылки из <img> тегов
                for img in img_tags:
                    try:
                        url = img['src']
                        if not url.startswith('http'):
                            from urllib.parse import urljoin
                            url = urljoin(temp_parser.base_url, url)
                        # Пропускаем превью и маленькие изображения
                        if any(x in url.lower() for x in ['thumb', 'preview', 'icon', 'thumbnail']):
                            continue
                        all_media_urls.add(url)
                    except:
                        continue

                # Создаем записи для каждого найденного URL
                for url in all_media_urls:
                    try:
                        filename = url.split('/')[-1].split('?')[0]
                        if filename and self.parser._is_valid_media_url(url):
                            media_urls.append({
                                'url': url,
                                'filename': filename
                            })
                    except:
                        continue

            finally:
                # Всегда закрываем временный парсер
                try:
                    temp_parser.close()
                except:
                    pass

        except Exception as e:
            print(f"   ❌ Ошибка анализа поста {post.id}: {e}")

        return media_urls

    def _analyze_post_for_media(self, parser, post):
        """Анализирует пост и собирает медиа URL без загрузки файлов"""
        media_urls = []

        try:
            # Используем логику из download_post_content, но только для сбора URL
            post_url = f"{parser.base_url}/{post.service}/post/{post.id}"

            html = parser._selenium_get(post_url)
            if not html:
                return media_urls

            soup = BeautifulSoup(html, 'lxml')

            # Ищем все ссылки на медиафайлы
            media_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.svg',
                               '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv',
                               '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2',
                               '.pdf', '.doc', '.docx', '.txt', '.psd']

            media_links = soup.find_all('a', href=lambda x: x and any(ext in x.lower() for ext in media_extensions))
            img_tags = soup.find_all('img', src=lambda x: x and any(ext in x.lower() for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']))

            all_media_urls = set()

            # Добавляем ссылки из <a> тегов
            for link in media_links:
                try:
                    url = link['href']
                    if not url.startswith('http'):
                        from urllib.parse import urljoin
                        url = urljoin(parser.base_url, url)
                    all_media_urls.add(url)
                except:
                    continue

            # Добавляем ссылки из <img> тегов
            for img in img_tags:
                try:
                    url = img['src']
                    if not url.startswith('http'):
                        from urllib.parse import urljoin
                        url = urljoin(parser.base_url, url)
                    # Пропускаем превью и маленькие изображения
                    if any(x in url.lower() for x in ['thumb', 'preview', 'icon', 'thumbnail']):
                        continue
                    all_media_urls.add(url)
                except:
                    continue

            # Создаем записи для каждого найденного URL
            for url in all_media_urls:
                try:
                    filename = url.split('/')[-1].split('?')[0]
                    if filename:
                        media_urls.append({
                            'url': url,
                            'filename': filename
                        })
                except:
                    continue

        except Exception as e:
            print(f"   ❌ Ошибка анализа поста {post.id}: {e}")

        return media_urls

    def _download_posts(self, posts):
        """Скачивание постов"""
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import re
        from pathlib import Path

        # Сначала собираем все медиа URL из постов
        all_media_info = self.collect_all_media_from_posts(posts)

        if not all_media_info:
            print("❌ Не найдено медиафайлов для скачивания")
            return

        # Создаем папки для постов
        created_dirs = set()
        for media in all_media_info:
            if 'filepath' not in media:
                print(f"❌ Ошибка: медиафайл без filepath: {media}")
                continue

            post_dir = Path(media['filepath']).parent
            if str(post_dir) not in created_dirs:
                try:
                    post_dir.mkdir(parents=True, exist_ok=True)
                    created_dirs.add(str(post_dir))
                    print(f"📁 Создана папка: {post_dir}")
                except Exception as e:
                    print(f"❌ Ошибка создания папки {post_dir}: {e}")

        # Начинаем многопоточную загрузку
        downloaded_count = 0
        errors = []

        total_files = len(all_media_info)
        max_workers = min(8, total_files)  # 8 потоков максимум, но не больше количества файлов

        print(f"\n🚀 Начинаю скачивание {total_files} файлов в {max_workers} потоков...")

        # Обновляем статус и прогресс в UI
        self.update_status(f"Скачивание медиа (0/{total_files})")
        self.root.after(0, lambda: self.mini_progress.configure(mode='determinate', maximum=total_files, value=0))
        self.root.after(0, lambda: self.root.title(f"🎨 Kemono.cr Parser - Скачано 0/{total_files} медиа"))

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Создаем задачи для загрузки
            future_to_media = {}

            for media in all_media_info:
                filepath = Path(media['filepath'])

                # Пропускаем если файл уже существует
                if filepath.exists():
                    downloaded_count += 1
                    self.root.after(0, lambda: self.mini_progress.configure(value=downloaded_count))
                    self.root.after(0, lambda: self.update_status(f"Скачивание медиа ({downloaded_count}/{total_files})"))
                    self.root.after(0, lambda: self.root.title(f"🎨 Kemono.cr Parser - Скачано {downloaded_count}/{total_files} медиа"))
                    continue

                future = executor.submit(self._download_single_file, media['url'], str(filepath))
                future_to_media[future] = media

            # Обрабатываем результаты
            for future in as_completed(future_to_media):
                media = future_to_media[future]
                try:
                    success = future.result()
                    if success:
                        downloaded_count += 1
                        print(f"✅ Скачан: {media['filename']}")
                    else:
                        errors.append(f"Не удалось скачать {media['filename']}")
                        print(f"❌ Ошибка скачивания: {media['filename']}")

                except Exception as e:
                    errors.append(f"Ошибка скачивания {media['filename']}: {str(e)}")
                    print(f"❌ Ошибка: {media['filename']} - {str(e)}")

                # Обновляем прогресс и статус в UI
                self.root.after(0, lambda: self.mini_progress.configure(value=downloaded_count))
                self.root.after(0, lambda: self.update_status(f"Скачивание медиа ({downloaded_count}/{total_files})"))
                self.root.after(0, lambda: self.root.title(f"🎨 Kemono.cr Parser - Скачано {downloaded_count}/{total_files} медиа"))

        # Завершаем загрузку
        self.update_status("Готов к работе")
        self.root.after(0, lambda: self.root.title("🎨 Kemono.cr Parser - Загрузка завершена"))
        self.root.after(0, lambda: self.mini_progress.configure(value=0))

        print("\n📊 Загрузка завершена:")
        print(f"   ✅ Скачано: {downloaded_count}")
        print(f"   ❌ Ошибок: {len(errors)}")

        # Обновляем статус скачивания
        self.download_status[f"posts_{int(time.time())}"] = {
            'type': 'posts',
            'artist': f"{self.current_artist.service}_{self.current_artist.id}",
            'count': len(posts),
            'total_media': total_files,
            'downloaded': downloaded_count,
            'errors': errors,
            'timestamp': datetime.now().isoformat()
        }

        self.save_download_state()
    
    def _download_media_files(self, media_files):
        """Скачивание отдельных медиафайлов"""
        if not self.parser:
            self.parser = KemonoParser(use_selenium=True, headless=True)
        
        if not self.current_artist or not self.selected_post:
            raise ValueError("Не выбран автор или пост")
        
        # Создаем папку для поста
        import re
        safe_title = re.sub(r'[<>:"/\\|?*]', '_', self.selected_post.title[:50])
        author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
        post_dir = Path("downloads") / author_name / safe_title
        post_dir.mkdir(parents=True, exist_ok=True)
        
        downloaded_count = 0
        errors = []
        
        # Начинаем загрузку - показываем прогресс
        self.mini_progress.configure(mode='determinate', maximum=len(media_files), value=0)
        self.root.title(f"🎨 Kemono.cr Parser - Загрузка {len(media_files)} файлов...")

        # Скачиваем только выбранные файлы
        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = {}

            for media in media_files:
                filename = media['filename']
                filepath = post_dir / filename

                # Пропускаем если файл уже существует
                if filepath.exists():
                    downloaded_count += 1
                    self.mini_progress.configure(value=downloaded_count)
                    self.root.title(f"🎨 Kemono.cr Parser - Скачано {downloaded_count}/{len(media_files)}")
                    continue

                future = executor.submit(self._download_single_file, media['url'], str(filepath))
                futures[future] = media

            # Ждем завершения всех загрузок
            for future in as_completed(futures):
                media = futures[future]
                try:
                    success = future.result()
                    if success:
                        downloaded_count += 1
                    else:
                        errors.append(f"Не удалось скачать {media['filename']}")

                    # Обновляем прогресс
                    self.mini_progress.configure(value=downloaded_count)
                    self.root.title(f"🎨 Kemono.cr Parser - Скачано {downloaded_count}/{len(media_files)}")

                except Exception as e:
                    errors.append(f"Ошибка скачивания {media['filename']}: {str(e)}")
                    downloaded_count += 1  # Считаем как завершенную для прогресса
                    self.mini_progress.configure(value=downloaded_count)
                    self.root.title(f"🎨 Kemono.cr Parser - Скачано {downloaded_count}/{len(media_files)}")

        # Завершаем загрузку
        self.root.title("🎨 Kemono.cr Parser - Загрузка завершена")
        self.mini_progress.configure(value=0)
        
        # Обновляем статус скачивания
        self.download_status[f"media_{int(time.time())}"] = {
            'type': 'media',
            'post_id': self.selected_post.id,
            'post_title': self.selected_post.title,
            'count': len(media_files),
            'downloaded': downloaded_count,
            'errors': errors,
            'timestamp': datetime.now().isoformat()
        }
        
        self.save_download_state()
    
    def _download_single_file(self, url, filepath):
        """Скачивание одного файла"""
        if not self.parser:
            return False
        
        return self.parser.download_file(url, filepath, show_progress=False)
    
    def update_download_buttons_state(self, enabled):
        """Обновление состояния кнопок скачивания"""
        state = tk.NORMAL if enabled else tk.DISABLED
        
        self.download_selected_posts_btn.configure(state=state)
        self.download_selected_media_btn.configure(state=state)
        self.download_all_media_btn.configure(state=state)
        self.download_page_posts_btn.configure(state=state)
        self.download_all_posts_btn.configure(state=state)
        
        # Обновляем текст кнопок
        if not enabled:
            # Показываем индикатор загрузки
            self.mini_progress.configure(mode='indeterminate')
            self.mini_progress.start()
        else:
            self.mini_progress.stop()
            self.mini_progress.configure(mode='determinate', value=0)
    
    def on_post_selection_changed(self):
        """Обработчик изменения выбора постов"""
        self.update_buttons_state()
    
    def on_media_selection_changed(self):
        """Обработчик изменения выбора медиафайлов"""
        self.update_buttons_state()
    
    def update_buttons_state(self):
        """Обновление состояния кнопок"""
        has_posts = bool(self.all_posts)
        has_media = bool(self.current_media)
        
        # Проверяем есть ли выбранные посты
        selected_posts = self.get_selected_posts()
        has_selected_posts = len(selected_posts) > 0
        
        # Проверяем есть ли выбранные медиафайлы
        selected_media = self.get_selected_media()
        has_selected_media = len(selected_media) > 0
        
        # Обновляем состояние кнопок для постов
        posts_text = f"Скачать выбранные посты ({len(selected_posts)})" if has_selected_posts else "Скачать выбранные посты"
        self.download_selected_posts_btn.configure(
            state=tk.NORMAL if has_selected_posts else tk.DISABLED,
            text=posts_text
        )
        self.download_page_posts_btn.configure(
            state=tk.NORMAL if has_posts else tk.DISABLED
        )
        self.download_all_posts_btn.configure(
            state=tk.NORMAL if has_posts else tk.DISABLED
        )
        
        # Обновляем состояние кнопок для медиафайлов
        media_text = f"Скачать выбранные медиа ({len(selected_media)})" if has_selected_media else "Скачать выбранные медиа"
        self.download_selected_media_btn.configure(
            state=tk.NORMAL if has_selected_media else tk.DISABLED,
            text=media_text
        )
        self.download_all_media_btn.configure(
            state=tk.NORMAL if has_media else tk.DISABLED
        )
    
    # === МЕТОДЫ ОКОН СТАТУСА ===
    
    def show_download_status(self):
        """Показать окно статуса загрузок"""
        if hasattr(self, 'status_window') and self.status_window.winfo_exists():
            self.status_window.lift()
            return
        
        self.status_window = tk.Toplevel(self.root)
        self.status_window.title("📊 Статус загрузок")
        self.status_window.geometry("600x400")
        self.status_window.minsize(500, 300)
        
        # Основная рамка
        main_frame = ttk.Frame(self.status_window, padding=10)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Заголовок
        title_label = ttk.Label(
            main_frame, 
            text="📊 Статус загрузок", 
            font=('Arial', 14, 'bold')
        )
        title_label.pack(pady=(0, 10))
        
        # Общий статус
        status_frame = ttk.LabelFrame(main_frame, text="Общий статус", padding=5)
        status_frame.pack(fill=tk.X, pady=(0, 10))
        
        # Текущая загрузка
        self.current_download_label = ttk.Label(
            status_frame,
            text="Загрузки не выполняются" if not self.is_downloading else "Выполняется загрузка..."
        )
        self.current_download_label.pack(anchor='w')
        
        # Общий прогресс
        self.overall_progress = ttk.Progressbar(
            status_frame,
            length=400,
            mode='determinate'
        )
        self.overall_progress.pack(fill=tk.X, pady=5)
        
        # Статистика
        total_downloads = len(self.download_status)
        successful = sum(1 for status in self.download_status.values() 
                        if status.get('downloaded', 0) > 0)
        
        stats_text = f"Всего загрузок: {total_downloads} | Успешных: {successful}"
        self.stats_label = ttk.Label(status_frame, text=stats_text)
        self.stats_label.pack(anchor='w')
        
        # История загрузок
        history_frame = ttk.LabelFrame(main_frame, text="История загрузок", padding=5)
        history_frame.pack(fill=tk.BOTH, expand=True)
        
        # Таблица истории
        columns = ('Время', 'Тип', 'Элементов', 'Скачано', 'Ошибки')
        self.history_tree = ttk.Treeview(history_frame, columns=columns, show='headings', height=10)
        
        # Настройка колонок
        self.history_tree.heading('Время', text='Время')
        self.history_tree.heading('Тип', text='Тип')
        self.history_tree.heading('Элементов', text='Элементов')
        self.history_tree.heading('Скачано', text='Скачано')
        self.history_tree.heading('Ошибки', text='Ошибки')
        
        self.history_tree.column('Время', width=120)
        self.history_tree.column('Тип', width=100)
        self.history_tree.column('Элементов', width=80)
        self.history_tree.column('Скачано', width=80)
        self.history_tree.column('Ошибки', width=80)
        
        # Скроллбар для таблицы
        history_scrollbar = ttk.Scrollbar(history_frame, orient="vertical", command=self.history_tree.yview)
        self.history_tree.configure(yscrollcommand=history_scrollbar.set)
        
        self.history_tree.pack(side="left", fill="both", expand=True)
        history_scrollbar.pack(side="right", fill="y")
        
        # Заполняем историю
        self.update_download_history()
        
        # Кнопки управления
        buttons_frame = ttk.Frame(main_frame)
        buttons_frame.pack(fill=tk.X, pady=(10, 0))
        
        # Кнопка обновления
        refresh_btn = ttk.Button(
            buttons_frame,
            text="🔄 Обновить",
            command=self.update_download_history
        )
        refresh_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Кнопка очистки истории
        clear_btn = ttk.Button(
            buttons_frame,
            text="🗑️ Очистить историю",
            command=self.clear_download_history
        )
        clear_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Кнопка паузы/возобновления (пока заглушка)
        self.pause_btn = ttk.Button(
            buttons_frame,
            text="⏸️ Пауза",
            command=self.toggle_download_pause,
            state=tk.DISABLED if not self.is_downloading else tk.NORMAL
        )
        self.pause_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Кнопка закрытия
        close_btn = ttk.Button(
            buttons_frame,
            text="❌ Закрыть",
            command=self.status_window.destroy
        )
        close_btn.pack(side=tk.RIGHT)
    
    def update_download_history(self):
        """Обновление истории загрузок"""
        if not hasattr(self, 'history_tree'):
            return
        
        # Очищаем таблицу
        for item in self.history_tree.get_children():
            self.history_tree.delete(item)
        
        # Заполняем историю (сортируем по времени, новые сверху)
        sorted_downloads = sorted(
            self.download_status.items(),
            key=lambda x: x[1].get('timestamp', ''),
            reverse=True
        )
        
        for download_id, status in sorted_downloads:
            timestamp = status.get('timestamp', '')
            try:
                # Форматируем время
                dt = datetime.fromisoformat(timestamp)
                time_str = dt.strftime('%H:%M:%S')
            except:
                time_str = 'N/A'
            
            type_str = status.get('type', 'Unknown')
            count = status.get('count', 0)
            downloaded = status.get('downloaded', 0)
            errors_count = len(status.get('errors', []))
            
            # Добавляем строку в таблицу
            self.history_tree.insert('', 'end', values=(
                time_str,
                type_str,
                count,
                downloaded,
                errors_count
            ))
        
        # Обновляем статистику
        if hasattr(self, 'stats_label'):
            total_downloads = len(self.download_status)
            successful = sum(1 for status in self.download_status.values() 
                            if status.get('downloaded', 0) > 0)
            
            stats_text = f"Всего загрузок: {total_downloads} | Успешных: {successful}"
            self.stats_label.configure(text=stats_text)
    
    def clear_download_history(self):
        """Очистка истории загрузок"""
        result = messagebox.askyesno(
            "Подтверждение",
            "Удалить всю историю загрузок?"
        )
        
        if result:
            self.download_status.clear()
            self.save_download_state()
            self.update_download_history()
            messagebox.showinfo("Успех", "История загрузок очищена")
    
    def toggle_download_pause(self):
        """Переключение паузы/возобновления загрузки"""
        # TODO: Реализовать логику паузы/возобновления
        if self.is_downloading:
            messagebox.showinfo("Информация", "Пауза загрузки\n(в разработке)")
        else:
            messagebox.showinfo("Информация", "Возобновление загрузки\n(в разработке)")
    
    def show_error_logs(self):
        """Показать окно логов ошибок"""
        if hasattr(self, 'error_window') and self.error_window.winfo_exists():
            self.error_window.lift()
            return
        
        self.error_window = tk.Toplevel(self.root)
        self.error_window.title("⚠️ Логи ошибок")
        self.error_window.geometry("700x500")
        self.error_window.minsize(600, 400)
        
        # Основная рамка
        main_frame = ttk.Frame(self.error_window, padding=10)
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Заголовок
        title_label = ttk.Label(
            main_frame, 
            text="⚠️ Логи ошибок", 
            font=('Arial', 14, 'bold')
        )
        title_label.pack(pady=(0, 10))
        
        # Статистика ошибок
        error_stats_frame = ttk.LabelFrame(main_frame, text="Статистика", padding=5)
        error_stats_frame.pack(fill=tk.X, pady=(0, 10))
        
        # Подсчитываем ошибки
        total_errors = 0
        recent_errors = 0
        now = datetime.now()
        
        for status in self.download_status.values():
            errors = status.get('errors', [])
            total_errors += len(errors)
            
            # Ошибки за последний час
            try:
                timestamp = datetime.fromisoformat(status.get('timestamp', ''))
                if (now - timestamp).total_seconds() < 3600:  # 1 час
                    recent_errors += len(errors)
            except:
                pass
        
        stats_text = f"Всего ошибок: {total_errors} | За последний час: {recent_errors}"
        self.error_stats_label = ttk.Label(error_stats_frame, text=stats_text)
        self.error_stats_label.pack(anchor='w')
        
        # Список ошибок
        errors_frame = ttk.LabelFrame(main_frame, text="Детальные логи", padding=5)
        errors_frame.pack(fill=tk.BOTH, expand=True)
        
        # Текстовое поле с прокруткой для логов
        self.error_text = scrolledtext.ScrolledText(
            errors_frame,
            wrap=tk.WORD,
            width=80,
            height=20,
            font=('Courier', 9)
        )
        self.error_text.pack(fill=tk.BOTH, expand=True)
        
        # Заполняем логи ошибок
        self.update_error_logs()
        
        # Кнопки управления
        buttons_frame = ttk.Frame(main_frame)
        buttons_frame.pack(fill=tk.X, pady=(10, 0))
        
        # Кнопка обновления
        refresh_error_btn = ttk.Button(
            buttons_frame,
            text="🔄 Обновить",
            command=self.update_error_logs
        )
        refresh_error_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Кнопка очистки логов
        clear_logs_btn = ttk.Button(
            buttons_frame,
            text="🗑️ Очистить логи",
            command=self.clear_error_logs
        )
        clear_logs_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Кнопка сохранения в файл
        save_logs_btn = ttk.Button(
            buttons_frame,
            text="💾 Сохранить в файл",
            command=self.save_error_logs
        )
        save_logs_btn.pack(side=tk.LEFT, padx=(0, 10))
        
        # Кнопка закрытия
        close_error_btn = ttk.Button(
            buttons_frame,
            text="❌ Закрыть",
            command=self.error_window.destroy
        )
        close_error_btn.pack(side=tk.RIGHT)
    
    def update_error_logs(self):
        """Обновление логов ошибок"""
        if not hasattr(self, 'error_text'):
            return
        
        # Очищаем текстовое поле
        self.error_text.delete(1.0, tk.END)
        
        # Собираем все ошибки с временными метками
        all_errors = []
        
        for download_id, status in self.download_status.items():
            errors = status.get('errors', [])
            timestamp = status.get('timestamp', '')
            download_type = status.get('type', 'Unknown')
            
            try:
                dt = datetime.fromisoformat(timestamp)
                time_str = dt.strftime('%Y-%m-%d %H:%M:%S')
            except:
                time_str = 'Unknown time'
            
            for error in errors:
                all_errors.append({
                    'time': time_str,
                    'type': download_type,
                    'error': error,
                    'download_id': download_id
                })
        
        # Сортируем по времени (новые сверху)
        all_errors.sort(key=lambda x: x['time'], reverse=True)
        
        # Добавляем ошибки в текстовое поле
        if not all_errors:
            self.error_text.insert(tk.END, "✅ Ошибок не найдено!\n\n")
            self.error_text.insert(tk.END, "Все загрузки выполнены успешно.")
        else:
            for i, error_info in enumerate(all_errors):
                # Заголовок ошибки
                header = f"[{error_info['time']}] {error_info['type'].upper()}\n"
                self.error_text.insert(tk.END, header, 'header')
                
                # Текст ошибки
                error_text = f"❌ {error_info['error']}\n"
                self.error_text.insert(tk.END, error_text, 'error')
                
                # ID загрузки
                id_text = f"   📄 Download ID: {error_info['download_id']}\n\n"
                self.error_text.insert(tk.END, id_text, 'info')
        
        # Настраиваем стили текста
        self.error_text.tag_configure('header', foreground='blue', font=('Courier', 9, 'bold'))
        self.error_text.tag_configure('error', foreground='red')
        self.error_text.tag_configure('info', foreground='gray')
        
        # Обновляем статистику
        if hasattr(self, 'error_stats_label'):
            total_errors = len(all_errors)
            now = datetime.now()
            recent_errors = 0
            
            for error_info in all_errors:
                try:
                    error_time = datetime.strptime(error_info['time'], '%Y-%m-%d %H:%M:%S')
                    if (now - error_time).total_seconds() < 3600:  # 1 час
                        recent_errors += 1
                except:
                    pass
            
            stats_text = f"Всего ошибок: {total_errors} | За последний час: {recent_errors}"
            self.error_stats_label.configure(text=stats_text)
    
    def clear_error_logs(self):
        """Очистка логов ошибок"""
        result = messagebox.askyesno(
            "Подтверждение",
            "Очистить все логи ошибок?\nЭто действие нельзя отменить."
        )
        
        if result:
            # Очищаем ошибки во всех статусах загрузок
            for status in self.download_status.values():
                status['errors'] = []
            
            self.save_download_state()
            self.update_error_logs()
            messagebox.showinfo("Успех", "Логи ошибок очищены")
    
    def save_error_logs(self):
        """Сохранение логов ошибок в файл"""
        try:
            from tkinter import filedialog
            
            # Диалог сохранения файла
            filename = filedialog.asksaveasfilename(
                title="Сохранить логи ошибок",
                defaultextension=".log",
                filetypes=[
                    ("Log files", "*.log"),
                    ("Text files", "*.txt"),
                    ("All files", "*.*")
                ]
            )
            
            if not filename:
                return
            
            # Получаем текст из поля
            log_content = self.error_text.get(1.0, tk.END)
            
            # Добавляем заголовок
            full_content = f"Kemono.cr Parser - Логи ошибок\n"
            full_content += f"Сгенерировано: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            full_content += "=" * 50 + "\n\n"
            full_content += log_content
            
            # Сохраняем в файл
            with open(filename, 'w', encoding='utf-8') as f:
                f.write(full_content)
            
            messagebox.showinfo("Успех", f"Логи сохранены в файл:\n{filename}")
            
        except Exception as e:
            messagebox.showerror("Ошибка", f"Не удалось сохранить логи:\n{str(e)}")
    
    # === МЕТОДЫ СОХРАНЕНИЯ СОСТОЯНИЯ ===
    
    def load_download_state(self):
        """Загрузка сохраненного состояния загрузок"""
        try:
            state_file = Path("download_state.json")
            if state_file.exists():
                with open(state_file, 'r', encoding='utf-8') as f:
                    self.download_status = json.load(f)
        except Exception as e:
            print(f"Ошибка загрузки состояния: {e}")
            self.download_status = {}
    
    def save_download_state(self):
        """Сохранение состояния загрузок"""
        try:
            with open("download_state.json", 'w', encoding='utf-8') as f:
                json.dump(self.download_status, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"Ошибка сохранения состояния: {e}")

    def load_url_history(self):
        """Загрузка истории URL запросов"""
        try:
            if os.path.exists(self.history_file):
                with open(self.history_file, "r", encoding="utf-8") as f:
                    self.url_history = json.load(f)
        except Exception as e:
            print(f"Ошибка загрузки истории URL: {e}")
            self.url_history = []

    def save_url_history(self):
        """Сохранение истории URL запросов"""
        try:
            with open(self.history_file, "w", encoding="utf-8") as f:
                json.dump(self.url_history, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"Ошибка сохранения истории URL: {e}")

    def add_url_to_history(self, url):
        """Добавить URL в историю"""
        if url and url.strip():
            url = url.strip()
            # Удаляем дубликаты
            if url in self.url_history:
                self.url_history.remove(url)
            # Добавляем в начало
            self.url_history.insert(0, url)
            # Ограничиваем количество
            self.url_history = self.url_history[:self.max_history_items]
            self.save_url_history()

    def show_history_menu(self):
        """Показать меню истории URL"""
        if not self.url_history:
            return

        # Создаем всплывающее меню
        menu = tk.Menu(self.root, tearoff=0)

        for i, url in enumerate(self.url_history):
            # Сокращаем длинные URL для отображения
            display_url = url
            if len(display_url) > 60:
                display_url = display_url[:57] + "..."

            menu.add_command(
                label=f"{i+1}. {display_url}",
                command=lambda u=url: self.select_history_url(u)
            )

        # Показываем меню рядом с кнопкой истории
        try:
            menu.post(self.history_btn.winfo_rootx(), self.history_btn.winfo_rooty() + self.history_btn.winfo_height())
        except:
            # Если не удается получить координаты, показываем в центре экрана
            menu.post(self.root.winfo_screenwidth() // 2, self.root.winfo_screenheight() // 2)

    def select_history_url(self, url):
        """Выбрать URL из истории"""
        if self.url_placeholder_active:
            self.url_entry.delete(0, tk.END)
            self.url_entry.configure(foreground='black')
            self.url_placeholder_active = False

        self.url_var.set(url)
        self.url_entry.configure(foreground='black')
    
    def run(self):
        """Запуск GUI"""
        try:
            self.root.mainloop()
        finally:
            # Сохраняем состояние при выходе
            self.save_download_state()
            
            # Закрываем парсер
            if self.parser:
                self.parser.close()


def main():
    """Главная функция"""
    app = KemonoGUI()
    app.run()


if __name__ == "__main__":
    main()
