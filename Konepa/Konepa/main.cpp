#include <QApplication>
#include <QMetaType>
#include <QMessageBox>
#include <QDebug>
#include <exception>
#include <stdexcept>
#include "gui/mainwindow.h"
#include "models/artist.h"
#include "models/post.h"

Q_DECLARE_METATYPE(Artist)
Q_DECLARE_METATYPE(Post)

// Глобальный обработчик необработанных исключений
void handleException(const char* context)
{
    try {
        throw;
    } catch (const std::exception& e) {
        qCritical() << "Exception in" << context << ":" << e.what();
        QMessageBox::critical(nullptr, "Ошибка", 
            QString("Критическая ошибка в %1:\n%2").arg(context).arg(e.what()));
    } catch (...) {
        qCritical() << "Unknown exception in" << context;
        QMessageBox::critical(nullptr, "Ошибка", 
            QString("Неизвестная ошибка в %1").arg(context));
    }
}

int main(int argc, char *argv[])
{
    try {
        QApplication app(argc, argv);

        // Регистрируем типы для QVariant
        qRegisterMetaType<Artist>("Artist");
        qRegisterMetaType<Post>("Post");

        qDebug() << "Creating MainWindow...";
        MainWindow window;
        qDebug() << "MainWindow created, showing...";
        window.show();
        qDebug() << "MainWindow shown, starting event loop...";

    return app.exec();
    } catch (const std::exception& e) {
        qCritical() << "Fatal exception in main:" << e.what();
        QMessageBox::critical(nullptr, "Критическая ошибка", 
            QString("Программа завершилась с ошибкой:\n%1").arg(e.what()));
        return 1;
    } catch (...) {
        qCritical() << "Unknown fatal exception in main";
        QMessageBox::critical(nullptr, "Критическая ошибка", 
            "Программа завершилась с неизвестной ошибкой");
        return 1;
    }
}
