#include "ui/SettingsDialog.h"

#include "api/ServerProbe.h"
#include "core/GallerySettings.h"
#include "core/PersonalFeedStore.h"
#include "core/SavedTagSetStore.h"
#include "core/ServerStore.h"

#include <QCheckBox>
#include <QColorDialog>
#include <QComboBox>
#include <QDialogButtonBox>
#include <QHBoxLayout>
#include <QPointer>
#include <QHeaderView>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

SettingsDialog::SettingsDialog(QWidget *parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Settings"));
    resize(820, 620);

    auto *root = new QVBoxLayout(this);
    auto *prefs = new QHBoxLayout;
    prefs->addWidget(new QLabel(QStringLiteral("Rating")));
    m_rating = new QComboBox;
    m_rating->addItems({QStringLiteral("Show All"), QStringLiteral("Hide Explicit"), QStringLiteral("Safe Only")});
    m_rating->setCurrentIndex(int(GallerySettings::instance().ratingFilter()));
    prefs->addWidget(m_rating);
    m_fullQuality = new QCheckBox(QStringLiteral("Load full quality in viewer"));
    m_fullQuality->setChecked(GallerySettings::instance().loadFullQuality());
    prefs->addWidget(m_fullQuality);
    prefs->addStretch(1);
    root->addLayout(prefs);
    connect(m_rating, &QComboBox::currentIndexChanged, this, [](int index) {
        GallerySettings::instance().setRatingFilter(RatingFilter(index));
    });
    connect(m_fullQuality, &QCheckBox::toggled, this, [](bool on) {
        GallerySettings::instance().setLoadFullQuality(on);
    });

    root->addWidget(new QLabel(QStringLiteral("Enable boards and optionally add API credentials.")));

    m_table = new QTableWidget(0, 6);
    m_table->setHorizontalHeaderLabels({
        QStringLiteral("Enabled"),
        QStringLiteral("Host"),
        QStringLiteral("API"),
        QStringLiteral("User / login"),
        QStringLiteral("API key"),
        QStringLiteral("Color"),
    });
    m_table->horizontalHeader()->setStretchLastSection(true);
    m_table->verticalHeader()->setVisible(false);
    m_table->setSelectionBehavior(QAbstractItemView::SelectRows);
    root->addWidget(m_table, 1);

    auto *addRow = new QHBoxLayout;
    m_host = new QLineEdit;
    m_host->setPlaceholderText(QStringLiteral("Add board host, e.g. rule34.xxx"));
    m_add = new QPushButton(QStringLiteral("Add"));
    auto *remove = new QPushButton(QStringLiteral("Remove"));
    addRow->addWidget(m_host, 1);
    addRow->addWidget(m_add);
    addRow->addWidget(remove);
    root->addLayout(addRow);

    root->addWidget(new QLabel(QStringLiteral("Personal feed — checked sets are mixed into Feed → Personal.")));
    m_personal = new QTableWidget(0, 3);
    m_personal->setHorizontalHeaderLabels({
        QStringLiteral("In feed"),
        QStringLiteral("Name"),
        QStringLiteral("Tags"),
    });
    m_personal->horizontalHeader()->setStretchLastSection(true);
    m_personal->verticalHeader()->setVisible(false);
    m_personal->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_personal->setMaximumHeight(180);
    root->addWidget(m_personal);

    m_status = new QLabel;
    m_status->setStyleSheet(QStringLiteral("color:#8e8e93;"));
    root->addWidget(m_status);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Close);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    root->addWidget(buttons);

    reload();
    reloadPersonal();
    connect(m_table, &QTableWidget::cellChanged, this, [this](int row, int) { applyRow(row); });
    connect(m_personal, &QTableWidget::cellChanged, this, [this](int row, int) { applyPersonalRow(row); });
    connect(m_add, &QPushButton::clicked, this, &SettingsDialog::addServer);
    connect(m_host, &QLineEdit::returnPressed, this, &SettingsDialog::addServer);
    connect(remove, &QPushButton::clicked, this, &SettingsDialog::removeSelected);
    connect(m_table, &QTableWidget::cellDoubleClicked, this, [this](int row, int column) {
        if (column == 5)
            pickColor(row);
    });
}

