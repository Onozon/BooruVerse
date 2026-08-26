#include "app/UiTheme.h"

#include <QGuiApplication>
#include <QStyleHints>

UiTheme::UiTheme(QObject *parent)
    : QObject(parent) {
    sync();
    if (auto *hints = QGuiApplication::styleHints()) {
        connect(hints, &QStyleHints::colorSchemeChanged, this, [this](Qt::ColorScheme) { sync(); });
    }
}

void UiTheme::sync() {
    const bool next = QGuiApplication::styleHints()
        && QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark;
    if (m_dark == next)
        return;
    m_dark = next;
    emit changed();
}
