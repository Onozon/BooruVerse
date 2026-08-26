#pragma once

#include <QColor>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVector>

enum class ApiFlavor { Moebooru, Danbooru2, Gelbooru };

enum class Rating { Safe, Sensitive, Questionable, Explicit };

enum class RatingFilter { All, HideExplicit, SafeOnly };

enum class PopularPeriod { Day, Week, Month };

enum class FeedChannel { Personal, Day, Week, Month };

enum class TilingMode { Columns, Adaptive };

enum class GallerySection { Browse, Feed, Favorites, Pools };

struct SavedTagSet {
    QString id;
    QString name;
    QStringList tags;
    qint64 createdAt = 0;

    QString joined() const { return tags.join(QLatin1Char(' ')); }
};

struct BooruPost {
    QString serverId;
    int id = 0;
    QString md5;
    QStringList tags;
    Rating rating = Rating::Safe;
    int score = 0;
    int width = 0;
    int height = 0;
    QUrl previewUrl;
    QUrl sampleUrl;
    QUrl fileUrl;
    QString fileExt;
    QUrl sourceUrl;
    qint64 createdAt = 0;
    int duplicateCount = 1;
    QString folderId;

    QString globalId() const { return serverId + QLatin1Char('#') + QString::number(id); }

    QUrl viewerUrl() const {
        if (!sampleUrl.isEmpty())
            return sampleUrl;
        if (!fileUrl.isEmpty())
            return fileUrl;
        return previewUrl;
    }

    bool hasHigherQualityOriginal() const {
        return !fileUrl.isEmpty() && fileUrl != viewerUrl();
    }

    double aspectRatio() const {
        if (height <= 0)
            return 1.0;
        return double(width) / double(height);
    }

    bool allowedBy(RatingFilter filter) const {
        switch (filter) {
        case RatingFilter::All:
            return true;
        case RatingFilter::HideExplicit:
            return rating != Rating::Explicit;
        case RatingFilter::SafeOnly:
            return rating == Rating::Safe;
        }
        return true;
    }
};

enum class TagType { Copyright, Character, Artist, General, Meta };

struct BooruTag {
    QString name;
    int postCount = 0;
    TagType type = TagType::General;
};

inline TagType tagTypeFromRaw(int raw) {
    switch (raw) {
    case 1:
        return TagType::Artist;
    case 3:
        return TagType::Copyright;
    case 4:
        return TagType::Character;
    case 5:
        return TagType::Meta;
    default:
        return TagType::General;
    }
}

inline QString tagTypeTitle(TagType type) {
    switch (type) {
    case TagType::Copyright:
        return QStringLiteral("Copyright");
    case TagType::Character:
        return QStringLiteral("Character");
    case TagType::Artist:
        return QStringLiteral("Artist");
    case TagType::Meta:
        return QStringLiteral("Meta");
    case TagType::General:
        return QStringLiteral("General");
    }
    return QStringLiteral("General");
}

inline QColor tagTypeColor(TagType type) {
    switch (type) {
    case TagType::Artist:
        return QColor(235, 79, 79);
    case TagType::Copyright:
        return QColor(184, 133, 209);
    case TagType::Character:
        return QColor(79, 184, 99);
    case TagType::Meta:
        return QColor(140, 140, 148);
    case TagType::General:
        return QColor(99, 130, 217);
    }
    return QColor(99, 130, 217);
}

inline QUrl postPageUrl(const BooruPost &post, ApiFlavor flavor) {
    switch (flavor) {
    case ApiFlavor::Moebooru:
        return QUrl(QStringLiteral("https://%1/post/show/%2").arg(post.serverId).arg(post.id));
    case ApiFlavor::Danbooru2:
        return QUrl(QStringLiteral("https://%1/posts/%2").arg(post.serverId).arg(post.id));
    case ApiFlavor::Gelbooru:
        return QUrl(QStringLiteral("https://%1/index.php?page=post&s=view&id=%2").arg(post.serverId).arg(post.id));
    }
    return {};
}

struct BooruPool {
    QString serverId;
    int id = 0;
    QString name;
    int postCount = 0;
    QString description;

