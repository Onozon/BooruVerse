#!/usr/bin/env python3
"""
Графический интерфейс для Kemono.cr Parser v2
Создан на основе PyQt6 с современным дизайном
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

# PyQt6 импорты
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QGridLayout,
    QLabel, QPushButton, QLineEdit, QTextEdit, QProgressBar,
    QListWidget, QListWidgetItem, QFrame, QScrollArea, QSplitter,
    QMessageBox, QMenuBar, QMenu, QStatusBar, QCheckBox, QGroupBox,
    QSizePolicy, QComboBox, QDialog, QDialogButtonBox
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
from kemono_parser import KemonoParser
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
                    print(f"🖼️ Показываем превью: {pixmap.width()}x{pixmap.height()}")
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
            print(f"🔍 Проверяем файл: {correct_filepath}")

            if correct_filepath.exists():
                print(f"✅ Файл существует: {correct_filepath}")
                # Файл уже существует, загружаем его напрямую
                pixmap = QPixmap(str(correct_filepath))
                if not pixmap.isNull():
                    print(f"🖼️ Загружаем существующий файл: {pixmap.width()}x{pixmap.height()}")
                    # Отправляем сигнал для обновления GUI
                    self.full_image_loaded.emit(pixmap)
                    return
                else:
                    print(f"❌ Файл поврежден, удаляем: {correct_filepath}")
                    # Файл поврежден, удаляем и скачиваем заново
                    correct_filepath.unlink(missing_ok=True)

            print(f"📥 Скачиваем файл: {correct_filepath}")
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
                    print(f"🖼️ Отображаем скачанный файл: {pixmap.width()}x{pixmap.height()}")
                    self.full_image_loaded.emit(pixmap)
                else:
                    print(f"❌ Не удалось загрузить скачанный файл")
            else:
                print(f"❌ Ошибка скачивания: HTTP {response.status_code}")

        except Exception as e:
            print(f"❌ Ошибка загрузки полной версии медиа: {e}")

    def _get_correct_filepath(self):
        """Получить правильный путь для файла"""
        from pathlib import Path
        import re

        # Получаем информацию из media_item
        filename = Path(self.media_item['filename']).name
        post_title = self.media_item.get('post_title', 'Unknown')
        post_id = self.media_item.get('post_id', 'unknown')

        print(f"📄 Имя файла: {filename}")
        print(f"📝 Название поста: {post_title}")
        print(f"🆔 ID поста: {post_id}")

        # Получаем информацию об авторе из родительского окна
        parent = self.parent()
        if hasattr(parent, 'current_artist') and parent.current_artist:
            author_name = f"{parent.current_artist.service}_{parent.current_artist.name}_{parent.current_artist.id}"
            print(f"👤 Автор: {author_name}")
        else:
            author_name = "unknown_author"
            print(f"❓ Автор неизвестен")

        # Создаем безопасное название поста
        safe_title = re.sub(r'[<>:"/\\|?*]', '_', post_title[:50])
        print(f"📁 Безопасное название: {safe_title}")

        # Формируем путь
        post_dir = Path("downloads") / author_name / safe_title
        final_path = post_dir / filename
        print(f"🎯 Итоговый путь: {final_path}")
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
        print(f"🔄 Заменяем превью на полную версию: {pixmap.width()}x{pixmap.height()}")
        print(f"📏 Размеры окна: {self.size().width()}x{self.size().height()}")
        self.display_image(pixmap, save_original=True)
        self.is_full_image_loaded = True
        print("✅ Превью заменено на полную версию")

    def resizeEvent(self, event):
        """Обработчик изменения размера окна"""
        super().resizeEvent(event)
        # Перемасштабируем изображение при изменении размера окна
        if self.original_pixmap and not self.original_pixmap.isNull():
            self.display_image(self.original_pixmap)
        elif hasattr(self, 'image_label') and self.image_label.pixmap():
            self.display_image(self.image_label.pixmap())


class KemonoGUI(QMainWindow):
    """Главное окно приложения Kemono.cr Parser v2"""

    # Сигналы для обновления GUI из других потоков
    status_updated = pyqtSignal(str)
    progress_updated = pyqtSignal(int, int)  # current, total
    posts_loaded = pyqtSignal(list)
    media_loaded = pyqtSignal(list)
    update_thumbnail_pixmap = pyqtSignal(object, object)  # label, pixmap
    update_thumbnail_text = pyqtSignal(object, str)  # label, text
    download_status_updated = pyqtSignal(str)  # Детальный статус загрузки

    def __init__(self):
        super().__init__()
        self.setWindowTitle("🎨 Kemono.cr Parser v2 - Qt Edition")
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

        # Система повторных попыток
        self.failed_previews = set()
        self.retry_thread = None
        self.retry_active = False

        # Инициализация интерфейса
        self.setup_ui()
        self.setup_connections()
        self.load_initial_state()

    def setup_ui(self):
        """Настройка пользовательского интерфейса"""
        # Центральный виджет
        central_widget = QWidget()
        self.setCentralWidget(central_widget)

        # Основной layout
        main_layout = QVBoxLayout(central_widget)

        # Верхняя панель управления
        self.setup_top_panel(main_layout)

        # Основная область с разделителем
        self.setup_main_area(main_layout)

        # Статус бар
        self.setup_status_bar()

        # Меню
        self.setup_menu()

    def setup_top_panel(self, parent_layout):
        """Настройка верхней панели управления"""
        top_frame = QFrame()
        top_frame.setMaximumHeight(60)  # Ограничиваем высоту
        top_layout = QHBoxLayout(top_frame)
        top_layout.setContentsMargins(10, 5, 10, 5)  # Уменьшаем отступы

        # Поле URL
        url_label = QLabel("URL автора:")
        self.url_entry = QLineEdit()
        self.url_entry.setPlaceholderText("https://kemono.cr/fanbox/user/123456")

        # Кнопка истории
        self.history_button = QPushButton("📚")
        self.history_button.setMaximumWidth(40)
        self.history_button.setToolTip("История запросов")

        # Кнопка загрузки
        self.load_button = QPushButton("🔍 Загрузить посты")
        self.load_button.setMinimumWidth(150)

        # Добавляем элементы
        top_layout.addWidget(url_label)
        top_layout.addWidget(self.url_entry)
        top_layout.addWidget(self.history_button)
        top_layout.addWidget(self.load_button)
        top_layout.addStretch()

        parent_layout.addWidget(top_frame)

    def setup_main_area(self, parent_layout):
        """Настройка основной рабочей области"""
        # Создаем разделитель
        splitter = QSplitter(Qt.Orientation.Horizontal)

        # Левая панель - посты
        self.setup_posts_panel(splitter)

        # Правая панель - медиа
        self.setup_media_panel(splitter)

        # Настраиваем пропорции разделителя (больше места для постов и медиа)
        splitter.setSizes([int(self.width() * 0.4), int(self.width() * 0.6)])

        # Добавляем разделитель в основной layout
        parent_layout.addWidget(splitter)

        # Убираем дублированную область прогресса - статус уже в статус-баре

    def setup_posts_panel(self, splitter):
        """Настройка панели постов"""
        posts_widget = QWidget()
        posts_layout = QVBoxLayout(posts_widget)

        # Заголовок
        posts_label = QLabel("📄 Посты автора")
        posts_label.setStyleSheet("font-weight: bold; font-size: 14px;")
        posts_layout.addWidget(posts_label)

        # Контролы пагинации
        pagination_layout = QHBoxLayout()

        self.prev_page_btn = QPushButton("⬅️ Назад")
        self.page_label = QLabel("Страница 1/1")
        self.next_page_btn = QPushButton("Вперед ➡️")

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
        self.select_all_posts_btn = QPushButton("☑️ Выбрать все")
        self.deselect_all_posts_btn = QPushButton("☐ Снять все")
        self.download_all_btn = QPushButton("📥 Скачать все посты")
        self.download_selected_btn = QPushButton("📥 Скачать выбранные")

        actions_layout.addWidget(self.select_all_posts_btn)
        actions_layout.addWidget(self.deselect_all_posts_btn)
        actions_layout.addWidget(self.download_all_btn)
        actions_layout.addWidget(self.download_selected_btn)

        posts_layout.addLayout(actions_layout)

        splitter.addWidget(posts_widget)

    def setup_media_panel(self, splitter):
        """Настройка панели медиа"""
        media_widget = QWidget()
        media_layout = QVBoxLayout(media_widget)

        # Заголовок
        self.media_label = QLabel("🖼️ Медиафайлы поста")
        self.media_label.setStyleSheet("font-weight: bold; font-size: 14px;")
        media_layout.addWidget(self.media_label)

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

        self.select_all_media_btn = QPushButton("☑️ Выбрать все")
        self.deselect_all_media_btn = QPushButton("☐ Снять все")
        self.download_media_btn = QPushButton("📥 Скачать выбранные")

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
        self.update_thumbnail_pixmap.connect(self.on_update_thumbnail_pixmap)
        self.update_thumbnail_text.connect(self.on_update_thumbnail_text)
        self.download_status_updated.connect(self.on_download_status_updated)

        # URL поле
        self.url_entry.returnPressed.connect(self.load_artist_posts)

    def load_initial_state(self):
        """Загрузка начального состояния"""
        self.load_url_history()
        self.update_ui_state()

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
                    print(f"❌ Поврежденное изображение {url}: {img_error}")
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
                        # TODO: Обновить GUI для отображения загруженного превью
                    else:
                        print(f"❌ Не удалось загрузить превью после повторных попыток: {url}")
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
        errors = 0
        error_details = []

        self.download_status_updated.emit(f"Загрузка медиа 0/{total} (0%)")

        for i, media_item in enumerate(media_files, 1):
            url = media_item['url']
            filepath = Path(media_item['filepath'])

            # Проверяем, существует ли файл уже
            if filepath.exists():
                already_exists += 1
                progress = int((i / total) * 100)
                self.download_status_updated.emit(f"Загрузка медиа {i}/{total} ({progress}%) - Уже существует")
                continue

            # Скачиваем файл
            if self._download_single_file(url, filepath):
                downloaded += 1
            else:
                errors += 1
                error_details.append(f"Не удалось скачать: {filepath.name}")
                print(f"Не удалось скачать: {url}")

            # Обновляем статус
            progress = int((i / total) * 100)
            self.download_status_updated.emit(f"Загрузка медиа {i}/{total} ({progress}%)")

        # Формируем итоговый статус
        status_parts = []
        if downloaded > 0:
            status_parts.append(f"Загружено: {downloaded}")
        if already_exists > 0:
            status_parts.append(f"Уже было: {already_exists}")
        if errors > 0:
            status_parts.append(f"Ошибки: {errors}")

        final_status = "Медиа " + " | ".join(status_parts)

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

        safe_title = re.sub(r'[<>:"/\\|?*]', '_', post.title[:50])
        author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
        post_dir = Path("downloads") / author_name / safe_title

        # Быстрый путь через attachments и files
        for attachment in post.attachments:
            filename = attachment['name']
            url = attachment['url']
            if self.parser._is_valid_media_url(url):
                filepath = post_dir / filename
                post_media.append({
                    'url': url, 'filename': filename, 'filepath': str(filepath),
                    'post_title': post.title, 'post_id': post.id
                })

        for file_info in post.files:
            filename = file_info['name']
            url = file_info['url']
            if self.parser._is_valid_media_url(url):
                filepath = post_dir / filename
                post_media.append({
                    'url': url, 'filename': filename, 'filepath': str(filepath),
                    'post_title': post.title, 'post_id': post.id
                })

        # Если нет вложений, анализируем HTML
        if not post_media:
            post_media_urls = self._analyze_post_for_media_safe(post)
            for url_info in post_media_urls:
                if self.parser._is_valid_media_url(url_info['url']):
                    filepath = post_dir / url_info['filename']
                    post_media.append({
                        'url': url_info['url'], 'filename': url_info['filename'], 'filepath': str(filepath),
                        'post_title': post.title, 'post_id': post.id
                    })

        return post_media

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
            print(f"   ❌ Ошибка анализа поста {post.id}: {e}")

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

        self.status_updated.emit("Загрузка постов автора...")
        self.progress_updated.emit(0, 0)  # Показываем прогресс-бар

        # Запускаем в отдельном потоке
        thread = threading.Thread(target=self._load_posts_worker, args=(url,))
        thread.daemon = True
        thread.start()

    def _load_posts_worker(self, url):
        """Рабочий поток для загрузки постов"""
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

            # Загружаем все посты
            posts = self.parser.get_all_artist_posts(artist)
            self.all_posts = posts

            # Добавляем URL в историю
            self.add_url_to_history(url)

            self.status_updated.emit(f"Загружено {len(posts)} постов")
            self.posts_loaded.emit(posts)

        except Exception as e:
            self.status_updated.emit(f"Ошибка загрузки: {str(e)}")
        finally:
            self.progress_updated.emit(0, 0)  # Скрываем прогресс-бар

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
        self.update_posts_display()
        self.update_ui_state()

    def on_media_loaded(self, media):
        """Обработчик загрузки медиа"""
        self.current_media = media
        self.update_media_display()
        self.update_ui_state()

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

        self.posts_layout.addLayout(posts_grid)
        self.posts_layout.addStretch()

    def clear_posts_layout(self):
        """Очистка layout постов"""
        while self.posts_layout.count():
            item = self.posts_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

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
        if hasattr(post, 'thumbnail') and post.thumbnail:
            self.load_post_thumbnail_async(post, thumbnail_label)

        # Чекбокс в углу превью
        checkbox = QCheckBox()
        checkbox.setStyleSheet("QCheckBox { margin: 5px; }")
        self.post_checkboxes.append(checkbox)  # Добавляем чекбокс поста в список

        # Оверлей для чекбокса
        overlay_layout = QVBoxLayout()
        overlay_layout.addWidget(checkbox, alignment=Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignRight)
        overlay_layout.addStretch()

        # Композитный виджет для превью + чекбокс
        preview_widget = QWidget()
        preview_layout = QVBoxLayout(preview_widget)
        preview_layout.setContentsMargins(0, 0, 0, 0)
        preview_layout.addWidget(thumbnail_label)
        preview_layout.addLayout(overlay_layout)

        # Информация о посте
        info_layout = QVBoxLayout()

        title_label = QLabel(f"{post.title[:35]}...")
        title_label.setStyleSheet("font-weight: bold; font-size: 11px;")
        title_label.setWordWrap(True)

        # Форматируем дату из published
        date_str = "Дата неизвестна"
        if hasattr(post, 'published') and post.published:
            try:
                date_str = post.published[:10]  # YYYY-MM-DD
            except:
                date_str = str(post.published)

        date_label = QLabel(f"📅 {date_str}")
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
                if hasattr(post, 'thumbnail') and post.thumbnail:
                    # Загружаем превью
                    cached_path = self.download_and_cache_preview(
                        post.thumbnail,
                        size=(200, 150),
                        preview_type="post",
                        max_retries=2
                    )

                    if cached_path:
                        # Создаем QPixmap и устанавливаем в label
                        pixmap = QPixmap(cached_path)
                        if not pixmap.isNull():
                            scaled_pixmap = pixmap.scaled(
                                200, 150,
                                Qt.AspectRatioMode.KeepAspectRatio,
                                Qt.TransformationMode.SmoothTransformation
                            )
                            # Обновляем GUI в главном потоке
                            thumbnail_label.setPixmap(scaled_pixmap)
                        else:
                            thumbnail_label.setText("🖼️ Нет превью")
                    else:
                        thumbnail_label.setText("🖼️ Нет превью")
                else:
                    thumbnail_label.setText("🖼️ Нет превью")

            except Exception as e:
                print(f"Ошибка загрузки превью поста {post.id}: {e}")
                thumbnail_label.setText("🖼️ Ошибка")

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
                url = media_item['url']
                filename = media_item['filename']
                result_pixmap = None
                result_text = None

                # Для изображений пытаемся загрузить превью
                file_ext = Path(filename).suffix.lower()
                if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
                    # Загружаем превью изображения
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
        label.setPixmap(pixmap)

    def on_update_thumbnail_text(self, label, text):
        """Обработчик сигнала обновления текста превью"""
        label.setText(text)

    def on_download_status_updated(self, status_text):
        """Обработчик сигнала обновления статуса загрузки"""
        self.status_bar.showMessage(status_text)

    def _get_file_icon_text(self, filename):
        """Возвращает текст иконки для файла"""
        file_ext = Path(filename).suffix.lower()
        if file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
            return "🖼️"
        elif file_ext in ['.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv']:
            return "🎬"
        elif file_ext in ['.zip', '.rar', '.7z', '.tar', '.gz']:
            return "📦"
        else:
            return "📄"

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

        # Оверлей для чекбокса
        overlay_layout = QVBoxLayout()
        overlay_layout.addWidget(checkbox, alignment=Qt.AlignmentFlag.AlignTop | Qt.AlignmentFlag.AlignRight)
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
            file_type = "🖼️ Изображение"
        elif file_ext in ['.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv']:
            file_type = "🎬 Видео"
        elif file_ext in ['.zip', '.rar', '.7z', '.tar', '.gz']:
            file_type = "📦 Архив"
        else:
            file_type = "📄 Файл"

        type_label = QLabel(file_type)
        type_label.setStyleSheet("font-size: 9px; color: #666;")

        info_layout.addWidget(filename_label)
        info_layout.addWidget(type_label)
        info_layout.addStretch()

        layout.addWidget(preview_widget)
        layout.addLayout(info_layout)

        # Обработчик двойного клика для открытия медиа в новом окне
        card_frame.mouseDoubleClickEvent = lambda event, item=media_item: self.open_media_viewer(item)

        grid_layout.addWidget(card_frame, row, col)

    # Обработчики событий
    def on_post_clicked(self, post, frame):
        """Обработчик клика по посту"""
        self.selected_post = post
        self.media_label.setText(f"🖼️ Медиафайлы: {post.title}")

        # Загружаем медиа для поста
        self.status_updated.emit("Поиск медиафайлов...")
        thread = threading.Thread(target=self._load_media_worker, args=(post,))
        thread.daemon = True
        thread.start()

    def _load_media_worker(self, post):
        """Рабочий поток для загрузки медиа (асинхронно)"""
        try:
            # Очищаем текущие медиа
            self.current_media = []

            # Запускаем асинхронный сбор медиа
            self.collect_media_from_post_async(post)

        except Exception as e:
            self.status_updated.emit(f"Ошибка загрузки медиа: {str(e)}")

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

                # Сначала обрабатываем attachments
                for attachment in post.attachments:
                    filename = attachment['name']
                    url = attachment['url']
                    if self.parser and self.parser._is_valid_media_url(url):
                        filepath = self.get_media_filepath(post, filename)
                        media_item = {
                            'url': url,
                            'filename': filename,
                            'filepath': str(filepath),
                            'post_title': post.title,
                            'post_id': post.id
                        }
                        all_media.append(media_item)

                # Затем обрабатываем files
                for file_info in post.files:
                    filename = file_info['name']
                    url = file_info['url']
                    if self.parser and self.parser._is_valid_media_url(url):
                        filepath = self.get_media_filepath(post, filename)
                        media_item = {
                            'url': url,
                            'filename': filename,
                            'filepath': str(filepath),
                            'post_title': post.title,
                            'post_id': post.id
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
                                'post_title': post.title,
                                'post_id': post.id
                            }
                            all_media.append(media_item)

                # Отправляем все медиа одним сигналом
                self.media_loaded.emit(all_media)
                self.status_updated.emit(f"Найдено {len(all_media)} медиафайлов")

            except Exception as e:
                self.status_updated.emit(f"Ошибка сбора медиа: {str(e)}")

        # Запускаем в отдельном потоке
        thread = threading.Thread(target=collect_worker, daemon=True)
        thread.start()

    def get_media_filepath(self, post, filename):
        """Получение пути для сохранения медиа"""
        safe_title = re.sub(r'[<>:"/\\|?*]', '_', post.title[:50])
        author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
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
            all_media = self.collect_all_media_from_posts(self.all_posts)
            self.download_status_updated.emit(f"Найдено медиа: {len(all_media)}")
            if all_media:
                self._download_media_files(all_media)
        except Exception as e:
            self.download_status_updated.emit(f"Ошибка сбора медиа: {str(e)}")

    def _download_selected_worker(self, posts):
        """Рабочий поток для скачивания выбранных постов"""
        try:
            all_media = self.collect_all_media_from_posts(posts)
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
                        print(f"   ❌ Ошибка при анализе поста {post.id}: {str(e)}")

                    processed_posts += 1
                    progress = int((processed_posts / total_posts) * 100)
                    self.download_status_updated.emit(f"Анализ постов {processed_posts}/{total_posts} ({progress}%)")

        return all_media_info

    def _analyze_post_worker(self, post):
        """Анализ одного поста для рабочего потока"""
        post_media = []

        safe_title = re.sub(r'[<>:"/\\|?*]', '_', post.title[:50])
        author_name = f"{self.current_artist.service}_{self.current_artist.name}_{self.current_artist.id}"
        post_dir = Path("downloads") / author_name / safe_title

        # Быстрый путь через attachments и files
        for attachment in post.attachments:
            filename = attachment['name']
            url = attachment['url']
            if self.parser._is_valid_media_url(url):
                filepath = post_dir / filename
                post_media.append({
                    'url': url, 'filename': filename, 'filepath': str(filepath),
                    'post_title': post.title, 'post_id': post.id
                })

        for file_info in post.files:
            filename = file_info['name']
            url = file_info['url']
            if self.parser._is_valid_media_url(url):
                filepath = post_dir / filename
                post_media.append({
                    'url': url, 'filename': filename, 'filepath': str(filepath),
                    'post_title': post.title, 'post_id': post.id
                })

        # Если нет вложений, анализируем HTML
        if not post_media:
            post_media_urls = self._analyze_post_for_media_safe(post)
            for url_info in post_media_urls:
                if self.parser._is_valid_media_url(url_info['url']):
                    filepath = post_dir / url_info['filename']
                    post_media.append({
                        'url': url_info['url'], 'filename': url_info['filename'], 'filepath': str(filepath),
                        'post_title': post.title, 'post_id': post.id
                    })

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
    def open_media_viewer(self, media_item):
        """Открыть медиа файл в новом окне"""
        try:
            viewer = MediaViewer(media_item, self)
            viewer.show()
        except Exception as e:
            print(f"Ошибка открытия просмотра медиа: {e}")

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
        """Очистка кэша"""
        try:
            import shutil
            if self.cache_dir.exists():
                shutil.rmtree(self.cache_dir)
                self.cache_dir.mkdir(exist_ok=True)
                self.post_thumbnails_dir.mkdir(exist_ok=True)
                self.media_previews_dir.mkdir(exist_ok=True)

            self.preview_cache.clear()
            self.url_validation_cache.clear()

            QMessageBox.information(self, "Успех", "Кэш очищен")
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


def main():
    """Главная функция"""
    app = QApplication(sys.argv)

    # Устанавливаем стиль приложения
    app.setStyle('Fusion')

    # Создаем и показываем главное окно
    window = KemonoGUI()
    window.show()

    # Запускаем приложение
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
