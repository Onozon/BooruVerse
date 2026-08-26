#pragma once

#include <QColor>
#include <QObject>

class UiTheme : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool dark READ dark NOTIFY changed)
    Q_PROPERTY(QColor accent READ accent CONSTANT)
    Q_PROPERTY(QColor background READ background NOTIFY changed)
    Q_PROPERTY(QColor surface READ surface NOTIFY changed)
    Q_PROPERTY(QColor bar READ bar NOTIFY changed)
    Q_PROPERTY(QColor elevated READ elevated NOTIFY changed)
    Q_PROPERTY(QColor text READ text NOTIFY changed)
    Q_PROPERTY(QColor secondary READ secondary CONSTANT)
    Q_PROPERTY(QColor separator READ separator NOTIFY changed)
    Q_PROPERTY(QColor overlay READ overlay CONSTANT)
    Q_PROPERTY(QColor danger READ danger CONSTANT)
    Q_PROPERTY(int compactBelow READ compactBelow CONSTANT)
    Q_PROPERTY(int hit READ hit CONSTANT)
    Q_PROPERTY(int hitCompact READ hitCompact CONSTANT)
    Q_PROPERTY(int hitRegular READ hitRegular CONSTANT)
    Q_PROPERTY(int radius READ radius CONSTANT)
    Q_PROPERTY(int chipRadius READ chipRadius CONSTANT)
    Q_PROPERTY(int gridPadding READ gridPadding CONSTANT)
    Q_PROPERTY(int gridSpacing READ gridSpacing CONSTANT)
    Q_PROPERTY(int captionHeight READ captionHeight CONSTANT)
    Q_PROPERTY(int sidebarMin READ sidebarMin CONSTANT)
    Q_PROPERTY(int sidebarIdeal READ sidebarIdeal CONSTANT)
    Q_PROPERTY(int sidebarMax READ sidebarMax CONSTANT)
    Q_PROPERTY(int closeSize READ closeSize CONSTANT)
    Q_PROPERTY(int actionBar READ actionBar CONSTANT)
    Q_PROPERTY(int tabIcon READ tabIcon CONSTANT)
    Q_PROPERTY(int tabLabel READ tabLabel CONSTANT)

public:
    explicit UiTheme(QObject *parent = nullptr);

    bool dark() const { return m_dark; }
    QColor accent() const { return QColor(QStringLiteral("#007AFF")); }
    QColor background() const { return m_dark ? QColor(QStringLiteral("#000000")) : QColor(QStringLiteral("#F2F2F7")); }
    QColor surface() const { return m_dark ? QColor(QStringLiteral("#1C1C1E")) : QColor(QStringLiteral("#FFFFFF")); }
    QColor bar() const { return m_dark ? QColor(QStringLiteral("#1C1C1E")) : QColor(QStringLiteral("#F9F9F9")); }
    QColor elevated() const { return m_dark ? QColor(QStringLiteral("#2C2C2E")) : QColor(QStringLiteral("#FFFFFF")); }
    QColor text() const { return m_dark ? QColor(QStringLiteral("#FFFFFF")) : QColor(QStringLiteral("#000000")); }
    QColor secondary() const { return QColor(QStringLiteral("#8E8E93")); }
    QColor separator() const { return m_dark ? QColor(QStringLiteral("#38383A")) : QColor(QStringLiteral("#C6C6C8")); }
    QColor overlay() const { return QColor(0, 0, 0, 204); }
    QColor danger() const { return QColor(QStringLiteral("#FF3B30")); }
    int compactBelow() const { return 700; }
    int hit() const { return 44; }
    int hitCompact() const { return 44; }
    int hitRegular() const { return 34; }
    int radius() const { return 12; }
    int chipRadius() const { return 14; }
    int gridPadding() const { return 16; }
    int gridSpacing() const { return 10; }
    int captionHeight() const { return 22; }
    int sidebarMin() const { return 260; }
    int sidebarIdeal() const { return 300; }
    int sidebarMax() const { return 360; }
    int closeSize() const { return 36; }
    int actionBar() const { return 64; }
    int tabIcon() const { return 18; }
    int tabLabel() const { return 11; }

signals:
    void changed();

private:
    void sync();
    bool m_dark = false;
};
