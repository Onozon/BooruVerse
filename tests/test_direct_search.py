#!/usr/bin/env python3
"""
Прямой тест поиска без Selenium - с правильными заголовками
"""

import requests
from bs4 import BeautifulSoup
import time
import random

def test_direct_search():
    """Тест поиска через прямые HTTP запросы"""

    print("🔍 Тестирование прямого поиска через HTTP")
    print("="*50)

    base_url = "https://kemono.cr"
    search_url = f"{base_url}/artists"

    # Расширенные заголовки для имитации реального браузера
    headers = {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
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
        'sec-ch-ua': '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"macOS"',
    }

    # Создаем сессию
    session = requests.Session()
    session.headers.update(headers)

    try:
        print("🌐 Получаем основную страницу...")
        response = session.get(search_url, timeout=10)
        print(f"📄 Статус: {response.status_code}")
        print(f"📏 Длина: {len(response.text)} символов")

        if response.status_code == 200:
            print("✅ Страница загружена успешно")

            # Ищем форму поиска
            soup = BeautifulSoup(response.text, 'lxml')
            search_form = soup.find('form', class_='search-form')
            if search_form:
                print("✅ Найдена форма поиска")

                # Получаем action формы
                action = search_form.get('action', '')
                if not action:
                    action = '/artists'  # По умолчанию
                elif not action.startswith('http'):
                    action = base_url + action

                print(f"🎯 Action формы: {action}")

                # Ищем поле поиска
                search_input = search_form.find('input', {'name': 'q'})
                if search_input:
                    print("✅ Найдено поле поиска")

                    # Отправляем поисковый запрос
                    search_data = {
                        'q': 'abmayo',
                        'service': '',
                        'sort_by': 'favorited',
                        'order': ''
                    }

                    print(f"🔍 Отправляем запрос: {search_data}")

                    search_response = session.post(action, data=search_data, timeout=10)
                    print(f"📄 Статус поиска: {search_response.status_code}")
                    print(f"📏 Длина результата: {len(search_response.text)}")

                    if search_response.status_code == 200:
                        print("✅ Поиск выполнен")

                        # Проверяем редирект
                        if 'nachdiewelt.click' in search_response.url:
                            print("❌ Редирект на внешнюю страницу!")
                            return

                        # Парсим результаты
                        search_soup = BeautifulSoup(search_response.text, 'lxml')
                        title = search_soup.find('title')
                        if title:
                            print(f"📄 Заголовок: {title.text.strip()}")

                        # Ищем карточки
                        cards = search_soup.find_all('a', class_='user-card')
                        print(f"🎴 Найдено карточек: {len(cards)}")

                        if cards:
                            print("✅ Найдены результаты!")
                            for i, card in enumerate(cards[:3]):
                                href = card.get('href', '')
                                text = card.get_text().strip()
                                print(f"  {i+1}. {text} -> {href}")
                        else:
                            print("❌ Результаты не найдены")

                            # Сохраняем для анализа
                            with open('direct_search_result.html', 'w', encoding='utf-8') as f:
                                f.write(search_response.text)
                            print("💾 HTML сохранён для анализа")
                    else:
                        print(f"❌ Ошибка поиска: {search_response.status_code}")
                else:
                    print("❌ Поле поиска не найдено")
            else:
                print("❌ Форма поиска не найдена")
        else:
            print(f"❌ Ошибка загрузки страницы: {response.status_code}")

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_direct_search()

