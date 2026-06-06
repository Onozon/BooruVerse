#!/usr/bin/env python3
"""
Простой тест поиска для диагностики
"""

from kemono_parser import KemonoParser

def simple_search_test():
    """Простой тест поиска"""

    parser = KemonoParser(use_selenium=True, headless=False)

    try:
        if not parser.driver:
            print("❌ Драйвер не инициализирован")
            return

        print("🌐 Переходим на страницу поиска...")
        parser.driver.get("https://kemono.cr/artists")

        import time
        time.sleep(3)

        print("🔍 Ищем поле поиска...")
        from selenium.webdriver.common.by import By
        search_input = parser.driver.find_element(By.ID, "q")
        print("✅ Поле найдено")

        print("✍️ Вводим запрос...")
        search_input.clear()
        search_input.send_keys("abmayo")
        time.sleep(1)

        print("🔘 Ищем кнопку...")
        search_button = parser.driver.find_element(By.CSS_SELECTOR, "button.search-button")
        print("✅ Кнопка найдена")

        print("🔘 Нажимаем...")
        search_button.click()

        print("⏳ Ждём 10 секунд...")
        time.sleep(10)

        print("📄 Получаем HTML...")
        html = parser.driver.page_source
        print(f"📏 Длина HTML: {len(html)}")

        # Ищем любые ссылки
        links = parser.driver.find_elements(By.TAG_NAME, "a")
        print(f"🔗 Всего ссылок: {len(links)}")

        # Ищем ссылки с fanbox
        fanbox_links = [link for link in links if 'fanbox' in link.get_attribute('href') or 'fanbox' in link.text.lower()]
        print(f"🎨 Fanbox ссылок: {len(fanbox_links)}")

        for i, link in enumerate(fanbox_links[:5]):
            href = link.get_attribute('href')
            text = link.text.strip()
            print(f"  {i+1}. {text} -> {href}")

        # Сохраняем HTML для анализа
        with open('simple_search_test.html', 'w', encoding='utf-8') as f:
            f.write(html)
        print("💾 HTML сохранён")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    simple_search_test()

