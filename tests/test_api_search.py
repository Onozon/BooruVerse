#!/usr/bin/env python3
"""
Тест API поиска Kemono
"""

import requests
import json

def test_api_search():
    """Тестируем поиск через API"""

    print("🧪 ТЕСТИРОВАНИЕ API ПОИСКА KEMONO")
    print("="*50)

    # Тестовые запросы
    test_queries = ["test", "fanbox", "patreon"]

    for query in test_queries:
        print(f"\n🔍 Поиск по запросу: '{query}'")

        try:
            # API URL
            api_url = f"https://kemono.cr/api/v1/creators?q={query}"

            # Заголовки как в браузере
            headers = {
                'Accept': 'text/css',
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }

            # Читаем сессионную куку
            cookies = {}
            try:
                with open('session_cookie.txt', 'r', encoding='utf-8') as f:
                    session_cookie = f.read().strip()
                    if session_cookie:
                        cookies['session'] = session_cookie
                        print(f"🍪 Используем сессионную куку: {session_cookie[:20]}...")
            except Exception as e:
                print(f"⚠️ Не удалось загрузить сессионную куку: {e}")

            print(f"📡 Запрос: {api_url}")

            # Делаем запрос с куками
            response = requests.get(api_url, headers=headers, cookies=cookies, timeout=10)

            print(f"📊 Статус: {response.status_code}")
            print(f"📊 Content-Type: {response.headers.get('content-type', 'unknown')}")

            if response.status_code == 200:
                try:
                    # API возвращает JSON с Content-Type: text/css для обхода ботов
                    data = response.json()
                    print(f"✅ Получено {len(data)} результатов")

                    # Показываем первые 3 результата
                    for i, item in enumerate(data[:3]):
                        print(f"  {i+1}. {item.get('name', 'Unknown')} ({item.get('service', 'unknown')}) - ID: {item.get('id', 'unknown')}")

                except json.JSONDecodeError as e:
                    print(f"❌ Ошибка парсинга JSON: {e}")
                    print(f"📄 Первые 200 символов: {response.text[:200]}")

            else:
                print(f"❌ HTTP ошибка: {response.status_code}")
                print(f"📄 Ответ: {response.text[:200]}")

        except requests.exceptions.RequestException as e:
            print(f"❌ Сетевая ошибка: {e}")

        except Exception as e:
            print(f"❌ Неожиданная ошибка: {e}")

if __name__ == "__main__":
    test_api_search()
