#!/usr/bin/env python3
"""
Анализ страниц авторов для определения правильных селекторов
"""

from kemono_parser import KemonoParser
from bs4 import BeautifulSoup

def analyze_page(url, page_name):
    """Анализ конкретной страницы авторов"""

    print(f"\n🔍 АНАЛИЗ СТРАНИЦЫ: {page_name}")
    print("="*60)
    print(f"URL: {url}")

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        html = parser._selenium_get(url)
        if not html:
            print("❌ Не удалось получить HTML")
            return

        soup = BeautifulSoup(html, 'lxml')
        print(f"📄 Получено HTML: {len(html)} символов")

        # Проверяем разные селекторы для карточек авторов
        selectors = [
            ('article', 'card'),
            ('div', 'card'),
            ('article', 'user-card'),
            ('div', 'user-card'),
            ('a', 'user-card'),
            ('article', None),
            ('div', None)
        ]

        print("\n🎴 ПОИСК КАРТОЧЕК АВТОРОВ:")
        for tag, class_name in selectors:
            if class_name:
                elements = soup.find_all(tag, class_=class_name)
            else:
                elements = soup.find_all(tag)[:10]  # Ограничиваем для анализа

            print(f"  {tag}.{'card' if class_name else ''}: {len(elements)} элементов")

            if elements and len(elements) <= 5:  # Показываем детали для небольшого числа
                for i, elem in enumerate(elements):
                    link = elem.find('a', href=True)
                    if link:
                        href = link.get('href', '')
                        title = elem.find('h2') or elem.find('header')
                        title_text = title.text.strip() if title else "Без названия"
                        print(f"    {i+1}. {title_text} - {href}")

        # Ищем любые ссылки на пользователей
        print("\n🔗 ПОИСК ССЫЛОК НА ПОЛЬЗОВАТЕЛЕЙ:")
        user_links = soup.find_all('a', href=lambda x: x and '/user/' in x)
        print(f"Найдено ссылок на пользователей: {len(user_links)}")

        for i, link in enumerate(user_links[:5]):
            href = link.get('href', '')
            text = link.text.strip()
            print(f"  {i+1}. {text} - {href}")

        # Сохраняем HTML для ручного анализа
        filename = f"artists_page_{page_name.replace('/', '_')}.html"
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(html)
        print(f"\n💾 HTML сохранен в: {filename}")

    except Exception as e:
        print(f"❌ Ошибка анализа: {e}")

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    pages = [
        ("https://kemono.cr/artists", "main"),
        ("https://kemono.cr/artists/updated", "updated"),
        ("https://kemono.cr/artists/random", "random")
    ]

    for url, name in pages:
        analyze_page(url, name)

