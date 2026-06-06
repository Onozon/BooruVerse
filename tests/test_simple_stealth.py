#!/usr/bin/env python3
"""
Простой и надежный Selenium скрипт для обхода защиты Kemono.cr
"""

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
from selenium.common.exceptions import TimeoutException, NoSuchElementException
from bs4 import BeautifulSoup
import time
import random

def create_simple_stealth_driver():
    """Создание простого, но эффективного драйвера"""

    chrome_options = Options()

    # Основные настройки
    chrome_options.add_argument('--headless')
    chrome_options.add_argument('--no-sandbox')
    chrome_options.add_argument('--disable-dev-shm-usage')
    chrome_options.add_argument('--disable-gpu')
    chrome_options.add_argument('--window-size=1366,768')  # Более реалистичный размер

    # Маскировка под реальный браузер
    chrome_options.add_argument('--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
    chrome_options.add_argument('--disable-blink-features=AutomationControlled')
    chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
    chrome_options.add_experimental_option('useAutomationExtension', False)

    # Минимальные дополнительные настройки
    chrome_options.add_argument('--disable-web-security')
    chrome_options.add_argument('--disable-extensions')
    chrome_options.add_argument('--no-first-run')
    chrome_options.add_argument('--disable-default-apps')

    return webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=chrome_options)

def simple_search_artists(driver, query, max_attempts=3):
    """Простой и надежный поиск авторов"""

    for attempt in range(max_attempts):
        try:
            print(f"\n🔄 Попытка {attempt + 1}/{max_attempts}")

            # Шаг 1: Прямой переход на страницу авторов
            print("🌐 Переходим на страницу авторов...")
            driver.get("https://kemono.cr/artists")

            # Ждем загрузки страницы
            time.sleep(random.uniform(3, 5))

            # Проверяем текущий URL
            current_url = driver.current_url
            if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                print("⚠️ Перенаправлены на внешнюю страницу, ждем...")
                time.sleep(5)
                current_url = driver.current_url

                if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                    print("❌ Все еще на внешней странице, пропускаем попытку")
                    continue

            print(f"📍 Текущий URL: {current_url}")

            # Шаг 2: Ищем поле поиска
            print("🔍 Ищем поле поиска...")
            try:
                search_input = WebDriverWait(driver, 10).until(
                    EC.presence_of_element_located((By.ID, "q"))
                )
                print("✅ Поле поиска найдено!")
            except TimeoutException:
                print("❌ Поле поиска не найдено")

                # Сохраняем HTML для анализа
                html = driver.page_source
                with open(f'no_search_field_{attempt}.html', 'w', encoding='utf-8') as f:
                    f.write(html)
                continue

            # Шаг 3: Вводим поисковый запрос
            print(f"✍️ Вводим запрос: {query}")
            search_input.clear()

            # Имитируем медленный ввод
            for char in query:
                search_input.send_keys(char)
                time.sleep(random.uniform(0.1, 0.2))

            time.sleep(1)

            # Шаг 4: Ищем и нажимаем кнопку поиска
            print("🔘 Ищем кнопку поиска...")
            try:
                search_button = driver.find_element(By.CSS_SELECTOR, "button.search-button")
                print("✅ Кнопка найдена по классу")
            except NoSuchElementException:
                try:
                    search_button = driver.find_element(By.CSS_SELECTOR, "button[type='submit']")
                    print("✅ Кнопка найдена по типу")
                except NoSuchElementException:
                    print("❌ Кнопка поиска не найдена")
                    continue

            # Нажимаем кнопку
            search_button.click()
            print("🔘 Кнопка нажата")

            # Ждем результат
            time.sleep(random.uniform(2, 4))

            # Шаг 5: Проверяем результат
            final_url = driver.current_url
            print(f"📍 URL после поиска: {final_url}")

            if 'nachdiewelt.click' in final_url or 'quantum' in final_url.lower():
                print("⚠️ Перенаправлены после поиска")
                continue

            # Шаг 6: Анализируем результаты
            html = driver.page_source
            soup = BeautifulSoup(html, 'lxml')

            cards = soup.find_all('article', class_='card')
            print(f"🎴 Найдено карточек: {len(cards)}")

            if cards:
                print("✅ Найдены результаты поиска!")

                # Сохраняем успешный результат
                with open('simple_search_success.html', 'w', encoding='utf-8') as f:
                    f.write(html)

                # Показываем результаты
                for i, card in enumerate(cards[:5]):
                    link = card.find('a', href=True)
                    title = card.find('h2') or card.find('header')
                    if link and title:
                        print(f"  {i+1}. {title.text.strip()}")
                        print(f"      {link['href']}")

                return True

            else:
                print("❌ Результаты не найдены")

                # Сохраняем HTML для анализа
                with open(f'no_results_{attempt}.html', 'w', encoding='utf-8') as f:
                    f.write(html)

                # Проверяем title страницы
                title = soup.find('title')
                if title:
                    print(f"📄 Заголовок: {title.text.strip()}")

        except Exception as e:
            print(f"❌ Ошибка в попытке {attempt + 1}: {e}")

        # Задержка между попытками
        if attempt < max_attempts - 1:
            delay = random.uniform(3, 6)
            print(f"⏳ Ждем {delay:.1f} секунд...")
            time.sleep(delay)

    return False

def test_different_user_agents():
    """Тестируем разные User-Agent"""

    user_agents = [
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    ]

    for i, ua in enumerate(user_agents):
        print(f"\n🧪 Тестируем User-Agent {i+1}")

        chrome_options = Options()
        chrome_options.add_argument('--headless')
        chrome_options.add_argument('--no-sandbox')
        chrome_options.add_argument(f'--user-agent={ua}')
        chrome_options.add_argument('--disable-blink-features=AutomationControlled')
        chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])

        driver = webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=chrome_options)

        try:
            driver.get("https://kemono.cr/artists")
            time.sleep(3)

            html = driver.page_source
            soup = BeautifulSoup(html, 'lxml')

            title = soup.find('title')
            if title:
                print(f"📄 Заголовок: {title.text.strip()}")

            search_input = soup.find('input', {'id': 'q'})
            if search_input:
                print("✅ Форма поиска найдена")
            else:
                print("❌ Форма поиска не найдена")

        except Exception as e:
            print(f"❌ Ошибка: {e}")

        finally:
            driver.quit()

def main():
    """Основная функция"""

    print("🚀 Тестируем простой и надежный Selenium подход")
    print("="*60)

    # Сначала тестируем разные User-Agent
    print("\n1️⃣ Тестируем разные User-Agent...")
    test_different_user_agents()

    # Затем тестируем поиск
    print("\n2️⃣ Тестируем поиск авторов...")

    driver = None
    try:
        driver = create_simple_stealth_driver()

        # Отключаем webdriver property
        driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

        # Тестируем поиск
        query = "abmayo"
        success = simple_search_artists(driver, query, max_attempts=2)

        if success:
            print("\n✅ Поиск прошел успешно!")
        else:
            print("\n❌ Поиск не удался")

    except Exception as e:
        print(f"❌ Критическая ошибка: {e}")

    finally:
        if driver:
            driver.quit()
            print("🔌 Браузер закрыт")

if __name__ == "__main__":
    main()

