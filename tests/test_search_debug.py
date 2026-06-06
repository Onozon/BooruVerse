#!/usr/bin/env python3
"""
Отладка поиска авторов с подробным логированием
"""

from kemono_parser import KemonoParser
import time

def test_search_step_by_step():
    """Пошаговое тестирование поиска"""

    print("🔧 Тестирование поиска авторов с подробным логированием")
    print("="*80)

    parser = KemonoParser(use_selenium=True, headless=False)  # Без headless для отладки

    try:
        query = "abmayo"
        search_url = "https://kemono.cr/artists"

        print(f"🎯 Поиск: '{query}' на {search_url}")
        print()

        if not parser.driver:
            print("❌ Selenium драйвер не инициализирован")
            return

        # ШАГ 1: Переход на страницу
        print("ШАГ 1: Переход на страницу поиска")
        print(f"🌐 Переходим на: {search_url}")
        parser.driver.get(search_url)

        time.sleep(5)  # Ждём загрузки

        current_url = parser.driver.current_url
        print(f"📍 Текущий URL: {current_url}")

        # Проверяем редирект
        if 'nachdiewelt.click' in current_url:
            print("❌ Редирект на внешнюю страницу! Поиск заблокирован.")
            return
        elif 'kemono.cr' not in current_url:
            print(f"❌ Не на kemono.cr: {current_url}")
            return
        else:
            print("✅ На правильной странице")

        # ШАГ 2: Поиск поля ввода
        print("\nШАГ 2: Поиск поля ввода")
        try:
            from selenium.webdriver.common.by import By
            from selenium.webdriver.support.ui import WebDriverWait
            from selenium.webdriver.support import expected_conditions as EC

            search_input = WebDriverWait(parser.driver, 10).until(
                EC.presence_of_element_located((By.ID, "q"))
            )
            print("✅ Поле поиска найдено!")
        except Exception as e:
            print(f"❌ Поле поиска не найдено: {e}")

            # Попробуем найти по другим селекторам
            try:
                inputs = parser.driver.find_elements(By.TAG_NAME, "input")
                for inp in inputs:
                    if inp.get_attribute("type") == "text" or inp.get_attribute("placeholder"):
                        print(f"🔍 Найден input: {inp.get_attribute('placeholder') or 'без placeholder'}")
            except:
                pass

            return

        # ШАГ 3: Ввод запроса
        print("\nШАГ 3: Ввод запроса")
        print(f"✍️ Вводим: '{query}'")
        search_input.clear()

        for char in query:
            search_input.send_keys(char)
            time.sleep(0.2)

        time.sleep(1)
        print("✅ Запрос введён")

        # ШАГ 4: Поиск кнопки
        print("\nШАГ 4: Поиск кнопки поиска")
        try:
            search_button = parser.driver.find_element(By.CSS_SELECTOR, "button.search-button")
            print("✅ Кнопка поиска найдена (search-button)")
        except:
            try:
                search_button = parser.driver.find_element(By.CSS_SELECTOR, "button[type='submit']")
                print("✅ Кнопка поиска найдена (type=submit)")
            except:
                print("❌ Кнопка поиска не найдена")
                # Ищем все кнопки
                try:
                    buttons = parser.driver.find_elements(By.TAG_NAME, "button")
                    print(f"🔍 Найдено кнопок: {len(buttons)}")
                    for i, btn in enumerate(buttons[:5]):
                        print(f"  {i+1}. {btn.text or 'без текста'}")
                except:
                    pass
                return

        # ШАГ 5: Нажатие кнопки
        print("\nШАГ 5: Нажатие кнопки поиска")
        search_button.click()
        print("🔘 Кнопка нажата")

        # ШАГ 6: Ожидание результатов
        print("\nШАГ 6: Ожидание результатов")
        print("⏳ Ждём 5 секунд...")
        time.sleep(5)

        final_url = parser.driver.current_url
        print(f"📍 URL после поиска: {final_url}")

        # ШАГ 7: Анализ результатов
        print("\nШАГ 7: Анализ результатов")
        html = parser.driver.page_source
        print(f"📄 Длина HTML: {len(html)} символов")

        # Проверяем title
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html, 'lxml')
        title = soup.find('title')
        if title:
            print(f"📄 Заголовок: {title.text.strip()}")

        # Ищем карточки
        cards = soup.find_all('article', class_='card')
        print(f"🎴 Найдено карточек: {len(cards)}")

        if cards:
            print("✅ Найдены результаты!")
            for i, card in enumerate(cards[:3]):
                link = card.find('a', href=True)
                title_elem = card.find('h2') or card.find('header')
                if link and title_elem:
                    print(f"  {i+1}. {title_elem.text.strip()}")
                    print(f"      {link['href']}")
        else:
            print("❌ Карточки не найдены")

            # Попробуем другие селекторы
            alt_cards = soup.find_all('article', attrs={'data-id': True})
            print(f"🎯 Альтернативный селектор: {len(alt_cards)} карточек")

            if alt_cards:
                for i, card in enumerate(alt_cards[:3]):
                    link = card.find('a', href=True)
                    if link:
                        print(f"  {i+1}. {link['href']}")

        # Сохраняем HTML для анализа
        with open('debug_search_result.html', 'w', encoding='utf-8') as f:
            f.write(html)
        print("💾 HTML сохранён в debug_search_result.html")

    except Exception as e:
        print(f"❌ Ошибка: {e}")

    finally:
        if parser.driver:
            print("\n🛑 Закрываем браузер...")
            parser.driver.quit()

if __name__ == "__main__":
    test_search_step_by_step()

