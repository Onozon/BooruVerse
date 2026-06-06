#ifndef IMAGEPROCESSOR_H
#define IMAGEPROCESSOR_H

#include <QObject>
#include <QPixmap>
#include <QString>
#include <QByteArray>

class ImageProcessor : public QObject
{
    Q_OBJECT

public:
    explicit ImageProcessor(QObject* parent = nullptr);

public slots:
    void processImage(const QByteArray& data, const QString& url, int maxWidth);

signals:
    void imageProcessed(const QPixmap& scaledPixmap, const QString& url);
    void processingFailed(const QString& url);
};

#endif // IMAGEPROCESSOR_H




