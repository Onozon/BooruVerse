#!/usr/bin/env python3
"""
Анализ страницы авторов kemono.cr для понимания структуры поиска
"""

import requests
from bs4 import BeautifulSoup
import json
import os
from pathlib import Path

def analyze_artists_page():
    """Анализ страницы авторов"""

    url = "https://kemono.cr/artists"
    print(f"Анализ страницы: {url}")

    try:
        # Пробуем с Selenium (нужен для динамического контента)
        print("🚀 Запуск Selenium для анализа страницы...")

        # Импортируем Selenium
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.common.by import By
        from selenium.webdriver.support.ui import WebDriverWait
        from selenium.webdriver.support import expected_conditions as EC
        from webdriver_manager.chrome import ChromeDriverManager

        # Настраиваем Chrome
        chrome_options = Options()
        chrome_options.add_argument('--headless')  # Без GUI
        chrome_options.add_argument('--no-sandbox')
        chrome_options.add_argument('--disable-dev-shm-usage')
        chrome_options.add_argument('--disable-gpu')
        chrome_options.add_argument('--window-size=1920,1080')

        print("📱 Создание экземпляра Chrome...")
        try:
            driver = webdriver.Chrome(ChromeDriverManager().install(), options=chrome_options)
        except TypeError:
            # Попытка с другой сигнатурой для совместимости
            driver = webdriver.Chrome(options=chrome_options)

        try:
            print("🌐 Загрузка страницы...")
            driver.get(url)

            # Ждем загрузки основного контента
            print("⏳ Ожидание загрузки контента...")
            WebDriverWait(driver, 30).until(
                lambda driver: driver.execute_script("return document.readyState") == "complete"
            )

            # Ждем появления каких-либо элементов (карточек или форм)
            try:
                WebDriverWait(driver, 10).until(
                    lambda driver: len(driver.find_elements(By.CSS_SELECTOR, "article, form, input")) > 0
                )
                print("✅ Контент загружен!")
            except:
                print("⚠️ Контент не появился в ожидаемое время, продолжаем...")

            # Получаем полный HTML после загрузки JavaScript
            html_content = driver.page_source
            print(f"✅ Получен HTML с Selenium. Длина: {len(html_content)} символов")

            # Сохраняем HTML для анализа
            with open('artists_page_raw_selenium.html', 'w', encoding='utf-8') as f:
                f.write(html_content)
            print("💾 HTML с Selenium сохранен в artists_page_raw_selenium.html")

            # Также сохраняем обычный HTML для сравнения
            print("\n🔄 Для сравнения: обычный HTTP запрос...")
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }
            response = requests.get(url, headers=headers, timeout=30)
            with open('artists_page_raw.html', 'w', encoding='utf-8') as f:
                f.write(response.text)
            print("💾 Обычный HTML сохранен в artists_page_raw.html")

            # Парсим с BeautifulSoup
            soup = BeautifulSoup(html_content, 'lxml')

            # Анализируем структуру
            analyze_page_structure(soup)

        finally:
            driver.quit()
            print("🔌 Chrome закрыт")

    except ImportError as e:
        print(f"❌ Ошибка импорта Selenium: {e}")
        print("💡 Установите selenium: pip install selenium webdriver-manager")
    except Exception as e:
        print(f"❌ Ошибка при анализе с Selenium: {e}")

        # Fallback: обычный HTTP запрос
        print("\n🔄 Попытка с обычным HTTP запросом...")
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }

            response = requests.get(url, headers=headers, timeout=30)

            if response.status_code == 200:
                print(f"✅ Успешный HTTP ответ. Длина HTML: {len(response.text)} символов")

                with open('artists_page_raw.html', 'w', encoding='utf-8') as f:
                    f.write(response.text)
                print("💾 HTML сохранен в artists_page_raw.html")

                soup = BeautifulSoup(response.text, 'lxml')
                analyze_page_structure(soup)

        except Exception as e2:
            print(f"❌ Ошибка и при HTTP запросе: {e2}")

