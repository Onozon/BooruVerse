#ifndef SECTIONSTATE_H
#define SECTIONSTATE_H

#include "models/artist.h"
#include "models/post.h"
#include <QList>
#include <QString>

// Состояние секции (Поиск, История, Оффлайн)
struct SectionState {
    int currentTab = 0; // 0 = Авторы, 1 = Посты
    Artist selectedArtist; // Выбранный автор (если есть)
    QList<Post> artistPosts; // Посты выбранного автора
    QList<Artist> artists; // Список авторов для текущей секции
    int postsPage = 0; // Текущая страница постов
    int artistsPage = 0; // Текущая страница авторов
    QString searchQuery; // Поисковый запрос (для секции Поиск)
    
    bool hasSelectedArtist() const {
        return !selectedArtist.id().isEmpty();
    }
    
    void reset() {
        currentTab = 0;
        selectedArtist = Artist();
        artistPosts.clear();
        artists.clear();
        postsPage = 0;
        artistsPage = 0;
        searchQuery.clear();
    }
};

#endif // SECTIONSTATE_H




