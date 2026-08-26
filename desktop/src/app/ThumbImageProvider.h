#pragma once

#include <QQuickAsyncImageProvider>
#include <QQuickImageResponse>

class ThumbImageProvider : public QQuickAsyncImageProvider {
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
    /// Must be called once on the GUI thread before any image://thumbs requests.
    static void ensureEngine();
    static void purgeCache();
};
