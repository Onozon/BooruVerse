#!/usr/bin/env python3
"""
Тест поиска через HTTP запросы
"""

import requests
from bs4 import BeautifulSoup
import json

def test_http_search():
    """Тест поиска через HTTP"""

    print("🌐 Тестируем поиск через HTTP запросы")

    # Сначала получим страницу /artists
    url = "https://kemono.cr/artists"
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
    }

    try:
        print(f"📄 Получаем страницу: {url}")
        response = requests.get(url, headers=headers, timeout=30)

        if response.status_code == 200:
            print(f"✅ Страница получена, длина: {len(response.text)}")

            # Сохраним страницу
            with open('artists_page_http.html', 'w', encoding='utf-8') as f:
                f.write(response.text)

            # Попробуем отправить поисковый запрос
            search_url = "https://kemono.cr/artists"
            search_data = {
                'q': 'abmayo'
            }

            print("🔍 Отправляем поисковый запрос...")
            search_response = requests.get(search_url, params=search_data, headers=headers, timeout=30)

            if search_response.status_code == 200:
                print(f"✅ Поиск выполнен, длина ответа: {len(search_response.text)}")

                # Сохраним результаты поиска
                with open('search_results_http.html', 'w', encoding='utf-8') as f:
                    f.write(search_response.text)

                # Проверим, есть ли результаты
                soup = BeautifulSoup(search_response.text, 'lxml')
                cards = soup.find_all('article', class_='card')

                print(f"🎴 Найдено карточек: {len(cards)}")

                if cards:
                    print("✅ Найдены результаты поиска!")

                    # Покажем первые несколько результатов
                    for i, card in enumerate(cards[:3]):
                        link = card.find('a', href=True)
                        title = card.find('h2') or card.find('header')

                        if link and title:
                            print(f"{i+1}. {title.text.strip()} - {link['href']}")

                else:
                    print("❌ Результаты поиска не найдены")

                    # Посмотрим, что в title страницы
                    title = soup.find('title')
                    if title:
                        print(f"📄 Заголовок страницы: {title.text.strip()}")

                    # Проверим URL после поиска
                    print(f"🔗 URL после поиска: {search_response.url}")

            else:
                print(f"❌ Ошибка поиска: {search_response.status_code}")

        else:
            print(f"❌ Ошибка получения страницы: {response.status_code}")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

def test_direct_search_url():
    """Тест прямого URL с параметрами поиска"""

    print("\n" + "="*50)
    print("🔍 Тест прямого URL с параметрами поиска")

    search_url = "https://kemono.cr/artists?q=abmayo"

    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Referer': 'https://kemono.cr/artists',
    }

    try:
        print(f"🌐 Прямой запрос: {search_url}")
        response = requests.get(search_url, headers=headers, timeout=30)

        if response.status_code == 200:
            print(f"✅ Ответ получен, длина: {len(response.text)}")

            with open('direct_search_results.html', 'w', encoding='utf-8') as f:
                f.write(response.text)

            soup = BeautifulSoup(response.text, 'lxml')
            cards = soup.find_all('article', class_='card')

            print(f"🎴 Найдено карточек: {len(cards)}")

            if cards:
                print("✅ Прямой поиск работает!")

                for i, card in enumerate(cards[:3]):
                    link = card.find('a', href=True)
                    title = card.find('h2') or card.find('header')

                    if link and title:
                        print(f"{i+1}. {title.text.strip()} - {link['href']}")

            else:
                title = soup.find('title')
                if title:
                    print(f"📄 Заголовок: {title.text.strip()}")
                print(f"🔗 Финальный URL: {response.url}")

        else:
            print(f"❌ Ошибка: {response.status_code}")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    test_http_search()
    test_direct_search_url()

