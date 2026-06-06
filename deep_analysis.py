#!/usr/bin/env python3
"""
Глубокий анализ структуры страницы kemono.cr для поиска постов
"""

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
import time
import json


def deep_analyze_page():
    """Глубокий анализ страницы автора"""
    print("🔬 Глубокий анализ страницы kemono.cr...")

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    driver = webdriver.Chrome(options=options)

    try:
        url = "https://kemono.cr/fanbox/user/3065392"
        driver.get(url)
        print("⏳ Загружаем страницу...")
        time.sleep(10)  # Ждем дольше для полной загрузки

        print("📊 Анализ структуры страницы...")

        # Получаем все элементы с классами, содержащими 'post' или 'card'
        post_related_elements = driver.find_elements(By.XPATH, "//*[contains(@class, 'post') or contains(@class, 'card')]")

        print(f"🎯 Найдено элементов с 'post' или 'card' в классе: {len(post_related_elements)}")

        # Анализируем каждый элемент
        elements_data = []
        for i, elem in enumerate(post_related_elements[:20]):  # Анализируем первые 20
            try:
                tag_name = elem.tag_name
                class_attr = elem.get_attribute('class')
                id_attr = elem.get_attribute('id')
                text_content = elem.text[:100] if elem.text else ""

                # Ищем ссылки внутри элемента
                links = elem.find_elements(By.TAG_NAME, 'a')
                link_hrefs = [link.get_attribute('href') for link in links if link.get_attribute('href')]

                element_info = {
                    'index': i,
                    'tag': tag_name,
                    'class': class_attr,
                    'id': id_attr,
                    'text_preview': text_content,
                    'links': link_hrefs
                }
                elements_data.append(element_info)

                print(f"\n📄 Элемент {i}:")
                print(f"   Тег: {tag_name}")
                print(f"   Класс: {class_attr}")
                print(f"   ID: {id_attr}")
                print(f"   Текст: {text_content}...")
                if link_hrefs:
                    print(f"   Ссылки: {link_hrefs[:3]}")

            except Exception as e:
                print(f"❌ Ошибка анализа элемента {i}: {e}")

        # Ищем все ссылки на посты
        post_links = driver.find_elements(By.XPATH, "//a[contains(@href, '/post/')]")
        print(f"\n🔗 Всего ссылок на посты: {len(post_links)}")

        for i, link in enumerate(post_links[:10]):
            href = link.get_attribute('href')
            text = link.text
            print(f"   {i+1}. {href} - '{text}'")

        # Ищем элементы с data-атрибутами
        data_elements = driver.find_elements(By.XPATH, "//*[@data-post-id or @data-id]")
        print(f"\n📋 Элементов с data-post-id или data-id: {len(data_elements)}")

        for i, elem in enumerate(data_elements[:5]):
            data_post_id = elem.get_attribute('data-post-id')
            data_id = elem.get_attribute('data-id')
            class_attr = elem.get_attribute('class')
            print(f"   {i+1}. data-post-id: {data_post_id}, data-id: {data_id}, class: {class_attr}")

        # Проверяем наличие определенных селекторов
        selectors_to_check = [
            'article.post-card',
            'div.post-card',
            'article.card',
            'div.card',
            '.post',
            '.card',
            '[data-testid]',
            '[role="article"]'
        ]

        print("\n🔍 Проверка селекторов:")
        for selector in selectors_to_check:
            try:
                elements = driver.find_elements(By.CSS_SELECTOR, selector)
                print(f"   {selector}: {len(elements)} элементов")
            except Exception as e:
                print(f"   {selector}: ошибка - {e}")

        # Сохраняем результаты анализа
        analysis_result = {
            'url': url,
            'total_post_related_elements': len(post_related_elements),
            'total_post_links': len(post_links),
            'total_data_elements': len(data_elements),
            'elements_data': elements_data[:10],  # Сохраняем только первые 10
            'selectors_check': {}
        }

        for selector in selectors_to_check:
            try:
                elements = driver.find_elements(By.CSS_SELECTOR, selector)
                analysis_result['selectors_check'][selector] = len(elements)
            except:
                analysis_result['selectors_check'][selector] = 0

        with open('deep_analysis_result.json', 'w', encoding='utf-8') as f:
            json.dump(analysis_result, f, ensure_ascii=False, indent=2)

        print("\n💾 Результаты анализа сохранены в deep_analysis_result.json")
        # Сохраняем HTML для ручного анализа
        html = driver.page_source
        with open('full_page_analysis.html', 'w', encoding='utf-8') as f:
            f.write(html)
        print("📄 Полный HTML сохранен в full_page_analysis.html")
        print("\n🎯 Рекомендации:")
        print("1. Откройте full_page_analysis.html в браузере")
        print("2. Найдите элементы, содержащие информацию о постах")
        print("3. Обратите внимание на data-атрибуты и специфические классы")

    except Exception as e:
        print(f"❌ Ошибка глубокого анализа: {e}")
        import traceback
        traceback.print_exc()
    finally:
        driver.quit()


if __name__ == "__main__":
    deep_analyze_page()
