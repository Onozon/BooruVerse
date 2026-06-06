#!/usr/bin/env python3
"""
Простой тест поиска авторов через HTTP
"""

from kemono_parser import KemonoParser

def test_simple_search():
    """Простой тест поиска"""
    print("🧪 Тестируем простой HTTP поиск авторов")

    # Создаем парсер без Selenium для чистого HTTP поиска
    parser = KemonoParser(use_selenium=False)

    try:
        query = "abmayo"
        print(f"🔍 Ищем: {query}")

        # Используем новый метод HTTP поиска
        artists = parser.search_artists_http(query, limit=10)

        print(f"✅ Найдено {len(artists)} авторов:")

        for i, artist in enumerate(artists, 1):
            print(f"{i}. {artist.name} ({artist.service}) - ID: {artist.id}")
            print(f"   URL: {artist.url}")

        if not artists:
            print("❌ Авторы не найдены")

            # Проверим, что записалось в лог файл
            try:
                with open('search_results_http.html', 'r', encoding='utf-8') as f:
                    content = f.read()
                    print(f"📄 HTML ответ имеет длину: {len(content)} символов")

                    # Проверим title страницы
                    from bs4 import BeautifulSoup
                    soup = BeautifulSoup(content, 'lxml')
                    title = soup.find('title')
                    if title:
                        print(f"📋 Заголовок страницы: {title.text.strip()}")

            except FileNotFoundError:
                print("❌ Файл search_results_http.html не найден")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    test_simple_search()

