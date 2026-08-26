#include "app/IconImageProvider.h"

#include <QColor>
#include <QPainter>
#include <QPixmap>
#include <QSize>
#include <QString>
#include <QSvgRenderer>

IconImageProvider::IconImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Pixmap) {
}

static QColor parseIconTint(QString token) {
    if (token.startsWith(QLatin1Char('#')))
        token.remove(0, 1);
    if (token.size() == 6)
        return QColor(QLatin1Char('#') + token);
    if (token.size() == 8) {
        // Qt 8-digit hex is #AARRGGBB. Older QML sent RRGGBBAA, which
        // made black (#000000ff) render as fully transparent blue.
        QColor aarrggbb(QLatin1Char('#') + token);
        if (aarrggbb.isValid() && aarrggbb.alpha() > 0)
            return aarrggbb;
        bool ok = false;
        const int r = token.mid(0, 2).toInt(&ok, 16);
        const int g = token.mid(2, 2).toInt(&ok, 16);
        const int b = token.mid(4, 2).toInt(&ok, 16);
        int a = token.mid(6, 2).toInt(&ok, 16);
        if (a <= 0)
            a = 255;
        return QColor(r, g, b, a);
    }
    QColor named(token);
    return named.isValid() ? named : QColor(Qt::black);
}

QPixmap IconImageProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) {
    const int slash = id.lastIndexOf(QLatin1Char('/'));
    QString file = id;
    QColor color(Qt::black);
    if (slash > 0) {
        file = id.left(slash);
        color = parseIconTint(id.mid(slash + 1));
        if (!color.isValid() || color.alpha() <= 0)
            color = Qt::black;
    }

    QSize sz = requestedSize;
    if (sz.width() <= 0)
        sz.setWidth(24);
    if (sz.height() <= 0)
        sz.setHeight(24);

    QSvgRenderer renderer(QStringLiteral(":/ui-icons/") + file);
    QPixmap pixmap(sz);
    pixmap.fill(Qt::transparent);
    if (renderer.isValid()) {
        QPainter painter(&pixmap);
        painter.setRenderHint(QPainter::Antialiasing);
        renderer.render(&painter);
        painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
        painter.fillRect(pixmap.rect(), color);
    }
    if (size)
        *size = sz;
    return pixmap;
}
