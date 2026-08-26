#pragma once

#include <QQuickAsyncImageProvider>
#include <QQuickImageResponse>

class ThumbImageProvider : public QQuickAsyncImageProvider {
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
    static void purgeCache();
};
