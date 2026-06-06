# Kemono.cr Parser

Парсер для сайта kemono.cr - агрегатора контента из Patreon, Fanbox, Gumroad и других платформ.

## Описание

Этот парсер позволяет:
- Получать список авторов с различных платформ
- Парсить посты конкретного автора
- Скачивать изображения, видео и другие файлы
- Работать как с обычными HTTP запросами, так и с Selenium для JavaScript-тяжелых страниц

## Установка

1. Установите зависимости:
```bash
pip install -r requirements.txt
```

2. Для работы с Selenium установите Chrome браузер

## Использование

### 🚀 Быстрый старт

**Для новичков:** Читайте **[GUIDE.md](GUIDE.md)** - подробный гайд по использованию!

**Для опытных пользователей:**

```bash
# Установка зависимостей
pip install -r requirements.txt

# Запуск интерактивного загрузчика
python interactive_downloader.py

# Или простого запуска
python run_downloader.py
```

**Что делает скрипт:**
1. Запрашивает URL автора (например: `https://kemono.cr/fanbox/user/3065392`)
2. Находит ВСЕ посты автора (без ограничений)
3. Скачивает ВСЕ медиафайлы из каждого поста
4. Организует файлы в структуру папок: `downloads/автор/пост/файлы`
5. Создает подробный отчет о скачанных файлах

**Пример использования:**
```
🔗 Введите URL автора: https://kemono.cr/fanbox/user/3065392
✅ URL распознан:
   Сервис: fanbox
   ID автора: 3065392
   Полный URL: https://kemono.cr/fanbox/user/3065392

🚀 Начать скачивание всех медиафайлов автора fanbox/3065392? (y/n): y

🔍 Поиск всех постов автора User_3065392 (fanbox)...
   Найдено 25 новых постов (всего: 25)

📊 Найдено 25 постов
   🖼️  Изображений: 45
   🎬 Видео: 3
   📁 Других файлов: 2

🚀 Скачать 50 медиафайлов из 25 постов? (y/n): y

📁 Создаю структуру папок в: downloads/fanbox_User_3065392_3065392

📄 [1/25] Обработка поста: Мой новый арт
   ⬇️  Скачиваю: image1.jpg
   ✅ Скачано: image1.jpg
   📊 Пост завершен: 1 скачано, 0 пропущено

🎉 Скачивание завершено!
   ⏱️  Время выполнения: 125.3 секунд
   📊 Скачано файлов: 48
   ⏭️  Пропущено (уже существуют): 2
   📁 Папка с файлами: downloads/fanbox_User_3065392_3065392
   📄 Отчет сохранен: downloads/fanbox_User_3065392_3065392/download_report.json
```

**Структура папок после скачивания:**
```
downloads/
└── fanbox_User_3065392_3065392/
    ├── Мой_новый_арт/
    │   ├── image1.jpg
    │   └── image2.png
    ├── Концепт_арт/
    │   ├── sketch.jpg
    │   └── final.png
    ├── download_report.json
    └── ...
```

### Базовое использование (программное API)

```python
from kemono_parser import KemonoParser

# Создаем экземпляр парсера
parser = KemonoParser()

try:
    # Получаем список авторов
    artists = parser.get_artists_list(limit=10)

    # Выбираем автора
    if artists:
        artist = artists[0]
        print(f"Автор: {artist.name} ({artist.service})")

        # Получаем посты автора
        posts = parser.get_artist_posts(artist, limit=5)

        # Скачиваем контент первого поста
        if posts:
            post = posts[0]
            parser.download_post_content(post)

finally:
    parser.close()
```

### Продвинутое использование

```python
from kemono_parser import KemonoParser
import json

# Загружаем конфигурацию
with open('config.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

# Создаем парсер с Selenium для JavaScript страниц
parser = KemonoParser(
    base_url=config['base_url'],
    use_selenium=True,
    headless=True
)

try:
    # Парсим конкретного автора по URL
    artist_url = "https://kemono.cr/patreon/user/123456"
    posts = parser.get_artist_posts_from_url(artist_url)

    # Скачиваем все посты
    for post in posts:
        downloaded = parser.download_post_content(post, config['download_dir'])
        print(f"Скачано файлов: {downloaded}")

finally:
    parser.close()
```