def analyze_page_structure(soup):
    """Анализ структуры страницы"""

    print("\n" + "="*50)
    print("АНАЛИЗ СТРУКТУРЫ СТРАНИЦЫ")
    print("="*50)

    # Ищем заголовок страницы
    title = soup.find('title')
    if title:
        print(f"📄 Заголовок страницы: {title.text.strip()}")

    # Ищем поисковые формы
    forms = soup.find_all('form')
    print(f"\n🔍 Найдено форм: {len(forms)}")

    for i, form in enumerate(forms):
        print(f"\n--- Форма #{i+1} ---")
        print(f"Action: {form.get('action', 'N/A')}")
        print(f"Method: {form.get('method', 'N/A')}")

        # Ищем инпуты в форме
        inputs = form.find_all('input')
        print(f"Инпуты в форме: {len(inputs)}")

        for j, input_elem in enumerate(inputs):
            input_type = input_elem.get('type', 'text')
            input_name = input_elem.get('name', 'N/A')
            input_id = input_elem.get('id', 'N/A')
            input_placeholder = input_elem.get('placeholder', 'N/A')
            input_value = input_elem.get('value', '')

            print(f"  Инпут #{j+1}:")
            print(f"    Тип: {input_type}")
            print(f"    Имя: {input_name}")
            print(f"    ID: {input_id}")
            print(f"    Placeholder: {input_placeholder}")
            print(f"    Значение: {input_value}")

    # Ищем все инпуты на странице (не только в формах)
    all_inputs = soup.find_all('input')
    print(f"\n📝 Все инпуты на странице: {len(all_inputs)}")

    for i, input_elem in enumerate(all_inputs):
        input_type = input_elem.get('type', 'text')
        input_name = input_elem.get('name', 'N/A')
        input_id = input_elem.get('id', 'N/A')
        input_placeholder = input_elem.get('placeholder', 'N/A')
        input_class = input_elem.get('class', [])

        print(f"Инпут #{i+1}: тип={input_type}, имя={input_name}, id={input_id}")
        print(f"  Placeholder: '{input_placeholder}'")
        print(f"  Class: {input_class}")

    # Ищем кнопки
    buttons = soup.find_all(['button', 'input[type="submit"]', 'input[type="button"]'])
    print(f"\n🔘 Найдено кнопок: {len(buttons)}")

    for i, button in enumerate(buttons):
        if button.name == 'button':
            btn_text = button.text.strip()
            btn_type = button.get('type', 'button')
        else:
            btn_text = button.get('value', 'N/A')
            btn_type = button.get('type', 'submit')

        btn_id = button.get('id', 'N/A')
        btn_class = button.get('class', [])

        print(f"Кнопка #{i+1}: '{btn_text}' (тип: {btn_type})")
        print(f"  ID: {btn_id}, Class: {btn_class}")

    # Ищем элементы с классом 'card' (авторы)
    cards = soup.find_all('article', class_='card')
    print(f"\n🎴 Найдено карточек авторов: {len(cards)}")

    if cards:
        print("\n--- Пример структуры карточки ---")
        first_card = cards[0]

        # Ищем ссылку
        link = first_card.find('a', href=True)
        if link:
            print(f"Ссылка: {link['href']}")

        # Ищем заголовок
        title = first_card.find('h2') or first_card.find('header')
        if title:
            print(f"Заголовок: {title.text.strip()}")

        # Ищем другие элементы
        all_text = first_card.get_text(separator=' | ', strip=True)
        print(f"Весь текст карточки: {all_text[:200]}...")

    # Сохраняем анализ в JSON
    analysis = {
        'page_title': title.text.strip() if title else 'N/A',
        'forms_count': len(forms),
        'inputs_count': len(all_inputs),
        'buttons_count': len(buttons),
        'cards_count': len(cards),
        'forms': [
            {
                'action': form.get('action'),
                'method': form.get('method'),
                'inputs': [
                    {
                        'type': inp.get('type'),
                        'name': inp.get('name'),
                        'id': inp.get('id'),
                        'placeholder': inp.get('placeholder'),
                        'value': inp.get('value')
                    } for inp in form.find_all('input')
                ]
            } for form in forms
        ]
    }

    # Сохраняем анализ Selenium
    with open('artists_page_analysis_selenium.json', 'w', encoding='utf-8') as f:
        json.dump(analysis, f, ensure_ascii=False, indent=2)

    # Также сохраняем обычный анализ для сравнения
    with open('artists_page_analysis.json', 'w', encoding='utf-8') as f:
        json.dump(analysis, f, ensure_ascii=False, indent=2)

    print("\n💾 Анализ сохранен в artists_page_analysis.json")
    # Ищем элементы с возможными селекторами для поиска
    print("\n🔍 ПОИСК ЭЛЕМЕНТОВ ПОИСКА:")

    # Разные возможные селекторы для поля поиска
    search_selectors = [
        'input[type="search"]',
        'input[name="q"]',
        'input[name="query"]',
        'input[name="search"]',
        'input[placeholder*="search"]',
        'input[placeholder*="поиск"]',
        'input[id*="search"]',
        'input[class*="search"]'
    ]

    for selector in search_selectors:
        try:
            # Простая проверка селектора через BeautifulSoup
            if 'type="search"' in selector:
                elements = soup.find_all('input', type='search')
            elif 'name="q"' in selector:
                elements = soup.find_all('input', attrs={'name': 'q'})
            elif 'name="query"' in selector:
                elements = soup.find_all('input', attrs={'name': 'query'})
            elif 'name="search"' in selector:
                elements = soup.find_all('input', attrs={'name': 'search'})
            elif 'placeholder' in selector and 'search' in selector:
                elements = soup.find_all('input', placeholder=lambda x: x and 'search' in x.lower())
            elif 'placeholder' in selector and 'поиск' in selector:
                elements = soup.find_all('input', placeholder=lambda x: x and 'поиск' in x.lower())
            elif 'id' in selector and 'search' in selector:
                elements = soup.find_all('input', id=lambda x: x and 'search' in x.lower())
            elif 'class' in selector and 'search' in selector:
                elements = soup.find_all('input', class_=lambda x: x and 'search' in x.lower())
            else:
                elements = []

            if elements:
                print(f"✅ {selector}: найдено {len(elements)} элементов")
                for elem in elements[:2]:  # Показываем первые 2
                    print(f"   - ID: {elem.get('id')}, Name: {elem.get('name')}, Placeholder: {elem.get('placeholder')}")
            else:
                print(f"❌ {selector}: не найдено")

        except Exception as e:
            print(f"❌ {selector}: ошибка - {e}")

def main():
    """Главная функция"""
    print("🚀 Анализ страницы авторов Kemono.cr")
    print("="*50)

    analyze_artists_page()

    print("\n" + "="*50)
    print("✅ Анализ завершен!")
    print("📄 HTML (Selenium) сохранен в: artists_page_raw_selenium.html")
    print("📄 HTML (обычный) сохранен в: artists_page_raw.html")
    print("📊 Анализ (Selenium) сохранен в: artists_page_analysis_selenium.json")
    print("📊 Анализ (обычный) сохранен в: artists_page_analysis.json")
    print("="*50)

if __name__ == "__main__":
    main()
