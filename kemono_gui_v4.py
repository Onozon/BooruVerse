#!/usr/bin/env python3
"""
Графический интерфейс для Kemono.cr Parser v4
Создан на основе PyQt6 с расширенной системой кэширования и встроенным браузером
"""

import sys
import os
import json
import re
import time
import threading
import queue
from pathlib import Path
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlparse, urljoin
import hashlib

# PyQt6 импорты
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QGridLayout,
    QLabel, QPushButton, QLineEdit, QTextEdit, QProgressBar,
    QListWidget, QListWidgetItem, QFrame, QScrollArea, QSplitter,
    QMessageBox, QMenuBar, QMenu, QStatusBar, QCheckBox, QGroupBox,
    QSizePolicy, QComboBox, QDialog, QDialogButtonBox, QTabWidget,
    QListView, QTreeWidget, QTreeWidgetItem, QHeaderView
)
from PyQt6.QtGui import QPixmap, QPainter, QMouseEvent
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtCore import (
    Qt, QThread, pyqtSignal, QTimer, QUrl, QSize, QRect
)
from PyQt6.QtGui import (
    QPixmap, QImage, QIcon, QFont, QPainter, QColor, QPalette
)

# HTTP и парсинг
import requests
from PIL import Image
from bs4 import BeautifulSoup

# Импорт нашего парсера
from kemono_parser import KemonoParser, Artist
from interactive_downloader import create_artist_from_url


class MediaViewer(QMainWindow):
    """Окно для просмотра медиа файлов"""

    # Сигналы для обновления GUI из другого потока
    full_image_loaded = pyqtSignal(object)  # Передаем QPixmap

    def __init__(self, media_item, parent=None):
        super().__init__(parent)
        self.media_item = media_item
        self.is_full_image_loaded = False  # Флаг состояния загрузки
        self.original_pixmap = None  # Храним оригинальное изображение

        # Подключаем сигналы
        self.full_image_loaded.connect(self.display_full_image)

        # Настраиваем окно
        filename = Path(media_item['filename']).name
        self.setWindowTitle(f"Просмотр: {filename}")
        self.setGeometry(100, 100, 800, 600)
        self.setMinimumSize(400, 300)

        # Центральный виджет
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        layout = QVBoxLayout(central_widget)

        # Label для изображения
        self.image_label = QLabel()
        self.image_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.image_label.setStyleSheet("QLabel { background-color: #1a1a1a; }")
        self.image_label.setMinimumSize(200, 200)
        layout.addWidget(self.image_label)

        # Показываем превью сразу
        self.show_preview()

        # Запускаем загрузку полной версии в фоне
        self.load_full_image_async()

    def show_preview(self):
        """Показать превью изображение"""
        try:
            # Проверяем кэш превью
            cached_path = self.parent().get_cached_preview_path(self.media_item['url'])
            if cached_path and Path(cached_path).exists():
                pixmap = QPixmap(cached_path)
                if not pixmap.isNull():
                    print(f"[IMG] Показываем превью: {pixmap.width()}x{pixmap.height()}")
                    self.display_image(pixmap, save_original=True)
            # Если превью нет, оставляем пустое изображение
        except Exception as e:
            print(f"Ошибка загрузки превью: {e}")

    def load_full_image_async(self):
        """Асинхронная загрузка полной версии изображения"""
        print("🚀 Начинаем асинхронную загрузку полной версии")
        import threading
        thread = threading.Thread(target=self._load_full_image, daemon=True)
        thread.start()

    def _load_full_image(self):
        """Загрузка полной версии в фоне"""
        try:
            # Получаем правильный путь для файла
            correct_filepath = self._get_correct_filepath()
            print(f"[SEARCH] Проверяем файл: {correct_filepath}")

            if correct_filepath.exists():
                print(f"[OK] Файл существует: {correct_filepath}")
                # Файл уже существует, загружаем его напрямую
                pixmap = QPixmap(str(correct_filepath))
                if not pixmap.isNull():
                    print(f"[IMG] Загружаем существующий файл: {pixmap.width()}x{pixmap.height()}")
                    # Отправляем сигнал для обновления GUI
                    self.full_image_loaded.emit(pixmap)
                    return
                else:
                    print(f"[ERROR] Файл поврежден, удаляем: {correct_filepath}")
                    # Файл поврежден, удаляем и скачиваем заново
                    correct_filepath.unlink(missing_ok=True)

            print(f"[DOWNLOAD] Скачиваем файл: {correct_filepath}")
            # Скачиваем полную версию
            response = requests.get(self.media_item['url'], timeout=30, stream=True)
            if response.status_code == 200:
                # Создаем директорию если не существует
                correct_filepath.parent.mkdir(parents=True, exist_ok=True)

                # Читаем и сохраняем изображение
                with open(correct_filepath, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)

                print(f"💾 Файл сохранен: {correct_filepath}")
                # Загружаем сохраненное изображение
                pixmap = QPixmap(str(correct_filepath))

                # Обновляем GUI в главном потоке
                if not pixmap.isNull():
                    print(f"[IMG] Отображаем скачанный файл: {pixmap.width()}x{pixmap.height()}")
                    self.full_image_loaded.emit(pixmap)
                else:
                    print(f"[ERROR] Не удалось загрузить скачанный файл")
            else:
                print(f"[ERROR] Ошибка скачивания: HTTP {response.status_code}")

        except Exception as e:
            print(f"[ERROR] Ошибка загрузки полной версии медиа: {e}")

    def _get_correct_filepath(self):
        """Получить правильный путь для файла"""
        from pathlib import Path
        import re

        # Получаем информацию из media_item
        filename = Path(self.media_item['filename']).name
        post_title = self.media_item.get('post_title', 'Неизвестно')
        post_id = self.media_item.get('post_id', 'неизвестен')

        print(f"[FILE] Имя файла: {filename}")
        print(f"[POST] Название поста: {post_title}")
        print(f"[ID] ID поста: {post_id}")

        # Получаем информацию об авторе из родительского окна
        parent = self.parent()
        if hasattr(parent, 'current_artist') and parent.current_artist:
            author_name = f"{parent.current_artist.service}_{parent.current_artist.name}_{parent.current_artist.id}"
            print(f"[AUTHOR] Автор: {author_name}")
        else:
            author_name = "неизвестный_автор"
            print(f"[UNKNOWN] Автор неизвестен")

        # Создаем безопасное название поста
        safe_title = re.sub(r'[<>:"/\\|?*]', '_', post_title[:50])
        print(f"[SAFE] Безопасное название: {safe_title}")

        # Формируем путь
        post_dir = Path("downloads") / author_name / safe_title
        final_path = post_dir / filename
        print(f"[TARGET] Итоговый путь: {final_path}")
        return final_path

    def display_image(self, pixmap, save_original=False):
        """Отобразить изображение с сохранением пропорций"""
        if pixmap.isNull():
            return

        # Сохраняем оригинальное изображение если нужно
        if save_original:
            self.original_pixmap = pixmap

        # Используем оригинал для масштабирования, если он есть
        source_pixmap = self.original_pixmap if self.original_pixmap else pixmap

        # Получаем размеры окна
        window_size = self.size()
        available_width = window_size.width() - 40  # Учитываем отступы
        available_height = window_size.height() - 60  # Учитываем только заголовок окна

        # Масштабируем с сохранением пропорций
        scaled_pixmap = source_pixmap.scaled(
            available_width, available_height,
            Qt.AspectRatioMode.KeepAspectRatio,
            Qt.TransformationMode.SmoothTransformation
        )

        self.image_label.setPixmap(scaled_pixmap)

    def display_full_image(self, pixmap):
        """Отобразить полную версию изображения"""
        print(f"[REPLACE] Заменяем превью на полную версию: {pixmap.width()}x{pixmap.height()}")
        print(f"[SIZE] Размеры окна: {self.size().width()}x{self.size().height()}")
        self.display_image(pixmap, save_original=True)
        self.is_full_image_loaded = True
        print("[OK] Превью заменено на полную версию")

    def resizeEvent(self, event):
        """Обработчик изменения размера окна"""
        super().resizeEvent(event)
        # Перемасштабируем изображение при изменении размера окна
        if self.original_pixmap and not self.original_pixmap.isNull():
            self.display_image(self.original_pixmap)
        elif hasattr(self, 'image_label') and self.image_label.pixmap():
            self.display_image(self.image_label.pixmap())