### Парсинг по сервисам

```python
# Парсим только Patreon авторов
patreon_artists = parser.get_artists_list(service="patreon", limit=20)

# Парсим только Fanbox авторов
fanbox_artists = parser.get_artists_list(service="fanbox", limit=20)
```

## Классы данных

### Artist
```python
@dataclass
class Artist:
    id: str          # ID автора
    service: str     # Сервис (patreon, fanbox, etc.)
    name: str        # Имя автора
    indexed: str     # Дата индексации
    updated: str     # Дата обновления
    url: str         # Полный URL страницы автора
```

### Post
```python
@dataclass
class Post:
    id: str                      # ID поста
    title: str                   # Заголовок
    content: str                 # Текстовый контент
    published: str              # Дата публикации
    edited: Optional[str]       # Дата редактирования
    author: str                 # Автор
    service: str                # Сервис
    attachments: List[Dict]     # Вложения (изображения)
    embeds: List[Dict]          # Встроенный контент
    files: List[Dict]           # Файлы для скачивания
```

## Методы

### KemonoParser

#### `__init__(base_url, use_selenium, headless)`
Создает экземпляр парсера

#### `get_artists_list(service, limit)`
Получает список авторов
- `service`: фильтр по сервису (опционально)
- `limit`: максимальное количество авторов

#### `get_artist_posts(artist, offset, limit)`
Получает посты автора
- `artist`: экземпляр Artist
- `offset`: смещение для пагинации
- `limit`: максимальное количество постов

#### `get_post_details(post_url)`
Получает детальную информацию о посте

#### `download_file(url, filepath, show_progress)`
Скачивает файл с отображением прогресса

#### `download_post_content(post, download_dir)`
Скачивает весь контент поста

#### `close()`
Закрывает соединения и освобождает ресурсы

## Конфигурация

Файл `config.json` содержит настройки:

```json
{
  "base_url": "https://kemono.cr",
  "use_selenium": false,
  "headless": true,
  "download_dir": "downloads",
  "max_posts_per_artist": 100,
  "max_artists": 50,
  "request_delay": 1.0,
  "timeout": 30,
  "retry_attempts": 3
}
```

## Поддерживаемые сервисы

- Patreon
- Fanbox (Pixiv)
- Gumroad
- SubscribeStar
- DLsite
- Discord
- И другие

## Особенности

1. **Ротация User-Agent**: Автоматическая смена User-Agent для избежания блокировок
2. **Обработка ошибок**: Повторные попытки при неудачных запросах
3. **Прогресс-бары**: Отображение прогресса при скачивании файлов
4. **Selenium поддержка**: Для страниц с динамическим контентом
5. **Безопасные имена файлов**: Автоматическая очистка имен файлов от недопустимых символов

## Предупреждения

1. Соблюдайте правила использования сайта kemono.cr
2. Не перегружайте сервер частыми запросами
3. Убедитесь, что у вас есть права на скачивание контента
4. Используйте парсер responsibly

## Примеры скриптов

### Скачивание всех постов автора
```python
def download_all_artist_posts(artist_url, download_dir="downloads"):
    parser = KemonoParser()

    try:
        # Получаем информацию об авторе
        artist = parser.get_artist_from_url(artist_url)

        # Получаем все посты
        posts = []
        offset = 0
        while True:
            batch = parser.get_artist_posts(artist, offset=offset, limit=50)
            if not batch:
                break
            posts.extend(batch)
            offset += 50

        print(f"Найдено {len(posts)} постов")

        # Скачиваем все посты
        for post in posts:
            parser.download_post_content(post, download_dir)

    finally:
        parser.close()
```

### Парсинг нескольких сервисов
```python
services = ["patreon", "fanbox", "gumroad"]

for service in services:
    print(f"Парсим {service}...")
    artists = parser.get_artists_list(service=service, limit=10)

    for artist in artists:
        posts = parser.get_artist_posts(artist, limit=5)
        print(f"{artist.name}: {len(posts)} постов")
```

## Лицензия

MIT License
