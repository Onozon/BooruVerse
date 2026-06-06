# Инструкция по запуску с виртуальным окружением

## Установка и настройка

Виртуальное окружение уже настроено в папке `.venv` со всеми необходимыми зависимостями.

## Запуск приложения

### Способ 1 - Через скрипт активации:
```bash
cd "/Users/onozon/Documents/kemono parcer"
source activate_venv.sh
```

### Способ 2 - Вручную:
```bash
cd "/Users/onozon/Documents/kemono parcer"
source .venv/bin/activate
python3 kemono_gui_v6.py
```

### Способ 3 - Прямой запуск:
```bash
cd "/Users/onozon/Documents/kemono parcer"
.venv/bin/python kemono_gui_v6.py
```

## Деактивация окружения

После работы с приложением:
```bash
deactivate
```

## Установленные зависимости

- **PyQt6 6.10.0** - GUI фреймворк
- **Selenium 4.37.0** - веб-автоматизация 
- **Pillow 12.0.0** - работа с изображениями
- **BeautifulSoup4 4.14.2** - парсинг HTML
- **requests 2.32.5** - HTTP запросы
- **lxml 6.0.2** - XML/HTML парсер
- **webdriver-manager 4.0.2** - управление веб-драйверами
- **tqdm 4.67.1** - прогресс-бары
- **fake-useragent 2.2.0** - генерация user-agent

## Решение проблем

### Если появляется ошибка cocoa plugin:
1. Полностью переустановите PyQt6:
```bash
source .venv/bin/activate
pip uninstall -y PyQt6 PyQt6-Qt6 PyQt6-sip
pip install --upgrade --force-reinstall PyQt6
```

### Переустановка зависимостей:
```bash
source .venv/bin/activate
pip install -r requirements.txt --force-reinstall
```

## Файловая структура

- `kemono_gui_v6.py` - основное приложение
- `kemono_parser.py` - модуль парсинга
- `interactive_downloader.py` - загрузчик контента
- `.venv/` - виртуальное окружение
- `requirements.txt` - список зависимостей
- `activate_venv.sh` - скрипт активации