class KemonoGUIv4(QMainWindow):
    """Главное окно приложения Kemono.cr Parser v4 с встроенным браузером"""

    # Сигналы для обновления GUI из других потоков
    status_updated = pyqtSignal(str)
    progress_updated = pyqtSignal(int, int)  # current, total
    posts_loaded = pyqtSignal(list)
    media_loaded = pyqtSignal(list)
    artists_loaded = pyqtSignal(list, str)  # artists_list, page_type
    posts_loaded_browser = pyqtSignal(list, str)  # posts_list, page_type
    update_thumbnail_pixmap = pyqtSignal(object, object)  # label, pixmap
    update_thumbnail_text = pyqtSignal(object, str)  # label, text
    download_status_updated = pyqtSignal(str)  # Детальный статус загрузки
    media_load_error = pyqtSignal(str, str)  # post_id, error_message
    open_artist_signal = pyqtSignal(object)  # artist object
    open_post_signal = pyqtSignal(object)  # post object

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Kemono.cr Parser v4 - Advanced Caching")
        self.setGeometry(100, 100, 1400, 900)
        self.setMinimumSize(800, 600)

        # Данные приложения
        self.parser = None
        self.current_artist = None
        self.all_posts = []
        self.current_page = 0
        self.posts_per_page = 50
        self.selected_post = None
        self.current_media = []
        self.media_error_post = None  # Пост, для которого произошла ошибка загрузки медиа
        self.media_checkboxes = []  # Список чекбоксов медиа элементов
        self.post_checkboxes = []   # Список чекбоксов постов

        # История URL запросов
        self.url_history = []
        self.history_file = "url_history.json"
        self.max_history_items = 20

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

        # Кэши для оптимизации
        self.preview_cache = {}  # URL -> cache_path
        self.url_validation_cache = {}  # URL -> bool

        # Расширенная система кэширования v3
        self.posts_cache_dir = self.cache_dir / "posts_metadata"
        self.media_cache_dir = self.cache_dir / "media_metadata"
        self.posts_cache_dir.mkdir(exist_ok=True)
        self.media_cache_dir.mkdir(exist_ok=True)

        # Кэши мета-данных
        self.posts_metadata_cache = {}  # artist_id -> posts_data
        self.media_metadata_cache = {}  # post_id -> media_data
        self.artist_cache_status = {}   # artist_id -> {'complete': bool, 'last_updated': datetime}

        # Кэши состояния скачиваний
        self.downloaded_files_cache = set()  # Множество путей скачанных файлов

        # Система повторных попыток
        self.failed_previews = set()
        self.retry_thread = None
        self.retry_active = False

        # Настройки типов файлов для скачивания
        self.file_types_settings = {
            'images': True,      # Картинки: jpg, jpeg, png, gif, webp, tiff, bmp
            'videos': True,      # Видео: mp4, avi, mkv, mov, wmv, webm
            'archives': True,    # Архивы: zip, rar, 7z, tar, gz
            'documents': True    # Прочие: psd, docx, doc, pdf, txt и т.д.
        }

        # Инициализация интерфейса
        self.setup_ui()
        self.setup_connections()
        self.load_initial_state()

    def setup_ui(self):
        """Настройка пользовательского интерфейса с вкладками"""
        # Центральный виджет
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        # Основной layout
        main_layout = QVBoxLayout(central_widget)

        # Создаем виджет вкладок
        self.tab_widget = QTabWidget()
        main_layout.addWidget(self.tab_widget)

        # Вкладка браузера
        self.setup_browser_tab()

        # Вкладка просмотра автора
        self.setup_viewer_tab()

        # Статус бар
        self.setup_status_bar()

        # Меню
        self.setup_menu()

    def setup_browser_tab(self):
        """Настройка вкладки браузера"""
        browser_widget = QWidget()
        browser_layout = QHBoxLayout(browser_widget)

        # Боковое меню
        self.setup_browser_sidebar(browser_layout)

        # Основная область браузера
        self.setup_browser_main_area(browser_layout)

        self.tab_widget.addTab(browser_widget, "Браузер")

    def setup_viewer_tab(self):
        """Настройка вкладки просмотра автора"""
        viewer_widget = QWidget()
        viewer_layout = QVBoxLayout(viewer_widget)

        # Верхняя панель управления (с полями автора и поста)
        self.setup_top_panel(viewer_layout)

        # Основная область просмотра (из v3)
        self.setup_viewer_main_area(viewer_layout)

        self.tab_widget.addTab(viewer_widget, "Просмотр автора")

    def setup_browser_sidebar(self, parent_layout):
        """Настройка бокового меню браузера"""
        sidebar = QWidget()
        sidebar.setFixedWidth(200)
        sidebar.setStyleSheet("background-color: #f8f9fa; border-right: 1px solid #dee2e6;")
        sidebar_layout = QVBoxLayout(sidebar)

        # Заголовок
        title_label = QLabel("Навигация")
        title_label.setStyleSheet("font-weight: bold; font-size: 14px; margin: 10px;")
        sidebar_layout.addWidget(title_label)

        # Раздел Artists
        artists_label = QLabel("Artists")
        artists_label.setStyleSheet("font-weight: bold; margin: 5px 10px;")
        sidebar_layout.addWidget(artists_label)

        # Кнопки для Artists
        self.artists_buttons = {}
        self.current_search_type = "artists"  # Текущий тип поиска
        self.current_search_url = "https://kemono.cr/artists"  # Текущий URL для поиска

        artists_urls = {
            "Поиск": "https://kemono.cr/artists",
            "Недавние": "https://kemono.cr/artists/updated",
            "Случайный": "https://kemono.cr/artists/random"
        }

        for name, url in artists_urls.items():
            btn = QPushButton(name)
            btn.setStyleSheet("""
                QPushButton {
                    text-align: left;
                    padding: 5px 10px;
                    border: none;
                    border-radius: 3px;
                    margin: 2px;
                }
                QPushButton:hover {
                    background-color: #e9ecef;
                }
            """)
            # Меняем тип поиска вместо навигации
            btn.clicked.connect(lambda checked, n=name, u=url: self.set_search_type("artists", n, u))
            sidebar_layout.addWidget(btn)
            self.artists_buttons[name] = btn

        # Раздел Posts
        posts_label = QLabel("Posts")
        posts_label.setStyleSheet("font-weight: bold; margin: 15px 10px 5px;")
        sidebar_layout.addWidget(posts_label)

        # Кнопки для Posts
        self.posts_buttons = {}
        posts_urls = {
            "Поиск": "https://kemono.cr/posts",
            "Популярные": "https://kemono.cr/posts/popular",
            "Тэги": "https://kemono.cr/posts/tags",
            "Случайный": "https://kemono.cr/posts/random"
        }

        for name, url in posts_urls.items():
            btn = QPushButton(name)
            btn.setStyleSheet("""
                QPushButton {
                    text-align: left;
                    padding: 5px 10px;
                    border: none;
                    border-radius: 3px;
                    margin: 2px;
                }
                QPushButton:hover {
                    background-color: #e9ecef;
                }
            """)
            # Меняем тип поиска вместо навигации
            btn.clicked.connect(lambda checked, n=name, u=url: self.set_search_type("posts", n, u))
            sidebar_layout.addWidget(btn)
            self.posts_buttons[name] = btn

        sidebar_layout.addStretch()
        parent_layout.addWidget(sidebar)

    def set_search_type(self, search_type, button_name, url):
        """Установка типа поиска"""
        print(f"[NAV] Переключение на тип поиска: {search_type}, кнопка: {button_name}, URL: {url}")
        self.current_search_type = search_type
        self.current_search_url = url

        # Обновляем интерфейс - показываем текущий тип поиска
        if hasattr(self, 'search_input'):
            placeholder_text = f"Поиск {search_type}..."
            self.search_input.setPlaceholderText(placeholder_text)
            print(f"[UI] Обновлен placeholder: {placeholder_text}")

        # Логируем изменение состояния
        print(f"[STATE] Текущий тип поиска: {self.current_search_type}")
        print(f"[STATE] Текущий URL: {self.current_search_url}")

    def setup_browser_main_area(self, parent_layout):
        """Настройка основной области браузера"""
        main_area = QWidget()
        main_layout = QVBoxLayout(main_area)

        # Панель поиска
        search_panel = QWidget()
        search_layout = QHBoxLayout(search_panel)

        self.browser_search_input = QLineEdit()
        self.browser_search_input.setPlaceholderText("Поиск авторов или постов...")
        search_layout.addWidget(self.browser_search_input)

        self.browser_search_btn = QPushButton("Искать")
        self.browser_search_btn.clicked.connect(self.browser_search)
        search_layout.addWidget(self.browser_search_btn)

        main_layout.addWidget(search_panel)

        # Область результатов
        self.browser_results_area = QScrollArea()
        self.browser_results_widget = QWidget()
        self.browser_results_layout = QVBoxLayout(self.browser_results_widget)

        self.browser_results_area.setWidget(self.browser_results_widget)
        self.browser_results_area.setWidgetResizable(True)
        main_layout.addWidget(self.browser_results_area)

        parent_layout.addWidget(main_area)


    def setup_viewer_main_area(self, parent_layout):
        """Настройка основной области просмотра (адаптировано из v3)"""
        # Основной layout для разделителя
        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Левая панель - посты
        self.setup_posts_panel(splitter)

        # Правая панель - медиа
        self.setup_media_panel(splitter)

        # Настраиваем пропорции разделителя
        splitter.setSizes([int(self.width() * 0.4), int(self.width() * 0.6)])

        parent_layout.addWidget(splitter)

    def browser_navigate(self, url):
        """Навигация в браузере"""
        print(f"[NAV] Навигация к: {url}")

        # Определяем тип страницы и обрабатываем соответствующим образом
        if "/artists" in url:
            self.handle_artists_navigation(url)
        elif "/posts" in url:
            self.handle_posts_navigation(url)
        else:
            print(f"[NAV] Неизвестный тип страницы: {url}")

    def handle_artists_navigation(self, url):
        """Обработка навигации по страницам авторов"""
        print(f"[ARTISTS] Обработка страницы: {url}")

        # Определяем тип страницы авторов
        if url.endswith("/artists"):
            # Основная страница авторов
            self.load_artists_page("main", limit=50)
        elif url.endswith("/artists/updated"):
            # Недавние обновления
            self.load_artists_page("updated", limit=50)
        elif url.endswith("/artists/random"):
            # Случайные авторы - загружаем и открываем первого
            self.load_artists_page_random_viewer(limit=1)
        else:
            print(f"[ARTISTS] Неизвестный тип страницы авторов: {url}")

    def handle_posts_navigation(self, url):
        """Обработка навигации по страницам постов"""
        print(f"[POSTS] Обработка страницы: {url}")

        # Определяем тип страницы постов
        if url.endswith("/posts"):
            # Основная страница постов
            self.load_posts_page("main", limit=50)
        elif url.endswith("/posts/popular"):
            # Популярные посты
            self.load_posts_page("popular", limit=50)
        elif url.endswith("/posts/tags"):
            # Посты по тэгам
            self.load_posts_page("tags", limit=50)
        elif url.endswith("/posts/random"):
            # Случайные посты - загружаем и открываем первый
            self.load_posts_page_random_viewer(limit=1)
        else:
            print(f"[POSTS] Неизвестный тип страницы постов: {url}")

    def load_artists_page_random_viewer(self, limit=1):
        """Загрузка случайных авторов и открытие первого в просмотре"""
        print(f"[RANDOM ARTIST] Загрузка случайного автора...")

        def load_worker():
            try:
                if not self.parser:
                    self.parser = KemonoParser(use_selenium=True, headless=True)

                # Получаем случайных авторов
                artists = self.parser.get_artists_page("https://kemono.cr/artists/random", limit=limit)
                if artists:
                    first_artist = artists[0]
                    print(f"[RANDOM ARTIST] Открываем автора: {first_artist.name}")
                    # Отправляем сигнал для открытия в просмотре
                    self.open_artist_signal.emit(first_artist)
                else:
                    print("[RANDOM ARTIST] Не найдено случайных авторов")
                    self.status_updated.emit("Не найдено случайных авторов")

            except Exception as e:
                print(f"[RANDOM ARTIST] Ошибка: {e}")
                self.status_updated.emit(f"Ошибка загрузки случайного автора: {str(e)}")

        thread = threading.Thread(target=load_worker, daemon=True)
        thread.start()

    def load_posts_page_random_viewer(self, limit=1):
        """Загрузка случайных постов и открытие первого в просмотре"""
        print(f"[RANDOM POST] Загрузка случайного поста...")

        def load_worker():
            try:
                if not self.parser:
                    self.parser = KemonoParser(use_selenium=True, headless=True)

                # Получаем случайные посты
                posts = self.parser.get_posts_page("https://kemono.cr/posts/random", limit=limit)
                if posts:
                    first_post = posts[0]
                    print(f"[RANDOM POST] Открываем пост: {first_post.title}")
                    # Отправляем сигнал для открытия в просмотре
                    self.open_post_signal.emit(first_post)
                else:
                    print("[RANDOM POST] Не найдено случайных постов")
                    self.status_updated.emit("Не найдено случайных постов")

            except Exception as e:
                print(f"[RANDOM POST] Ошибка: {e}")
                self.status_updated.emit(f"Ошибка загрузки случайного поста: {str(e)}")

        thread = threading.Thread(target=load_worker, daemon=True)
        thread.start()

    def load_posts_page(self, page_type, limit=50):
        """Загрузка страницы постов"""
        print(f"[POSTS] Загрузка страницы типа: {page_type}, лимит: {limit}")

        try:
            # Показываем индикатор загрузки
            self.status_updated.emit("Загрузка списка постов...")

            # Загружаем данные в фоновом потоке
            self.load_posts_async(page_type, limit)

        except Exception as e:
            print(f"[POSTS] Ошибка загрузки страницы: {e}")
            self.status_updated.emit(f"Ошибка загрузки: {str(e)}")

    def load_posts_async(self, page_type, limit):
        """Асинхронная загрузка списка постов"""
        def load_worker():
            try:
                # Проверяем, что парсер инициализирован
                if not self.parser:
                    print("[POSTS] Ошибка: парсер не инициализирован")
                    self.status_updated.emit("Ошибка: парсер не инициализирован")
                    return

                posts = []

                # Определяем URL страницы в зависимости от типа
                page_urls = {
                    "main": "https://kemono.cr/posts",
                    "popular": "https://kemono.cr/posts/popular",
                    "tags": "https://kemono.cr/posts/tags",
                    "random": "https://kemono.cr/posts/random"
                }

                if page_type in page_urls:
                    page_url = page_urls[page_type]
                    print(f"[POSTS] Загружаем страницу: {page_url} (лимит: {limit})...")
                    posts = self.parser.get_posts_page(page_url, limit=limit)
                else:
                    print(f"[POSTS] Неизвестный тип страницы: {page_type}")
                    self.status_updated.emit(f"Неизвестный тип страницы: {page_type}")
                    return

                if not posts:
                    print("[POSTS] Не удалось загрузить посты")
                    self.status_updated.emit("Не удалось загрузить посты")
                    return

                print(f"[POSTS] Загружено {len(posts)} постов типа '{page_type}'")

                # Отправляем результаты в главный поток
                self.posts_loaded_browser.emit(posts, page_type)

            except Exception as e:
                print(f"[POSTS] Ошибка в фоне: {e}")
                self.status_updated.emit(f"Ошибка загрузки постов: {str(e)}")

        # Запускаем в отдельном потоке
        thread = threading.Thread(target=load_worker, daemon=True)
        thread.start()

    def load_artists_page(self, page_type, limit=50):
        """Загрузка страницы авторов"""
        print(f"[ARTISTS] Загрузка страницы типа: {page_type}, лимит: {limit}")

        try:
            # Показываем индикатор загрузки
            self.status_updated.emit("Загрузка списка авторов...")

            # Загружаем данные в фоновом потоке
            self.load_artists_async(page_type, limit)

        except Exception as e:
            print(f"[ARTISTS] Ошибка загрузки страницы: {e}")
            self.status_updated.emit(f"Ошибка загрузки: {str(e)}")

    def load_artists_async(self, page_type, limit):
        """Асинхронная загрузка списка авторов"""
        def load_worker():
            try:
                # Проверяем, что парсер инициализирован
                if not self.parser:
                    print("[ARTISTS] Ошибка: парсер не инициализирован")
                    self.status_updated.emit("Ошибка: парсер не инициализирован")
                    return

                artists = []

                # Определяем URL страницы в зависимости от типа
                page_urls = {
                    "main": "https://kemono.cr/artists",
                    "updated": "https://kemono.cr/artists/updated",
                    "random": "https://kemono.cr/artists/random"
                }

                if page_type in page_urls:
                    page_url = page_urls[page_type]
                    print(f"[ARTISTS] Загружаем страницу: {page_url} (лимит: {limit})...")
                    artists = self.parser.get_artists_page(page_url, limit=limit)
                else:
                    print(f"[ARTISTS] Неизвестный тип страницы: {page_type}")
                    self.status_updated.emit(f"Неизвестный тип страницы: {page_type}")
                    return

                if not artists:
                    print("[ARTISTS] Не удалось загрузить авторов")
                    self.status_updated.emit("Не удалось загрузить авторов")
                    return

                print(f"[ARTISTS] Загружено {len(artists)} авторов типа '{page_type}'")

                # Отправляем результаты в главный поток
                self.artists_loaded.emit(artists, page_type)

            except Exception as e:
                print(f"[ARTISTS] Ошибка в фоне: {e}")
                self.status_updated.emit(f"Ошибка загрузки авторов: {str(e)}")

        # Запускаем в отдельном потоке
        thread = threading.Thread(target=load_worker, daemon=True)
        thread.start()

    def browser_search(self):
        """Поиск в браузере с учетом текущего типа"""
        query = self.browser_search_input.text().strip()
        if query:
            print(f"[SEARCH] Начинаем поиск '{query}' в разделе {self.current_search_type}")
            print(f"[SEARCH] Используем URL: {self.current_search_url}")

            if self.current_search_type == "artists":
                self.search_artists(query)
            elif self.current_search_type == "posts":
                self.search_posts(query)
            else:
                print(f"[SEARCH] Неизвестный тип поиска: {self.current_search_type}")
                self.status_updated.emit(f"Неизвестный тип поиска: {self.current_search_type}")

    def search_artists(self, query):
        """Поиск авторов по имени или ID"""
        print(f"[SEARCH] Начинаем поиск авторов по запросу: {query}")

        # Показываем статус загрузки
        self.status_updated.emit(f"Поиск авторов: {query}...")

        # Выполняем поиск в фоновом потоке
        self.search_artists_async(query)

    def search_artists_async(self, query):
        """Асинхронный поиск авторов на странице /artists"""
        def search_worker():
            try:
                # Проверяем, что парсер инициализирован
                if not self.parser:
                    print("[SEARCH] Ошибка: парсер не инициализирован")
                    self.status_updated.emit("Ошибка: парсер не инициализирован")
                    return

                print(f"[SEARCH] Выполняем поиск авторов по запросу '{query}' используя URL: {self.current_search_url}")

                # Используем Selenium для поиска (HTTP не работает из-за защиты)
                print(f"[SEARCH] Вызываем Selenium поиск с query='{query}' и URL='{self.current_search_url}'")
                found_artists = self.parser.search_artists_selenium(query, limit=100, search_url=self.current_search_url)
                print(f"[SEARCH] Метод вернул {len(found_artists) if found_artists else 0} результатов")

                if found_artists is None:
                    print("[SEARCH] Поиск вернул None - возможно ошибка в парсере")
                    self.status_updated.emit("Ошибка выполнения поиска")
                    return

                print(f"[SEARCH] Найдено {len(found_artists)} авторов по запросу '{query}'")

                # Отправляем результаты в главный поток
                self.artists_loaded.emit(found_artists, "search")

            except Exception as e:
                print(f"[SEARCH] Ошибка поиска: {e}")
                self.status_updated.emit(f"Ошибка поиска: {str(e)}")

        # Запускаем в отдельном потоке
        thread = threading.Thread(target=search_worker, daemon=True)
        thread.start()

    def search_posts_async(self, query):
        """Асинхронный поиск постов"""
        def search_worker():
            try:
                # Проверяем, что парсер инициализирован
                if not self.parser:
                    print("[SEARCH] Ошибка: парсер не инициализирован")
                    self.status_updated.emit("Ошибка: парсер не инициализирован")
                    return

                print(f"[SEARCH] Выполняем поиск постов по запросу '{query}' используя URL: {self.current_search_url}")

                # Используем Selenium для поиска постов (HTTP не работает из-за защиты)
                print(f"[SEARCH] Вызываем Selenium поиск постов с query='{query}' и URL='{self.current_search_url}'")
                found_posts = self.parser.search_posts_selenium(query, limit=50, search_url=self.current_search_url)
                print(f"[SEARCH] Метод вернул {len(found_posts) if found_posts else 0} результатов")

                if found_posts is None:
                    print("[SEARCH] Поиск постов вернул None - возможно ошибка в парсере")
                    self.status_updated.emit("Ошибка выполнения поиска постов")
                    return

                if not found_posts:
                    print("[SEARCH] Посты по запросу '{query}' не найдены")
                    self.status_updated.emit(f"Посты по запросу '{query}' не найдены")
                    return

                # Отправляем результаты в главный поток
                self.posts_loaded_browser.emit(found_posts, "search")

            except Exception as e:
                print(f"[SEARCH] Ошибка поиска постов: {e}")
                self.status_updated.emit(f"Ошибка поиска постов: {str(e)}")

        # Запускаем в отдельном потоке
        thread = threading.Thread(target=search_worker, daemon=True)
        thread.start()

    def load_artist_from_url(self):
        """Загрузка автора из URL"""
        url = self.url_entry.text().strip()
        if url:
            print(f"[AUTHOR] Загрузка автора: {url}")
            # Переключаемся на вкладку просмотра
            self.tab_widget.setCurrentIndex(1)
            # Запускаем загрузку постов автора
            self.load_artist_posts()

    def load_post_from_url(self):
        """Загрузка поста из URL"""
        url = self.post_url_input.text().strip()
        if url:
            print(f"[POST] Загрузка поста: {url}")
            # Переключаемся на вкладку просмотра
            self.tab_widget.setCurrentIndex(1)

            # Запускаем загрузку в отдельном потоке
            def load_worker():
                try:
                    if not self.parser:
                        self.parser = KemonoParser(use_selenium=True, headless=True)

                    # Получаем детали поста
                    post = self.parser.get_post_details(url)
                    if post:
                        print(f"[POST] Пост загружен: {post.title}")
                        # Отправляем пост в основной поток
                        self.posts_loaded.emit([post])
                        self.status_updated.emit(f"Загружен пост: {post.title}")
                    else:
                        print(f"[POST] Не удалось загрузить пост: {url}")
                        self.status_updated.emit("Не удалось загрузить пост")

                except Exception as e:
                    print(f"[POST] Ошибка загрузки поста: {e}")
                    self.status_updated.emit(f"Ошибка загрузки поста: {str(e)}")

            thread = threading.Thread(target=load_worker, daemon=True)
            thread.start()

    def create_artist_card(self, artist_data):
        """Создание карточки автора для браузера"""
        card = QWidget()
        card.setStyleSheet("""
            QWidget {
                border: 1px solid #dee2e6;
                border-radius: 5px;
                background-color: white;
                margin: 5px;
                padding: 10px;
            }
            QWidget:hover {
                background-color: #f8f9fa;
            }
        """)
        card_layout = QVBoxLayout(card)

        # Информация об авторе
        # Поддержка как словарей, так и объектов Artist
        if hasattr(artist_data, 'name'):
            name = artist_data.name
        else:
            name = artist_data.get('name', 'Неизвестный автор')

        if hasattr(artist_data, 'service'):
            service = artist_data.service
        else:
            service = artist_data.get('service', 'Неизвестно')

        if hasattr(artist_data, 'updated'):
            updated = artist_data.updated
        else:
            updated = artist_data.get('updated', 'Неизвестно')

        name_label = QLabel(f"{name}")
        name_label.setStyleSheet("font-weight: bold; font-size: 14px;")
        card_layout.addWidget(name_label)

        service_label = QLabel(f"Сервис: {service}")
        service_label.setStyleSheet("color: #6c757d; font-size: 12px;")
        card_layout.addWidget(service_label)

        updated_label = QLabel(f"Обновлено: {updated}")
        updated_label.setStyleSheet("color: #6c757d; font-size: 12px;")
        card_layout.addWidget(updated_label)

        # Кнопки действий
        buttons_layout = QHBoxLayout()

        # Кнопка открытия автора
        open_btn = QPushButton("Открыть")
        open_btn.setStyleSheet("""
            QPushButton {
                background-color: #007bff;
                color: white;
                border: none;
                padding: 5px 10px;
                border-radius: 3px;
            }
            QPushButton:hover {
                background-color: #0056b3;
            }
        """)
        open_btn.clicked.connect(lambda: self.open_artist_in_viewer(artist_data))
        buttons_layout.addWidget(open_btn)

        # Кнопка копирования ссылки
        copy_btn = QPushButton("Копировать")
        copy_btn.setStyleSheet("""
            QPushButton {
                background-color: #6c757d;
                color: white;
                border: none;
                padding: 5px 10px;
                border-radius: 3px;
            }
            QPushButton:hover {
                background-color: #545b62;
            }
        """)
        copy_btn.clicked.connect(lambda: self.copy_artist_url(artist_data))
        buttons_layout.addWidget(copy_btn)

        buttons_layout.addStretch()
        card_layout.addLayout(buttons_layout)

        return card

    def create_post_card(self, post_data):
        """Создание карточки поста для браузера"""
        card = QWidget()
        card.setStyleSheet("""
            QWidget {
                border: 1px solid #dee2e6;
                border-radius: 5px;
                background-color: white;
                margin: 5px;
                padding: 10px;
            }
            QWidget:hover {
                background-color: #f8f9fa;
            }
        """)
        card_layout = QVBoxLayout(card)

        # Заголовок поста
        title = post_data.get('title', 'Без заголовка')[:50]
        if len(post_data.get('title', '')) > 50:
            title += "..."

        title_label = QLabel(f"{title}")
        title_label.setStyleSheet("font-weight: bold; font-size: 14px;")
        card_layout.addWidget(title_label)

        # Информация об авторе
        author_label = QLabel(f"Автор: {post_data.get('author', 'Неизвестный автор')}")
        author_label.setStyleSheet("color: #6c757d; font-size: 12px;")
        card_layout.addWidget(author_label)

        # Дата публикации
        date_label = QLabel(f"Дата: {post_data.get('date', 'Неизвестно')}")
        date_label.setStyleSheet("color: #6c757d; font-size: 12px;")
        card_layout.addWidget(date_label)

        # Кнопки действий
        buttons_layout = QHBoxLayout()

        # Кнопка открытия поста
        open_btn = QPushButton("Открыть")
        open_btn.setStyleSheet("""
            QPushButton {
                background-color: #28a745;
                color: white;
                border: none;
                padding: 5px 10px;
                border-radius: 3px;
            }
            QPushButton:hover {
                background-color: #1e7e34;
            }
        """)
        open_btn.clicked.connect(lambda: self.open_post_in_viewer(post_data))
        buttons_layout.addWidget(open_btn)

        # Кнопка копирования ссылки
        copy_btn = QPushButton("Копировать")
        copy_btn.setStyleSheet("""
            QPushButton {
                background-color: #6c757d;
                color: white;
                border: none;
                padding: 5px 10px;
                border-radius: 3px;
            }
            QPushButton:hover {
                background-color: #545b62;
            }
        """)
        copy_btn.clicked.connect(lambda: self.copy_post_url(post_data))
        buttons_layout.addWidget(copy_btn)

        buttons_layout.addStretch()
        card_layout.addLayout(buttons_layout)

        return card

    def open_artist_in_viewer(self, artist_data):
        """Открытие автора в вкладке просмотра"""
        # Поддержка как словарей, так и объектов Artist
        if hasattr(artist_data, 'url'):
            url = artist_data.url
        else:
            url = artist_data.get('url', '')

        if url:
            self.url_entry.setText(url)
            self.tab_widget.setCurrentIndex(1)
            self.load_artist_from_url()
            print(f"[AUTHOR] Открытие автора в просмотре: {url}")

    def copy_artist_url(self, artist_data):
        """Копирование ссылки на автора"""
        # Поддержка как словарей, так и объектов Artist
        if hasattr(artist_data, 'url'):
            url = artist_data.url
        else:
            url = artist_data.get('url', '')

        if url:
            # Имитируем копирование в буфер обмена
            print(f"[COPY] Скопирована ссылка на автора: {url}")
            # TODO: Реализовать реальное копирование в буфер обмена

    def open_post_in_viewer(self, post_data):
        """Открытие поста в вкладке просмотра"""
        # Поддержка как словарей, так и объектов Post
        if hasattr(post_data, 'url'):
            url = post_data.url
        else:
            url = post_data.get('url', '')

        if url:
            self.post_url_input.setText(url)
            self.tab_widget.setCurrentIndex(1)
            self.load_post_from_url()
            print(f"[POST] Открытие поста в просмотре: {url}")

    def copy_post_url(self, post_data):
        """Копирование ссылки на пост"""
        # Поддержка как словарей, так и объектов Post
        if hasattr(post_data, 'url'):
            url = post_data.url
        else:
            url = post_data.get('url', '')

        if url:
            # Имитируем копирование в буфер обмена
            print(f"[COPY] Скопирована ссылка на пост: {url}")
            # TODO: Реализовать реальное копирование в буфер обмена

    def setup_top_panel(self, parent_layout):
        """Настройка верхней панели управления"""
        top_frame = QFrame()
        top_frame.setMaximumHeight(80)
        top_layout = QHBoxLayout(top_frame)
        top_layout.setContentsMargins(10, 5, 10, 5)

        # Левая половина экрана - поле автора
        left_panel = QWidget()
        left_layout = QHBoxLayout(left_panel)
        left_layout.setContentsMargins(0, 0, 0, 0)

        # Метка автора
        author_label = QLabel("Автор:")
        author_label.setStyleSheet("font-weight: bold;")
        left_layout.addWidget(author_label)

        # Поле URL автора
        self.url_entry = QLineEdit()
        self.url_entry.setPlaceholderText("https://kemono.cr/fanbox/user/123456")
        left_layout.addWidget(self.url_entry)

        # Кнопка истории (между полем и кнопкой загрузки)
        self.history_button = QPushButton("История")
        self.history_button.setMaximumWidth(60)
        self.history_button.setToolTip("История запросов")
        self.history_button.clicked.connect(self.show_history_menu)
        left_layout.addWidget(self.history_button)

        # Кнопка загрузки постов
        self.load_button = QPushButton("Загрузить посты")
        self.load_button.clicked.connect(self.load_artist_posts)
        self.load_button.setMaximumWidth(130)
        left_layout.addWidget(self.load_button)

        # Чекбокс очистки кэша (правее кнопки загрузки)
        self.clear_cache_checkbox = QCheckBox("Очистить кэш")
        self.clear_cache_checkbox.setToolTip("При загрузке сначала удалить кэш этого пользователя")
        left_layout.addWidget(self.clear_cache_checkbox)

        top_layout.addWidget(left_panel, stretch=1)  # Растягиваем на половину экрана

        # Разделитель между половинами
        separator = QLabel(" | ")
        separator.setStyleSheet("color: #ccc; font-size: 12px; font-weight: bold;")
        top_layout.addWidget(separator)

        # Правая половина экрана - поле поста
        right_panel = QWidget()
        right_layout = QHBoxLayout(right_panel)
        right_layout.setContentsMargins(0, 0, 0, 0)

        # Метка поста
        post_label = QLabel("Пост:")
        post_label.setStyleSheet("font-weight: bold;")
        right_layout.addWidget(post_label)

        # Поле URL поста
        self.post_url_input = QLineEdit()
        self.post_url_input.setPlaceholderText("https://kemono.cr/fanbox/user/123456/post/789")
        right_layout.addWidget(self.post_url_input)

        # Кнопка загрузки поста
        self.post_load_btn = QPushButton("Загрузить")
        self.post_load_btn.clicked.connect(self.load_post_from_url)
        self.post_load_btn.setMaximumWidth(100)
        right_layout.addWidget(self.post_load_btn)

        top_layout.addWidget(right_panel, stretch=1)  # Растягиваем на половину экрана

        parent_layout.addWidget(top_frame)

    def setup_main_area(self, parent_layout):
        """Настройка основной рабочей области (устаревший метод для совместимости)"""
        # Этот метод больше не используется в v4, так как логика перенесена в setup_viewer_main_area
        pass

    def setup_posts_panel(self, splitter):
        """Настройка панели постов"""
        posts_widget = QWidget()
        posts_layout = QVBoxLayout(posts_widget)

        # Заголовок
        posts_label = QLabel("Посты автора")
        posts_label.setStyleSheet("font-weight: bold; font-size: 14px;")
        posts_layout.addWidget(posts_label)

        # Контролы пагинации
        pagination_layout = QHBoxLayout()

        self.prev_page_btn = QPushButton("Назад")
        self.page_label = QLabel("Страница 1/1")
        self.next_page_btn = QPushButton("Вперед")

        pagination_layout.addWidget(self.prev_page_btn)
        pagination_layout.addStretch()
        pagination_layout.addWidget(self.page_label)
        pagination_layout.addStretch()
        pagination_layout.addWidget(self.next_page_btn)

        posts_layout.addLayout(pagination_layout)

        # Область прокрутки для постов
        self.posts_scroll = QScrollArea()
        self.posts_container = QWidget()
        self.posts_layout = QVBoxLayout(self.posts_container)

        self.posts_scroll.setWidget(self.posts_container)
        self.posts_scroll.setWidgetResizable(True)
        self.posts_scroll.setMinimumWidth(400)

        posts_layout.addWidget(self.posts_scroll)

        # Кнопки действий
        actions_layout = QHBoxLayout()

        # Кнопки управления постами
        self.select_all_posts_btn = QPushButton("Выбрать все")
        self.deselect_all_posts_btn = QPushButton("Снять все")
        self.download_all_btn = QPushButton("Скачать все посты")
        self.download_selected_btn = QPushButton("Скачать выбранные")

        # Кнопка выбора типов файлов
        self.file_types_btn = QPushButton("Типы файлов")
        self.file_types_btn.setToolTip("Выбрать какие типы файлов скачивать")
        self.file_types_btn.clicked.connect(self.show_file_types_dialog)

        actions_layout.addWidget(self.select_all_posts_btn)
        actions_layout.addWidget(self.deselect_all_posts_btn)
        actions_layout.addWidget(self.download_all_btn)
        actions_layout.addWidget(self.download_selected_btn)
        actions_layout.addWidget(self.file_types_btn)

        posts_layout.addLayout(actions_layout)

        splitter.addWidget(posts_widget)

    def setup_media_panel(self, splitter):
        """Настройка панели медиа"""
        media_widget = QWidget()
        media_layout = QVBoxLayout(media_widget)

        # Кнопка "Показать в Finder" (скрыта по умолчанию)
        self.show_in_finder_btn = QPushButton("Показать в Finder")
        self.show_in_finder_btn.setStyleSheet("""
            QPushButton {
                background-color: #6c757d;
                color: white;
                border: none;
                padding: 6px 12px;
                border-radius: 4px;
                font-size: 11px;
            }
            QPushButton:hover {
                background-color: #5a6268;
            }
        """)
        self.show_in_finder_btn.setVisible(False)
        self.show_in_finder_btn.clicked.connect(self.show_current_post_in_finder)
        media_layout.addWidget(self.show_in_finder_btn, alignment=Qt.AlignmentFlag.AlignRight)

        # Заголовок
        self.media_label = QLabel("Медиафайлы поста")
        self.media_label.setStyleSheet("font-weight: bold; font-size: 14px;")
        media_layout.addWidget(self.media_label)

        # Сообщение об ошибке (скрыто по умолчанию)
        self.media_error_label = QLabel("")
        self.media_error_label.setStyleSheet("color: #dc3545; font-size: 12px; padding: 5px;")
        self.media_error_label.setWordWrap(True)
        self.media_error_label.setVisible(False)
        media_layout.addWidget(self.media_error_label)

        # Кнопка повтора (скрыта по умолчанию)
        self.retry_media_btn = QPushButton("Повторить загрузку")
        self.retry_media_btn.setStyleSheet("""
            QPushButton {
                background-color: #28a745;
                color: white;
                border: none;
                padding: 8px 16px;
                border-radius: 4px;
                font-size: 12px;
            }
            QPushButton:hover {
                background-color: #218838;
            }
        """)
        self.retry_media_btn.setVisible(False)
        self.retry_media_btn.clicked.connect(self.retry_load_media)
        media_layout.addWidget(self.retry_media_btn)

        # Область прокрутки для медиа
        self.media_scroll = QScrollArea()
        self.media_container = QWidget()
        self.media_layout = QVBoxLayout(self.media_container)

        self.media_scroll.setWidget(self.media_container)
        self.media_scroll.setWidgetResizable(True)
        self.media_scroll.setMinimumWidth(400)

        media_layout.addWidget(self.media_scroll)

        # Кнопки действий с медиа
        media_actions_layout = QHBoxLayout()

        self.select_all_media_btn = QPushButton("Выбрать все")
        self.deselect_all_media_btn = QPushButton("Снять все")
        self.download_media_btn = QPushButton("Скачать выбранные")

        media_actions_layout.addWidget(self.select_all_media_btn)
        media_actions_layout.addWidget(self.deselect_all_media_btn)
        media_actions_layout.addWidget(self.download_media_btn)

        media_layout.addLayout(media_actions_layout)

        splitter.addWidget(media_widget)


    def setup_status_bar(self):
        """Настройка статус бара"""
        self.status_bar = self.statusBar()

        # Добавляем прогресс бар в статус бар
        self.progress_bar = QProgressBar()
        self.progress_bar.setVisible(False)
        self.progress_bar.setMaximumWidth(300)
        self.status_bar.addPermanentWidget(self.progress_bar)

        self.status_bar.showMessage("Готов к работе")

    def setup_menu(self):
        """Настройка меню приложения"""
        menubar = self.menuBar()

        # Меню Файл
        file_menu = menubar.addMenu("Файл")
        exit_action = file_menu.addAction("Выход")
        exit_action.triggered.connect(self.close)

        # Меню Инструменты
        tools_menu = menubar.addMenu("Инструменты")
        clear_cache_action = tools_menu.addAction("Очистить кэш")
        clear_cache_action.triggered.connect(self.clear_cache)

        # Меню Справка
        help_menu = menubar.addMenu("Справка")
        about_action = help_menu.addAction("О программе")
        about_action.triggered.connect(self.show_about)

    def setup_connections(self):
        """Настройка сигналов и слотов"""
        # Кнопки
        self.load_button.clicked.connect(self.load_artist_posts)
        self.post_load_btn.clicked.connect(self.load_post_from_url)
        self.history_button.clicked.connect(self.show_history_menu)
        self.prev_page_btn.clicked.connect(self.prev_page)
        self.next_page_btn.clicked.connect(self.next_page)
        # Кнопки постов
        self.select_all_posts_btn.clicked.connect(self.select_all_posts)
        self.deselect_all_posts_btn.clicked.connect(self.deselect_all_posts)
        self.download_all_btn.clicked.connect(self.download_all_posts)
        self.download_selected_btn.clicked.connect(self.download_selected_posts)

        # Медиа кнопки
        self.select_all_media_btn.clicked.connect(self.select_all_media)
        self.deselect_all_media_btn.clicked.connect(self.deselect_all_media)
        self.download_media_btn.clicked.connect(self.download_selected_media)

        # Сигналы
        self.status_updated.connect(self.update_status)
        self.progress_updated.connect(self.update_progress)
        self.posts_loaded.connect(self.on_posts_loaded)
        self.media_loaded.connect(self.on_media_loaded)
        self.artists_loaded.connect(self.on_artists_loaded)
        self.posts_loaded_browser.connect(self.on_posts_loaded_browser)
        self.update_thumbnail_pixmap.connect(self.on_update_thumbnail_pixmap)
        self.update_thumbnail_text.connect(self.on_update_thumbnail_text)
        self.download_status_updated.connect(self.on_download_status_updated)
        self.media_load_error.connect(self.on_media_load_error)
        self.open_artist_signal.connect(self.open_artist_in_viewer)
        self.open_post_signal.connect(self.open_post_in_viewer)

        # URL поля
        self.url_entry.returnPressed.connect(self.load_artist_posts)
        self.post_url_input.returnPressed.connect(self.load_post_from_url)

    def load_initial_state(self):
        """Загрузка начального состояния"""
        # Инициализируем парсер для браузерной функциональности
        if not self.parser:
            self.parser = KemonoParser(use_selenium=True, headless=True)
            print("[INIT] Парсер KemonoParser инициализирован для браузера")

        self.load_url_history()
        self.load_downloaded_files_cache()  # Загружаем кэш скачанных файлов
        self.load_file_types_settings()  # Загружаем настройки типов файлов
        self.update_ui_state()

    def get_cached_preview_path(self, url, preview_type="media"):
        """Получить путь к кэшированному превью"""
        # Проверяем корректность URL
        if not url or not isinstance(url, str) or not url.strip():
            return None

        # Сначала проверяем in-memory кэш
        if url in self.preview_cache:
            cached_path = self.preview_cache[url]
            if Path(cached_path).exists():
                return cached_path

        # Если не найдено в кэше, вычисляем путь и проверяем файл на диске
        try:
            import hashlib
            filename = hashlib.md5(url.encode()).hexdigest() + ".png"

            # Выбираем директорию в зависимости от типа превью
            if preview_type == "post":
                target_dir = self.post_thumbnails_dir
            else:  # media
                target_dir = self.media_previews_dir

            cache_path = target_dir / filename

            # Проверяем существование файла
            if cache_path.exists() and cache_path.stat().st_size > 0:
                # Добавляем в кэш для будущих запросов
                self.preview_cache[url] = str(cache_path)
                return str(cache_path)

        except Exception as e:
            print(f"Ошибка проверки кэша превью для {url}: {e}")

        return None

    def cleanup_corrupted_cache(self):
        """Очистка поврежденных файлов из кэша"""
        print("🧹 Очищаем поврежденные файлы из кэша...")
        cleaned_count = 0

        for cache_dir in [self.post_thumbnails_dir, self.media_previews_dir]:
            if not cache_dir.exists():
                continue

            for filename in os.listdir(cache_dir):
                filepath = cache_dir / filename
                try:
                    # Проверяем что файл не пустой
                    if filepath.stat().st_size == 0:
                        filepath.unlink()
                        cleaned_count += 1
                        continue

                    # Проверяем что файл - корректное изображение
                    with Image.open(filepath) as img:
                        img.verify()

                except (OSError, IOError, Image.UnidentifiedImageError, RecursionError):
                    try:
                        filepath.unlink()
                        cleaned_count += 1
                    except:
                        pass

        if cleaned_count > 0:
            print(f"[CLEAN] Удалено {cleaned_count} поврежденных файлов из кэша")

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

                # Читаем данные без ограничения размера
                image_data = BytesIO()

                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:  # Проверяем, что chunk не пустой
                        image_data.write(chunk)
                    else:
                        # Пустой chunk - конец данных
                        break

                image_data.seek(0)

                # Проверяем и открываем изображение с обработкой ошибок
                try:
                    pil_image = Image.open(image_data)
                    # Проверяем что изображение корректное
                    pil_image.verify()
                    image_data.seek(0)  # Возвращаемся к началу после проверки
                    pil_image = Image.open(image_data)  # Открываем заново

                except (OSError, IOError, Image.UnidentifiedImageError, RecursionError) as img_error:
                    print(f"[ERROR] Поврежденное изображение {url}: {img_error}")
                    print(f"   Скачано: {downloaded} байт")

                    # Для поврежденных изображений просто повторяем попытку
                    if attempt < max_retries - 1:
                        print(f"   Повтор попытки {attempt + 2}/{max_retries} через {2 ** attempt} сек...")
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

    # ===== МЕТОДЫ КЭШИРОВАНИЯ МЕТА-ДАННЫХ v3 =====

    def get_artist_cache_path(self, artist_id):
        """Получить путь к файлу кэша для артиста"""
        return self.posts_cache_dir / f"{artist_id}_posts.json"

    def get_post_cache_path(self, post_id):
        """Получить путь к файлу кэша для поста"""
        return self.media_cache_dir / f"{post_id}_media.json"

    def serialize_post(self, post):
        """Преобразовать объект поста в сериализуемый словарь"""
        try:
            # Проверяем, что пост существует
            if post is None:
                return None

            # Получаем основные атрибуты поста
            post_dict = {
                'id': getattr(post, 'id', ''),
                'title': getattr(post, 'title', ''),
                'content': getattr(post, 'content', ''),
                'published': getattr(post, 'published', None),
                'date': getattr(post, 'date', None),
                'service': getattr(post, 'service', ''),
                'user': getattr(post, 'author', ''),
                'added': getattr(post, 'added', None),
                'edited': getattr(post, 'edited', None),
                'url': getattr(post, 'url', ''),
                'post_type': getattr(post, 'post_type', ''),
                'embed': getattr(post, 'embed', {}),
                'file': getattr(post, 'file', {}),
                'attachments': getattr(post, 'attachments', []),
                'files': getattr(post, 'files', []),
                'links': getattr(post, 'links', []),
                'shared_file': getattr(post, 'shared_file', False),
                'thumbnail': getattr(post, 'thumbnail', '')  # Добавлено поле превью
            }

            # Преобразуем даты в строки для JSON сериализации
            for date_field in ['published', 'date', 'added', 'edited']:
                if post_dict[date_field] is not None:
                    if hasattr(post_dict[date_field], 'isoformat'):
                        post_dict[date_field] = post_dict[date_field].isoformat()
                    elif isinstance(post_dict[date_field], str):
                        # Уже строка, оставляем как есть
                        pass
                    else:
                        # Другие типы преобразуем в строку
                        post_dict[date_field] = str(post_dict[date_field])

            return post_dict
        except Exception as e:
            print(f"[ERROR] Ошибка сериализации поста {getattr(post, 'id', 'unknown')}: {e}")
            return None

    def deserialize_post(self, post_dict):
        """Восстановить объект поста из словаря (простая заглушка)"""
        # Пока возвращаем словарь, в будущем можно создать объект Post
        return post_dict

    def save_posts_cache(self, artist_id, posts_data, is_complete=False):
        """Сохранить кэш постов артиста"""
        try:
            cache_path = self.get_artist_cache_path(artist_id)

            # Сериализуем посты
            serialized_posts = []
            for post in posts_data:
                serialized_post = self.serialize_post(post)
                if serialized_post:
                    serialized_posts.append(serialized_post)

            cache_data = {
                'artist_id': artist_id,
                'posts': serialized_posts,
                'is_complete': is_complete,
                'last_updated': datetime.now().isoformat(),
                'version': 'v3'
            }

            with open(cache_path, 'w', encoding='utf-8') as f:
                json.dump(cache_data, f, ensure_ascii=False, indent=2)

            # Обновляем статус кэша в памяти
            self.artist_cache_status[artist_id] = {
                'complete': is_complete,
                'last_updated': datetime.now()
            }

            print(f"💾 Кэш постов сохранен: {artist_id} ({len(serialized_posts)} постов)")
            return True
        except Exception as e:
            print(f"[ERROR] Ошибка сохранения кэша постов: {e}")
            import traceback
            traceback.print_exc()
            return False

    def load_posts_cache(self, artist_id):
        """Загрузить кэш постов артиста"""
        try:
            cache_path = self.get_artist_cache_path(artist_id)
            if not cache_path.exists():
                return None

            with open(cache_path, 'r', encoding='utf-8') as f:
                cache_data = json.load(f)

            # Проверяем версию кэша
            if cache_data.get('version') != 'v3':
                print(f"[WARN] Устаревший кэш для {artist_id}, будет пересоздан")
                return None

            serialized_posts = cache_data.get('posts', [])
            is_complete = cache_data.get('is_complete', False)

            # Десериализуем посты (пока возвращаем словари)
            posts_data = []
            for post_dict in serialized_posts:
                post = self.deserialize_post(post_dict)
                if post:
                    posts_data.append(post)

            # Обновляем статус кэша в памяти
            self.artist_cache_status[artist_id] = {
                'complete': is_complete,
                'last_updated': datetime.fromisoformat(cache_data.get('last_updated'))
            }

            print(f"[CACHE] Кэш постов загружен: {artist_id} ({len(posts_data)} постов)")
            return posts_data, is_complete
        except Exception as e:
            print(f"[ERROR] Ошибка загрузки кэша постов: {e}")
            import traceback
            traceback.print_exc()
            return None

    def save_media_cache(self, post_id, media_data):
        """Сохранить кэш медиа поста"""
        try:
            cache_path = self.get_post_cache_path(post_id)
            cache_data = {
                'post_id': post_id,
                'media': media_data,
                'last_updated': datetime.now().isoformat(),
                'version': 'v3'
            }

            with open(cache_path, 'w', encoding='utf-8') as f:
                json.dump(cache_data, f, ensure_ascii=False, indent=2)

            print(f"💾 Кэш медиа сохранен: {post_id} ({len(media_data)} файлов)")
            return True
        except Exception as e:
            print(f"[ERROR] Ошибка сохранения кэша медиа: {e}")
            return False

    def load_media_cache(self, post_id):
        """Загрузить кэш медиа поста"""
        try:
            cache_path = self.get_post_cache_path(post_id)
            if not cache_path.exists():
                return None

            with open(cache_path, 'r', encoding='utf-8') as f:
                cache_data = json.load(f)

            # Проверяем версию кэша
            if cache_data.get('version') != 'v3':
                print(f"[WARN] Устаревший кэш медиа для {post_id}, будет пересоздан")
                return None

            media_data = cache_data.get('media', [])
            print(f"[CACHE] Кэш медиа загружен: {post_id} ({len(media_data)} файлов)")
            return media_data
        except Exception as e:
            print(f"[ERROR] Ошибка загрузки кэша медиа: {e}")
            return None

    def load_downloaded_files_cache(self):
        """Загрузить кэш скачанных файлов"""
        try:
            cache_path = self.cache_dir / "downloaded_files.json"
            if not cache_path.exists():
                return set()

            with open(cache_path, 'r', encoding='utf-8') as f:
                downloaded_files = json.load(f)

            self.downloaded_files_cache = set(downloaded_files)
            print(f"[CACHE] Кэш скачанных файлов загружен: {len(self.downloaded_files_cache)} файлов")
            return self.downloaded_files_cache
        except Exception as e:
            print(f"[ERROR] Ошибка загрузки кэша скачанных файлов: {e}")
            return set()

    def save_downloaded_files_cache(self):
        """Сохранить кэш скачанных файлов"""
        try:
            cache_path = self.cache_dir / "downloaded_files.json"
            with open(cache_path, 'w', encoding='utf-8') as f:
                json.dump(list(self.downloaded_files_cache), f, ensure_ascii=False, indent=2)

            print(f"💾 Кэш скачанных файлов сохранен: {len(self.downloaded_files_cache)} файлов")
            return True
        except Exception as e:
            print(f"[ERROR] Ошибка сохранения кэша скачанных файлов: {e}")
            return False

    def is_file_downloaded(self, filepath):
        """Проверить, скачан ли файл"""
        return str(filepath) in self.downloaded_files_cache

    def mark_file_downloaded(self, filepath):
        """Отметить файл как скачанный"""
        self.downloaded_files_cache.add(str(filepath))
        self.save_downloaded_files_cache()

    def clear_artist_cache(self, artist_id):
        """Очистить кэш конкретного артиста"""
        try:
            # Удаляем файл кэша постов
            posts_cache_path = self.get_artist_cache_path(artist_id)
            if posts_cache_path.exists():
                posts_cache_path.unlink()
                print(f"[DELETE] Удален кэш постов: {artist_id}")

            # Удаляем статус кэша из памяти
            if artist_id in self.artist_cache_status:
                del self.artist_cache_status[artist_id]

            # Также можно удалить кэш медиа для всех постов этого артиста
            # Но это может быть слишком агрессивно, поэтому оставим только кэш постов
            print(f"[OK] Кэш артиста {artist_id} очищен")
            return True

        except Exception as e:
            print(f"[ERROR] Ошибка при очистке кэша артиста {artist_id}: {e}")
            return False

    def clear_all_cache(self):
        """Очистить весь кэш"""
        try:
            cache_cleared = False

            # Очищаем кэш постов
            if self.posts_cache_dir.exists():
                import shutil
                shutil.rmtree(self.posts_cache_dir)
                self.posts_cache_dir.mkdir(exist_ok=True)
                print(f"[DELETE] Очищен кэш постов")
                cache_cleared = True

            # Очищаем кэш медиа
            if self.media_cache_dir.exists():
                shutil.rmtree(self.media_cache_dir)
                self.media_cache_dir.mkdir(exist_ok=True)
                print(f"[DELETE] Очищен кэш медиа")
                cache_cleared = True

            # Очищаем превью
            if self.post_thumbnails_dir.exists():
                shutil.rmtree(self.post_thumbnails_dir)
                self.post_thumbnails_dir.mkdir(exist_ok=True)
                print(f"[DELETE] Очищены превью постов")
                cache_cleared = True

            if self.media_previews_dir.exists():
                shutil.rmtree(self.media_previews_dir)
                self.media_previews_dir.mkdir(exist_ok=True)
                print(f"[DELETE] Очищены превью медиа")
                cache_cleared = True

            # Очищаем кэш состояний в памяти
            self.artist_cache_status.clear()
            self.posts_metadata_cache.clear()
            self.media_metadata_cache.clear()
            self.preview_cache.clear()
            self.downloaded_files_cache.clear()

            if cache_cleared:
                print(f"[OK] Весь кэш очищен")
                return True
            else:
                print(f"[INFO] Кэш уже был пуст")
                return True

        except Exception as e:
            print(f"[ERROR] Ошибка при очистке всего кэша: {e}")
            return False

    def get_post_attr(self, post, attr_name, default_value=""):
        """Универсальный метод для получения атрибута поста (работает с объектами и словарями)"""
        if hasattr(post, attr_name):
            value = getattr(post, attr_name)
            return value if value is not None else default_value
        elif isinstance(post, dict):
            return post.get(attr_name, default_value)
        else:
            return default_value

    def is_post_downloaded(self, post):
        """Проверяет, скачаны ли все медиафайлы поста"""
        try:
            # Получаем все медиафайлы поста
            attachments = self.get_post_attr(post, 'attachments', [])
            files = self.get_post_attr(post, 'files', [])

            # Собираем все пути к файлам
            all_files = []

            for attachment in attachments:
                filename = attachment.get('name', '')
                if filename:
                    filepath = self.get_media_filepath(post, filename)
                    all_files.append(str(filepath))

            for file_info in files:
                filename = file_info.get('name', '')
                if filename:
                    filepath = self.get_media_filepath(post, filename)
                    all_files.append(str(filepath))

            # Если нет файлов, считаем пост скачанным
            if not all_files:
                return True

            # Проверяем, все ли файлы скачаны
            for filepath in all_files:
                if not self.is_file_downloaded(filepath):
                    return False

            return True

        except Exception as e:
            print(f"Ошибка проверки статуса скачивания поста: {e}")
            return False

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
                        print(f"[OK] Успешно загружено превью после повторной попытки: {url}")
                        # TODO: Обновить GUI для отображения загруженного превью
                    else:
                        print(f"[ERROR] Не удалось загрузить превью после повторных попыток: {url}")
                except Exception as e:
                    print(f"Ошибка при повторной попытке загрузки превью {url}: {e}")

                # Небольшая задержка между попытками
                time.sleep(1)

            self.retry_active = False

        retry_thread = threading.Thread(target=retry_worker, daemon=True)
        retry_thread.start()
        self.retry_thread = retry_thread

    def _download_single_file(self, url, filepath):
        """Скачать один файл"""
        try:
            # Создаем директорию если не существует
            filepath.parent.mkdir(parents=True, exist_ok=True)

            # Скачиваем файл
            response = requests.get(url, timeout=30, stream=True)
            response.raise_for_status()

            with open(filepath, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)

            # Отмечаем файл как скачанный
            self.mark_file_downloaded(filepath)
            return True
        except Exception as e:
            print(f"Ошибка скачивания {url}: {e}")
            return False

    def _download_media_files(self, media_files):
        """Скачать медиафайлы с подробным статусом"""
        if not media_files:
            return

        total = len(media_files)
        downloaded = 0
        already_exists = 0
        skipped = 0
        errors = 0
        error_details = []

        self.download_status_updated.emit(f"Загрузка медиа 0/{total} (0%)")

        for i, media_item in enumerate(media_files, 1):
            url = media_item['url']
            filepath = Path(media_item['filepath'])

            # Проверяем, нужно ли скачивать этот файл по типу
            if not self.should_download_file(media_item):
                skipped += 1
                progress = int((i / total) * 100)
                self.download_status_updated.emit(f"Загрузка медиа {i}/{total} ({progress}%) - Пропущен по типу файла")
                continue

            # Проверяем, существует ли файл уже
            if filepath.exists():
                already_exists += 1
                # Отмечаем файл как скачанный (если еще не отмечен)
                self.mark_file_downloaded(filepath)
                progress = int((i / total) * 100)
                self.download_status_updated.emit(f"Загрузка медиа {i}/{total} ({progress}%) - Уже существует")
            else:
                # Скачиваем файл
                if self._download_single_file(url, filepath):
                    downloaded += 1
                else:
                    errors += 1
                    error_details.append(f"Не удалось скачать: {filepath.name}")
                    print(f"Не удалось скачать: {url}")

            # Скачиваем превью для изображений (независимо от того, существовал файл или нет)
            file_ext = filepath.suffix.lower()
            if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
                try:
                    # Скачиваем превью большего размера для медиа (160x120)
                    preview_path = self.download_and_cache_preview(
                        url,
                        size=(160, 120),
                        preview_type="media",
                        max_retries=2
                    )
                    if preview_path:
                        print(f"Превью скачано: {filepath.name}")
                    else:
                        print(f"Не удалось скачать превью: {filepath.name}")
                except Exception as e:
                    print(f"Ошибка при скачивании превью {filepath.name}: {e}")

            # Обновляем статус
            progress = int((i / total) * 100)
            self.download_status_updated.emit(f"Загрузка медиа {i}/{total} ({progress}%)")

        # Формируем итоговый статус
        status_parts = []
        if downloaded > 0:
            status_parts.append(f"Загружено: {downloaded}")
        if already_exists > 0:
            status_parts.append(f"Уже было: {already_exists}")
        if skipped > 0:
            status_parts.append(f"Пропущено: {skipped}")
        if errors > 0:
            status_parts.append(f"Ошибки: {errors}")

        final_status = "Медиа " + " | ".join(status_parts)
        self.download_status_updated.emit(final_status + " | Превью обработаны")

        # Показываем ошибки в логах если они есть
        if error_details:
            print("Ошибки загрузки:")
            for error in error_details[:5]:  # Показываем первые 5 ошибок
                print(f"  - {error}")
            if len(error_details) > 5:
                print(f"  ... и еще {len(error_details) - 5} ошибок")

        self.download_status_updated.emit(final_status)
        self.progress_updated.emit(0, 0)  # Скрываем прогресс-бар

    def _analyze_post_worker(self, post):
        """Анализ одного поста для рабочего потока"""
        post_media = []

        post_title = self.get_post_attr(post, 'title', 'untitled')
        post_id = self.get_post_attr(post, 'id', '')

        safe_title = re.sub(r'[<>:"/\\|?*]', '_', str(post_title)[:50])
        author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
        post_dir = Path("downloads") / author_name / safe_title

        # Быстрый путь через attachments и files
        attachments = self.get_post_attr(post, 'attachments', [])
        for attachment in attachments:
            filename = attachment['name']
            url = attachment['url']
            if self.parser._is_valid_media_url(url):
                filepath = post_dir / filename
                post_media.append({
                    'url': url, 'filename': filename, 'filepath': str(filepath),
                    'post_title': post_title, 'post_id': post_id
                })

        files = self.get_post_attr(post, 'files', [])
        for file_info in files:
            filename = file_info['name']
            url = file_info['url']
            if self.parser._is_valid_media_url(url):
                filepath = post_dir / filename
                post_media.append({
                    'url': url, 'filename': filename, 'filepath': str(filepath),
                    'post_title': post_title, 'post_id': post_id
                })

        # Если нет вложений, анализируем HTML
        if not post_media:
            post_media_urls = self._analyze_post_for_media_safe(post)
            for url_info in post_media_urls:
                if self.parser._is_valid_media_url(url_info['url']):
                    filepath = post_dir / url_info['filename']
                    post_media.append({
                        'url': url_info['url'], 'filename': url_info['filename'], 'filepath': str(filepath),
                        'post_title': post_title, 'post_id': post_id
                    })

        return post_media

    def _analyze_post_for_media_safe(self, post):
        """Анализирует пост и собирает медиа URL в многопоточном режиме"""
        media_urls = []

        try:
            # Создаем временный парсер только для этого поста
            temp_parser = KemonoParser(use_selenium=True, headless=True)

            try:
                # Получаем данные поста
                service = self.get_post_attr(post, 'service', 'fanbox')
                post_id = self.get_post_attr(post, 'id', '')

                # Используем логику из download_post_content, но только для сбора URL
                post_url = f"{temp_parser.base_url}/{service}/post/{post_id}"

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

                all_media_urls = []  # Используем list вместо set для сохранения порядка

                # Добавляем ссылки из <a> тегов (сохраняем порядок)
                for link in media_links:
                    try:
                        url = link['href']
                        if not url.startswith('http'):
                            from urllib.parse import urljoin
                            url = urljoin(temp_parser.base_url, url)
                        # Проверяем, не добавляли ли уже этот URL
                        if url not in [item['url'] for item in all_media_urls]:
                            all_media_urls.append({'url': url, 'type': 'link'})
                    except:
                        continue

                # Добавляем ссылки из <img> тегов (сохраняем порядок)
                for img in img_tags:
                    try:
                        url = img['src']
                        if not url.startswith('http'):
                            from urllib.parse import urljoin
                            url = urljoin(temp_parser.base_url, url)
                        # Пропускаем превью и маленькие изображения
                        if any(x in url.lower() for x in ['thumb', 'preview', 'icon', 'thumbnail']):
                            continue
                        # Проверяем, не добавляли ли уже этот URL
                        if url not in [item['url'] for item in all_media_urls]:
                            all_media_urls.append({'url': url, 'type': 'image'})
                    except:
                        continue

                # Создаем записи для каждого найденного URL (сохраняем порядок)
                for media_info in all_media_urls:
                    try:
                        url = media_info['url']
                        filename = url.split('/')[-1].split('?')[0]
                        if filename and temp_parser._is_valid_media_url(url):
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
            print(f"   [ERROR] Ошибка анализа поста {post.id}: {e}")

        return media_urls

    def update_ui_state(self):
        """Обновление состояния интерфейса"""
        has_artist = self.current_artist is not None
        has_posts = len(self.all_posts) > 0
        has_media = len(self.current_media) > 0

        # Обновляем кнопки
        self.download_all_btn.setEnabled(has_posts)
        self.download_selected_btn.setEnabled(has_posts)
        self.select_all_media_btn.setEnabled(has_media)
        self.deselect_all_media_btn.setEnabled(has_media)
        self.download_media_btn.setEnabled(has_media)

        # Пагинация
        total_pages = (len(self.all_posts) + self.posts_per_page - 1) // self.posts_per_page
        self.page_label.setText(f"Страница {self.current_page + 1}/{max(1, total_pages)}")
        self.prev_page_btn.setEnabled(self.current_page > 0)
        self.next_page_btn.setEnabled(self.current_page < total_pages - 1)

    # Методы загрузки данных
    def load_artist_posts(self):
        """Загрузка постов автора"""
        url = self.url_entry.text().strip()
        if not url:
            QMessageBox.warning(self, "Ошибка", "Введите URL автора")
            return

        # Проверяем чекбокс очистки кэша
        if self.clear_cache_checkbox.isChecked():
            # Спрашиваем подтверждение
            reply = QMessageBox.question(
                self,
                "Подтверждение очистки кэша",
                "Вы уверены, что хотите очистить кэш для этого автора?\n\n"
                "Это удалит все сохраненные данные о постах и потребуется их повторная загрузка.",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No
            )

            if reply == QMessageBox.StandardButton.Yes:
                try:
                    # Извлекаем artist_id из URL
                    from interactive_downloader import create_artist_from_url
                    temp_artist = create_artist_from_url(url)
                    if temp_artist:
                        artist_id = temp_artist.id
                        self.status_updated.emit(f"Очистка кэша для {artist_id}...")
                        if self.clear_artist_cache(artist_id):
                            self.status_updated.emit("Кэш очищен, начинаем загрузку...")
                        else:
                            self.status_updated.emit("Ошибка при очистке кэша")
                    else:
                        self.status_updated.emit("Не удалось определить ID артиста для очистки кэша")
                except Exception as e:
                    print(f"[ERROR] Ошибка при очистке кэша: {e}")
                    self.status_updated.emit("Ошибка очистки кэша, продолжаем загрузку...")
            else:
                # Пользователь отменил очистку
                self.status_updated.emit("Очистка кэша отменена пользователем")

            # Автоматически снимаем галочку после использования
            self.clear_cache_checkbox.setChecked(False)

        self.status_updated.emit("Загрузка постов автора...")
        self.progress_updated.emit(0, 0)  # Показываем прогресс-бар

        # Запускаем в отдельном потоке
        thread = threading.Thread(target=self._load_posts_worker, args=(url,))
        thread.daemon = True
        thread.start()

    def _load_posts_worker(self, url):
        """Рабочий поток для загрузки постов с поддержкой кэширования v3"""
        try:
            # Создаем парсер если нужно
            if not self.parser:
                self.parser = KemonoParser(use_selenium=True, headless=True)

            # Создаем объект автора
            artist = create_artist_from_url(url)
            if not artist:
                self.status_updated.emit("Ошибка: Неверный URL")
                return

            self.current_artist = artist
            artist_id = artist.id

            # Сначала пытаемся загрузить из кэша
            cached_data = self.load_posts_cache(artist_id)
            if cached_data:
                cached_posts, is_complete = cached_data

                if is_complete:
                    # Кэш полный, показываем из кэша
                    self.status_updated.emit(f"Загружено из кэша: {len(cached_posts)} постов")
                    self.all_posts = cached_posts
                    self.posts_loaded.emit(cached_posts)
                    return
                else:
                    # Кэш неполный, продолжаем анализ от последнего поста
                    self.status_updated.emit(f"Кэш найден ({len(cached_posts)} постов), продолжаем анализ...")
                    if cached_posts:
                        last_cached_post = cached_posts[-1]  # Самый старый пост в кэше

                        # Получаем дату из объекта или словаря
                        published_str = self.get_post_attr(last_cached_post, 'published')
                        date_str = self.get_post_attr(last_cached_post, 'date')

                        if published_str:
                            try:
                                if isinstance(published_str, str):
                                    last_cached_date = datetime.fromisoformat(published_str.replace('Z', '+00:00'))
                                else:
                                    last_cached_date = published_str
                            except:
                                last_cached_date = None
                        elif date_str:
                            try:
                                if isinstance(date_str, str):
                                    last_cached_date = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
                                else:
                                    last_cached_date = date_str
                            except:
                                last_cached_date = None
                        else:
                            last_cached_date = None

                        post_id = self.get_post_attr(last_cached_post, 'id', 'unknown')
                        self.status_updated.emit(f"Продолжаем анализ от поста: {post_id}")
                    else:
                        last_cached_date = None
            else:
                # Кэша нет, начинаем полный анализ
                cached_posts = []
                last_cached_date = None
                self.status_updated.emit("Начинаем полный анализ постов...")

            # Выполняем анализ постов с кэшированием
            posts = self._analyze_posts_incremental(artist, cached_posts, last_cached_date)

            # Сохраняем результат в кэш
            is_complete = len(posts) > 0 and len(posts) >= len(cached_posts)
            self.save_posts_cache(artist_id, posts, is_complete)

            self.all_posts = posts

            # Добавляем URL в историю
            self.add_url_to_history(url)

            self.status_updated.emit(f"Загружено {len(posts)} постов")
            self.posts_loaded.emit(posts)

        except Exception as e:
            self.status_updated.emit(f"Ошибка загрузки: {str(e)}")
            import traceback
            traceback.print_exc()
        finally:
            self.progress_updated.emit(0, 0)  # Скрываем прогресс-бар

    def _analyze_posts_incremental(self, artist, existing_posts, last_cached_date):
        """Инкрементальный анализ постов с поддержкой кэширования"""
        try:
            all_posts = existing_posts.copy()
            page = 1
            found_cached_post = False

            while True:
                self.status_updated.emit(f"Анализ страницы {page}...")
                self.progress_updated.emit(page, 0)  # Показываем текущую страницу

                # Загружаем посты страницы
                try:
                    # Используем offset вместо page (page-1)*50
                    offset = (page - 1) * 50
                    page_posts = self.parser.get_artist_posts(artist, offset=offset, limit=50)

                    # Проверяем, что это список или подобная структура
                    try:
                        posts_list = list(page_posts) if hasattr(page_posts, '__iter__') and not isinstance(page_posts, (str, dict)) else [page_posts] if page_posts else []
                        page_posts = posts_list
                    except Exception as conv_e:
                        page_posts = []

                except AttributeError as e:
                    # Если метод get_artist_posts_page не существует, используем get_all_artist_posts
                    all_posts_from_old_method = self.parser.get_all_artist_posts(artist)

                    if all_posts_from_old_method:
                        # Добавляем все посты из старого метода
                        all_posts.extend(all_posts_from_old_method)

                    return all_posts

                if not page_posts:
                    # Достигли конца
                    break

                # Обрабатываем посты страницы
                new_posts = []
                for post in page_posts:
                    # Получаем дату поста
                    published_date = self.get_post_attr(post, 'published')
                    date_field = self.get_post_attr(post, 'date')

                    if published_date:
                        post_date = published_date
                    elif date_field:
                        post_date = date_field
                    else:
                        post_date = None

                    # Проверяем, не достигли ли мы кэшированного поста
                    if last_cached_date and post_date and post_date <= last_cached_date:
                        found_cached_post = True
                        break

                    new_posts.append(post)

                # Добавляем новые посты
                all_posts.extend(new_posts)

                # Если нашли кэшированный пост, прекращаем анализ
                if found_cached_post:
                    self.status_updated.emit(f"Найден кэшированный пост, анализ завершен")
                    break

                # Если на странице меньше постов чем ожидалось, значит конец
                if len(page_posts) < 50:  # Предполагаем 50 постов на страницу
                    break

                page += 1

                # Ограничение на количество страниц для безопасности
                if page > 100:
                    self.status_updated.emit("Превышен лимит страниц, анализ прерван")
                    break

            return all_posts

        except Exception as e:
            self.status_updated.emit(f"Ошибка анализа: {str(e)}")
            return existing_posts  # Возвращаем то, что есть

    # Обработчики сигналов
    def update_status(self, message):
        """Обновление статуса"""
        self.status_bar.showMessage(message)

    def update_progress(self, current, total):
        """Обновление прогресс бара"""
        if total > 0:
            self.progress_bar.setVisible(True)
            self.progress_bar.setMaximum(total)
            self.progress_bar.setValue(current)
        else:
            self.progress_bar.setVisible(False)

    def on_posts_loaded(self, posts):
        """Обработчик загрузки постов"""
        self.current_page = 0

        # Сбрасываем состояние ошибки медиа при загрузке новых постов
        self.media_error_post = None
        self.media_error_label.setVisible(False)
        self.retry_media_btn.setVisible(False)

        # Скрываем кнопку "Показать в Finder" при загрузке новых постов
        self.show_in_finder_btn.setVisible(False)

        self.update_posts_display()
        self.update_ui_state()

    def on_media_loaded(self, media):
        """Обработчик загрузки медиа"""
        self.current_media = media

        # Сбрасываем состояние ошибки при успешной загрузке
        self.media_error_post = None
        self.media_error_label.setVisible(False)
        self.retry_media_btn.setVisible(False)

        self.update_media_display()
        self.update_ui_state()

    def on_artists_loaded(self, artists, page_type):
        """Обработчик загрузки списка авторов"""
        print(f"[ARTISTS] Получено {len(artists)} авторов типа: {page_type}")

        # Очищаем предыдущие результаты
        self.clear_browser_results()

        # Отображаем результаты
        self.display_artists_results(artists, page_type)

        # Обновляем статус
        self.status_updated.emit(f"Загружено {len(artists)} авторов")

    def on_posts_loaded_browser(self, posts, page_type):
        """Обработчик загрузки списка постов для браузера"""
        print(f"[POSTS] Получено {len(posts)} постов типа: {page_type}")

        # Очищаем предыдущие результаты
        self.clear_browser_results()

        # Отображаем результаты
        self.display_posts_results(posts, page_type)

        # Обновляем статус
        self.status_updated.emit(f"Загружено {len(posts)} постов")

    def display_posts_results(self, posts, page_type):
        """Отображение результатов поиска постов"""
        print(f"[POSTS] Отображение {len(posts)} постов")

        # Создаем карточки для каждого поста
        for post in posts:
            card = self.create_post_card_browser(post)
            self.browser_results_layout.addWidget(card)

        # Добавляем растяжку в конце
        self.browser_results_layout.addStretch()

    def display_artists_results(self, artists, page_type):
        """Отображение результатов поиска авторов"""
        print(f"[ARTISTS] Отображение {len(artists)} авторов")

        # Создаем карточки для каждого автора
        for artist in artists:
            card = self.create_artist_card_browser(artist)
            self.browser_results_layout.addWidget(card)

        # Добавляем растяжку в конце
        self.browser_results_layout.addStretch()

    def create_artist_card_browser(self, artist):
        """Создание карточки автора для браузера"""
        card = QWidget()
        card.setStyleSheet("""
            QWidget {
                border: 1px solid #dee2e6;
                border-radius: 8px;
                background-color: white;
                margin: 5px;
                padding: 15px;
            }
            QWidget:hover {
                border: 1px solid #0078d4;
                background-color: #f8f9fa;
            }
        """)
        card_layout = QVBoxLayout(card)

        # Имя автора
        name_label = QLabel(f"{artist.name}")
        name_label.setStyleSheet("font-weight: bold; font-size: 16px; margin-bottom: 5px;")
        card_layout.addWidget(name_label)

        # Сервис
        service_label = QLabel(f"Сервис: {artist.service}")
        service_label.setStyleSheet("color: #6c757d; font-size: 12px;")
        card_layout.addWidget(service_label)

        # ID автора
        id_label = QLabel(f"ID: {artist.id}")
        id_label.setStyleSheet("color: #6c757d; font-size: 12px;")
        card_layout.addWidget(id_label)

        # Кнопки действий
        buttons_layout = QHBoxLayout()

        # Кнопка открытия автора
        open_btn = QPushButton("Открыть")
        open_btn.setStyleSheet("""
            QPushButton {
                background-color: #28a745;
                color: white;
                border: none;
                padding: 8px 15px;
                border-radius: 4px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1e7e34;
            }
        """)
        open_btn.clicked.connect(lambda: self.open_artist_in_viewer(artist))
        buttons_layout.addWidget(open_btn)

        # Кнопка копирования ссылки
        copy_btn = QPushButton("Копировать")
        copy_btn.setStyleSheet("""
            QPushButton {
                background-color: #6c757d;
                color: white;
                border: none;
                padding: 8px 15px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #545b62;
            }
        """)
        copy_btn.clicked.connect(lambda: self.copy_artist_url(artist))
        buttons_layout.addWidget(copy_btn)

        buttons_layout.addStretch()
        card_layout.addLayout(buttons_layout)

        return card

    def create_post_card_browser(self, post):
        """Создание карточки поста для браузера"""
        card = QWidget()
        card.setStyleSheet("""
            QWidget {
                border: 1px solid #dee2e6;
                border-radius: 8px;
                background-color: white;
                margin: 5px;
                padding: 15px;
            }
            QWidget:hover {
                border: 1px solid #0078d4;
                background-color: #f8f9fa;
            }
        """)
        card_layout = QVBoxLayout(card)

        # Заголовок поста
        title = getattr(post, 'title', 'Без названия')[:60]
        if len(getattr(post, 'title', '')) > 60:
            title += "..."

        title_label = QLabel(f"{title}")
        title_label.setStyleSheet("font-weight: bold; font-size: 16px; margin-bottom: 5px;")
        card_layout.addWidget(title_label)

        # Информация об авторе
        author = getattr(post, 'author', 'Неизвестный автор')
        author_label = QLabel(f"Автор: {author}")
        author_label.setStyleSheet("color: #6c757d; font-size: 12px;")
        card_layout.addWidget(author_label)

        # Дата публикации
        published = getattr(post, 'published', 'Неизвестно')
        if published and len(published) > 10:
            published = published[:10]  # YYYY-MM-DD
        date_label = QLabel(f"Дата: {published}")
        date_label.setStyleSheet("color: #6c757d; font-size: 12px;")
        card_layout.addWidget(date_label)

        # Кнопки действий
        buttons_layout = QHBoxLayout()

        # Кнопка открытия поста
        open_btn = QPushButton("Открыть")
        open_btn.setStyleSheet("""
            QPushButton {
                background-color: #28a745;
                color: white;
                border: none;
                padding: 8px 15px;
                border-radius: 4px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #1e7e34;
            }
        """)
        open_btn.clicked.connect(lambda: self.open_post_in_viewer(post))
        buttons_layout.addWidget(open_btn)

        # Кнопка копирования ссылки
        copy_btn = QPushButton("Копировать")
        copy_btn.setStyleSheet("""
            QPushButton {
                background-color: #6c757d;
                color: white;
                border: none;
                padding: 8px 15px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #545b62;
            }
        """)
        copy_btn.clicked.connect(lambda: self.copy_post_url(post))
        buttons_layout.addWidget(copy_btn)

        buttons_layout.addStretch()
        card_layout.addLayout(buttons_layout)

        return card

    def clear_browser_results(self):
        """Очистка результатов браузера"""
        while self.browser_results_layout.count():
            item = self.browser_results_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

    # Методы отображения
    def update_posts_display(self):
        """Обновление отображения постов"""
        # Очищаем предыдущие посты
        self.clear_posts_layout()
        # Очищаем список чекбоксов постов
        self.post_checkboxes.clear()

        if not self.all_posts:
            return

        # Вычисляем посты для текущей страницы
        start_idx = self.current_page * self.posts_per_page
        end_idx = start_idx + self.posts_per_page
        page_posts = self.all_posts[start_idx:end_idx]

        # Создаем сетку для постов (адаптивная разметка)
        posts_grid = QGridLayout()
        posts_grid.setSpacing(10)

        row, col = 0, 0
        max_cols = 2  # Максимум 2 колонки

        for post in page_posts:
            self.create_post_card(post, posts_grid, row, col)
            col += 1
            if col >= max_cols:
                col = 0
                row += 1

        # Добавляем сетку постов в основной layout
        self.posts_layout.addLayout(posts_grid)
        # Добавляем растяжку для выравнивания по верху
        self.posts_layout.addStretch()

    def clear_posts_layout(self):
        """Очистка layout постов"""
        # Отключаем сигналы обновления превью перед удалением виджетов
        try:
            self.update_thumbnail_pixmap.disconnect()
            self.update_thumbnail_text.disconnect()
        except (TypeError, RuntimeError):
            # Сигналы уже отключены или не существуют
            pass

        # Очищаем все элементы из layout, включая вложенные layout'ы
        while self.posts_layout.count():
            item = self.posts_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
            elif item.layout():
                # Рекурсивно очищаем вложенные layout'ы
                self.clear_nested_layout(item.layout())

        # Переподключаем сигналы после очистки
        try:
            self.update_thumbnail_pixmap.connect(self.on_update_thumbnail_pixmap)
            self.update_thumbnail_text.connect(self.on_update_thumbnail_text)
        except (TypeError, RuntimeError):
            # Сигналы уже подключены
            pass

    def clear_nested_layout(self, layout):
        """Рекурсивная очистка вложенных layout'ов"""
        while layout.count():
            item = layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
            elif item.layout():
                self.clear_nested_layout(item.layout())

    def create_post_card(self, post, grid_layout, row, col):
        """Создание карточки поста с превью"""
        # Основной фрейм карточки
        card_frame = QFrame()
        card_frame.setFrameStyle(QFrame.Shape.Box)
        card_frame.setStyleSheet("""
            QFrame {
                border: 1px solid #ddd;
                border-radius: 8px;
                background-color: white;
                padding: 8px;
            }
            QFrame:hover {
                border: 1px solid #0078d4;
                background-color: #f8f9fa;
            }
        """)
        card_frame.setFixedSize(220, 280)  # Фиксированный размер карточки

        layout = QVBoxLayout(card_frame)
        layout.setContentsMargins(8, 8, 8, 8)

        # Превью изображение
        thumbnail_label = QLabel()
        thumbnail_label.setFixedSize(200, 150)
        thumbnail_label.setStyleSheet("""
            QLabel {
                border: 1px solid #eee;
                border-radius: 4px;
                background-color: #f8f9fa;
            }
        """)
        thumbnail_label.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # Загружаем превью асинхронно
        post_thumbnail = self.get_post_attr(post, 'thumbnail')
        if post_thumbnail:
            self.load_post_thumbnail_async(post, thumbnail_label)

        # Чекбокс в углу превью
        checkbox = QCheckBox()
        checkbox.setStyleSheet("QCheckBox { margin: 5px; }")
        self.post_checkboxes.append(checkbox)  # Добавляем чекбокс поста в список

        # Индикатор скачанного поста (зеленый кружочек)
        download_indicator = QLabel("●")
        download_indicator.setStyleSheet("font-size: 12px; color: #28a745; margin: 5px;")
        download_indicator.setVisible(False)  # По умолчанию скрыт

        # Проверяем, скачан ли пост (все его медиафайлы)
        post_id = self.get_post_attr(post, 'id', '')
        if self.is_post_downloaded(post):
            download_indicator.setVisible(True)

        # Оверлей для чекбокса и индикатора
        overlay_layout = QVBoxLayout()
        overlay_layout.addWidget(checkbox, alignment=Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignRight)
        overlay_layout.addWidget(download_indicator, alignment=Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignLeft)
        overlay_layout.addStretch()

        # Композитный виджет для превью + чекбокс
        preview_widget = QWidget()
        preview_layout = QVBoxLayout(preview_widget)
        preview_layout.setContentsMargins(0, 0, 0, 0)
        preview_layout.addWidget(thumbnail_label)
        preview_layout.addLayout(overlay_layout)

        # Информация о посте
        info_layout = QVBoxLayout()

        post_title = self.get_post_attr(post, 'title', 'Без названия')
        title_label = QLabel(f"{post_title[:35]}...")
        title_label.setStyleSheet("font-weight: bold; font-size: 11px;")
        title_label.setWordWrap(True)

        # Форматируем дату из published
        date_str = "Дата неизвестна"
        published_date = self.get_post_attr(post, 'published')
        if published_date:
            try:
                if isinstance(published_date, str):
                    date_str = published_date[:10]  # YYYY-MM-DD
                else:
                    date_str = str(published_date)[:10]
            except:
                date_str = str(published_date)

        date_label = QLabel(f"Дата: {date_str}")
        date_label.setStyleSheet("font-size: 10px; color: #666;")

        info_layout.addWidget(title_label)
        info_layout.addWidget(date_label)
        info_layout.addStretch()

        layout.addWidget(preview_widget)
        layout.addLayout(info_layout)

        # Обработчик клика
        card_frame.mousePressEvent = lambda e: self.on_post_clicked(post, card_frame)

        grid_layout.addWidget(card_frame, row, col)

    def load_post_thumbnail_async(self, post, thumbnail_label):
        """Асинхронная загрузка превью поста"""
        def load_thumbnail():
            try:
                # Проверяем, что thumbnail_label все еще существует
                if thumbnail_label is None or not hasattr(thumbnail_label, 'setPixmap'):
                    return

                post_thumbnail = self.get_post_attr(post, 'thumbnail')

                # Если thumbnail отсутствует, попробуем найти первое изображение из attachments, files или file
                if not post_thumbnail:
                    attachments = self.get_post_attr(post, 'attachments', [])
                    files = self.get_post_attr(post, 'files', [])
                    file_info = self.get_post_attr(post, 'file', {})

                    # Ищем первое изображение в attachments
                    for attachment in attachments:
                        if isinstance(attachment, dict) and attachment.get('url'):
                            file_url = attachment.get('url')
                            if file_url and any(file_url.lower().endswith(ext) for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']):
                                post_thumbnail = file_url
                                print(f"Найдено превью в attachments: {file_url}")
                                break

                    # Если не нашли в attachments, ищем в files
                    if not post_thumbnail:
                        for file_item in files:
                            if isinstance(file_item, dict) and file_item.get('url'):
                                file_url = file_item.get('url')
                                if file_url and any(file_url.lower().endswith(ext) for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']):
                                    post_thumbnail = file_url
                                    print(f"Найдено превью в files: {file_url}")
                                    break

                    # Если не нашли в files, проверяем основной file
                    if not post_thumbnail and isinstance(file_info, dict) and file_info.get('url'):
                        file_url = file_info.get('url')
                        if file_url and any(file_url.lower().endswith(ext) for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']):
                            post_thumbnail = file_url
                            print(f"Найдено превью в file: {file_url}")

                if post_thumbnail:
                    # Сначала проверяем кэш
                    cached_path = self.get_cached_preview_path(post_thumbnail, preview_type="post")
                    if cached_path:
                        # Загружаем из кэша
                        pixmap = QPixmap(cached_path)
                        if not pixmap.isNull():
                            scaled_pixmap = pixmap.scaled(
                                200, 150,
                                Qt.AspectRatioMode.KeepAspectRatio,
                                Qt.TransformationMode.SmoothTransformation
                            )
                            # Обновляем GUI через сигнал в главном потоке
                            self.update_thumbnail_pixmap.emit(thumbnail_label, scaled_pixmap)
                        else:
                            self.update_thumbnail_text.emit(thumbnail_label, "Нет превью")
                    else:
                        # Пытаемся загрузить из интернета
                        try:
                            cached_path = self.download_and_cache_preview(
                                post_thumbnail,
                                size=(200, 150),
                                preview_type="post",
                                max_retries=2
                            )

                            if cached_path:
                                # Создаем QPixmap
                                pixmap = QPixmap(cached_path)
                                if not pixmap.isNull():
                                    scaled_pixmap = pixmap.scaled(
                                        200, 150,
                                        Qt.AspectRatioMode.KeepAspectRatio,
                                        Qt.TransformationMode.SmoothTransformation
                                    )
                                    # Обновляем GUI через сигнал в главном потоке
                                    self.update_thumbnail_pixmap.emit(thumbnail_label, scaled_pixmap)
                                else:
                                    self.update_thumbnail_text.emit(thumbnail_label, "Нет превью")
                            else:
                                self.update_thumbnail_text.emit(thumbnail_label, "Нет превью")
                        except Exception as network_error:
                            # Обработка ошибок сети
                            if "net::ERR_NAME_NOT_RESOLVED" in str(network_error) or "Connection" in str(network_error):
                                self.update_thumbnail_text.emit(thumbnail_label, "Нет интернета")
                            else:
                                self.update_thumbnail_text.emit(thumbnail_label, "Ошибка загрузки")
                else:
                    self.update_thumbnail_text.emit(thumbnail_label, "Нет превью")

            except Exception as e:
                post_id = self.get_post_attr(post, 'id', 'unknown')
                print(f"Ошибка загрузки превью поста {post_id}: {e}")
                try:
                    if thumbnail_label is not None and hasattr(thumbnail_label, 'setText'):
                        self.update_thumbnail_text.emit(thumbnail_label, "Ошибка")
                except (RuntimeError, AttributeError):
                    pass

        # Запускаем в отдельном потоке
        import threading
        thread = threading.Thread(target=load_thumbnail, daemon=True)
        thread.start()

    def update_media_display(self):
        """Обновление отображения медиа"""
        # Очищаем предыдущие медиа
        self.clear_media_layout()
        # Очищаем список чекбоксов
        self.media_checkboxes.clear()

        if not self.current_media:
            return

        # Создаем сетку для медиа (адаптивная разметка)
        media_grid = QGridLayout()
        media_grid.setSpacing(10)

        row, col = 0, 0
        max_cols = 3  # Максимум 3 колонки для медиа

        for media_item in self.current_media:
            self.create_media_card(media_item, media_grid, row, col)
            col += 1
            if col >= max_cols:
                col = 0
                row += 1

        self.media_layout.addLayout(media_grid)
        self.media_layout.addStretch()

    def clear_media_layout(self):
        """Очистка layout медиа"""
        while self.media_layout.count():
            item = self.media_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
            elif item.layout():
                # Рекурсивно очищаем вложенные layout'ы
                self.clear_layout(item.layout())

    def clear_layout(self, layout):
        """Рекурсивная очистка layout"""
        while layout.count():
            item = layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
            elif item.layout():
                self.clear_layout(item.layout())


    def load_media_thumbnail_async(self, media_item, thumbnail_label):
        """Асинхронная загрузка превью медиа файла"""
        def load_thumbnail():
            try:
                # Проверяем, что thumbnail_label все еще существует
                if thumbnail_label is None or not hasattr(thumbnail_label, 'setPixmap'):
                    return

                url = media_item['url']
                filename = media_item['filename']
                result_pixmap = None
                result_text = None

                # Для изображений пытаемся загрузить превью
                file_ext = Path(filename).suffix.lower()
                if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
                    # Сначала проверяем кэш
                    cached_path = self.get_cached_preview_path(url, preview_type="media")
                    if cached_path:
                        # Загружаем из кэша
                        pixmap = QPixmap(cached_path)
                        if not pixmap.isNull():
                            result_pixmap = pixmap.scaled(
                                160, 120,
                                Qt.AspectRatioMode.KeepAspectRatio,
                                Qt.TransformationMode.SmoothTransformation
                            )
                        else:
                            result_text = self._get_file_icon_text(filename)
                    else:
                        # Пытаемся загрузить из интернета
                        try:
                            cached_path = self.download_and_cache_preview(
                                url,
                                size=(160, 120),
                                preview_type="media",
                                max_retries=2
                            )

                            if cached_path:
                                # Создаем QPixmap
                                pixmap = QPixmap(cached_path)
                                if not pixmap.isNull():
                                    result_pixmap = pixmap.scaled(
                                        160, 120,
                                        Qt.AspectRatioMode.KeepAspectRatio,
                                        Qt.TransformationMode.SmoothTransformation
                                    )
                                else:
                                    result_text = self._get_file_icon_text(filename)
                            else:
                                result_text = self._get_file_icon_text(filename)
                        except Exception as network_error:
                            # Обработка ошибок сети
                            if "net::ERR_NAME_NOT_RESOLVED" in str(network_error) or "Connection" in str(network_error):
                                result_text = "Нет интернета"
                            else:
                                result_text = self._get_file_icon_text(filename)
                else:
                    # Для других типов файлов показываем иконку
                    result_text = self._get_file_icon_text(filename)

                # Обновляем GUI в главном потоке через сигнал
                if result_pixmap:
                    # Используем сигнал для обновления pixmap
                    self.update_thumbnail_pixmap.emit(thumbnail_label, result_pixmap)
                elif result_text:
                    # Используем сигнал для обновления текста
                    self.update_thumbnail_text.emit(thumbnail_label, result_text)

            except Exception as e:
                print(f"Ошибка загрузки превью медиа {media_item['filename']}: {e}")
                # В случае ошибки показываем иконку
                icon_text = self._get_file_icon_text(media_item['filename'])
                self.update_thumbnail_text.emit(thumbnail_label, icon_text)

        # Запускаем в отдельном потоке
        import threading
        thread = threading.Thread(target=load_thumbnail, daemon=True)
        thread.start()

    def on_update_thumbnail_pixmap(self, label, pixmap):
        """Обработчик сигнала обновления pixmap превью"""
        try:
            # Проверяем, что QLabel все еще существует
            if label is not None and hasattr(label, 'setPixmap') and label.parent() is not None:
                label.setPixmap(pixmap)
        except (RuntimeError, AttributeError):
            # QLabel был удален, игнорируем ошибку
            pass

    def on_update_thumbnail_text(self, label, text):
        """Обработчик сигнала обновления текста превью"""
        try:
            # Проверяем, что QLabel все еще существует
            if label is not None and hasattr(label, 'setText') and label.parent() is not None:
                label.setText(text)
        except (RuntimeError, AttributeError):
            # QLabel был удален, игнорируем ошибку
            pass

    def on_download_status_updated(self, status_text):
        """Обработчик сигнала обновления статуса загрузки"""
        self.status_bar.showMessage(status_text)

    def on_media_load_error(self, post_id, error_message):
        """Обработчик сигнала ошибки загрузки медиа"""
        try:
            # Сохраняем информацию об ошибке
            self.media_error_post = self.selected_post

            # Показываем сообщение об ошибке
            self.media_error_label.setText(f"[ERROR] {error_message}")
            self.media_error_label.setVisible(True)

            # Показываем кнопку повтора
            self.retry_media_btn.setVisible(True)

            # Очищаем область медиа
            self.clear_media_layout()

        except Exception as e:
            print(f"Ошибка при обработке ошибки загрузки медиа: {e}")

    def retry_load_media(self):
        """Повторная загрузка медиа для поста с ошибкой"""
        if self.media_error_post:
            # Скрываем сообщение об ошибке и кнопку повтора
            self.media_error_label.setVisible(False)
            self.retry_media_btn.setVisible(False)

            # Повторяем загрузку медиа
            self.status_updated.emit("Повторная загрузка медиа...")
            thread = threading.Thread(target=self._load_media_worker, args=(self.media_error_post,))
            thread.daemon = True
            thread.start()

    def _get_file_icon_text(self, filename):
        """Возвращает текст иконки для файла"""
        file_ext = Path(filename).suffix.lower()
        if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
            return "[IMG]"
        elif file_ext in ['.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv']:
            return "[VID]"
        elif file_ext in ['.zip', '.rar', '.7z', '.tar', '.gz']:
            return "[ZIP]"
        else:
            return "[FILE]"

    def create_media_card(self, media_item, grid_layout, row, col):
        """Создание карточки медиа с превью"""
        # Основной фрейм карточки
        card_frame = QFrame()
        card_frame.setFrameStyle(QFrame.Shape.Box)
        card_frame.setStyleSheet("""
            QFrame {
                border: 1px solid #ddd;
                border-radius: 8px;
                background-color: white;
                padding: 8px;
            }
            QFrame:hover {
                border: 1px solid #0078d4;
                background-color: #f8f9fa;
            }
        """)
        card_frame.setFixedSize(180, 200)  # Фиксированный размер карточки медиа

        layout = QVBoxLayout(card_frame)
        layout.setContentsMargins(8, 8, 8, 8)

        # Превью медиа
        thumbnail_label = QLabel()
        thumbnail_label.setFixedSize(160, 120)
        thumbnail_label.setStyleSheet("""
            QLabel {
                border: 1px solid #eee;
                border-radius: 4px;
                background-color: #f8f9fa;
            }
        """)
        thumbnail_label.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # Загружаем превью асинхронно для медиа
        self.load_media_thumbnail_async(media_item, thumbnail_label)

        # Чекбокс в углу превью
        checkbox = QCheckBox()
        checkbox.setStyleSheet("QCheckBox { margin: 5px; }")
        self.media_checkboxes.append(checkbox)  # Добавляем чекбокс в список

        # Индикатор скачанного файла (зеленый кружочек)
        download_indicator = QLabel("●")
        download_indicator.setStyleSheet("font-size: 12px; color: #28a745; margin: 5px;")
        download_indicator.setVisible(False)  # По умолчанию скрыт

        # Проверяем, скачан ли файл
        filepath = Path(media_item.get('filepath', ''))
        if self.is_file_downloaded(filepath):
            download_indicator.setVisible(True)

        # Оверлей для чекбокса и индикатора
        overlay_layout = QVBoxLayout()
        overlay_layout.addWidget(checkbox, alignment=Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignRight)
        overlay_layout.addWidget(download_indicator, alignment=Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignLeft)
        overlay_layout.addStretch()

        # Композитный виджет для превью + чекбокс
        preview_widget = QWidget()
        preview_layout = QVBoxLayout(preview_widget)
        preview_layout.setContentsMargins(0, 0, 0, 0)
        preview_layout.addWidget(thumbnail_label)
        preview_layout.addLayout(overlay_layout)

        # Информация о файле
        info_layout = QVBoxLayout()

        filename = Path(media_item['filename']).name
        filename_label = QLabel(f"{filename[:25]}...")
        filename_label.setStyleSheet("font-weight: bold; font-size: 10px;")
        filename_label.setWordWrap(True)

        # Определяем тип файла по расширению
        file_ext = Path(filename).suffix.lower()
        if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
            file_type = "Изображение"
        elif file_ext in ['.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv']:
            file_type = "Видео"
        elif file_ext in ['.zip', '.rar', '.7z', '.tar', '.gz']:
            file_type = "Архив"
        else:
            file_type = "Файл"

        type_label = QLabel(file_type)
        type_label.setStyleSheet("font-size: 9px; color: #666;")

        info_layout.addWidget(filename_label)
        info_layout.addWidget(type_label)
        info_layout.addStretch()

        layout.addWidget(preview_widget)
        layout.addLayout(info_layout)

        # Прогресс-бар для скачивания (в нижней части карточки)
        progress_bar = QProgressBar()
        progress_bar.setRange(0, 100)
        progress_bar.setValue(0)
        progress_bar.setFixedHeight(4)  # Тонкий прогресс-бар
        progress_bar.setStyleSheet("""
            QProgressBar {
                border: none;
                border-radius: 2px;
                background-color: #f0f0f0;
            }
            QProgressBar::chunk {
                background-color: #0078d4;
                border-radius: 2px;
            }
        """)
        progress_bar.setVisible(False)  # Скрыт по умолчанию
        layout.addWidget(progress_bar)

        # Сохраняем ссылку на прогресс-бар для обновления
        media_item['progress_bar'] = progress_bar

        # Обработчик двойного клика для открытия медиа в новом окне
        card_frame.mouseDoubleClickEvent = lambda event, item=media_item: self.open_media_viewer(item)

        grid_layout.addWidget(card_frame, row, col)

    # Обработчики событий
    def on_post_clicked(self, post, frame):
        """Обработчик клика по посту"""
        self.selected_post = post
        post_title = self.get_post_attr(post, 'title', 'Без названия')
        self.media_label.setText(f"Медиафайлы: {post_title}")

        # Показываем кнопку "Показать в Finder"
        self.show_in_finder_btn.setVisible(True)

        # Загружаем медиа для поста
        self.status_updated.emit("Поиск медиафайлов...")
        thread = threading.Thread(target=self._load_media_worker, args=(post,))
        thread.daemon = True
        thread.start()

    def _load_media_worker(self, post):
        """Рабочий поток для загрузки медиа с поддержкой кэширования v3"""
        try:
            # Очищаем текущие медиа
            self.current_media = []

            # Получаем ID поста
            post_id = self.get_post_attr(post, 'id', '')

            # Сначала пытаемся загрузить из кэша
            cached_media = self.load_media_cache(post_id)
            if cached_media:
                self.status_updated.emit(f"Медиа загружено из кэша: {len(cached_media)} файлов")
                self.current_media = cached_media
                self.media_loaded.emit(cached_media)
                return

            # Кэша нет, запускаем сбор медиа
            self.status_updated.emit("Сбор медиа из поста...")
            self.collect_media_from_post_async(post)

        except Exception as e:
            error_message = str(e)
            self.status_updated.emit(f"Ошибка загрузки медиа: {error_message}")

            # Отправляем сигнал об ошибке для отображения в UI
            if post_id:
                if "net::ERR_NAME_NOT_RESOLVED" in error_message or "Connection" in error_message:
                    self.media_load_error.emit(post_id, "Нет подключения к интернету")
                elif "timeout" in error_message.lower():
                    self.media_load_error.emit(post_id, "Превышено время ожидания ответа сервера")
                else:
                    self.media_load_error.emit(post_id, f"Ошибка загрузки медиа: {error_message}")

            import traceback
            traceback.print_exc()

    def collect_media_from_post(self, post):
        """Сбор медиа из поста"""
        media_info = []

        # Быстрый путь через attachments и files
        for attachment in post.attachments:
            filename = attachment['name']
            url = attachment['url']
            if self.parser and self.parser._is_valid_media_url(url):
                filepath = self.get_media_filepath(post, filename)
                media_info.append({
                    'url': url,
                    'filename': filename,
                    'filepath': str(filepath),
                    'post_title': post.title,
                    'post_id': post.id
                })

        for file_info in post.files:
            filename = file_info['name']
            url = file_info['url']
            if self.parser and self.parser._is_valid_media_url(url):
                filepath = self.get_media_filepath(post, filename)
                media_info.append({
                    'url': url,
                    'filename': filename,
                    'filepath': str(filepath),
                    'post_title': post.title,
                    'post_id': post.id
                })

        # Если нет вложений, анализируем HTML
        if not media_info:
            media_urls = self._analyze_post_for_media_safe(post) if self.parser else []
            for url_info in media_urls:
                if self.parser._is_valid_media_url(url_info['url']):
                    filepath = self.get_media_filepath(post, url_info['filename'])
                    media_info.append({
                        'url': url_info['url'],
                        'filename': url_info['filename'],
                        'filepath': str(filepath),
                        'post_title': post.title,
                        'post_id': post.id
                    })

        return media_info

    def collect_media_from_post_async(self, post):
        """Асинхронный сбор медиа из поста"""
        def collect_worker():
            try:
                all_media = []

                # Получаем атрибуты поста
                attachments = self.get_post_attr(post, 'attachments', [])
                files = self.get_post_attr(post, 'files', [])
                post_title = self.get_post_attr(post, 'title', '')
                post_id = self.get_post_attr(post, 'id', '')

                # Сначала обрабатываем attachments
                for attachment in attachments:
                    filename = attachment['name']
                    url = attachment['url']
                    if self.parser and self.parser._is_valid_media_url(url):
                        filepath = self.get_media_filepath(post, filename)
                        media_item = {
                            'url': url,
                            'filename': filename,
                            'filepath': str(filepath),
                            'post_title': post_title,
                            'post_id': post_id
                        }
                        all_media.append(media_item)

                # Затем обрабатываем files
                for file_info in files:
                    filename = file_info['name']
                    url = file_info['url']
                    if self.parser and self.parser._is_valid_media_url(url):
                        filepath = self.get_media_filepath(post, filename)
                        media_item = {
                            'url': url,
                            'filename': filename,
                            'filepath': str(filepath),
                            'post_title': post_title,
                            'post_id': post_id
                        }
                        all_media.append(media_item)

                # Если нет вложений, анализируем HTML
                if not all_media:
                    media_urls = self._analyze_post_for_media_safe(post) if self.parser else []
                    for url_info in media_urls:
                        if self.parser._is_valid_media_url(url_info['url']):
                            filepath = self.get_media_filepath(post, url_info['filename'])
                            media_item = {
                                'url': url_info['url'],
                                'filename': url_info['filename'],
                                'filepath': str(filepath),
                                'post_title': post_title,
                                'post_id': post_id
                            }
                            all_media.append(media_item)

                # Сохраняем в кэш
                if all_media:
                    self.save_media_cache(post_id, all_media)

                # Отправляем все медиа одним сигналом
                self.media_loaded.emit(all_media)
                self.status_updated.emit(f"Найдено {len(all_media)} медиафайлов")

            except Exception as e:
                error_message = str(e)
                self.status_updated.emit(f"Ошибка сбора медиа: {error_message}")

                # Отправляем сигнал об ошибке
                if post_id:
                    if "net::ERR_NAME_NOT_RESOLVED" in error_message or "Connection" in error_message:
                        self.media_load_error.emit(post_id, "Нет подключения к интернету")
                    elif "timeout" in error_message.lower():
                        self.media_load_error.emit(post_id, "Превышено время ожидания ответа сервера")
                    else:
                        self.media_load_error.emit(post_id, f"Ошибка сбора медиа: {error_message}")

        # Запускаем в отдельном потоке
        thread = threading.Thread(target=collect_worker, daemon=True)
        thread.start()

    def get_media_filepath(self, post, filename):
        """Получение пути для сохранения медиа"""
        # Получаем заголовок поста
        post_title = self.get_post_attr(post, 'title', 'untitled')
        safe_title = re.sub(r'[<>:"/\\|?*]', '_', str(post_title)[:50])

        # Получаем данные автора
        if self.current_artist:
            author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
        else:
            author_name = "неизвестный_автор"

        post_dir = Path("downloads") / author_name / safe_title
        return post_dir / filename

    # Навигация
    def prev_page(self):
        """Предыдущая страница"""
        if self.current_page > 0:
            self.current_page -= 1
            self.update_posts_display()
            self.update_ui_state()

    def next_page(self):
        """Следующая страница"""
        total_pages = (len(self.all_posts) + self.posts_per_page - 1) // self.posts_per_page
        if self.current_page < total_pages - 1:
            self.current_page += 1
            self.update_posts_display()
            self.update_ui_state()

    # Скачивание
    def download_all_posts(self):
        """Скачивание всех постов"""
        if not self.all_posts:
            return

        self.download_status_updated.emit("Сбор медиа из всех постов...")
        thread = threading.Thread(target=self._download_all_worker)
        thread.daemon = True
        thread.start()

    def download_selected_posts(self):
        """Скачивание выбранных постов"""
        selected_posts = []

        # Собираем выбранные посты по чекбоксам
        for i, checkbox in enumerate(self.post_checkboxes):
            if checkbox.isChecked():
                # Находим соответствующий пост (учитывая пагинацию)
                page_start = self.current_page * self.posts_per_page
                post_index = page_start + i
                if post_index < len(self.all_posts):
                    selected_posts.append(self.all_posts[post_index])

        if not selected_posts:
            self.download_status_updated.emit("Не выбрано ни одного поста")
            return

        self.download_status_updated.emit(f"Сбор медиа из {len(selected_posts)} выбранных постов...")
        thread = threading.Thread(target=self._download_selected_worker, args=(selected_posts,))
        thread.daemon = True
        thread.start()

    def _download_all_worker(self):
        """Рабочий поток для скачивания всех постов"""
        try:
            all_media = self.collect_all_media_from_posts_with_cache(self.all_posts)
            self.download_status_updated.emit(f"Найдено медиа: {len(all_media)}")
            if all_media:
                self._download_media_files(all_media)
        except Exception as e:
            self.download_status_updated.emit(f"Ошибка сбора медиа: {str(e)}")

    def _download_selected_worker(self, posts):
        """Рабочий поток для скачивания выбранных постов"""
        try:
            all_media = self.collect_all_media_from_posts_with_cache(posts)
            self.download_status_updated.emit(f"Найдено медиа: {len(all_media)}")
            if all_media:
                self._download_media_files(all_media)
        except Exception as e:
            self.download_status_updated.emit(f"Ошибка сбора медиа: {str(e)}")

    def collect_all_media_from_posts(self, posts):
        """Сбор медиа из нескольких постов"""
        if not self.parser:
            self.parser = KemonoParser(use_selenium=True, headless=True)

        all_media_info = []
        total_posts = len(posts)
        processed_posts = 0

        batch_size = 10
        post_batches = [posts[i:i + batch_size] for i in range(0, len(posts), batch_size)]

        for batch_idx, batch in enumerate(post_batches):
            batch_progress = int(((batch_idx) / len(post_batches)) * 100)
            self.download_status_updated.emit(f"Анализ постов {processed_posts}/{total_posts} ({batch_progress}%)")

            with ThreadPoolExecutor(max_workers=batch_size) as executor:
                future_to_post = {
                    executor.submit(self._analyze_post_worker, post): post
                    for post in batch
                }

                for future in as_completed(future_to_post):
                    post = future_to_post[future]
                    try:
                        post_media = future.result()
                        all_media_info.extend(post_media)
                    except Exception as e:
                        print(f"   [ERROR] Ошибка при анализе поста {post.id}: {str(e)}")

                    processed_posts += 1
                    progress = int((processed_posts / total_posts) * 100)
                    self.download_status_updated.emit(f"Анализ постов {processed_posts}/{total_posts} ({progress}%)")

        return all_media_info

    def collect_all_media_from_posts_with_cache(self, posts):
        """Сбор медиа из нескольких постов с использованием кэша"""
        all_media_info = []
        total_posts = len(posts)
        processed_posts = 0
        cached_posts = 0
        analyzed_posts = 0

        self.download_status_updated.emit("Проверка кэша медиа...")

        # Сначала проверяем кэш для всех постов
        for post in posts:
            post_id = self.get_post_attr(post, 'id', '')
            if post_id:
                cached_media = self.load_media_cache(post_id)
                if cached_media:
                    # Применяем фильтрацию по типам файлов к кэшированным данным
                    filtered_media = [media for media in cached_media if self.should_download_file(media)]
                    all_media_info.extend(filtered_media)
                    cached_posts += 1
                    processed_posts += 1
                    progress = int((processed_posts / total_posts) * 100)
                    self.download_status_updated.emit(f"Кэш проверен {processed_posts}/{total_posts} ({progress}%) - Кэш: {cached_posts}")

        # Для постов без кэша выполняем анализ
        posts_to_analyze = []
        for post in posts:
            post_id = self.get_post_attr(post, 'id', '')
            if not post_id or not self.load_media_cache(post_id):
                posts_to_analyze.append(post)

        if posts_to_analyze:
            self.download_status_updated.emit(f"Анализ {len(posts_to_analyze)} постов без кэша...")
            analyzed_media = self.collect_all_media_from_posts(posts_to_analyze)
            # Применяем фильтрацию к проанализированным данным
            for media in analyzed_media:
                if self.should_download_file(media):
                    all_media_info.append(media)
            analyzed_posts = len(posts_to_analyze)

        final_status = f"Медиа собрано: {len(all_media_info)} файлов"
        if cached_posts > 0:
            final_status += f" | Из кэша: {cached_posts} постов"
        if analyzed_posts > 0:
            final_status += f" | Проанализировано: {analyzed_posts} постов"

        self.download_status_updated.emit(final_status)
        return all_media_info

    def _analyze_post_worker(self, post):
        """Анализ одного поста для рабочего потока"""
        post_media = []

        post_title = self.get_post_attr(post, 'title', 'untitled')
        post_id = self.get_post_attr(post, 'id', '')

        safe_title = re.sub(r'[<>:"/\\|?*]', '_', str(post_title)[:50])
        author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
        post_dir = Path("downloads") / author_name / safe_title

        # Быстрый путь через attachments и files
        attachments = self.get_post_attr(post, 'attachments', [])
        for attachment in attachments:
            filename = attachment['name']
            url = attachment['url']
            if self.parser._is_valid_media_url(url):
                filepath = post_dir / filename
                post_media.append({
                    'url': url, 'filename': filename, 'filepath': str(filepath),
                    'post_title': post_title, 'post_id': post_id
                })

        files = self.get_post_attr(post, 'files', [])
        for file_info in files:
            filename = file_info['name']
            url = file_info['url']
            if self.parser._is_valid_media_url(url):
                filepath = post_dir / filename
                post_media.append({
                    'url': url, 'filename': filename, 'filepath': str(filepath),
                    'post_title': post_title, 'post_id': post_id
                })

        # Если нет вложений, анализируем HTML
        if not post_media:
            post_media_urls = self._analyze_post_for_media_safe(post)
            for url_info in post_media_urls:
                if self.parser._is_valid_media_url(url_info['url']):
                    filepath = post_dir / url_info['filename']
                    post_media.append({
                        'url': url_info['url'], 'filename': url_info['filename'], 'filepath': str(filepath),
                        'post_title': post_title, 'post_id': post_id
                    })

        # Сохраняем кэш медиа для этого поста (даже при массовом скачивании)
        if post_media:
            self.save_media_cache(post_id, post_media)

        return post_media

            # Операции с постами
    def select_all_posts(self):
        """Выбрать все посты на текущей странице"""
        for checkbox in self.post_checkboxes:
            checkbox.setChecked(True)
        self.download_status_updated.emit(f"Выбраны все посты на странице ({len(self.post_checkboxes)})")

    def deselect_all_posts(self):
        """Снять выбор со всех постов"""
        for checkbox in self.post_checkboxes:
            checkbox.setChecked(False)
        self.download_status_updated.emit("Снята отметка со всех постов")

        # Просмотр медиа
    def is_media_supported_by_viewer(self, media_item):
        """Проверяет, поддерживается ли тип файла встроенным просмотрщиком"""
        filename = media_item.get('filename', '')
        file_ext = Path(filename).suffix.lower()

        # MediaViewer поддерживает только изображения
        supported_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp']
        return file_ext in supported_extensions

    def open_media_viewer(self, media_item):
        """Открыть медиа файл в новом окне или в системной программе"""
        try:
            if self.is_media_supported_by_viewer(media_item):
                # Открываем во встроенном просмотрщике изображений
                viewer = MediaViewer(media_item, self)
                viewer.show()
            else:
                # Для неподдерживаемых файлов открываем в системной программе
                # Если файл не существует, он будет скачан с прогрессом
                self.open_file_with_default_app(media_item)
        except Exception as e:
            print(f"Ошибка открытия медиа: {e}")

    def open_file_with_default_app(self, media_item):
        """Открыть файл в программе по умолчанию для этого типа файлов"""
        try:
            filepath = Path(media_item['filepath'])

            # Если файл не существует, сначала скачиваем его
            if not filepath.exists():
                print(f"[DOWNLOAD] Файл не найден, скачиваем: {filepath.name}")
                self.download_single_file_with_progress(media_item)
                return

            # Открываем файл в системной программе
            import subprocess
            import platform

            if platform.system() == "Darwin":  # macOS
                subprocess.run(["open", str(filepath)], check=True)
            elif platform.system() == "Windows":
                import os
                os.startfile(str(filepath))
            elif platform.system() == "Linux":
                subprocess.run(["xdg-open", str(filepath)], check=True)

            print(f"[OPEN] Открыт файл: {filepath.name}")

        except Exception as e:
            print(f"Ошибка открытия файла: {e}")

    def show_current_post_in_finder(self):
        """Показать папку текущего поста в Finder"""
        try:
            if not self.selected_post:
                return

            # Получаем путь к папке поста
            post_title = self.get_post_attr(self.selected_post, 'title', 'untitled')
            author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
            safe_title = re.sub(r'[<>:"/\\|?*]', '_', str(post_title)[:50])
            post_dir = Path("downloads") / author_name / safe_title

            # Открываем папку в Finder
            import subprocess
            import platform

            if platform.system() == "Darwin":  # macOS
                if post_dir.exists():
                    subprocess.run(["open", str(post_dir)], check=True)
                else:
                    # Если папки нет, открываем родительскую папку автора
                    author_dir = Path("downloads") / author_name
                    if author_dir.exists():
                        subprocess.run(["open", str(author_dir)], check=True)
            elif platform.system() == "Windows":
                import os
                if post_dir.exists():
                    os.startfile(str(post_dir))
                else:
                    author_dir = Path("downloads") / author_name
                    if author_dir.exists():
                        os.startfile(str(author_dir))
            elif platform.system() == "Linux":
                if post_dir.exists():
                    subprocess.run(["xdg-open", str(post_dir)], check=True)
                else:
                    author_dir = Path("downloads") / author_name
                    if author_dir.exists():
                        subprocess.run(["xdg-open", str(author_dir)], check=True)

            print(f"[OPEN] Открыта папка поста: {post_title}")

        except Exception as e:
            print(f"Ошибка открытия папки в Finder: {e}")

    def download_single_file_with_progress(self, media_item):
        """Скачать один файл с отображением прогресса в карточке"""
        try:
            filepath = Path(media_item['filepath'])
            url = media_item['url']

            # Показываем прогресс-бар если он есть
            progress_bar = media_item.get('progress_bar')
            if progress_bar:
                progress_bar.setVisible(True)
                progress_bar.setValue(0)

            # Создаем директорию если не существует
            filepath.parent.mkdir(parents=True, exist_ok=True)

            # Скачиваем файл с прогрессом
            import requests
            response = requests.get(url, timeout=30, stream=True)
            response.raise_for_status()

            total_size = int(response.headers.get('content-length', 0))
            downloaded_size = 0

            with open(filepath, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded_size += len(chunk)

                        # Обновляем прогресс-бар если знаем общий размер
                        if total_size > 0 and progress_bar:
                            progress = int((downloaded_size / total_size) * 100)
                            # Обновляем прогресс-бар в главном потоке
                            progress_bar.setValue(progress)

            # Отмечаем файл как скачанный
            self.mark_file_downloaded(filepath)

            # Скрываем прогресс-бар после завершения
            if progress_bar:
                progress_bar.setVisible(False)

            # После завершения скачивания открываем файл
            self.open_file_with_default_app(media_item)

            print(f"[OK] Файл скачан и открыт: {filepath.name}")

        except Exception as e:
            print(f"Ошибка скачивания файла: {e}")
            # Скрываем прогресс-бар при ошибке
            progress_bar = media_item.get('progress_bar')
            if progress_bar:
                progress_bar.setVisible(False)

        # Медиа операции
    def select_all_media(self):
        """Выбрать все медиа"""
        for checkbox in self.media_checkboxes:
            checkbox.setChecked(True)
        self.download_status_updated.emit(f"Выбрано {len(self.media_checkboxes)} медиафайлов")

    def deselect_all_media(self):
        """Снять выбор со всех медиа"""
        for checkbox in self.media_checkboxes:
            checkbox.setChecked(False)
        self.download_status_updated.emit("Снята отметка со всех медиафайлов")

    def download_selected_media(self):
        """Скачать выбранные медиа"""
        selected_media = []
        selected_indices = []

        # Собираем выбранные медиа
        for i, checkbox in enumerate(self.media_checkboxes):
            if checkbox.isChecked():
                selected_media.append(self.current_media[i])
                selected_indices.append(i)

        if not selected_media:
            self.download_status_updated.emit("Не выбрано ни одного медиафайла")
            return

        self.download_status_updated.emit(f"Начинаем скачивание {len(selected_media)} медиафайлов...")

        # Скачиваем выбранные медиа
        self._download_media_files(selected_media)

    # История URL
    def load_url_history(self):
        """Загрузка истории URL"""
        try:
            if os.path.exists(self.history_file):
                with open(self.history_file, 'r', encoding='utf-8') as f:
                    self.url_history = json.load(f)
        except Exception as e:
            print(f"Ошибка загрузки истории: {e}")

    def save_url_history(self):
        """Сохранение истории URL"""
        try:
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(self.url_history, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"Ошибка сохранения истории: {e}")

    def add_url_to_history(self, url):
        """Добавление URL в историю"""
        if url in self.url_history:
            self.url_history.remove(url)
        self.url_history.insert(0, url)

        if len(self.url_history) > self.max_history_items:
            self.url_history = self.url_history[:self.max_history_items]

        self.save_url_history()

    def show_history_menu(self):
        """Показать меню истории"""
        menu = QMenu(self)

        if not self.url_history:
            no_history_action = menu.addAction("История пуста")
            no_history_action.setEnabled(False)
        else:
            for url in self.url_history:
                action = menu.addAction(url)
                action.triggered.connect(lambda checked, u=url: self.select_history_url(u))

        menu.exec(self.history_button.mapToGlobal(self.history_button.rect().bottomLeft()))

    def select_history_url(self, url):
        """Выбор URL из истории"""
        self.url_entry.setText(url)

    # Вспомогательные методы
    def clear_cache(self):
        """Очистка всего кэша с подтверждением"""
        reply = QMessageBox.question(
            self,
            "Подтверждение очистки кэша",
            "Вы уверены, что хотите очистить ВЕСЬ кэш?\n\n"
            "Это удалит:\n"
            "• Все сохраненные данные о постах\n"
            "• Все сохраненные превью изображений\n"
            "• Все метаданные медиафайлов\n"
            "• Список скачанных файлов\n\n"
            "При следующем запуске все данные потребуется загрузить заново.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No
        )

        if reply == QMessageBox.StandardButton.Yes:
            try:
                if self.clear_all_cache():
                    QMessageBox.information(self, "Успех", "Весь кэш успешно очищен")
                    self.status_updated.emit("Весь кэш очищен")
                else:
                    QMessageBox.warning(self, "Предупреждение", "Не удалось полностью очистить кэш")
            except Exception as e:
                QMessageBox.warning(self, "Ошибка", f"Не удалось очистить кэш: {str(e)}")

    def show_about(self):
        """Показать информацию о программе"""
        QMessageBox.about(
            self,
            "О программе",
            "Kemono.cr Parser v2\n\n"
            "Графический интерфейс для скачивания контента с Kemono.cr\n"
            "Разработано с использованием PyQt6"
        )

    def show_file_types_dialog(self):
        """Показать диалог выбора типов файлов"""
        dialog = FileTypesDialog(self, self.file_types_settings)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            self.file_types_settings = dialog.get_settings()
            self.save_file_types_settings()  # Сохраняем настройки
            self.statusBar().showMessage("Настройки типов файлов обновлены", 3000)
            print(f"🐛 DEBUG: Настройки типов файлов: {self.file_types_settings}")

    def save_file_types_settings(self):
        """Сохранить настройки типов файлов"""
        try:
            settings_path = Path("file_types_settings.json")
            with open(settings_path, 'w', encoding='utf-8') as f:
                json.dump(self.file_types_settings, f, ensure_ascii=False, indent=2)
            print(f"💾 Настройки типов файлов сохранены: {settings_path}")
        except Exception as e:
            print(f"[ERROR] Ошибка сохранения настроек типов файлов: {e}")

    def load_file_types_settings(self):
        """Загрузить настройки типов файлов"""
        try:
            settings_path = Path("file_types_settings.json")
            if settings_path.exists():
                with open(settings_path, 'r', encoding='utf-8') as f:
                    loaded_settings = json.load(f)
                    # Проверяем корректность загруженных настроек
                    if isinstance(loaded_settings, dict):
                        # Обновляем только существующие ключи
                        for key in self.file_types_settings.keys():
                            if key in loaded_settings:
                                self.file_types_settings[key] = loaded_settings[key]
                        print(f"[SETTINGS] Настройки типов файлов загружены: {settings_path}")
                        print(f"🐛 DEBUG: Загруженные настройки: {self.file_types_settings}")
                    else:
                        print("[WARN] Неверный формат настроек типов файлов, используем значения по умолчанию")
            else:
                print("[SETTINGS] Файл настроек типов файлов не найден, используем значения по умолчанию")
        except Exception as e:
            print(f"[ERROR] Ошибка загрузки настроек типов файлов: {e}")

    def get_file_type_categories(self):
        """Получить категории файлов по расширениям"""
        return {
            'images': {
                'jpg', 'jpeg', 'png', 'gif', 'webp', 'tiff', 'bmp', 'svg', 'ico'
            },
            'videos': {
                'mp4', 'avi', 'mkv', 'mov', 'wmv', 'webm', 'flv', 'm4v', '3gp', 'mpg', 'mpeg'
            },
            'archives': {
                'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'tbz2', 'iso'
            },
            'documents': {
                'psd', 'docx', 'doc', 'pdf', 'txt', 'rtf', 'odt', 'xls', 'xlsx',
                'ppt', 'pptx', 'ai', 'eps', 'cdr', 'dwg', 'dxf', 'obj', 'fbx',
                'blend', 'max', 'ma', 'mb', 'xml', 'json', 'csv', 'log', 'cfg', 'ini'
            }
        }

    def should_download_file(self, filename_or_url):
        """Проверить, нужно ли скачивать файл по его типу"""
        # Извлекаем расширение файла
        if isinstance(filename_or_url, dict) and 'filename' in filename_or_url:
            filename = filename_or_url['filename']
        elif isinstance(filename_or_url, str):
            filename = filename_or_url
        else:
            return True  # Если не можем определить, скачиваем по умолчанию

        # Получаем расширение файла (без точки)
        file_ext = Path(filename).suffix.lower().lstrip('.')

        # Получаем категории файлов
        categories = self.get_file_type_categories()

        # Проверяем, к какой категории относится файл
        for category, extensions in categories.items():
            if file_ext in extensions:
                # Проверяем, выбрана ли эта категория для скачивания
                return self.file_types_settings.get(category, True)

        # Если расширение не найдено в категориях, скачиваем (для неизвестных типов)
        return True


class FileTypesDialog(QDialog):
    """Диалоговое окно для выбора типов файлов для скачивания"""

    def __init__(self, parent=None, current_settings=None):
        super().__init__(parent)
        self.setWindowTitle("Выбор типов файлов")
        self.setModal(True)
        self.resize(400, 300)

        if current_settings is None:
            current_settings = {
                'images': True,
                'videos': True,
                'archives': True,
                'documents': True
            }

        self.settings = current_settings.copy()
        self.setup_ui()

    def setup_ui(self):
        """Настройка интерфейса диалога"""
        layout = QVBoxLayout(self)

        # Заголовок
        title_label = QLabel("Выберите типы файлов для скачивания:")
        title_label.setStyleSheet("font-weight: bold; font-size: 14px; margin-bottom: 10px;")
        layout.addWidget(title_label)

        # Группа для картинок
        images_group = QGroupBox("Картинки")
        images_layout = QVBoxLayout(images_group)
        self.images_checkbox = QCheckBox("JPG, JPEG, PNG, GIF, WebP, TIFF, BMP")
        self.images_checkbox.setChecked(self.settings.get('images', True))
        images_layout.addWidget(self.images_checkbox)
        layout.addWidget(images_group)

        # Группа для видео
        videos_group = QGroupBox("Видео")
        videos_layout = QVBoxLayout(videos_group)
        self.videos_checkbox = QCheckBox("MP4, AVI, MKV, MOV, WMV, WebM")
        self.videos_checkbox.setChecked(self.settings.get('videos', True))
        videos_layout.addWidget(self.videos_checkbox)
        layout.addWidget(videos_group)

        # Группа для архивов
        archives_group = QGroupBox("Архивы")
        archives_layout = QVBoxLayout(archives_group)
        self.archives_checkbox = QCheckBox("ZIP, RAR, 7Z, TAR, GZ")
        self.archives_checkbox.setChecked(self.settings.get('archives', True))
        archives_layout.addWidget(self.archives_checkbox)
        layout.addWidget(archives_group)

        # Группа для прочих файлов
        documents_group = QGroupBox("Прочие")
        documents_layout = QVBoxLayout(documents_group)
        self.documents_checkbox = QCheckBox("PSD, DOCX, DOC, PDF, TXT и другие")
        self.documents_checkbox.setChecked(self.settings.get('documents', True))
        documents_layout.addWidget(self.documents_checkbox)
        layout.addWidget(documents_group)

        # Кнопки управления
        buttons_layout = QHBoxLayout()

        self.select_all_btn = QPushButton("Выбрать все")
        self.select_all_btn.clicked.connect(self.select_all)

        self.deselect_all_btn = QPushButton("Снять все")
        self.deselect_all_btn.clicked.connect(self.deselect_all)

        buttons_layout.addWidget(self.select_all_btn)
        buttons_layout.addWidget(self.deselect_all_btn)
        buttons_layout.addStretch()

        layout.addLayout(buttons_layout)

        # Кнопки OK/Cancel
        button_box = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
        )
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)

    def select_all(self):
        """Выбрать все типы файлов"""
        self.images_checkbox.setChecked(True)
        self.videos_checkbox.setChecked(True)
        self.archives_checkbox.setChecked(True)
        self.documents_checkbox.setChecked(True)

    def deselect_all(self):
        """Снять выбор со всех типов файлов"""
        self.images_checkbox.setChecked(False)
        self.videos_checkbox.setChecked(False)
        self.archives_checkbox.setChecked(False)
        self.documents_checkbox.setChecked(False)

    def get_settings(self):
        """Получить выбранные настройки"""
        return {
            'images': self.images_checkbox.isChecked(),
            'videos': self.videos_checkbox.isChecked(),
            'archives': self.archives_checkbox.isChecked(),
            'documents': self.documents_checkbox.isChecked()
        }


def main():
    """Главная функция"""
    app = QApplication(sys.argv)

    # Устанавливаем стиль приложения
    app.setStyle('Fusion')

    # Создаем и показываем главное окно
    window = KemonoGUIv4()
    window.show()

    # Запускаем приложение
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
