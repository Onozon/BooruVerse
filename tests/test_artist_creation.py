#!/usr/bin/env python3
"""
Тест создания объекта Artist
"""

from kemono_parser import Artist

def test_artist_creation():
    """Тест создания объекта Artist"""

    print("🧪 ТЕСТИРОВАНИЕ СОЗДАНИЯ ОБЪЕКТА ARTIST")
    print("="*50)

    try:
        # Тест 1: Создание с позиционными аргументами
        print("📋 Тест 1: Позиционные аргументы")
        artist1 = Artist("test_id", "fanbox", "Test Name", "", "", "https://kemono.cr/fanbox/user/test_id")
        print(f"✅ Создан: {artist1.name} ({artist1.service})")
        print(f"   ID: {artist1.id}")
        print(f"   URL: {artist1.url}")
        print()

        # Тест 2: Создание с именованными аргументами
        print("📋 Тест 2: Именованные аргументы")
        artist2 = Artist(
            id="test2_id",
            service="patreon",
            name="Test Artist 2",
            indexed="2023-01-01",
            updated="2023-12-01",
            url="https://kemono.cr/patreon/user/test2_id"
        )
        print(f"✅ Создан: {artist2.name} ({artist2.service})")
        print(f"   ID: {artist2.id}")
        print(f"   URL: {artist2.url}")
        print()

        # Тест 3: Создание через присваивание (как в коде)
        print("📋 Тест 3: Присваивание полей")
        artist3 = Artist()
        artist3.id = "test3_id"
        artist3.service = "discord"
        artist3.name = "Test Artist 3"
        artist3.indexed = ""
        artist3.updated = ""
        artist3.url = "https://kemono.cr/discord/user/test3_id"
        print(f"✅ Создан: {artist3.name} ({artist3.service})")
        print(f"   ID: {artist3.id}")
        print(f"   URL: {artist3.url}")
        print()

        print("🎯 ВСЕ ТЕСТЫ ПРОШЛИ УСПЕШНО!")
        return True

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    test_artist_creation()

