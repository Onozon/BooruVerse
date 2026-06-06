#!/usr/bin/env python3
"""
Тест с более реалистичным поведением Selenium
"""

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
from bs4 import BeautifulSoup
import time
import random

def create_realistic_driver():
    """Создание более реалистичного драйвера Chrome"""
    chrome_options = Options()

    # Включаем headless для работы в среде без GUI
    chrome_options.add_argument('--headless')

    # Настройки для большей реалистичности
    chrome_options.add_argument('--no-sandbox')
    chrome_options.add_argument('--disable-dev-shm-usage')
    chrome_options.add_argument('--disable-gpu')
    chrome_options.add_argument('--window-size=1366,768')

    # Имитация реального браузера
    chrome_options.add_argument('--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
    chrome_options.add_argument('--disable-blink-features=AutomationControlled')
    chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
    chrome_options.add_experimental_option('useAutomationExtension', False)

    # Отключаем некоторые защиты
    chrome_options.add_argument('--disable-web-security')
    chrome_options.add_argument('--allow-running-insecure-content')

    return webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=chrome_options)

def test_realistic_search():
    """Тест поиска с реалистичным поведением"""

    print("🚀 Тестируем реалистичный поиск в браузере")

    driver = None
    try:
        driver = create_realistic_driver()

        # Отключаем webdriver property для большей скрытности
        driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

        print("🌐 Открываем главную страницу...")
        driver.get("https://kemono.cr")
        time.sleep(random.uniform(2, 4))  # Имитация чтения страницы

        print("📄 Переходим на страницу авторов...")
        driver.get("https://kemono.cr/artists")
        time.sleep(random.uniform(3, 6))  # Ожидание загрузки

        # Имитируем скроллинг страницы
        print("📜 Имитируем скроллинг...")
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight / 4);")
        time.sleep(random.uniform(1, 2))

        driver.execute_script("window.scrollTo(0, document.body.scrollHeight / 2);")
        time.sleep(random.uniform(1, 2))

        # Проверяем, загрузилась ли страница
        print("🔍 Проверяем наличие формы поиска...")
        try:
            search_input = WebDriverWait(driver, 10).until(
                EC.presence_of_element_located((By.ID, "q"))
            )
            print("✅ Форма поиска найдена!")

            # Имитируем медленный ввод текста
            print("✍️ Вводим поисковый запрос...")
            query = "abmayo"

            for char in query:
                search_input.send_keys(char)
                time.sleep(random.uniform(0.1, 0.3))

            time.sleep(1)  # Пауза перед нажатием

            # Находим и нажимаем кнопку поиска
            print("🔘 Нажимаем кнопку поиска...")
            search_button = driver.find_element(By.CSS_SELECTOR, "button.search-button")
            search_button.click()

            # Ждем результатов
            print("⏳ Ждем результатов поиска...")
            time.sleep(5)

            # Проверяем URL
            current_url = driver.current_url
            print(f"📍 Текущий URL: {current_url}")

            if "nachdiewelt.click" in current_url:
                print("⚠️ Перенаправлено на внешнюю страницу!")

                # Попробуем вернуться назад
                print("🔙 Возвращаемся на kemono.cr...")
                driver.get("https://kemono.cr/artists")
                time.sleep(3)

                # Повторяем поиск
                print("🔄 Повторяем поиск...")
                search_input = driver.find_element(By.ID, "q")
                search_input.clear()
                search_input.send_keys(query)

                search_button = driver.find_element(By.CSS_SELECTOR, "button.search-button")
                search_button.click()

                time.sleep(5)
                print(f"📍 URL после повторного поиска: {driver.current_url}")

            # Получаем результаты
            html = driver.page_source
            soup = BeautifulSoup(html, 'lxml')

            cards = soup.find_all('article', class_='card')
            print(f"🎴 Найдено карточек: {len(cards)}")

            if cards:
                print("✅ Найдены результаты!")
                for i, card in enumerate(cards[:3]):
                    link = card.find('a', href=True)
                    title = card.find('h2') or card.find('header')
                    if link and title:
                        print(f"  {i+1}. {title.text.strip()} - {link['href']}")
            else:
                print("❌ Результаты не найдены")

                # Сохраняем HTML для анализа
                with open('realistic_search_debug.html', 'w', encoding='utf-8') as f:
                    f.write(html)
                print("💾 HTML сохранен в realistic_search_debug.html")

        except Exception as e:
            print(f"❌ Ошибка при поиске: {e}")

            # Сохраняем HTML для анализа даже при ошибке
            try:
                html = driver.page_source
                with open('search_error_debug.html', 'w', encoding='utf-8') as f:
                    f.write(html)
                print("💾 HTML ошибки сохранен в search_error_debug.html")
            except:
                pass

    except Exception as e:
        print(f"❌ Ошибка: {e}")

    finally:
        if driver:
            driver.quit()
            print("🔌 Браузер закрыт")

def test_with_cookies():
    """Тест с использованием cookies для обхода защиты"""

    print("\n" + "="*60)
    print("🍪 Тест с имитацией cookies и сессии")

    driver = None
    try:
        driver = create_realistic_driver()

        # Устанавливаем cookies перед загрузкой страницы
        driver.get("https://kemono.cr")

        # Добавляем типичные cookies
        driver.add_cookie({
            'name': 'session',
            'value': 'dummy_session_value',
            'domain': 'kemono.cr'
        })

        driver.add_cookie({
            'name': 'user_agent',
            'value': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
            'domain': 'kemono.cr'
        })

        print("🌐 Открываем страницу авторов с cookies...")
        driver.get("https://kemono.cr/artists")
        time.sleep(5)

        # Проверяем наличие контента
        html = driver.page_source
        soup = BeautifulSoup(html, 'lxml')

        title = soup.find('title')
        if title:
            print(f"📄 Заголовок: {title.text.strip()}")

        cards = soup.find_all('article', class_='card')
        print(f"🎴 Найдено карточек: {len(cards)}")

        # Проверяем наличие формы поиска
        search_form = soup.find('form', id='search-form')
        if search_form:
            print("✅ Форма поиска найдена!")
        else:
            print("❌ Форма поиска не найдена")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

    finally:
        if driver:
            driver.quit()

if __name__ == "__main__":
    test_realistic_search()
    test_with_cookies()
