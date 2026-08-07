"""
Kemono.cr Parser
Парсер для сайта kemono.cr - агрегатора контента из Patreon, Fanbox и других платформ
"""

import requests
import json
import os
import time
import re
from urllib.parse import urljoin, urlparse
from typing import List, Dict, Optional, Union
from dataclasses import dataclass
from pathlib import Path
import logging
from fake_useragent import UserAgent
from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
from tqdm import tqdm


@dataclass
class Artist:
    """Класс для представления автора"""
    id: str
    service: str
    name: str
    indexed: str
    updated: str
    url: str
    avatar: str = ""  # URL аватарки автора

    def __post_init__(self):
        if not self.url:
            self.url = f"https://kemono.cr/{self.service}/user/{self.id}"
        # Формируем URL аватарки, если не указан
        if not self.avatar and self.service and self.id:
            self.avatar = f"https://img.kemono.cr/icons/{self.service}/{self.id}"


@dataclass
class Post:
    """Класс для представления поста"""
    id: str
    title: str
    content: str
    published: str
    edited: Optional[str]
    author: str
    service: str
    url: str  # URL поста
    thumbnail: Optional[str]  # URL превью поста
    attachments: List[Dict]
    embeds: List[Dict]
    files: List[Dict]


class KemonoParser:
    """Основной класс парсера Kemono.cr"""

    def __init__(self, base_url: str = "https://kemono.cr", use_selenium: bool = False, headless: bool = True):
        self.base_url = base_url
        self.use_selenium = use_selenium
        self.headless = headless  # Сохраняем параметр headless
        self.session = requests.Session()
        self.ua = UserAgent()

        # Настройка сессии
        self.session.headers.update({
            'User-Agent': self.ua.random,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
        })

        # Настройка Selenium если нужно
        if self.use_selenium:
            self.driver = self._setup_selenium_driver(headless)

        # Настройка логирования
        self.logger = logging.getLogger(__name__)
        self.logger.setLevel(logging.DEBUG)  # Изменено на DEBUG для более подробного логирования

        if not self.logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)

    def _setup_selenium_driver(self, headless: bool = True) -> webdriver.Chrome:
        """Настройка Selenium WebDriver с расширенными stealth настройками"""
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
        import random

        options = Options()

        if headless:
            options.add_argument('--headless')

        # Расширенные stealth настройки
        options.add_argument('--no-sandbox')
        options.add_argument('--disable-dev-shm-usage')
        options.add_argument('--disable-gpu')
        options.add_argument('--window-size=1366,768')
        options.add_argument('--disable-blink-features=AutomationControlled')
        options.add_experimental_option("excludeSwitches", ["enable-automation"])
        options.add_experimental_option('useAutomationExtension', False)

        # Дополнительные настройки для обхода защиты
        options.add_argument('--disable-web-security')
        options.add_argument('--disable-features=VizDisplayCompositor')
        options.add_argument('--disable-extensions')
        options.add_argument('--no-first-run')
        options.add_argument('--disable-default-apps')
        options.add_argument('--disable-infobars')
        options.add_argument('--disable-notifications')
        options.add_argument('--disable-popup-blocking')
        options.add_argument('--disable-background-timer-throttling')
        options.add_argument('--disable-backgrounding-occluded-windows')
        options.add_argument('--disable-renderer-backgrounding')

        # Режим инкогнито для обхода cookie-based защиты
        options.add_argument('--incognito')
        options.add_argument('--disable-plugins')
        options.add_argument('--disable-plugins-discovery')

        # Отключаем кэширование
        options.add_argument('--disable-cache')
        options.add_argument('--disable-application-cache')
        options.add_argument('--disable-offline-load-stale-cache')
        options.add_argument('--disk-cache-dir=/dev/null')

        # Блокировка редиректов
        options.add_argument('--disable-features=VizDisplayCompositor,VizHitTestSurfaceLayer')

        # Отключаем некоторые проверки безопасности
        options.add_argument('--disable-blink-features=AutomationControlled')
        options.add_argument('--disable-component-extensions-with-background-pages')

        # Отключаем вебRTC для предотвращения fingerprinting
        options.add_argument('--disable-webrtc')

        # Случайный User-Agent из списка реальных браузеров
        user_agents = [
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15'
        ]

        selected_ua = random.choice(user_agents)
        options.add_argument(f'--user-agent={selected_ua}')

        # Логируем только если logger уже инициализирован
        if hasattr(self, 'logger'):
            self.logger.info(f"🎭 Using User-Agent: {selected_ua}")

        # Используем webdriver-manager для автоматической установки
        from selenium.webdriver.chrome.service import Service
        from webdriver_manager.chrome import ChromeDriverManager

        driver = webdriver.Chrome(
            service=Service(ChromeDriverManager().install()),
            options=options
        )

        # Расширенные техники скрытия автоматизации
        driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

        # Маскировка navigator.plugins
        driver.execute_script("""
            Object.defineProperty(navigator, 'plugins', {
                get: () => [
                    {0: {type: "application/x-google-chrome-pdf", suffixes: "pdf", description: "Portable Document Format", __pluginName: "Chrome PDF Plugin"},
                     description: "Portable Document Format", filename: "internal-pdf-viewer", length: 1, name: "Chrome PDF Plugin"}
                ]
            });
        """)

        # Маскировка navigator.languages
        driver.execute_script("""
            Object.defineProperty(navigator, 'languages', {
                get: () => ['en-US', 'en', 'ru']
            });
        """)

        # Установка дополнительных свойств
        driver.execute_script("""
            Object.defineProperty(navigator, 'platform', {
                get: () => 'MacIntel'
            });
        """)

        # Загружаем и внедряем блокировщик редиректов
        try:
            with open('block_redirects.js', 'r', encoding='utf-8') as f:
                redirect_blocker_js = f.read()

            driver.execute_script(redirect_blocker_js)
            if hasattr(self, 'logger'):
                self.logger.info("✅ Redirect blocker script loaded")
        except FileNotFoundError:
            if hasattr(self, 'logger'):
                self.logger.warning("⚠️ block_redirects.js not found, using basic redirect blocking")

            # Базовая блокировка редиректов
            driver.execute_script("""
                // Блокировка window.open для внешних ссылок
                const originalOpen = window.open;
                window.open = function(url, ...args) {
                    if (url && (url.includes('nachdiewelt.click') || url.includes('quantum'))) {
                        console.log('Blocked external window.open:', url);
                        return null;
                    }
                    return originalOpen.call(this, url, ...args);
                };

                // Перехватываем события кликов
                document.addEventListener('click', function(e) {
                    const target = e.target;
                    if (target && target.href) {
                        if (target.href.includes('nachdiewelt.click') || target.href.includes('quantum')) {
                            console.log('Blocked external link click:', target.href);
                            e.preventDefault();
                            e.stopPropagation();
                            return false;
                        }
                    }
                }, true);
            """)
        except Exception as e:
            if hasattr(self, 'logger'):
                self.logger.warning(f"⚠️ Failed to load redirect blocker: {e}")

        # Логируем только если logger уже инициализирован
        if hasattr(self, 'logger'):
            self.logger.info("✅ Selenium driver configured with advanced stealth settings and redirect blocking")
        return driver

    def _make_request(self, url: str, method: str = 'GET', **kwargs) -> Optional[requests.Response]:
        """Выполнение HTTP запроса с обработкой ошибок"""
        try:
            self.logger.info(f"Making {method} request to {url}")
            response = self.session.request(method, url, **kwargs)
            response.raise_for_status()

            # Обновляем User-Agent время от времени
            if hasattr(self, '_request_count'):
                self._request_count += 1
            else:
                self._request_count = 1

            if self._request_count % 10 == 0:
                self.session.headers.update({'User-Agent': self.ua.random})

            return response
        except requests.exceptions.RequestException as e:
            self.logger.error(f"Request failed: {e}")
            return None

    def _selenium_get(self, url: str) -> Optional[str]:
        """Получение страницы через Selenium"""
        if not self.use_selenium:
            return None

        try:
            self.logger.info(f"Selenium getting {url}")
            self.driver.get(url)

            # Ждем загрузки body (уменьшаем время ожидания)
            WebDriverWait(self.driver, 10).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )

            # Оптимизированное ожидание для загрузки JavaScript контента
            # Вместо фиксированной задержки используем умное ожидание
            max_wait = 8  # Максимум 8 секунд ожидания
            wait_step = 1  # Проверяем каждую секунду

            for i in range(max_wait):
                try:
                    posts = self.driver.find_elements(By.CSS_SELECTOR, 'article.post-card, article[data-id]')
                    if len(posts) > 0:
                        self.logger.info(f"Selenium found {len(posts)} posts after {i+1}s")
                        break
                    time.sleep(wait_step)
                except:
                    time.sleep(wait_step)

            # Финальная проверка количества постов
            final_posts = self.driver.find_elements(By.CSS_SELECTOR, 'article.post-card, article[data-id]')
            self.logger.info(f"Selenium found {len(final_posts)} posts on page")

            html = self.driver.page_source
            self.logger.info(f"Retrieved HTML length: {len(html)}")

            return html

        except Exception as e:
            self.logger.error(f"Selenium request failed: {e}")
            return None

    def get_artists_list(self, service: Optional[str] = None, limit: int = 100) -> List[Artist]:
        """Получение списка авторов"""
        artists = []

        if service:
            url = f"{self.base_url}/{service}"
        else:
            url = self.base_url

        try:
            if self.use_selenium:
                html = self._selenium_get(url)
                if not html:
                    return artists
                soup = BeautifulSoup(html, 'lxml')
            else:
                response = self._make_request(url)
                if not response:
                    return artists
                soup = BeautifulSoup(response.content, 'lxml')

            # Парсим авторов с главной страницы
            artist_cards = soup.find_all('article', class_='card')

            for card in artist_cards[:limit]:
                try:
                    link = card.find('a', href=True)
                    if link:
                        href = link['href']
                        # Парсим URL вида /service/user/id
                        parts = href.strip('/').split('/')
                        if len(parts) >= 3:
                            service_name = parts[0]
                            user_id = parts[2]

                            name_elem = card.find('h2') or card.find('header')
                            name = name_elem.text.strip() if name_elem else f"User_{user_id}"

                            # Создаем объект Artist с правильными полями
                            artist = Artist(
                                id=user_id,
                                service=service_name,
                                name=name,
                                indexed="",
                                updated="",
                                url=f"{self.base_url}{href}"
                            )
                            artists.append(artist)
                except Exception as e:
                    self.logger.error(f"Error parsing artist card: {e}")
                    continue

        except Exception as e:
            self.logger.error(f"Error getting artists list: {e}")

        return artists

    def get_artists_page(self, page_url: str, limit: int = 100) -> List[Artist]:
        """Получение списка авторов с конкретной страницы браузера"""
        artists = []

        try:
            if self.use_selenium:
                html = self._selenium_get(page_url)
                if not html:
                    return artists
                soup = BeautifulSoup(html, 'lxml')
            else:
                response = self._make_request(page_url)
                if not response:
                    return artists
                soup = BeautifulSoup(response.content, 'lxml')

            # Парсим авторов с страницы
            artist_cards = soup.find_all('a', class_='user-card')

            for card in artist_cards[:limit]:
                try:
                    # card уже является ссылкой <a>
                    href = card.get('href', '')
                    if href:
                        # Парсим URL вида /service/user/id
                        parts = href.strip('/').split('/')
                        if len(parts) >= 3:
                            service_name = parts[0]
                            user_id = parts[2]

                            # Ищем имя в user-card__name
                            name_elem = card.find('div', class_='user-card__name')
                            if not name_elem:
                                # Fallback: ищем в других элементах
                                name_elem = card.find('h2') or card.find('header')
                            
                            name = name_elem.text.strip() if name_elem else f"User_{user_id}"

                            # Создаем объект Artist с правильными полями
                            artist = Artist(
                                id=user_id,
                                service=service_name,
                                name=name,
                                indexed="",
                                updated="",
                                url=f"{self.base_url}{href}"
                            )
                            artists.append(artist)
                except Exception as e:
                    self.logger.error(f"Error parsing artist card: {e}")
                    continue

        except Exception as e:
            self.logger.error(f"Error getting artists page {page_url}: {e}")

        return artists

    def search_artists_on_page(self, query: str, limit: int = 100) -> List[Artist]:
        """Поиск авторов на странице /artists с использованием поискового поля"""
        artists = []

        try:
            if not self.use_selenium:
                self.logger.warning("Search requires Selenium for form interaction")
                return artists

            # Открываем страницу авторов
            search_url = f"{self.base_url}/artists"
            html = self._selenium_get(search_url)
            if not html:
                return artists

            # Находим поисковое поле и вводим запрос
            from selenium.webdriver.common.by import By
            from selenium.webdriver.support.ui import WebDriverWait
            from selenium.webdriver.support import expected_conditions as EC

            try:
                # Ждем загрузки формы поиска (используем найденный ID)
                self.logger.info("Waiting for search form to load...")
                WebDriverWait(self.driver, 15).until(
                    EC.presence_of_element_located((By.ID, "q"))
                )

                # Находим поле поиска по ID (id="q")
                search_input = self.driver.find_element(By.ID, "q")
                search_input.clear()
                search_input.send_keys(query)
                self.logger.info(f"Entered search query: {query}")

                # Находим и нажимаем кнопку поиска (class="search-button")
                search_button = self.driver.find_element(By.CSS_SELECTOR, "button.search-button")
                search_button.click()
                self.logger.info("Clicked search button")

                # Ждем результатов поиска (увеличим время ожидания)
                self.logger.info("Waiting for search results to load...")
                try:
                    WebDriverWait(self.driver, 15).until(
                        lambda driver: len(driver.find_elements(By.CSS_SELECTOR, "article.card")) > 0
                    )
                    self.logger.info("Search results loaded successfully")
                except:
                    self.logger.warning("Standard selector didn't work, trying alternatives...")
                    # Попробуем подождать подольше или проверить текущий URL
                    import time
                    time.sleep(3)

                    current_url = self.driver.current_url
                    self.logger.info(f"Current URL after search: {current_url}")

                # Получаем HTML после поиска
                html = self.driver.page_source
                soup = BeautifulSoup(html, 'lxml')

                # Парсим результаты поиска
                artist_cards = soup.find_all('article', class_='card')
                self.logger.info(f"Found {len(artist_cards)} artist cards")

                # Если не найдено, попробуем другие селекторы
                if not artist_cards:
                    self.logger.info("Trying alternative selectors...")
                    artist_cards = soup.find_all('article', attrs={'data-id': True})
                    self.logger.info(f"Alternative selector found {len(artist_cards)} cards")

                # Сохраним HTML для анализа даже если ничего не найдено
                with open('search_results_debug.html', 'w', encoding='utf-8') as f:
                    f.write(html)
                self.logger.info("Saved search results HTML to search_results_debug.html")

                for card in artist_cards[:limit]:
                    try:
                        link = card.find('a', href=True)
                        if link:
                            href = link['href']
                            parts = href.strip('/').split('/')
                            if len(parts) >= 3:
                                service_name = parts[0]
                                user_id = parts[2]

                                name_elem = card.find('h2') or card.find('header')
                                name = name_elem.text.strip() if name_elem else f"User_{user_id}"

                                # Создаем объект Artist с правильными полями
                                artist = Artist(
                                    id=user_id,
                                    service=service_name,
                                    name=name,
                                    indexed="",
                                    updated="",
                                    url=f"{self.base_url}{href}"
                                )
                                artists.append(artist)
                    except Exception as e:
                        self.logger.error(f"Error parsing search result: {e}")
                        continue

            except Exception as e:
                self.logger.error(f"Error performing search: {e}")

        except Exception as e:
            self.logger.error(f"Error searching artists: {e}")

        return artists

    def get_posts_page(self, page_url: str, limit: int = 50) -> List[Post]:
        """Получение списка постов с конкретной страницы браузера"""
        posts = []

        try:
            if self.use_selenium:
                html = self._selenium_get(page_url)
                if not html:
                    return posts
                soup = BeautifulSoup(html, 'lxml')
            else:
                response = self._make_request(page_url)
                if not response:
                    return posts
                soup = BeautifulSoup(response.content, 'lxml')

            # Парсим посты с страницы
            post_articles = soup.find_all('article', class_='post-card')

            # Если не найдено, пробуем другие селекторы
            if not post_articles:
                post_articles = soup.find_all('article', attrs={'data-id': True})
            if not post_articles:
                post_articles = soup.find_all('article', class_='post-card--preview')

            # Специальная обработка для страницы случайных постов
            if not post_articles and 'random' in page_url:
                print(f"[RANDOM_POST] Страница случайных постов, создаем пост из текущего URL")
                # На странице случайных постов показывается один пост
                # Извлекаем информацию о посте из страницы

                # Получаем заголовок
                title_elem = soup.find('h1') or soup.find('title')
                title = title_elem.text.strip() if title_elem else "Случайный пост"

                # Извлекаем автора из URL или страницы
                author_name = "Неизвестный автор"
                if self.use_selenium and hasattr(self, 'driver'):
                    current_url = self.driver.current_url
                    print(f"[RANDOM_POST] Текущий URL после перенаправления: {current_url}")
                    # Извлекаем информацию из URL
                    if '/user/' in current_url:
                        parts = current_url.split('/user/')
                        if len(parts) > 1:
                            user_part = parts[1].split('/')[0]
                            author_name = f"User {user_part}"

                # Создаем пост с текущим URL
                current_url = page_url  # Используем запрошенный URL как URL поста
                if self.use_selenium and hasattr(self, 'driver'):
                    current_url = self.driver.current_url  # Получаем реальный URL после перенаправления

                post = Post(
                    id="random",
                    title=title,
                    content="",  # Не парсим полное содержимое
                    published="",  # Неизвестно
                    edited="",
                    author=author_name,
                    service="",  # Определим позже
                    url=current_url,
                    thumbnail="",  # Нет превью
                    attachments=[],  # Нет вложений
                    embeds=[],  # Нет эмбедов
                    files=[]  # Нет файлов
                )
                posts.append(post)
                print(f"[RANDOM_POST] Создан случайный пост: {title} от {author_name}")
                return posts  # Возвращаем сразу, так как это один пост

            for article in post_articles[:limit]:
                try:
                    # Извлекаем данные поста
                    post_id = article.get('data-id') or ""
                    title_elem = article.find('h2') or article.find('h1') or article.find('header')
                    title = title_elem.text.strip() if title_elem else "Без названия"

                    # Извлекаем ссылку на пост
                    link_elem = article.find('a', href=True)
                    post_url = ""
                    if link_elem:
                        href = link_elem['href']
                        if href.startswith('/'):
                            post_url = f"{self.base_url}{href}"
                        else:
                            post_url = href

                    # Извлекаем автора
                    author_elem = article.find('a', href=lambda x: x and '/user/' in x)
                    author_name = ""
                    author_url = ""
                    if author_elem:
                        author_name = author_elem.text.strip()
                        author_href = author_elem['href']
                        if author_href.startswith('/'):
                            author_url = f"{self.base_url}{author_href}"

                    # Извлекаем дату
                    date_elem = article.find('time') or article.find(attrs={'datetime': True})
                    published = ""
                    if date_elem:
                        published = date_elem.get('datetime') or date_elem.text.strip()

                    # Создаем объект поста
                    post = Post(
                        id=post_id,
                        title=title,
                        content="",  # Не парсим полное содержимое на странице списка
                        published=published,
                        edited="",
                        author=author_name,
                        service="",  # Определим позже по URL автора
                        url=post_url,
                        thumbnail="",  # На странице списка нет превью
                        attachments=[],  # На странице списка нет вложений
                        embeds=[],  # На странице списка нет эмбедов
                        files=[]  # На странице списка нет файлов
                    )
                    posts.append(post)

                except Exception as e:
                    self.logger.error(f"Error parsing post card: {e}")
                    continue

        except Exception as e:
            self.logger.error(f"Error getting posts page {page_url}: {e}")

        return posts

    def get_artist_posts(self, artist: Artist, offset: int = 0, limit: int = 50) -> List[Post]:
        """Получение постов автора"""
        posts = []
        url = f"{artist.url}?o={offset}"

        try:
            if self.use_selenium:
                # Используем Selenium для получения полного HTML
                html = self._selenium_get(url)
                if not html:
                    return posts
                soup = BeautifulSoup(html, 'lxml')
            else:
                # Обычный HTTP запрос (может не работать для JS сайтов)
                response = self._make_request(url)
                if not response:
                    return posts
                soup = BeautifulSoup(response.content, 'lxml')

            # Парсим посты с правильными селекторами (на основе анализа страницы)
            post_articles = []

            # Основной селектор для постов на kemono.cr
            post_articles = soup.find_all('article', class_='post-card')

            # Если не найдено, пробуем другие селекторы
            if not post_articles:
                post_articles = soup.find_all('article', attrs={'data-id': True})
            if not post_articles:
                post_articles = soup.find_all('article', class_='post-card--preview')
            if not post_articles:
                post_articles = soup.find_all('div', class_='post-card')
            if not post_articles:
                post_articles = soup.find_all('article', class_=lambda x: x and 'post' in x.lower())
            if not post_articles:
                post_articles = soup.find_all('div', class_=lambda x: x and 'post' in x.lower() and 'card' in x.lower())

            # Ищем ссылки на посты как запасной вариант
            if not post_articles:
                post_links = soup.find_all('a', href=lambda x: x and '/post/' in x)
                if post_links:
                    # Создаем искусственные посты на основе ссылок
                    for link in post_links[:limit]:
                        try:
                            href = link['href']
                            post_id = href.split('/')[-1] if '/' in href else str(hash(href))
                            post = Post(
                                id=post_id,
                                title=f"Post {post_id}",
                                content="",
                                published="",
                                edited="",
                                author=artist.name,
                                service=artist.service,
                                url=f"{self.base_url}{href}",
                                thumbnail="",
                                attachments=[],
                                embeds=[],
                                files=[]
                            )
                            posts.append(post)
                        except Exception as e:
                            self.logger.error(f"Error creating post from link: {e}")
                            continue
                    return posts

            self.logger.info(f"Found {len(post_articles)} post elements")

            for article in post_articles[:limit]:
                try:
                    post = self._parse_post(article, artist)
                    if post:
                        posts.append(post)
                except Exception as e:
                    self.logger.error(f"Error parsing post: {e}")
                    continue

        except Exception as e:
            self.logger.error(f"Error getting artist posts: {e}")

        return posts

    def get_all_artist_posts(self, artist: Artist) -> List[Post]:
        """Получение ВСЕХ постов автора со всех страниц (параллельно)"""
        import concurrent.futures
        import time

        all_posts = []
        page_size = 50
        max_workers = 4  # Количество параллельных потоков

        self.logger.info(f"Loading all posts for {artist.name} with {max_workers} parallel threads...")

        # Шаг 1: Быстро определяем общее количество страниц (загружаем первую страницу)
        self.logger.info("Determining total number of pages...")
        first_page_posts = self.get_artist_posts(artist, offset=0, limit=page_size)

        if not first_page_posts:
            self.logger.info("No posts found at all")
            return []

        all_posts.extend(first_page_posts)

        # Если первая страница содержит меньше постов, чем page_size, то это все посты
        if len(first_page_posts) < page_size:
            self.logger.info(f"All posts loaded from first page. Total: {len(all_posts)}")
            return all_posts

        # Шаг 2: Поэтапная параллельная загрузка (эффективнее)
        pages_data = {}  # offset -> posts
        batch_size = 4  # Загружаем по 4 страницы за раз

        current_batch_start = 1  # Начинаем со второй страницы (offset=50)

        while True:
            # Определяем offsets для текущего батча
            batch_offsets = []
            for i in range(batch_size):
                offset = (current_batch_start + i) * page_size
                batch_offsets.append(offset)

            self.logger.info(f"Loading batch: offsets {batch_offsets}")

            # Загружаем батч параллельно
            batch_results = {}
            with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
                future_to_offset = {
                    executor.submit(self._load_single_page, artist, offset, page_size): offset
                    for offset in batch_offsets
                }

                for future in concurrent.futures.as_completed(future_to_offset):
                    offset = future_to_offset[future]
                    try:
                        page_posts = future.result()
                        batch_results[offset] = page_posts or []
                        if page_posts:
                            self.logger.info(f"Loaded {len(page_posts)} posts from offset {offset}")
                        else:
                            self.logger.info(f"No posts found at offset {offset}")
                    except Exception as exc:
                        self.logger.error(f"Page {offset} generated an exception: {exc}")
                        batch_results[offset] = []

            # Добавляем результаты батча в общий словарь
            pages_data.update(batch_results)

            # Проверяем, нужно ли продолжать
            # Если в батче есть страница с < 50 постами, прекращаем
            has_incomplete_page = any(len(posts) < page_size for posts in batch_results.values())

            # Если в батче есть пустая страница, прекращаем
            has_empty_page = any(len(posts) == 0 for posts in batch_results.values())

            if has_incomplete_page or has_empty_page:
                self.logger.info("Found incomplete or empty page, stopping batch loading")
                break

            # Если все страницы в батче полные, продолжаем
            current_batch_start += batch_size

            # Ограничение на максимальное количество батчей (чтобы не зависнуть)
            if current_batch_start > 20:  # Максимум 20 батчей = 80 страниц
                self.logger.warning("Reached maximum batch limit, stopping")
                break

        # Шаг 3: Собираем все посты в правильном порядке
        for offset in sorted(pages_data.keys()):
            posts = pages_data[offset]
            if posts:  # Только непустые страницы
                all_posts.extend(posts)

        # Шаг 4: Финальная проверка на дополнительные страницы
        # Если последняя страница была полной, проверяем следующую
        if pages_data:
            last_offset = max(pages_data.keys())
            last_page_posts = pages_data[last_offset]

            if len(last_page_posts) == page_size:
                next_offset = last_offset + page_size
                self.logger.info(f"Checking for additional page at offset {next_offset}...")

                additional_posts = self.get_artist_posts(artist, offset=next_offset, limit=page_size)
                if additional_posts:
                    all_posts.extend(additional_posts)
                    self.logger.info(f"Loaded additional {len(additional_posts)} posts from offset {next_offset}")

        self.logger.info(f"Finished loading all posts. Total: {len(all_posts)}")
        return all_posts

    def _load_single_page(self, artist: Artist, offset: int, page_size: int) -> List[Post]:
        """Загрузка одной страницы постов (для параллельной обработки)"""
        # Создаем новый экземпляр парсера для каждого потока
        thread_parser = KemonoParser(use_selenium=self.use_selenium, headless=self.headless)
        try:
            return thread_parser.get_artist_posts(artist, offset=offset, limit=page_size)
        except Exception as e:
            self.logger.error(f"Error loading page at offset {offset}: {e}")
            return []
        finally:
            # Закрываем драйвер потока
            if hasattr(thread_parser, 'driver') and thread_parser.driver:
                try:
                    thread_parser.driver.quit()
                except:
                    pass

    def _parse_post(self, article, artist: Artist) -> Optional[Post]:
        """Парсинг отдельного поста"""
        try:
            # Получаем ID поста из data-id атрибута или ссылки
            post_id = None

            # Сначала пробуем получить из data-id атрибута
            if hasattr(article, 'get') and article.get('data-id'):
                post_id = article['data-id']
            else:
                # Ищем ссылку на пост
                post_link = article.find('a', href=lambda x: x and '/post/' in x)
                if post_link:
                    href = post_link['href']
                    post_id = href.split('/')[-1] if '/' in href else str(hash(href))

            if not post_id:
                return None

            # Получаем заголовок
            title_elem = article.find('header') or article.find('h2') or article.find('h1')
            title = title_elem.text.strip() if title_elem else f"Post_{post_id}"

            # Получаем дату публикации
            time_elem = article.find('time')
            published = ""
            if time_elem:
                published = time_elem.get('datetime', '') or time_elem.text.strip()

            # Получаем превью контента
            content_elem = article.find('div', class_=lambda x: x and 'content' in x.lower())
            content = content_elem.text.strip() if content_elem else ""

            # Получаем превью поста - ищем thumbnail изображение
            thumbnail = None

            # Сначала ищем в контейнере изображения поста
            image_container = article.find('div', class_='post-card__image-container')
            if image_container:
                img_tag = image_container.find('img')
                if img_tag:
                    src = img_tag.get('src')
                    if src and not src.startswith('data:'):
                        full_url = urljoin(self.base_url, src)
                        # Проверяем, что это thumbnail URL
                        if 'thumbnail' in src.lower():
                            thumbnail = full_url

            # Если не нашли в контейнере, ищем среди всех img тегов
            if not thumbnail:
                img_tags = article.find_all('img')
                for img in img_tags:
                    src = img.get('src')
                    if src and not src.startswith('data:'):
                        full_url = urljoin(self.base_url, src)
                        # Ищем thumbnail изображение
                        if 'thumbnail' in src.lower():
                            thumbnail = full_url
                            break

            # Получаем вложения (изображения)
            attachments = []
            embeds = []
            files = []

            # Ищем все изображения в посте
            img_tags = article.find_all('img')
            for img in img_tags:
                src = img.get('src')
                if src and not src.startswith('data:'):
                    full_url = urljoin(self.base_url, src)
                    # Проверяем, является ли это превью или основным изображением
                    if 'preview' in src.lower() or 'thumb' in src.lower():
                        continue  # Пропускаем превью, будем искать оригиналы на странице поста

                    attachments.append({
                        'type': 'image',
                        'url': full_url,
                        'name': src.split('/')[-1]
                    })

            # Ищем информацию о вложениях в тексте поста
            footer_elem = article.find('footer')
            if footer_elem:
                footer_text = footer_elem.text.lower()
                # Ищем количество вложений
                if 'attachment' in footer_text:
                    # Это указывает на наличие вложений, которые будут загружены с полной страницы поста
                    pass

            return Post(
                id=post_id,
                title=title,
                content=content,
                published=published,
                edited="",
                author=artist.name,
                service=artist.service,
                url=f"{self.base_url}/{artist.service}/user/{artist.id}/post/{post_id}",
                thumbnail=thumbnail or "",
                attachments=attachments,
                embeds=embeds,
                files=files
            )

        except Exception as e:
            self.logger.error(f"Error parsing post element: {e}")
            return None

    def get_post_details(self, post_url: str) -> Optional[Post]:
        """Получение детальной информации о посте"""
        try:
            if self.use_selenium:
                html = self._selenium_get(post_url)
                if not html:
                    return None
                soup = BeautifulSoup(html, 'lxml')
            else:
                response = self._make_request(post_url)
                if not response:
                    return None
                soup = BeautifulSoup(response.content, 'lxml')

            # Парсим полную информацию о посте
            return self._parse_full_post(soup, post_url)

        except Exception as e:
            self.logger.error(f"Error getting post details: {e}")
            return None

    def _parse_full_post(self, soup: BeautifulSoup, post_url: str) -> Optional[Post]:
        """Парсинг полной информации о посте"""
        try:
            # Получаем заголовок
            title_elem = soup.find('h1') or soup.find('header', class_='post__header')
            title = title_elem.text.strip() if title_elem else "Untitled"

            # Получаем контент
            content_elem = soup.find('div', class_='post__content') or soup.find('div', class_='content')
            content = content_elem.text.strip() if content_elem else ""

            # Получаем дату
            time_elem = soup.find('time')
            published = time_elem['datetime'] if time_elem and 'datetime' in time_elem.attrs else ""

            # Получаем автора
            author_elem = soup.find('a', href=lambda x: x and '/user/' in x)
            author_name = author_elem.text.strip() if author_elem else "Unknown"

            # Получаем сервис
            url_parts = urlparse(post_url).path.split('/')
            service = url_parts[1] if len(url_parts) > 1 else "unknown"

            # Получаем ID поста
            post_id = url_parts[-1]

            # Парсим вложения
            attachments = []
            embeds = []
            files = []

            # Ищем все изображения
            img_tags = soup.find_all('img')
            for img in img_tags:
                src = img.get('src')
                if src and not src.startswith('data:'):
                    full_url = urljoin(self.base_url, src)
                    attachments.append({
                        'type': 'image',
                        'url': full_url,
                        'name': src.split('/')[-1]
                    })

            # Ищем ссылки на файлы
            file_links = soup.find_all('a', href=lambda x: x and any(ext in x.lower() for ext in ['.zip', '.rar', '.pdf', '.mp4', '.mp3']))
            for link in file_links:
                href = link['href']
                full_url = urljoin(self.base_url, href)
                files.append({
                    'type': 'file',
                    'url': full_url,
                    'name': href.split('/')[-1]
                })

            return Post(
                id=post_id,
                title=title,
                content=content,
                published=published,
                edited=None,
                author=author_name,
                service=service,
                url=post_url,
                thumbnail="",  # Можно добавить логику извлечения превью позже
                attachments=attachments,
                embeds=embeds,
                files=files
            )

        except Exception as e:
            self.logger.error(f"Error parsing full post: {e}")
            return None

    def download_file(self, url: str, filepath: str, show_progress: bool = True) -> bool:
        """Скачивание файла с отображением прогресса"""
        try:
            response = self._make_request(url, stream=True)
            if not response:
                return False

            total_size = int(response.headers.get('content-length', 0))

            # Создаем директорию если не существует
            os.makedirs(os.path.dirname(filepath), exist_ok=True)

            with open(filepath, 'wb') as f:
                if show_progress and total_size > 0:
                    with tqdm(total=total_size, unit='B', unit_scale=True, desc=os.path.basename(filepath)) as pbar:
                        for chunk in response.iter_content(chunk_size=8192):
                            if chunk:
                                f.write(chunk)
                                pbar.update(len(chunk))
                else:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)

            self.logger.info(f"Downloaded: {filepath}")
            return True

        except Exception as e:
            self.logger.error(f"Error downloading file {url}: {e}")
            return False

    def search_artists_http(self, query: str, limit: int = 100, search_url: str = None) -> List[Artist]:
        """Поиск авторов с использованием HTTP запросов с параметрами поиска"""
        artists = []

        try:
            # Используем переданный URL или по умолчанию
            if search_url is None:
                search_url = f"{self.base_url}/artists"

            # Формируем URL с параметрами поиска
            params = {
                'q': query,
                'service': '',  # Все сервисы
                'sort_by': 'favorited',  # Сортировка по популярности
                'order': ''  # Направление сортировки
            }

            self.logger.info(f"🔍 HTTP Search for '{query}' via URL: {search_url}")
            self.logger.info(f"📊 Search params: {params}")

            # Пробуем обычный HTTP запрос
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.5',
                'Accept-Encoding': 'gzip, deflate',
                'Connection': 'keep-alive',
                'Upgrade-Insecure-Requests': '1',
                'Referer': search_url,
            }

            self.logger.info(f"🌐 Sending HTTP GET to: {search_url} with params: {params}")
            response = requests.get(search_url, params=params, headers=headers, timeout=30)
            self.logger.info(f"📡 HTTP Response status: {response.status_code}, length: {len(response.text)}")

            if response.status_code == 200:
                self.logger.info(f"Search request successful, response length: {len(response.text)}")

                # Сохраняем HTML для анализа
                with open('search_results_http.html', 'w', encoding='utf-8') as f:
                    f.write(response.text)

                soup = BeautifulSoup(response.text, 'lxml')

                # Проверяем, что мы на правильной странице
                title = soup.find('title')
                if title:
                    self.logger.info(f"Page title: {title.text.strip()}")

                # Проверяем URL после редиректа
                final_url = response.url
                self.logger.info(f"Final URL: {final_url}")

                # Если нас перенаправили на внешнюю страницу - поиск не удался
                if 'nachdiewelt.click' in final_url or 'quantum' in final_url.lower():
                    self.logger.warning("Redirected to external page - search blocked")
                    return artists

                # Парсим результаты поиска
                artist_cards = soup.find_all('article', class_='card')
                self.logger.info(f"Found {len(artist_cards)} artist cards")

                # Если не найдено, попробуем другие селекторы
                if not artist_cards:
                    self.logger.info("Trying alternative selectors...")
                    artist_cards = soup.find_all('article', attrs={'data-id': True})
                    self.logger.info(f"Alternative selector found {len(artist_cards)} cards")

                # Парсим найденных авторов
                for card in artist_cards[:limit]:
                    try:
                        link = card.find('a', href=True)
                        if link:
                            href = link['href']
                            parts = href.strip('/').split('/')
                            if len(parts) >= 3:
                                service_name = parts[0]
                                user_id = parts[2]

                                name_elem = card.find('h2') or card.find('header')
                                name = name_elem.text.strip() if name_elem else f"User_{user_id}"

                                # Создаем объект Artist с правильными полями
                                artist = Artist(
                                    id=user_id,
                                    service=service_name,
                                    name=name,
                                    indexed="",
                                    updated="",
                                    url=f"{self.base_url}{href}"
                                )
                                artists.append(artist)
                    except Exception as e:
                        self.logger.error(f"Error parsing search result: {e}")
                        continue

                self.logger.info(f"Successfully parsed {len(artists)} artists from search")

            else:
                self.logger.error(f"Search request failed with status {response.status_code}")

        except Exception as e:
            self.logger.error(f"Error searching artists: {e}")

        return artists

    def search_posts(self, query: str, limit: int = 50, search_url: str = None) -> List[Post]:
        """Поиск постов с использованием HTTP запросов"""
        posts = []

        try:
            # Используем переданный URL или по умолчанию
            if search_url is None:
                search_url = f"{self.base_url}/posts"

            # Формируем URL с параметрами поиска
            params = {
                'q': query,
                'service': '',  # Все сервисы
                'sort_by': 'favorited',  # Сортировка по популярности
                'order': ''  # Направление сортировки
            }

            self.logger.info(f"🔍 HTTP Search posts for '{query}' via URL: {search_url}")
            self.logger.info(f"📊 Search params: {params}")

            # HTTP запрос
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.5',
                'Accept-Encoding': 'gzip, deflate',
                'Connection': 'keep-alive',
                'Upgrade-Insecure-Requests': '1',
                'Referer': search_url,
            }

            self.logger.info(f"🌐 Sending HTTP GET to: {search_url} with params: {params}")
            response = requests.get(search_url, params=params, headers=headers, timeout=30)
            self.logger.info(f"📡 HTTP Response status: {response.status_code}, length: {len(response.text)}")

            if response.status_code == 200:
                self.logger.info(f"Search posts request successful, response length: {len(response.text)}")

                # Сохраняем HTML для анализа
                with open('search_posts_results_http.html', 'w', encoding='utf-8') as f:
                    f.write(response.text)

                soup = BeautifulSoup(response.text, 'lxml')

                # Проверяем, что мы на правильной странице
                title = soup.find('title')
                if title:
                    self.logger.info(f"Page title: {title.text.strip()}")

                # Проверяем URL после редиректа
                final_url = response.url
                self.logger.info(f"Final URL: {final_url}")

                # Если нас перенаправили на внешнюю страницу - поиск не удался
                if 'nachdiewelt.click' in final_url or 'quantum' in final_url.lower():
                    self.logger.warning("Redirected to external page - posts search blocked")
                    return posts

                # Парсим результаты поиска постов
                self.logger.info("🔍 Parsing post search results...")

                # Проверяем, что мы на правильной странице
                title = soup.find('title')
                if title:
                    page_title = title.text.strip()
                    self.logger.info(f"📄 Page title: {page_title}")

                    if 'Kemono' not in page_title and 'Posts' not in page_title:
                        self.logger.warning(f"⚠️ Wrong page title: {page_title}")
                        return posts

                # Ищем карточки постов
                post_cards = soup.find_all('article', class_='card')
                self.logger.info(f"🎴 Found {len(post_cards)} post cards with class='card'")

                # Если не найдено, попробуем другие селекторы
                if not post_cards:
                    self.logger.info("🔍 Trying alternative selectors...")
                    post_cards = soup.find_all('article', attrs={'data-id': True})
                    self.logger.info(f"🎯 Alternative selector found {len(post_cards)} cards")

                # Ещё один вариант - поиск по data-атрибутам
                if not post_cards:
                    self.logger.info("🔍 Trying data-post selector...")
                    post_cards = soup.find_all(attrs={'data-post': True})
                    self.logger.info(f"📝 Data-post selector found {len(post_cards)} cards")

                # Выводим информацию о найденных карточках
                if post_cards:
                    self.logger.info(f"✅ Total post cards found: {len(post_cards)}")
                    for i, card in enumerate(post_cards[:3]):
                        link = card.find('a', href=True)
                        title_elem = card.find('h2') or card.find('header')
                        if link:
                            self.logger.info(f"  {i+1}. Link: {link.get('href')}")
                        if title_elem:
                            self.logger.info(f"      Title: {title_elem.text.strip()}")
                else:
                    self.logger.warning("❌ No post cards found with any selector")

                # Парсим найденные посты
                for card in post_cards[:limit]:
                    try:
                        link = card.find('a', href=True)
                        if link:
                            href = link['href']
                            parts = href.strip('/').split('/')
                            if len(parts) >= 4:  # /service/user_id/post_id
                                service_name = parts[0]
                                user_id = parts[2]
                                post_id = parts[3]

                                title_elem = card.find('h2') or card.find('header')
                                title = title_elem.text.strip() if title_elem else f"Post_{post_id}"

                                # Создаем объект Post с правильными полями
                                post = Post(
                                    id=post_id,
                                    service=service_name,
                                    author=user_id,  # Используем author вместо user
                                    title=title,
                                    content="",
                                    published="",
                                    edited="",
                                    url=f"{self.base_url}{href}",
                                    thumbnail="",  # На странице поиска нет превью
                                    attachments=[],  # На странице поиска нет вложений
                                    embeds=[],  # На странице поиска нет эмбедов
                                    files=[]  # На странице поиска нет файлов
                                )
                                posts.append(post)
                    except Exception as e:
                        self.logger.error(f"Error parsing post search result: {e}")
                        continue

                self.logger.info(f"Successfully parsed {len(posts)} posts from search")

            else:
                self.logger.error(f"Posts search request failed with status {response.status_code}")

        except Exception as e:
            self.logger.error(f"Error searching posts: {e}")

        return posts

    def search_artists_selenium(self, query: str, limit: int = 100, search_url: str = None) -> List[Artist]:
        """Поиск авторов через Selenium (для обхода защиты)"""
        artists = []

        try:
            # Используем переданный URL или по умолчанию
            if search_url is None:
                search_url = f"{self.base_url}/artists"

            # Используем Selenium для поиска
            self.logger.info(f"🔍 Selenium Search for '{query}' via URL: {search_url}")

            if self.driver:
                try:
                    # ШАГ 1: Переходим на страницу поиска с обработкой редиректов
                    self.logger.info(f"🌐 Navigating to: {search_url}")
                    self.driver.get(search_url)

                    # Ждем загрузки и проверяем редирект
                    import time
                    import random
                    delay = random.uniform(2, 4)
                    time.sleep(delay)

                    current_url = self.driver.current_url
                    self.logger.info(f"📍 Current URL after navigation: {current_url}")

                    # Если произошел редирект на внешнюю страницу - возвращаемся
                    if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                        self.logger.warning("⚠️ Detected redirect to external page - returning to search page")

                        # Принудительно возвращаемся на страницу поиска
                        self.driver.get(search_url)
                        time.sleep(random.uniform(1, 3))

                        # Проверяем, что теперь на правильной странице
                        current_url = self.driver.current_url
                        if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                            self.logger.error("❌ Still redirected to external page after retry")
                            return artists

                        self.logger.info(f"✅ Successfully returned to: {current_url}")

                    # Имитируем естественное поведение: случайная задержка
                    delay = random.uniform(3, 6)
                    self.logger.info(f"⏳ Waiting {delay:.1f}s for page load...")
                    time.sleep(delay)

                    # Имитируем движение мыши и прокрутку
                    try:
                        self.logger.info("🖱️ Simulating human behavior...")
                        # Случайное движение мыши
                        from selenium.webdriver.common.action_chains import ActionChains
                        actions = ActionChains(self.driver)
                        actions.move_by_offset(random.randint(100, 500), random.randint(100, 300)).perform()
                        time.sleep(random.uniform(0.5, 1.5))

                        # Небольшая прокрутка
                        self.driver.execute_script(f"window.scrollBy(0, {random.randint(200, 500)});")
                        time.sleep(random.uniform(0.5, 1.5))
                    except Exception as e:
                        self.logger.warning(f"Human behavior simulation failed: {e}")

                    # Проверяем, что мы на правильной странице
                    current_url = self.driver.current_url
                    self.logger.info(f"📍 Current URL: {current_url}")

                    # Проверяем на редирект
                    if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                        self.logger.warning("⚠️ Redirected to external page - search blocked")
                        return artists

                    if 'kemono.cr' not in current_url:
                        self.logger.warning(f"⚠️ Not on kemono.cr anymore: {current_url}")
                        return artists

                    # ШАГ 2: Ищем поле поиска
                    self.logger.info("🔍 Looking for search input field...")
                    from selenium.webdriver.common.by import By
                    from selenium.webdriver.support.ui import WebDriverWait
                    from selenium.webdriver.support import expected_conditions as EC

                    try:
                        search_input = WebDriverWait(self.driver, 15).until(
                            EC.presence_of_element_located((By.ID, "q"))
                        )
                        self.logger.info("✅ Search input found!")
                    except Exception as e:
                        self.logger.error(f"❌ Search input not found: {e}")
                        return artists

                    # ШАГ 3: Вводим запрос
                    self.logger.info(f"✍️ Entering query: {query}")
                    search_input.clear()

                    # Имитируем медленный ввод
                    for char in query:
                        search_input.send_keys(char)
                        time.sleep(0.15)

                    time.sleep(1)

                    # ШАГ 4: Ищем и нажимаем кнопку поиска
                    self.logger.info("🔘 Looking for search button...")
                    try:
                        search_button = self.driver.find_element(By.CSS_SELECTOR, "button.search-button")
                        self.logger.info("✅ Search button found!")
                    except Exception as e:
                        self.logger.warning(f"❌ Search button not found: {e}")
                        # Пробуем альтернативный селектор
                        try:
                            search_button = self.driver.find_element(By.CSS_SELECTOR, "button[type='submit']")
                            self.logger.info("✅ Alternative search button found!")
                        except Exception as e2:
                            self.logger.error(f"❌ No search button found: {e2}")
                            return artists

                    # Нажимаем кнопку (используем JavaScript, чтобы избежать перехвата)
                    try:
                        self.driver.execute_script("arguments[0].click();", search_button)
                        self.logger.info("🔘 Search button clicked (via JavaScript)")
                    except:
                        # Если JavaScript не сработал, пробуем обычный клик
                        search_button.click()
                        self.logger.info("🔘 Search button clicked (regular click)")

                    # ШАГ 5: Ждем результатов (увеличенное время для загрузки JS)
                    self.logger.info("⏳ Waiting for results...")
                    time.sleep(2)

                    # ШАГ 6: Проверяем на новую вкладку (белый список доменов)
                    allowed_domains = ['kemono.cr', 'kemono.su', 'kemono.party']

                    def is_allowed_url(url):
                        try:
                            from urllib.parse import urlparse
                            domain = urlparse(url).netloc.lower()
                            return any(allowed in domain for allowed in allowed_domains)
                        except:
                            return False

                    # Проверяем текущую вкладку
                    current_url = self.driver.current_url
                    self.logger.info(f"📍 Current URL after search: {current_url}")

                    # Если текущая вкладка не на разрешенном домене - ищем новую вкладку
                    if not is_allowed_url(current_url):
                        self.logger.info("🔍 Current tab redirected - looking for new tab with results...")

                        # Ждем открытия новой вкладки
                        max_attempts = 10
                        for attempt in range(max_attempts):
                            try:
                                # Получаем все вкладки
                                all_handles = self.driver.window_handles
                                self.logger.info(f"📑 Found {len(all_handles)} tabs")

                                # Ищем вкладку с разрешенным доменом
                                for handle in all_handles:
                                    self.driver.switch_to.window(handle)
                                    tab_url = self.driver.current_url
                                    self.logger.info(f"🔍 Checking tab: {tab_url}")

                                    if is_allowed_url(tab_url):
                                        self.logger.info("✅ Found correct tab with kemono.cr!")
                                        current_url = tab_url
                                        break

                                if is_allowed_url(self.driver.current_url):
                                    break

                                time.sleep(1)  # Ждем еще

                            except Exception as e:
                                self.logger.warning(f"Attempt {attempt + 1} failed: {e}")
                                time.sleep(0.5)

                        # Если нашли правильную вкладку - повторяем поиск
                        if is_allowed_url(self.driver.current_url):
                            self.logger.info("🔄 Retrying search in correct tab...")

                            try:
                                # Ждем загрузки страницы
                                time.sleep(2)

                                # Ищем поле поиска
                                search_input = WebDriverWait(self.driver, 10).until(
                                    EC.presence_of_element_located((By.ID, "q"))
                                )
                                self.logger.info("✅ Search input found in new tab")

                                # Очищаем и вводим запрос заново
                                search_input.clear()
                                for char in query:
                                    search_input.send_keys(char)
                                    time.sleep(0.1)
                                time.sleep(0.5)

                                # Ищем кнопку поиска
                                search_button = self.driver.find_element(By.CSS_SELECTOR, "button.search-button")

                                # Нажимаем кнопку
                                self.driver.execute_script("arguments[0].click();", search_button)
                                self.logger.info("🔘 Search button clicked in new tab")

                                # Ждем результаты
                                time.sleep(4)

                                # Финальная проверка
                                final_url = self.driver.current_url
                                self.logger.info(f"📍 Final URL after retry: {final_url}")

                                if not is_allowed_url(final_url):
                                    self.logger.error("❌ Still not on correct domain after retry")
                                    return artists

                            except Exception as e:
                                self.logger.error(f"❌ Failed to retry search in new tab: {e}")
                                return artists
                        else:
                            self.logger.error("❌ Could not find tab with kemono.cr")
                            return artists

                    # Получаем HTML результатов
                    html = self.driver.page_source
                    self.logger.info(f"📄 Got HTML: {len(html)} characters")

                    # Проверяем, появились ли результаты поиска
                    self.logger.info("🔍 Checking for search results...")
                    try:
                        # Ждем появления карточек результатов
                        WebDriverWait(self.driver, 10).until(
                            lambda driver: len(driver.find_elements(By.CSS_SELECTOR, "a.user-card")) > 0 or
                                           len(driver.find_elements(By.CSS_SELECTOR, "a.fancy-link--kemono")) > 0
                        )
                        self.logger.info("✅ Search results loaded!")
                    except:
                        self.logger.warning("⚠️ Search results not found within timeout, proceeding anyway...")

                    # Дополнительное ожидание для полной загрузки
                    time.sleep(2)

                except Exception as e:
                    self.logger.error(f"Selenium interaction failed: {e}")
                    return artists
            else:
                self.logger.error("Selenium driver not available")
                return artists

            # Сохраняем HTML для анализа
            with open('selenium_search_artists.html', 'w', encoding='utf-8') as f:
                f.write(html)

            # Парсим результаты
            soup = BeautifulSoup(html, 'lxml')

            # Проверяем, что мы на правильной странице
            title = soup.find('title')
            if title:
                self.logger.info(f"Page title: {title.text.strip()}")

            # Проверяем URL после редиректа
            final_url = self.driver.current_url if self.driver else search_url
            self.logger.info(f"Final URL: {final_url}")

            # Если нас перенаправили на внешнюю страницу - поиск не удался
            if 'nachdiewelt.click' in final_url or 'quantum' in final_url.lower():
                self.logger.warning("Redirected to external page - search blocked")
                return artists

            # Парсим результаты поиска
            self.logger.info("🔍 Parsing search results...")

            # Проверяем, что мы на правильной странице
            title = soup.find('title')
            if title:
                page_title = title.text.strip()
                self.logger.info(f"📄 Page title: {page_title}")

                if 'Kemono' not in page_title and 'Artists' not in page_title:
                    self.logger.warning(f"⚠️ Wrong page title: {page_title}")
                    return artists

            # Ищем карточки авторов - правильные селекторы для kemono.cr
            artist_cards = soup.find_all('a', class_='user-card')
            self.logger.info(f"🎴 Found {len(artist_cards)} artist cards with class='user-card'")

            # Если не найдено, попробуем найти по href паттерну
            if not artist_cards:
                self.logger.info("🔍 Trying href pattern selector...")
                all_links = soup.find_all('a', href=True)
                artist_cards = [link for link in all_links if '/user/' in link.get('href', '')]
                self.logger.info(f"👤 Found {len(artist_cards)} links with user pattern")

            # Если всё ещё не найдено, пробуем более широкий поиск
            if not artist_cards:
                self.logger.info("🔍 Trying broad search for service links...")
                all_links = soup.find_all('a', href=True)
                artist_cards = [link for link in all_links if any(service in link.get('href', '') for service in ['fanbox', 'patreon', 'discord', 'fantia'])]
                self.logger.info(f"🎯 Found {len(artist_cards)} service links")

            # Выводим информацию о найденных карточках
            if artist_cards:
                self.logger.info(f"✅ Total artist cards found: {len(artist_cards)}")
                for i, card in enumerate(artist_cards[:3]):
                    link = card.find('a', href=True)
                    title_elem = card.find('h2') or card.find('header')
                    if link:
                        self.logger.info(f"  {i+1}. Link: {link.get('href')}")
                    if title_elem:
                        self.logger.info(f"      Title: {title_elem.text.strip()}")
            else:
                self.logger.warning("❌ No artist cards found with any selector")

            # Парсим найденных авторов
            for card in artist_cards[:limit]:
                try:
                    # Карточка сама является ссылкой
                    href = card.get('href')
                    if href:
                        parts = href.strip('/').split('/')
                        if len(parts) >= 3:
                            service_name = parts[0]
                            user_id = parts[2]

                            # Ищем имя в дочерних элементах
                            name_elem = card.find('div', class_='user-card__name')
                            if name_elem:
                                name = name_elem.text.strip()
                            else:
                                # Попробуем найти в других местах
                                name_spans = card.find_all('div')
                                name = f"User_{user_id}"  # значение по умолчанию
                                for span in name_spans:
                                    text = span.text.strip()
                                    if text and not text.isdigit() and len(text) > 2:
                                        name = text
                                        break

                            # Создаем объект Artist с правильными полями
                            artist = Artist(
                                id=user_id,
                                service=service_name,
                                name=name,
                                indexed="",
                                updated="",
                                url=f"{self.base_url}{href}"
                            )
                            artists.append(artist)
                            self.logger.info(f"✅ Parsed artist: {name} ({service_name}) - {href}")
                except Exception as e:
                    self.logger.error(f"Error parsing search result: {e}")
                    continue

            self.logger.info(f"Successfully parsed {len(artists)} artists from Selenium search")

        except Exception as e:
            self.logger.error(f"Error searching artists with Selenium: {e}")

        return artists

    def search_posts_selenium(self, query: str, limit: int = 50, search_url: str = None) -> List[Post]:
        """Поиск постов через Selenium (для обхода защиты)"""
        posts = []

        try:
            # Используем переданный URL или по умолчанию
            if search_url is None:
                search_url = f"{self.base_url}/posts"

            self.logger.info(f"🔍 Selenium Search posts for '{query}' via URL: {search_url}")

            if self.driver:
                try:
                    # ШАГ 1: Переходим на страницу поиска с обработкой редиректов
                    self.logger.info(f"🌐 Navigating to: {search_url}")
                    self.driver.get(search_url)

                    # Ждем загрузки и проверяем редирект
                    import time
                    import random
                    delay = random.uniform(2, 4)
                    time.sleep(delay)

                    current_url = self.driver.current_url
                    self.logger.info(f"📍 Current URL after navigation: {current_url}")

                    # Если произошел редирект на внешнюю страницу - возвращаемся
                    if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                        self.logger.warning("⚠️ Detected redirect to external page - returning to search page")

                        # Принудительно возвращаемся на страницу поиска
                        self.driver.get(search_url)
                        time.sleep(random.uniform(1, 3))

                        # Проверяем, что теперь на правильной странице
                        current_url = self.driver.current_url
                        if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                            self.logger.error("❌ Still redirected to external page after retry")
                            return posts

                        self.logger.info(f"✅ Successfully returned to: {current_url}")

                    # Имитируем естественное поведение: случайная задержка
                    delay = random.uniform(3, 6)
                    self.logger.info(f"⏳ Waiting {delay:.1f}s for page load...")
                    time.sleep(delay)

                    # Имитируем движение мыши и прокрутку
                    try:
                        self.logger.info("🖱️ Simulating human behavior...")
                        # Случайное движение мыши
                        from selenium.webdriver.common.action_chains import ActionChains
                        actions = ActionChains(self.driver)
                        actions.move_by_offset(random.randint(100, 500), random.randint(100, 300)).perform()
                        time.sleep(random.uniform(0.5, 1.5))

                        # Небольшая прокрутка
                        self.driver.execute_script(f"window.scrollBy(0, {random.randint(200, 500)});")
                        time.sleep(random.uniform(0.5, 1.5))
                    except Exception as e:
                        self.logger.warning(f"Human behavior simulation failed: {e}")

                    # Проверяем, что мы на правильной странице
                    current_url = self.driver.current_url
                    self.logger.info(f"📍 Current URL: {current_url}")

                    # Проверяем на редирект
                    if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                        self.logger.warning("⚠️ Redirected to external page - search blocked")
                        return posts

                    if 'kemono.cr' not in current_url:
                        self.logger.warning(f"⚠️ Not on kemono.cr anymore: {current_url}")
                        return posts

                    # ШАГ 2: Ищем поле поиска
                    self.logger.info("🔍 Looking for search input field...")
                    from selenium.webdriver.common.by import By
                    from selenium.webdriver.support.ui import WebDriverWait
                    from selenium.webdriver.support import expected_conditions as EC

                    try:
                        search_input = WebDriverWait(self.driver, 15).until(
                            EC.presence_of_element_located((By.ID, "q"))
                        )
                        self.logger.info("✅ Search input found!")
                    except Exception as e:
                        self.logger.error(f"❌ Search input not found: {e}")
                        return posts

                    # ШАГ 3: Вводим запрос
                    self.logger.info(f"✍️ Entering query: {query}")
                    search_input.clear()

                    # Имитируем медленный ввод
                    for char in query:
                        search_input.send_keys(char)
                        time.sleep(0.15)

                    time.sleep(1)

                    # ШАГ 4: Ищем и нажимаем кнопку поиска
                    self.logger.info("🔘 Looking for search button...")
                    try:
                        search_button = self.driver.find_element(By.CSS_SELECTOR, "button.search-button")
                        self.logger.info("✅ Search button found!")
                    except Exception as e:
                        self.logger.warning(f"❌ Search button not found: {e}")
                        # Пробуем альтернативный селектор
                        try:
                            search_button = self.driver.find_element(By.CSS_SELECTOR, "button[type='submit']")
                            self.logger.info("✅ Alternative search button found!")
                        except Exception as e2:
                            self.logger.error(f"❌ No search button found: {e2}")
                            return posts

                    # Нажимаем кнопку (используем JavaScript, чтобы избежать перехвата)
                    try:
                        self.driver.execute_script("arguments[0].click();", search_button)
                        self.logger.info("🔘 Search button clicked (via JavaScript)")
                    except:
                        # Если JavaScript не сработал, пробуем обычный клик
                        search_button.click()
                        self.logger.info("🔘 Search button clicked (regular click)")

                    # ШАГ 5: Ждем результатов и обрабатываем новую вкладку
                    self.logger.info("⏳ Waiting for results...")
                    time.sleep(2)

                    # ШАГ 6: Проверяем на новую вкладку (белый список доменов)
                    allowed_domains = ['kemono.cr', 'kemono.su', 'kemono.party']

                    def is_allowed_url(url):
                        try:
                            from urllib.parse import urlparse
                            domain = urlparse(url).netloc.lower()
                            return any(allowed in domain for allowed in allowed_domains)
                        except:
                            return False

                    # Проверяем текущую вкладку
                    current_url = self.driver.current_url
                    self.logger.info(f"📍 Current URL after search: {current_url}")

                    # Если текущая вкладка не на разрешенном домене - ищем новую вкладку
                    if not is_allowed_url(current_url):
                        self.logger.info("🔍 Current tab redirected - looking for new tab with results...")

                        # Ждем открытия новой вкладки
                        max_attempts = 10
                        for attempt in range(max_attempts):
                            try:
                                # Получаем все вкладки
                                all_handles = self.driver.window_handles
                                self.logger.info(f"📑 Found {len(all_handles)} tabs")

                                # Ищем вкладку с разрешенным доменом
                                for handle in all_handles:
                                    self.driver.switch_to.window(handle)
                                    tab_url = self.driver.current_url
                                    self.logger.info(f"🔍 Checking tab: {tab_url}")

                                    if is_allowed_url(tab_url):
                                        self.logger.info("✅ Found correct tab with kemono.cr!")
                                        current_url = tab_url
                                        break

                                if is_allowed_url(self.driver.current_url):
                                    break

                                time.sleep(1)  # Ждем еще

                            except Exception as e:
                                self.logger.warning(f"Attempt {attempt + 1} failed: {e}")
                                time.sleep(0.5)

                        # Если нашли правильную вкладку - повторяем поиск
                        if is_allowed_url(self.driver.current_url):
                            self.logger.info("🔄 Retrying search in correct tab...")

                            try:
                                # Ждем загрузки страницы
                                time.sleep(2)

                                # Ищем поле поиска
                                search_input = WebDriverWait(self.driver, 10).until(
                                    EC.presence_of_element_located((By.ID, "q"))
                                )
                                self.logger.info("✅ Search input found in new tab")

                                # Очищаем и вводим запрос заново
                                search_input.clear()
                                for char in query:
                                    search_input.send_keys(char)
                                    time.sleep(0.1)
                                time.sleep(0.5)

                                # Ищем кнопку поиска
                                search_button = self.driver.find_element(By.CSS_SELECTOR, "button.search-button")

                                # Нажимаем кнопку
                                self.driver.execute_script("arguments[0].click();", search_button)
                                self.logger.info("🔘 Search button clicked in new tab")

                                # Ждем результаты
                                time.sleep(4)

                                # Финальная проверка
                                final_url = self.driver.current_url
                                self.logger.info(f"📍 Final URL after retry: {final_url}")

                                if not is_allowed_url(final_url):
                                    self.logger.error("❌ Still not on correct domain after retry")
                                    return posts

                            except Exception as e:
                                self.logger.error(f"❌ Failed to retry search in new tab: {e}")
                                return posts
                        else:
                            self.logger.error("❌ Could not find tab with kemono.cr")
                            return posts

                    # Получаем HTML результатов
                    html = self.driver.page_source
                    self.logger.info(f"📄 Got HTML: {len(html)} characters")

                except Exception as e:
                    self.logger.error(f"Selenium interaction failed: {e}")
                    return posts
            else:
                self.logger.error("Selenium driver not available")
                return posts

            # Сохраняем HTML для анализа
            with open('selenium_search_posts.html', 'w', encoding='utf-8') as f:
                f.write(html)

            # Парсим результаты
            soup = BeautifulSoup(html, 'lxml')

            # Проверяем, что мы на правильной странице
            title = soup.find('title')
            if title:
                self.logger.info(f"Page title: {title.text.strip()}")

            # Проверяем URL после редиректа
            final_url = self.driver.current_url if self.driver else search_url
            self.logger.info(f"Final URL: {final_url}")

            # Если нас перенаправили на внешнюю страницу - поиск не удался
            if 'nachdiewelt.click' in final_url or 'quantum' in final_url.lower():
                self.logger.warning("Redirected to external page - posts search blocked")
                return posts

            # Парсим результаты поиска постов
            post_cards = soup.find_all('article', class_='card')
            self.logger.info(f"Found {len(post_cards)} post cards")

            # Если не найдено, попробуем другие селекторы
            if not post_cards:
                self.logger.info("Trying alternative selectors...")
                post_cards = soup.find_all('article', attrs={'data-id': True})
                self.logger.info(f"Alternative selector found {len(post_cards)} cards")

            # Парсим найденные посты
            for card in post_cards[:limit]:
                try:
                    link = card.find('a', href=True)
                    if link:
                        href = link['href']
                        parts = href.strip('/').split('/')
                        if len(parts) >= 4:  # /service/user_id/post_id
                            service_name = parts[0]
                            user_id = parts[2]
                            post_id = parts[3]

                            title_elem = card.find('h2') or card.find('header')
                            title = title_elem.text.strip() if title_elem else f"Post_{post_id}"

                            # Создаем объект Post с правильными полями
                            post = Post(
                                id=post_id,
                                title=title,
                                content="",
                                published="",
                                edited="",
                                author=user_id,  # Используем author вместо user
                                service=service_name,
                                url=f"{self.base_url}{href}",
                                thumbnail="",  # На странице поиска нет превью
                                attachments=[],  # На странице поиска нет вложений
                                embeds=[],  # На странице поиска нет эмбедов
                                files=[]  # На странице поиска нет файлов
                            )
                            posts.append(post)
                except Exception as e:
                    self.logger.error(f"Error parsing post search result: {e}")
                    continue

            self.logger.info(f"Successfully parsed {len(posts)} posts from Selenium search")

        except Exception as e:
            self.logger.error(f"Error searching posts with Selenium: {e}")

        return posts

    def download_post_content(self, post: Post, download_dir: str = "downloads", artist: Artist = None) -> int:
        """Скачивание всего контента поста"""
        downloaded_count = 0

        # Создаем директорию для поста
        safe_title = re.sub(r'[<>:"/\\|?*]', '_', post.title[:50])

        # Используем информацию из artist объекта, если он передан
        if artist:
            author_name = f"{artist.service}_{artist.name}_{artist.id}"
        else:
            author_name = f"{post.service}_{post.author}"

        post_dir = os.path.join(download_dir, author_name, safe_title)
        os.makedirs(post_dir, exist_ok=True)

        self.logger.info(f"Processing post: {post.title} (ID: {post.id})")
        self.logger.info(f"Post has {len(post.attachments)} attachments and {len(post.files)} files")

        # Если у нас есть вложения из превью, скачиваем их
        for attachment in post.attachments:
            try:
                filename = attachment['name']
                filepath = os.path.join(post_dir, filename)
                if self.download_file(attachment['url'], filepath):
                    downloaded_count += 1
            except Exception as e:
                self.logger.error(f"Error downloading attachment: {e}")

        # Если у нас есть файлы из превью, скачиваем их
        for file_info in post.files:
            try:
                filename = file_info['name']
                filepath = os.path.join(post_dir, filename)
                if self.download_file(file_info['url'], filepath):
                    downloaded_count += 1
            except Exception as e:
                self.logger.error(f"Error downloading file: {e}")

        # Если вложений мало или их нет, пробуем загрузить с полной страницы поста
        self.logger.info(f"Downloaded count: {downloaded_count}, checking if we need to load full post page")
        if downloaded_count == 0:
            # Используем правильный ID автора из artist объекта, если он передан
            author_id = artist.id if artist else (post.author if post.author.isdigit() else post.author.split('_')[-1] if '_' in post.author else post.author)
            post_url = f"{self.base_url}/{post.service}/post/{post.id}"
            self.logger.info(f"Loading full post page: {post_url}")

            try:
                if self.use_selenium:
                    html = self._selenium_get(post_url)
                    if html:
                        soup = BeautifulSoup(html, 'lxml')

                        # Ищем все ссылки на медиафайлы
                        media_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.svg', 
                                           '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv',
                                           '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2',
                                           '.pdf', '.doc', '.docx', '.txt', '.psd']
                        media_links = soup.find_all('a', href=lambda x: x and any(ext in x.lower() for ext in media_extensions))

                        self.logger.info(f"Found {len(media_links)} media links on post page")

                        # Также ищем прямые ссылки на изображения в атрибутах src
                        img_tags = soup.find_all('img', src=lambda x: x and any(ext in x.lower() for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']))
                        self.logger.info(f"Found {len(img_tags)} image tags with media src")

                        # Обрабатываем все найденные медиа URL
                        all_media_urls = set()

                        # Добавляем ссылки из <a> тегов
                        for link in media_links:
                            try:
                                url = link['href']
                                if not url.startswith('http'):
                                    url = f"https:{url}" if url.startswith('//') else urljoin(self.base_url, url)
                                all_media_urls.add(url)
                            except:
                                continue

                        # Добавляем ссылки из <img> тегов
                        for img in img_tags:
                            try:
                                url = img['src']
                                if not url.startswith('http'):
                                    url = f"https:{url}" if url.startswith('//') else urljoin(self.base_url, url)
                                # Пропускаем превью и маленькие изображения
                                if any(x in url.lower() for x in ['thumb', 'preview', 'icon', 'thumbnail']):
                                    continue
                                all_media_urls.add(url)
                            except:
                                continue

                        self.logger.info(f"Total unique media URLs found: {len(all_media_urls)}")

                        for url in all_media_urls:
                            try:
                                filename = url.split('/')[-1].split('?')[0]  # Убираем параметры запроса
                                if not filename:
                                    continue

                                filepath = os.path.join(post_dir, filename)

                                # Проверяем, существует ли файл
                                if os.path.exists(filepath):
                                    self.logger.info(f"File already exists: {filename}")
                                    continue

                                self.logger.info(f"Attempting to download: {filename}")
                                if self.download_file(url, filepath):
                                    downloaded_count += 1
                                    self.logger.info(f"Successfully downloaded: {filename}")
                                else:
                                    self.logger.warning(f"Failed to download: {filename}")

                            except Exception as e:
                                self.logger.error(f"Error downloading {url}: {e}")

            except Exception as e:
                self.logger.error(f"Error loading post page: {e}")

        return downloaded_count

    def _is_valid_media_url(self, url):
        """Проверяет, является ли URL допустимым для скачивания медиа"""
        try:
            # Пропускаем URL с проблемными доменами
            skip_domains = [
                'ads.', 'advertising', 'analytics', 'tracking', 'googletagmanager',
                'google-analytics', 'doubleclick', 'facebook.com', 'twitter.com',
                'instagram.com', 'youtube.com', 'vimeo.com'
            ]

            if any(domain in url.lower() for domain in skip_domains):
                return False

            # Пропускаем URL с двойными слешами или подозрительными параметрами
            if '//' in url[8:] or any(x in url.lower() for x in ['utm_', 'fbclid', 'ref=', 'source=']):
                return False

            # Проверяем что URL содержит /data/
            if '/data/' not in url:
                return False

            # Проверяем расширение файла
            filename = url.split('/')[-1].split('?')[0].lower()
            valid_extensions = [
                '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tiff', '.svg',
                '.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv',
                '.zip', '.rar', '.7z', '.tar', '.gz', '.bz2',
                '.pdf', '.doc', '.docx', '.txt', '.psd'
            ]

            return any(filename.endswith(ext) for ext in valid_extensions)

        except Exception:
            return False

    def close(self):
        """Закрытие ресурсов"""
        if hasattr(self, 'driver') and self.driver is not None:
            try:
                self.driver.quit()
                print("[CLEANUP] Chrome драйвер закрыт")
            except Exception as e:
                print(f"[CLEANUP] Ошибка при закрытии драйвера: {e}")
            finally:
                self.driver = None
        
        if hasattr(self, 'session') and self.session is not None:
            try:
                self.session.close()
            except Exception as e:
                print(f"[CLEANUP] Ошибка при закрытии сессии: {e}")

    def __del__(self):
        """Деструктор для автоматического закрытия ресурсов"""
        self.close()


def main():
    """Пример использования парсера"""
    parser = KemonoParser()

    try:
        # Получаем список авторов
        print("Получаем список авторов...")
        artists = parser.get_artists_list(limit=10)

        if not artists:
            print("Не удалось получить список авторов")
            return

        print(f"Найдено {len(artists)} авторов")

        # Выбираем первого автора
        artist = artists[0]
        print(f"Парсим посты автора: {artist.name}")

        # Получаем посты автора
        posts = parser.get_artist_posts(artist, limit=5)

        print(f"Найдено {len(posts)} постов")

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


        return artists


if __name__ == "__main__":
    main()
