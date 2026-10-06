#include "artwork-fetch.h"
#include <QCoreApplication>
#include <QFile>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <cstdio>
#include <sys/resource.h>
#include <unistd.h>

// One remote artwork fetch for the helper, in its own short-lived process so
// the TLS stack never stays resident in the helper. Arguments: the URL, and
// optionally --ca-file <pem> naming the only trusted CA (the isolated network
// tests' fixture). Standard output is one line, "ok <mime>" followed by the
// body, or "error <code>"; the helper bounds what it reads.
int main(int argc, char **argv) {
    const rlimit coreLimit{0, 0};
    if (setrlimit(RLIMIT_CORE, &coreLimit)) return 2;
    QCoreApplication app(argc, argv);
    const auto arguments = app.arguments();
    if (arguments.size() != 2 && !(arguments.size() == 4 && arguments[2] == "--ca-file")) return 2;
    if (arguments.size() == 4) {
        QFile file(arguments[3]);
        if (!file.open(QIODevice::ReadOnly)) return 2;
        const auto certificates = QSslCertificate::fromData(file.readAll());
        if (certificates.isEmpty()) return 2;
        auto configuration = QSslConfiguration::defaultConfiguration();
        configuration.setCaCertificates(certificates);
        QSslConfiguration::setDefaultConfiguration(configuration);
    }
    QFile output;
    if (!output.open(STDOUT_FILENO, QIODevice::WriteOnly)) return 2;
    Island::ArtworkFetch fetch;
    QObject::connect(&fetch, &Island::ArtworkFetch::fetched, &app, [&](const QByteArray &bytes, const QByteArray &mime) {
        const bool written = output.write("ok " + mime + "\n") > 0 && output.write(bytes) == bytes.size() && output.flush();
        app.exit(written ? 0 : 4);
    });
    QObject::connect(&fetch, &Island::ArtworkFetch::failed, &app, [&](const QString &code) {
        output.write("error " + code.toLatin1() + "\n");
        output.flush();
        app.exit(0);
    });
    fetch.start(QUrl(arguments[1], QUrl::StrictMode));
    return app.exec();
}