void SettingsDialog::reload() {
    const QVector<BooruServer> servers = ServerStore::instance().servers();
    m_table->blockSignals(true);
    m_table->setRowCount(servers.size());
    for (int i = 0; i < servers.size(); ++i) {
        const BooruServer &server = servers[i];
        auto *enabled = new QTableWidgetItem;
        enabled->setFlags(Qt::ItemIsUserCheckable | Qt::ItemIsEnabled);
        enabled->setCheckState(server.enabled ? Qt::Checked : Qt::Unchecked);
        m_table->setItem(i, 0, enabled);

        auto *host = new QTableWidgetItem(server.host);
        host->setFlags(Qt::ItemIsEnabled | Qt::ItemIsSelectable);
        host->setData(Qt::UserRole, server.builtIn);
        m_table->setItem(i, 1, host);

        auto *flavor = new QTableWidgetItem(flavorTitle(server.flavor));
        flavor->setFlags(Qt::ItemIsEnabled | Qt::ItemIsSelectable);
        m_table->setItem(i, 2, flavor);

        auto *user = new QTableWidgetItem(server.userId);
        m_table->setItem(i, 3, user);
        auto *key = new QTableWidgetItem(server.apiKey);
        m_table->setItem(i, 4, key);
        auto *color = new QTableWidgetItem(server.colorHex);
        color->setFlags(Qt::ItemIsEnabled | Qt::ItemIsSelectable);
        if (server.color().isValid())
            color->setBackground(server.color());
        m_table->setItem(i, 5, color);
    }
    m_table->resizeColumnsToContents();
    m_table->blockSignals(false);
}

void SettingsDialog::reloadPersonal() {
    const QVector<SavedTagSet> sets = SavedTagSetStore::instance().sets();
    m_personal->blockSignals(true);
    m_personal->setRowCount(sets.size());
    for (int i = 0; i < sets.size(); ++i) {
        const SavedTagSet &set = sets[i];
        auto *enabled = new QTableWidgetItem;
        enabled->setFlags(Qt::ItemIsUserCheckable | Qt::ItemIsEnabled);
        enabled->setCheckState(PersonalFeedStore::instance().contains(set.id) ? Qt::Checked : Qt::Unchecked);
        enabled->setData(Qt::UserRole, set.id);
        m_personal->setItem(i, 0, enabled);
        auto *name = new QTableWidgetItem(set.name);
        name->setFlags(Qt::ItemIsEnabled | Qt::ItemIsSelectable);
        m_personal->setItem(i, 1, name);
        auto *tags = new QTableWidgetItem(set.joined());
        tags->setFlags(Qt::ItemIsEnabled | Qt::ItemIsSelectable);
        m_personal->setItem(i, 2, tags);
    }
    m_personal->resizeColumnsToContents();
    m_personal->blockSignals(false);
}

void SettingsDialog::applyPersonalRow(int row) {
    const QTableWidgetItem *item = m_personal->item(row, 0);
    if (!item)
        return;
    PersonalFeedStore::instance().setEnabled(item->data(Qt::UserRole).toString(),
                                             item->checkState() == Qt::Checked);
}

void SettingsDialog::applyRow(int row) {
    QVector<BooruServer> servers = ServerStore::instance().servers();
    if (row < 0 || row >= servers.size())
        return;
    servers[row].enabled = m_table->item(row, 0)->checkState() == Qt::Checked;
    servers[row].userId = m_table->item(row, 3)->text().trimmed();
    servers[row].apiKey = m_table->item(row, 4)->text().trimmed();
    ServerStore::instance().setServers(servers);
}

void SettingsDialog::addServer() {
    const QString host = m_host->text().trimmed();
    if (host.isEmpty()) {
        m_status->setText(QStringLiteral("Enter a host."));
        return;
    }
    m_add->setEnabled(false);
    m_status->setText(QStringLiteral("Detecting API…"));
    const QPointer<SettingsDialog> self(this);
    ServerProbe::detect(host, [self, host](bool ok, ApiFlavor flavor, QString error) {
        if (!self)
            return;
        self->m_add->setEnabled(true);
        if (!ok) {
            self->m_status->setText(error);
            return;
        }
        const QString normalized = ServerProbe::normalizeHost(host);
        if (ServerStore::instance().addCustom(normalized, flavor)) {
            self->m_host->clear();
            self->m_status->setText(QStringLiteral("Added %1 as %2.").arg(normalized, flavorTitle(flavor)));
            self->reload();
        }
    });
}

void SettingsDialog::removeSelected() {
    const int row = m_table->currentRow();
    if (row < 0)
        return;
    const QTableWidgetItem *host = m_table->item(row, 1);
    if (!host)
        return;
    if (host->data(Qt::UserRole).toBool()) {
        m_status->setText(QStringLiteral("Built-in boards stay in the list. Disable them instead."));
        return;
    }
    ServerStore::instance().removeHost(host->text());
    reload();
    m_status->setText(QStringLiteral("Removed %1.").arg(host->text()));
}

void SettingsDialog::pickColor(int row) {
    const QTableWidgetItem *host = m_table->item(row, 1);
    if (!host)
        return;
    const QColor current = ServerStore::instance().colorFor(host->text());
    const QColor color = QColorDialog::getColor(current, this, QStringLiteral("Server color"));
    if (!color.isValid())
        return;
    ServerStore::instance().setColor(host->text(), color.name());
    reload();
}
