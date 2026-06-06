#include "gui/imageprocessor.h"
#include <QDebug>

ImageProcessor::ImageProcessor(QObject* parent)
    : QObject(parent)
{
}

void ImageProcessor::processImage(const QByteArray& data, const QString& url, int maxWidth)
{
    if (data.isEmpty()) {
        emit processingFailed(url);
        return;
    }

    QPixmap pixmap;
    if (!pixmap.loadFromData(data)) {
        qDebug() << "Failed to load pixmap from data for:" << url;
        emit processingFailed(url);
        return;
    }

    // Масштабируем в фоновом потоке
    QPixmap scaled = pixmap.scaledToWidth(maxWidth, Qt::SmoothTransformation);
    
    emit imageProcessed(scaled, url);
}




