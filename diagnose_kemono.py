#!/usr/bin/env python3
"""
Диагностика проблем с парсингом kemono.cr
"""

import requests
from bs4 import BeautifulSoup
from fake_useragent import UserAgent
import json
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
import time


def setup_selenium_driver():
    """Настройка Selenium WebDriver"""
    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-blink-features=AutomationControlled')
    options.add_experimental_option("excludeSwitches", ["enable-automation"])
    options.add_experimental_option('useAutomationExtension', False)

    driver = webdriver.Chrome(options=options)
    driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
    return driver


def diagnose_artist_page(url: str, use_selenium: bool = True):
    """Диагностика страницы автора"""
    print(f"🔍 Диагностика страницы: {url}")

    if use_selenium:
        print("🌐 Используем Selenium для загрузки страницы с JavaScript...")
        driver = setup_selenium_driver()

        try:
            driver.get(url)
            print("⏳ Ждем загрузки страницы...")
            WebDriverWait(driver, 15).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )

            # Ждем дополнительно для загрузки динамического контента
            time.sleep(5)

            html = driver.page_source
            print(f"✅ Страница загружена. Длина: {len(html)} байт")

            soup = BeautifulSoup(html, 'lxml')
            driver.quit()

        except Exception as e:
            print(f"❌ Ошибка Selenium: {e}")
            driver.quit()
            return
    else:
        # Настраиваем сессию
        session = requests.Session()
        ua = UserAgent()
        session.headers.update({
            'User-Agent': ua.random,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1',
        })

        try:
            print("📡 Отправка HTTP запроса...")
            response = session.get(url, timeout=30)
            response.raise_for_status()

            print(f"✅ Ответ получен. Статус: {response.status_code}")
            print(f"📏 Длина контента: {len(response.content)} байт")

            soup = BeautifulSoup(response.content, 'lxml')

        except Exception as e:
            print(f"❌ Ошибка HTTP запроса: {e}")
            return

        # Проверяем основные элементы
        print("\n🔎 Поиск элементов на странице:")

        # Ищем заголовок страницы
        title = soup.find('title')
        print(f"📄 Title: {title.text.strip() if title else 'Не найден'}")

        # Ищем все article элементы
        articles = soup.find_all('article')
        print(f"📝 Всего article элементов: {len(articles)}")

        # Ищем элементы с классом post-card
        post_cards = soup.find_all('article', class_='post-card')
        print(f"🎴 Элементов с классом 'post-card': {len(post_cards)}")

        # Ищем другие возможные селекторы для постов
        possible_selectors = [
            ('div', 'post-card'),
            ('div', 'card'),
            ('article', 'card'),
            ('div', 'post'),
            ('article', 'post'),
            ('div', 'content'),
        ]

        print("\n🎯 Поиск постов с разными селекторами:")
        for tag, class_name in possible_selectors:
            elements = soup.find_all(tag, class_=class_name)
            if elements:
                print(f"  {tag}.{class_name}: {len(elements)} элементов")

        # Ищем ссылки на посты
        post_links = soup.find_all('a', href=lambda x: x and '/post/' in x)
        print(f"\n🔗 Ссылок на посты (/post/): {len(post_links)}")

        # Показываем первые несколько ссылок
        if post_links:
            print("  Примеры ссылок:")
            for i, link in enumerate(post_links[:3]):
                print(f"    {i+1}. {link['href']}")

        # Ищем div с постами
        post_containers = soup.find_all('div', class_=lambda x: x and ('post' in x.lower() or 'card' in x.lower()))
        print(f"\n📦 Контейнеров с постами: {len(post_containers)}")

        # Проверяем, есть ли вообще контент
        body = soup.find('body')
        if body:
            print(f"\n📊 Содержимое body: {len(body.text)} символов")
            # Показываем первые 500 символов
            print(f"📝 Первые 500 символов:\n{body.text[:500]}...")

        # Ищем возможные альтернативные селекторы
        print("\n🔍 Поиск альтернативных селекторы:")

        # Ищем все элементы с data- атрибутами
        data_elements = soup.find_all(attrs={'data-post-id': True})
        print(f"  Элементов с data-post-id: {len(data_elements)}")

        # Ищем элементы с id
        id_elements = soup.find_all(attrs={'id': lambda x: x and ('post' in x.lower() or 'card' in x.lower())})
        print(f"  Элементов с ID содержащим 'post' или 'card': {len(id_elements)}")

        # Сохраняем HTML для анализа
        with open('debug_page.html', 'w', encoding='utf-8') as f:
            f.write(str(soup))
        print("\n💾 HTML сохранен в debug_page.html для анализа")

        # Проверяем, не является ли страница пустой или с ошибкой
        if "error" in soup.text.lower() or "not found" in soup.text.lower():
            print("⚠️  Обнаружен текст ошибки на странице!")
        elif len(soup.text.strip()) < 100:
            print("⚠️  Страница содержит очень мало текста - возможно проблема с загрузкой")
        else:
            print("✅ Страница выглядит нормально")


def main():
    """Главная функция"""
    print("🔧 Kemono.cr Диагностика")
    print("=" * 50)

    # URL для тестирования
    test_url = "https://kemono.cr/fanbox/user/3065392"

    print(f"Тестируемый URL: {test_url}")
    print()

    print("Сначала тест без Selenium...")
    diagnose_artist_page(test_url, use_selenium=False)

    print("\n" + "="*60)
    print("Теперь тест с Selenium...")
    diagnose_artist_page(test_url, use_selenium=True)


if __name__ == "__main__":
    main()
