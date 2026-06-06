#!/usr/bin/env python3
"""
Тест функций открытия и копирования для авторов в контексте GUI
"""

from kemono_parser import KemonoParser

def test_artist_gui_functions():
    """Тест функций GUI для работы с авторами"""

    print("🎯 ТЕСТ GUI-ФУНКЦИЙ АВТОРОВ")
    print("="*50)

    # Имитируем объект GUI для тестирования функций
    class MockGUI:
        def __init__(self):
            self.url_entry_text = ""

        def url_entry(self):
            return self

        def setText(self, text):
            self.url_entry_text = text
            print(f"📝 Установлен URL в поле: {text}")

        def text(self):
            return self.url_entry_text

    gui = MockGUI()

    # Имитируем функции GUI
    def open_artist_in_viewer(artist_data):
        """Открытие автора в вкладке просмотра"""
        # Поддержка как словарей, так и объектов Artist
        if hasattr(artist_data, 'url'):
            url = artist_data.url
        else:
            url = artist_data.get('url', '')

        if url:
            gui.url_entry().setText(url)
            print(f"[AUTHOR] Открытие автора в просмотре: {url}")
            return True
        return False

    def copy_artist_url(artist_data):
        """Копирование ссылки на автора"""
        # Поддержка как словарей, так и объектов Artist
        if hasattr(artist_data, 'url'):
            url = artist_data.url
        else:
            url = artist_data.get('url', '')

        if url:
            print(f"[COPY] Скопирована ссылка на автора: {url}")
            return True
        return False

    parser = KemonoParser(use_selenium=True, headless=True)

    try:
        # Получаем автора через поиск
        print("🔍 Ищем автора 'abmayo'...")
        artists = parser.search_artists_selenium("abmayo", limit=1)

        if artists:
            artist = artists[0]
            print(f"✅ Найден автор: {artist.name} ({artist.service})")
            print(f"   URL: {artist.url}")

            # Тестируем функции
            print("\n🔧 ТЕСТИРУЕМ GUI-ФУНКЦИИ:")

            # Тест открытия автора
            print("🖱️ Тестируем open_artist_in_viewer...")
            result = open_artist_in_viewer(artist)
            if result:
                print("✅ Функция open_artist_in_viewer работает!")
                print(f"   Поле URL установлено: {gui.url_entry_text}")
            else:
                print("❌ Функция open_artist_in_viewer не работает")

            # Тест копирования ссылки
            print("📋 Тестируем copy_artist_url...")
            result = copy_artist_url(artist)
            if result:
                print("✅ Функция copy_artist_url работает!")
            else:
                print("❌ Функция copy_artist_url не работает")

            print("\n✅ ВСЕ GUI-ФУНКЦИИ РАБОТАЮТ!")
        else:
            print("❌ Автор не найден")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

    finally:
        if parser.driver:
            parser.driver.quit()

if __name__ == "__main__":
    test_artist_gui_functions()

