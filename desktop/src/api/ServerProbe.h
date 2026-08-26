#pragma once

#include "core/Models.h"

#include <functional>

class ServerProbe {
public:
    using Callback = std::function<void(bool ok, ApiFlavor flavor, QString error)>;

    static QString normalizeHost(QString host);
    static void detect(const QString &host, Callback callback);
};
