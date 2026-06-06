#!/usr/bin/env python3
"""
Тест создания объектов Post
"""

from kemono_parser import Post

def test_post_creation():
    """Тест разных способов создания объекта Post"""

    print("🧪 Тестирование создания объектов Post")
    print("="*50)

    # Способ 1: Пустой конструктор + ручная инициализация
    print("\n1️⃣ Способ 1: Post() + ручная инициализация")
    try:
        post1 = Post()
        post1.id = "123"
        post1.title = "Test Post"
        post1.content = "Test content"
        post1.published = "2023-01-01"
        post1.edited = None
        post1.author = "test_author"
        post1.service = "fanbox"
        post1.thumbnail = None
        post1.attachments = []
        post1.embeds = []
        post1.files = []

        print(f"✅ Успешно создан: {post1.title} ({post1.service})")
    except Exception as e:
        print(f"❌ Ошибка: {e}")

    # Способ 2: Создание с ключевыми аргументами
    print("\n2️⃣ Способ 2: Post(**kwargs)")
    try:
        post2 = Post(
            id="456",
            title="Test Post 2",
            content="Test content 2",
            published="2023-01-02",
            edited=None,
            author="test_author2",
            service="patreon",
            thumbnail=None,
            attachments=[],
            embeds=[],
            files=[]
        )
        print(f"✅ Успешно создан: {post2.title} ({post2.service})")
    except Exception as e:
        print(f"❌ Ошибка: {e}")
        print(f"   Тип ошибки: {type(e)}")

    # Способ 3: Проверка атрибутов класса
    print("\n3️⃣ Способ 3: Проверка атрибутов класса Post")
    try:
        post_attrs = [attr for attr in dir(Post) if not attr.startswith('_')]
        print(f"Атрибуты класса Post: {post_attrs}")

        # Проверка __init__
        if hasattr(Post, '__init__'):
            print("✅ Класс имеет метод __init__")
            init_signature = Post.__init__.__code__.co_varnames
            print(f"   Параметры __init__: {init_signature}")
        else:
            print("❌ Класс не имеет метода __init__")

    except Exception as e:
        print(f"❌ Ошибка анализа класса: {e}")

if __name__ == "__main__":
    test_post_creation()