    QString globalId() const { return serverId + QLatin1Char('#') + QString::number(id); }
    QString displayName() const {
        QString title = name;
        title.replace(QLatin1Char('_'), QLatin1Char(' '));
        return title.isEmpty() ? QString::number(id) : title;
    }
};

struct BooruServer {
    QString host;
    ApiFlavor flavor = ApiFlavor::Moebooru;
    bool enabled = true;
    bool builtIn = false;
    QString apiKey;
    QString userId;
    QString colorHex;

    QString displayName() const { return host; }

    QColor color() const {
        if (colorHex.startsWith(QLatin1Char('#')))
            return QColor(colorHex);
        return QColor();
    }

    bool supportsCredentials() const {
        return flavor == ApiFlavor::Gelbooru || flavor == ApiFlavor::Danbooru2;
    }

    bool requiresCredentials() const {
        return flavor == ApiFlavor::Gelbooru && host == QLatin1String("gelbooru.com");
    }

    bool hasCredentials() const {
        return !apiKey.trimmed().isEmpty() && !userId.trimmed().isEmpty();
    }

    QString credentialUserTitle() const {
        return flavor == ApiFlavor::Danbooru2 ? QStringLiteral("Username") : QStringLiteral("User ID");
    }
};

struct FavoriteFolder {
    QString id;
    QString name;
};

inline QString defaultFavoriteFolderId() {
    return QStringLiteral("default");
}

inline QString flavorTitle(ApiFlavor flavor) {
    switch (flavor) {
    case ApiFlavor::Moebooru:
        return QStringLiteral("Moebooru");
    case ApiFlavor::Danbooru2:
        return QStringLiteral("Danbooru");
    case ApiFlavor::Gelbooru:
        return QStringLiteral("Gelbooru");
    }
    return {};
}

inline Rating ratingFromRaw(const QString &raw, ApiFlavor flavor) {
    const QString value = raw.toLower();
    if (value == QLatin1String("e") || value == QLatin1String("explicit"))
        return Rating::Explicit;
    if (value == QLatin1String("q") || value == QLatin1String("questionable"))
        return Rating::Questionable;
    if (flavor == ApiFlavor::Danbooru2 && value == QLatin1String("s"))
        return Rating::Sensitive;
    if (value == QLatin1String("sensitive"))
        return Rating::Sensitive;
    return Rating::Safe;
}

inline QString periodQuery(PopularPeriod period, ApiFlavor flavor) {
    if (flavor == ApiFlavor::Danbooru2) {
        switch (period) {
        case PopularPeriod::Day:
            return QStringLiteral("day");
        case PopularPeriod::Week:
            return QStringLiteral("week");
        case PopularPeriod::Month:
            return QStringLiteral("month");
        }
    }
    switch (period) {
    case PopularPeriod::Day:
        return QStringLiteral("1d");
    case PopularPeriod::Week:
        return QStringLiteral("1w");
    case PopularPeriod::Month:
        return QStringLiteral("1m");
    }
    return QStringLiteral("1d");
}

inline QString ratingTag(RatingFilter filter, ApiFlavor flavor) {
    switch (filter) {
    case RatingFilter::All:
        return {};
    case RatingFilter::HideExplicit:
        switch (flavor) {
        case ApiFlavor::Moebooru:
            return QStringLiteral("-rating:e");
        case ApiFlavor::Gelbooru:
            return QStringLiteral("-rating:explicit");
        case ApiFlavor::Danbooru2:
            return QStringLiteral("rating:g,s,q");
        }
        break;
    case RatingFilter::SafeOnly:
        switch (flavor) {
        case ApiFlavor::Moebooru:
            return QStringLiteral("rating:s");
        case ApiFlavor::Gelbooru:
            return QStringLiteral("-rating:questionable -rating:explicit");
        case ApiFlavor::Danbooru2:
            return QStringLiteral("rating:g");
        }
        break;
    }
    return {};
}

inline QString queryWithRating(const QString &base, RatingFilter filter, ApiFlavor flavor) {
    const QString extra = ratingTag(filter, flavor);
    if (extra.isEmpty())
        return base;
    return base.isEmpty() ? extra : base + QLatin1Char(' ') + extra;
}
