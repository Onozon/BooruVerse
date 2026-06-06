#!/usr/bin/env python3
"""
Анализ структуры отдельного поста для поиска медиафайлов
"""

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from bs4 import BeautifulSoup
import time


def analyze_single_post():
    """Анализ одного поста для понимания структуры медиафайлов"""
    print("🔍 Анализ структуры поста...")

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    driver = webdriver.Chrome(options=options)

    try:
        # Возьмем URL одного поста из найденных
        post_url = "https://kemono.cr/fanbox/user/3065392/post/10388909"
        print(f"🌐 Загружаем пост: {post_url}")

        driver.get(post_url)
        print("⏳ Ждем загрузки поста...")
        time.sleep(8)  # Ждем дольше для загрузки медиа

        html = driver.page_source
        print(f"📏 Длина HTML поста: {len(html)} байт")

        soup = BeautifulSoup(html, 'lxml')

        # Ищем заголовок поста
        title = soup.find('h1') or soup.find('header')
        print(f"📄 Заголовок: {title.text.strip() if title else 'Не найден'}")

        # Ищем все изображения
        images = soup.find_all('img')
        print(f"🖼️  Всего изображений: {len(images)}")

        for i, img in enumerate(images[:10]):  # Показываем первые 10
            src = img.get('src')
            alt = img.get('alt', '')
            print(f"   {i+1}. {src}")
            if alt:
                print(f"      Alt: {alt}")

        # Ищем видео
        videos = soup.find_all('video')
        print(f"🎬 Видео элементов: {len(videos)}")

        for i, video in enumerate(videos[:5]):
            src = video.get('src')
            print(f"   {i+1}. {src}")

        # Ищем iframe (могут содержать видео)
        iframes = soup.find_all('iframe')
        print(f"📺 Iframe элементов: {len(iframes)}")

        for i, iframe in enumerate(iframes[:5]):
            src = iframe.get('src')
            print(f"   {i+1}. {src}")

        # Ищем ссылки на скачивание
        download_links = soup.find_all('a', href=lambda x: x and any(ext in x.lower() for ext in ['.jpg', '.png', '.gif', '.webp', '.mp4', '.zip', '.rar']))
        print(f"📥 Ссылок на скачивание: {len(download_links)}")

        for i, link in enumerate(download_links[:10]):
            href = link.get('href')
            text = link.text.strip()
            print(f"   {i+1}. {href} - '{text}'")

        # Ищем элементы с классом attachment или file
        attachments = soup.find_all(class_=lambda x: x and ('attachment' in x.lower() or 'file' in x.lower()))
        print(f"📎 Элементов с attachment/file: {len(attachments)}")

        # Ищем все ссылки вообще
        all_links = soup.find_all('a', href=True)
        media_links = [link for link in all_links if any(ext in link['href'].lower() for ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.mp4', '.avi', '.mov', '.zip', '.rar', '.pdf'])]
        print(f"🔗 Всех медиа-ссылок: {len(media_links)}")

        for i, link in enumerate(media_links[:15]):
            href = link['href']
            text = link.text.strip()[:50]
            print(f"   {i+1}. {href} - '{text}'")

        # Ищем элементы с data-src (lazy loading)
        lazy_images = soup.find_all(attrs={'data-src': True})
        print(f"🖼️  Lazy loading изображений: {len(lazy_images)}")

        for i, img in enumerate(lazy_images[:5]):
            data_src = img.get('data-src')
            print(f"   {i+1}. {data_src}")

        # Сохраняем HTML для анализа
        with open('single_post_analysis.html', 'w', encoding='utf-8') as f:
            f.write(html)
        print("💾 HTML поста сохранен в single_post_analysis.html")
        # Ищем кнопки или элементы управления
        buttons = soup.find_all(['button', 'a'], class_=lambda x: x and any(word in x.lower() for word in ['download', 'attachment', 'file']))
        print(f"🔘 Кнопок/ссылок для скачивания: {len(buttons)}")

        for i, btn in enumerate(buttons[:5]):
            tag = btn.name
            text = btn.text.strip()
            href = btn.get('href', '')
            print(f"   {i+1}. {tag}: '{text}' href='{href}'")

    except Exception as e:
        print(f"❌ Ошибка анализа поста: {e}")
        import traceback
        traceback.print_exc()
    finally:
        driver.quit()


def test_preview_extraction():
    """Тест извлечения медиа из превью постов"""
    print("\n🔍 Анализ превью постов...")

    options = Options()
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    driver = webdriver.Chrome(options=options)

    try:
        url = "https://kemono.cr/fanbox/user/3065392"
        driver.get(url)
        time.sleep(8)

        # Находим превью постов
        post_previews = driver.find_elements(By.CSS_SELECTOR, 'article.post-card')

        if post_previews:
            print(f"📄 Найдено превью постов: {len(post_previews)}")

            # Анализируем первое превью
            preview = post_previews[0]
            preview_html = preview.get_attribute('outerHTML')
            print("📋 HTML превью первого поста:")
            print(preview_html[:500] + "..." if len(preview_html) > 500 else preview_html)

            # Ищем изображения в превью
            images = preview.find_elements(By.TAG_NAME, 'img')
            print(f"🖼️  Изображений в превью: {len(images)}")

            for i, img in enumerate(images[:3]):
                src = img.get_attribute('src')
                alt = img.get_attribute('alt')
                print(f"   {i+1}. Src: {src}")
                print(f"      Alt: {alt}")

            # Ищем текст о вложениях
            text = preview.text
            print(f"📝 Текст превью: {text}")

    except Exception as e:
        print(f"❌ Ошибка анализа превью: {e}")
    finally:
        driver.quit()


if __name__ == "__main__":
    analyze_single_post()
    test_preview_extraction()
