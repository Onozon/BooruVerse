#ifndef KEMONOPARSER_H
#define KEMONOPARSER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QList>
#include <QString>
#include "models/artist.h"
#include "models/post.h"
#include "core/lockmanager.h"
#include "core/threadpool.h"

class KemonoParser : public QObject
{
    Q_OBJECT

public:
    explicit KemonoParser(QObject *parent = nullptr);
    explicit KemonoParser(const QString& baseUrl, QObject *parent = nullptr);
    ~KemonoParser();

    // Поиск авторов
    void searchArtists(const QString& query, int limit = 20, int offset = 0);
    void getRecentArtists(int limit = 20, int offset = 0);
    void getArtistsPage(int limit = 20, int offset = 0);
    void getAllArtists(); // Загрузить всех пользователей без лимита
    
    // Сортировка авторов
    void getPopularArtists(int limit = 50); // По популярности (faved)
    void getRecentlyUpdatedArtists(int limit = 50); // По дате последнего обновления
    
    // Случайный контент
    void getRandomArtist(); // Случайный автор
    void getRandomPost(); // Случайный пост

    // Получение постов автора
    void getArtistPosts(const Artist& artist, int limit = 50, int offset = 0);
    void getAllArtistPosts(const Artist& artist); // Загрузить все посты пользователя
    void getPost(const QString& service, const QString& userId, const QString& postId);
    
    // Поиск постов по всему сервису
    void searchPosts(const QString& query, const QString& sortBy = "published", int offset = 0);
    void getPopularPosts(int offset = 0); // Популярные посты
    void getRecentPosts(int offset = 0); // Последние посты

    // Получение информации об авторе
    void getArtistInfo(const QString& service, const QString& userId);

    QString baseUrl() const { return m_baseUrl; }
    void setBaseUrl(const QString& url) { m_baseUrl = url; }

signals:
    void artistsFound(const QList<Artist>& artists);
    void allArtistsLoaded(const QList<Artist>& artists); // Сигнал для загрузки всех пользователей
    void popularArtistsLoaded(const QList<Artist>& artists);
    void recentlyUpdatedArtistsLoaded(const QList<Artist>& artists);
    void randomArtistLoaded(const Artist& artist);
    void postsFound(const QList<Post>& posts);
    void allArtistPostsLoaded(const QList<Post>& posts, const Artist& artist); // Сигнал для загрузки всех постов пользователя
    void searchPostsFound(const QList<Post>& posts);
    void popularPostsLoaded(const QList<Post>& posts);
    void recentPostsLoaded(const QList<Post>& posts);
    void randomPostLoaded(const Post& post);
    void postLoaded(const Post& post);
    void artistLoaded(const Artist& artist);
    void error(const QString& errorMessage);
    void progress(int current, int total);

private slots:
    void onNetworkReplyFinished(QNetworkReply* reply);

private:
    void setupNetworkManager();
    QNetworkRequest createRequest(const QString& url);
    QList<Artist> parseArtistsFromJson(const QByteArray& data, int limit = 0, int offset = 0);
    QList<Post> parsePostsFromJson(const QByteArray& data);
    Artist parseArtistFromJson(const QJsonObject& obj);
    Post parsePostFromJson(const QJsonObject& obj);
    
public:
    // Публичные методы для конвертации JSON (для использования в MainWindow)
    Artist parseArtistFromJsonPublic(const QJsonObject& obj) { return parseArtistFromJson(obj); }
    Post parsePostFromJsonPublic(const QJsonObject& obj) { return parsePostFromJson(obj); }

    QString m_baseUrl;
    QNetworkAccessManager* m_networkManager;
    QMap<QNetworkReply*, QString> m_replyTypes; // Для определения типа ответа
    QMap<QNetworkReply*, int> m_replyLimits; // Для хранения limit для каждого запроса
    QMap<QNetworkReply*, int> m_replyOffsets; // Для хранения offset для каждого запроса
    QMap<QNetworkReply*, Artist> m_replyArtists; // Для хранения информации об артисте для fallback
};

#endif // KEMONOPARSER_H

