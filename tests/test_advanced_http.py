#!/usr/bin/env python3
"""
Продвинутый тест обхода защиты Kemono.cr
"""

import requests
from bs4 import BeautifulSoup
import time
import random
import json
from urllib.parse import urlencode

def create_stealth_session():
    """Создание сессии с максимальной скрытностью"""

    session = requests.Session()

    # Разные User-Agent для тестирования
    user_agents = [
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15',
    ]

    headers = {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'en-US,en;q=0.9,ru;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'DNT': '1',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Cache-Control': 'max-age=0',
    }

    # Выбираем случайный User-Agent
    headers['User-Agent'] = random.choice(user_agents)

    session.headers.update(headers)

    return session

def test_with_session(url, query, session, attempt_num):
    """Тест с сессией и дополнительными заголовками"""

    print(f"\n🔄 Попытка {attempt_num} для {url}")

    try:
        # Сначала посещаем главную страницу
        print("🌐 Посещаем главную страницу...")
        main_response = session.get("https://kemono.cr", timeout=15)

        if main_response.status_code != 200:
            print(f"❌ Ошибка главной страницы: {main_response.status_code}")
            return None

        print(f"✅ Главная страница загружена ({len(main_response.text)} символов)")

        # Небольшая задержка
        time.sleep(random.uniform(1, 3))

        # Теперь делаем поисковый запрос
        params = {
            'q': query,
            'service': '',
            'sort_by': 'favorited',
            'order': ''
        }

        # Добавляем дополнительные заголовки для поиска
        search_headers = session.headers.copy()
        search_headers.update({
            'Referer': url,
            'X-Requested-With': 'XMLHttpRequest',  # Имитируем AJAX
        })

        print(f"🔍 Выполняем поиск: {query}")
        print(f"📊 Параметры: {params}")

        search_response = session.get(url, params=params, headers=search_headers, timeout=15)

        print(f"📡 Статус ответа: {search_response.status_code}")
        print(f"📏 Длина ответа: {len(search_response.text)} символов")
        print(f"🔗 Финальный URL: {search_response.url}")

        # Проверяем редирект
        if 'nachdiewelt.click' in search_response.url or 'quantum' in search_response.url.lower():
            print("⚠️ Редирект на внешнюю страницу!")
            return None

        # Сохраняем HTML для анализа
        filename = f'session_search_attempt_{attempt_num}.html'
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(search_response.text)
        print(f"💾 HTML сохранен в {filename}")

        # Анализируем контент
        soup = BeautifulSoup(search_response.text, 'lxml')

        title = soup.find('title')
        if title:
            print(f"📄 Заголовок: {title.text.strip()}")

        # Ищем карточки
        cards = soup.find_all('article', class_='card')
        print(f"🎴 Найдено карточек: {len(cards)}")

        if cards:
            print("✅ Найдены результаты!")
            for i, card in enumerate(cards[:3]):
                link = card.find('a', href=True)
                title_elem = card.find('h2') or card.find('header')
                if link and title_elem:
                    print(f"  {i+1}. {title_elem.text.strip()}")
                    print(f"      {link['href']}")
            return cards

        # Если не нашли стандартные карточки, ищем альтернативные
        alt_cards = soup.find_all('article', attrs={'data-id': True})
        if alt_cards:
            print(f"🎯 Найдены альтернативные карточки: {len(alt_cards)}")
            return alt_cards

        return []

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        return None

def test_multiple_sessions():
    """Тест с множественными сессиями"""

    print("🚀 Тест множественных сессий для обхода защиты")

    base_urls = [
        "https://kemono.cr/artists",
        "https://kemono.cr/artists/updated",
        "https://kemono.cr/posts"
    ]

    query = "abmayo"
    max_attempts = 3

    for url in base_urls:
        print(f"\n{'='*60}")
        print(f"🎯 Тестируем URL: {url}")

        for attempt in range(max_attempts):
            # Создаем новую сессию для каждой попытки
            session = create_stealth_session()

            result = test_with_session(url, query, session, attempt + 1)

            if result and len(result) > 0:
                print(f"🎉 УСПЕХ! Найдено {len(result)} результатов на {url}")
                return True

            # Задержка между попытками
            if attempt < max_attempts - 1:
                delay = random.uniform(3, 7)
                print(f"⏳ Ждем {delay:.1f} секунд...")
                time.sleep(delay)

        print(f"❌ Все попытки для {url} неудачны")

    return False

def test_cloudflare_bypass():
    """Тест специальных техник для обхода Cloudflare"""

    print("\n" + "="*60)
    print("🛡️ Тест обхода Cloudflare защиты")

    session = create_stealth_session()

    # Добавляем дополнительные заголовки для обхода Cloudflare
    cf_headers = {
        'CF-RAY': '',
        'CF-Visitor': '{"scheme":"https"}',
        'CF-Connecting-IP': '',
        '__cfduid': '',
        'cf-browser-verification': '',
    }

    session.headers.update(cf_headers)

    # Имитируем посещение страницы несколько раз
    print("🔄 Имитируем естественное поведение...")

    for i in range(3):
        try:
            response = session.get("https://kemono.cr", timeout=10)
            print(f"Посещение {i+1}: статус {response.status_code}, длина {len(response.text)}")

            # Ищем признаки Cloudflare
            if 'cf-browser-verification' in response.text:
                print("⚠️ Обнаружена Cloudflare проверка!")
            elif 'challenge-platform' in response.text:
                print("⚠️ Обнаружена Cloudflare challenge!")
            elif len(response.text) > 10000:  # Нормальная страница
                print("✅ Страница загружается нормально")
                break

            time.sleep(random.uniform(2, 5))

        except Exception as e:
            print(f"❌ Ошибка посещения {i+1}: {e}")

    # Теперь пробуем поиск
    return test_with_session("https://kemono.cr/artists", "abmayo", session, 1)

def main():
    """Основная функция"""

    print("🚀 Продвинутый тест обхода защиты Kemono.cr")
    print("="*80)

    # Тест 1: Множественные сессии
    print("\n1️⃣ ТЕСТ МНОЖЕСТВЕННЫХ СЕССИЙ")
    success1 = test_multiple_sessions()

    if success1:
        print("\n✅ Тест множественных сессий прошел успешно!")
        return

    # Тест 2: Обход Cloudflare
    print("\n2️⃣ ТЕСТ ОБХОДА CLOUDFLARE")
    success2 = test_cloudflare_bypass()

    if success2:
        print("\n✅ Тест обхода Cloudflare прошел успешно!")
        return

    print("\n❌ Все тесты завершились неудачно")
    print("💡 Возможные причины:")
    print("   - Слишком агрессивная защита сайта")
    print("   - Требуется Selenium для JavaScript рендеринга")
    print("   - Необходимы прокси или VPN")
    print("   - Сайт использует advanced bot detection")

if __name__ == "__main__":
    main()

