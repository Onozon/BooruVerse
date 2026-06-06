#!/usr/bin/env python3
"""
Улучшенный Selenium скрипт для обхода защиты Kemono.cr
"""

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
from selenium.common.exceptions import TimeoutException, WebDriverException
from bs4 import BeautifulSoup
import time
import random
import json

def create_stealth_driver():
    """Создание максимально незаметного драйвера Chrome"""

    chrome_options = Options()

    # Основные настройки для скрытности
    chrome_options.add_argument('--headless')
    chrome_options.add_argument('--no-sandbox')
    chrome_options.add_argument('--disable-dev-shm-usage')
    chrome_options.add_argument('--disable-gpu')
    chrome_options.add_argument('--window-size=1920,1080')

    # Маскировка под реальный браузер
    chrome_options.add_argument('--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

    # Отключение автоматизации
    chrome_options.add_argument('--disable-blink-features=AutomationControlled')
    chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
    chrome_options.add_experimental_option('useAutomationExtension', False)

    # Дополнительные настройки для реалистичности
    chrome_options.add_argument('--disable-web-security')
    chrome_options.add_argument('--allow-running-insecure-content')
    chrome_options.add_argument('--disable-extensions')
    chrome_options.add_argument('--disable-plugins')
    chrome_options.add_argument('--disable-images')  # Для скорости
    chrome_options.add_argument('--disable-plugins-discovery')

    # Язык и локаль
    chrome_options.add_argument('--lang=en-US')
    chrome_options.add_argument('--accept-lang=en-US')

    # Отключение логов
    chrome_options.add_argument('--log-level=3')
    chrome_options.add_argument('--silent')

    return webdriver.Chrome(service=Service(ChromeDriverManager().install()), options=chrome_options)

def human_like_delay(min_delay=1, max_delay=3):
    """Имитация человеческой задержки"""
    delay = random.uniform(min_delay, max_delay)
    time.sleep(delay)

def simulate_human_behavior(driver):
    """Имитация человеческого поведения на странице"""

    # Случайные движения мыши
    actions = ActionChains(driver)

    # Имитируем чтение страницы
    for _ in range(random.randint(2, 5)):
        x = random.randint(100, 800)
        y = random.randint(100, 600)
        actions.move_by_offset(x, y)
        actions.perform()
        human_like_delay(0.5, 1.5)

    # Скроллинг страницы
    driver.execute_script("window.scrollTo(0, document.body.scrollHeight / 4);")
    human_like_delay(1, 2)

    driver.execute_script("window.scrollTo(0, document.body.scrollHeight / 2);")
    human_like_delay(1, 2)

    driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
    human_like_delay(1, 2)

def wait_for_page_load(driver, timeout=30):
    """Ожидание полной загрузки страницы"""

    try:
        # Ждем пока документ будет готов
        WebDriverWait(driver, timeout).until(
            lambda driver: driver.execute_script("return document.readyState") == "complete"
        )

        # Ждем появления основного контента
        WebDriverWait(driver, timeout).until(
            lambda driver: driver.find_elements(By.CSS_SELECTOR, "div, article, form")
        )

        return True

    except TimeoutException:
        print("⚠️ Страница не загрузилась полностью")
        return False

def advanced_search_artists(driver, query, max_attempts=3):
    """Улучшенный поиск авторов с обработкой блокировок"""

    for attempt in range(max_attempts):
        try:
            print(f"🔄 Попытка {attempt + 1}/{max_attempts}")

            # Шаг 1: Открываем главную страницу
            print("🌐 Открываем главную страницу...")
            driver.get("https://kemono.cr")
            human_like_delay(2, 4)

            # Шаг 2: Имитируем человеческое поведение
            simulate_human_behavior(driver)

            # Шаг 3: Переходим на страницу авторов
            print("📄 Переходим на страницу авторов...")
            driver.get("https://kemono.cr/artists")
            human_like_delay(3, 6)

            # Шаг 4: Проверяем, не перенаправлены ли мы
            current_url = driver.current_url
            if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                print("⚠️ Перенаправлены на внешнюю страницу, пробуем обойти...")

                # Возвращаемся и пробуем снова
                driver.get("https://kemono.cr/artists")
                human_like_delay(5, 8)
                current_url = driver.current_url

            if 'nachdiewelt.click' in current_url or 'quantum' in current_url.lower():
                print("❌ Не удалось обойти перенаправление")
                continue

            # Шаг 5: Ждем загрузки формы поиска
            print("🔍 Ждем загрузки формы поиска...")
            try:
                search_input = WebDriverWait(driver, 15).until(
                    EC.presence_of_element_located((By.ID, "q"))
                )
                print("✅ Форма поиска найдена!")
            except TimeoutException:
                print("❌ Форма поиска не загрузилась")

                # Сохраняем HTML для анализа
                html = driver.page_source
                with open(f'search_attempt_{attempt}_failed.html', 'w', encoding='utf-8') as f:
                    f.write(html)
                continue

            # Шаг 6: Имитируем поиск
            print(f"✍️ Вводим запрос: {query}")

            # Очищаем поле
            search_input.clear()
            human_like_delay(0.5, 1)

            # Вводим текст посимвольно
            for char in query:
                search_input.send_keys(char)
                time.sleep(random.uniform(0.1, 0.3))

            human_like_delay(1, 2)

            # Шаг 7: Нажимаем кнопку поиска
            print("🔘 Нажимаем кнопку поиска...")
            try:
                search_button = driver.find_element(By.CSS_SELECTOR, "button.search-button")
                search_button.click()
            except:
                # Альтернативный селектор
                search_button = driver.find_element(By.CSS_SELECTOR, "button[type='submit']")
                search_button.click()

            human_like_delay(2, 4)

            # Шаг 8: Проверяем результат
            final_url = driver.current_url
            print(f"📍 Финальный URL: {final_url}")

            if 'nachdiewelt.click' in final_url or 'quantum' in final_url.lower():
                print("⚠️ Перенаправлены после поиска")
                continue

            # Шаг 9: Ждем и анализируем результаты
            human_like_delay(3, 5)

            html = driver.page_source
            soup = BeautifulSoup(html, 'lxml')

            # Проверяем результаты
            cards = soup.find_all('article', class_='card')
            print(f"🎴 Найдено карточек: {len(cards)}")

            if cards:
                print("✅ Найдены результаты поиска!")

                # Сохраняем успешный результат
                with open('search_success.html', 'w', encoding='utf-8') as f:
                    f.write(html)

                # Показываем первые результаты
                for i, card in enumerate(cards[:3]):
                    link = card.find('a', href=True)
                    title = card.find('h2') or card.find('header')
                    if link and title:
                        print(f"  {i+1}. {title.text.strip()} - {link['href']}")

                return True

            else:
                print("❌ Результаты не найдены")

                # Сохраняем HTML для анализа
                with open(f'search_attempt_{attempt}_no_results.html', 'w', encoding='utf-8') as f:
                    f.write(html)

        except Exception as e:
            print(f"❌ Ошибка в попытке {attempt + 1}: {e}")

            # Сохраняем HTML при ошибке
            try:
                html = driver.page_source
                with open(f'search_attempt_{attempt}_error.html', 'w', encoding='utf-8') as f:
                    f.write(html)
            except:
                pass

        # Задержка между попытками
        if attempt < max_attempts - 1:
            delay = random.uniform(5, 10)
            print(f"⏳ Ждем {delay:.1f} секунд перед следующей попыткой...")
            time.sleep(delay)

    return False

def main():
    """Основная функция тестирования"""

    print("🚀 Запуск улучшенного Selenium поиска Kemono.cr")
    print("="*60)

    driver = None
    try:
        # Создаем драйвер
        driver = create_stealth_driver()

        # Отключаем webdriver property
        driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

        # Добавляем дополнительные свойства для маскировки
        driver.execute_script("""
            // Переопределяем свойства navigator
            Object.defineProperty(navigator, 'plugins', {
                get: function() { return [1, 2, 3, 4, 5]; }
            });

            Object.defineProperty(navigator, 'languages', {
                get: function() { return ['en-US', 'en']; }
            });
        """)

        # Тестируем поиск
        query = "abmayo"
        success = advanced_search_artists(driver, query)

        if success:
            print("\n✅ Поиск прошел успешно!")
        else:
            print("\n❌ Не удалось выполнить поиск")

    except Exception as e:
        print(f"❌ Критическая ошибка: {e}")

    finally:
        if driver:
            driver.quit()
            print("🔌 Браузер закрыт")

if __name__ == "__main__":
    main()
