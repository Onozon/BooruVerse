#pragma once

#include <QDialog>

class QCheckBox;
class QComboBox;
class QLabel;
class QLineEdit;
class QPushButton;
class QTableWidget;

class SettingsDialog : public QDialog {
    Q_OBJECT
public:
    explicit SettingsDialog(QWidget *parent = nullptr);

private:
    void reload();
    void reloadPersonal();
    void applyRow(int row);
    void applyPersonalRow(int row);
    void addServer();
    void removeSelected();
    void pickColor(int row);

    QComboBox *m_rating = nullptr;
    QCheckBox *m_fullQuality = nullptr;
    QTableWidget *m_table = nullptr;
    QTableWidget *m_personal = nullptr;
    QLineEdit *m_host = nullptr;
    QPushButton *m_add = nullptr;
    QLabel *m_status = nullptr;
};
