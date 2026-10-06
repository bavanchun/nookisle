#include "artwork-loader.h"
#include "image-decode.h"
#include "thumbnail-cache.h"
#include <QCryptographicHash>
#include <QBuffer>
#include <QFile>
#include <QImageReader>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTcpServer>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslKey>
#include <QtEndian>
#include <QtTest>
#include <sys/stat.h>

class ArtworkLoaderTest : public QObject {
    Q_OBJECT
    QByteArray previousRuntime;
    QTemporaryDir runtime;
    static QByteArray png(const QSize &size = QSize(64, 64)) {
        QImage image(size, QImage::Format_ARGB32);
        image.fill(QColor(40, 80, 160));
        image.setText("title", "must not survive sanitization");
        QByteArray bytes;
        QBuffer out(&bytes);
        out.open(QIODevice::WriteOnly);
        if (!image.save(&out, "PNG")) return {};
        return bytes;
    }
    static QByteArray response(const QByteArray &bytes, const QByteArray &headers = {}) {
        return "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n" + headers + "\r\n" + bytes;
    }
    static void decode(Island::ArtworkLoader &loader, const QByteArray &bytes, int id = 1) {
        loader.cancel();
        loader.generation_ = QString::number(id);
        loader.cacheKey_ = QByteArray::number(id);
        loader.elapsed_.start();
        loader.deadline_.start();
        loader.publish(bytes, "image/png");
    }
private slots:
    void initTestCase() {
        QVERIFY(runtime.isValid());
        QVERIFY(QFile::setPermissions(runtime.path(), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        previousRuntime = qgetenv("XDG_RUNTIME_DIR");
        qputenv("XDG_RUNTIME_DIR", QFile::encodeName(runtime.path()));
    }
    void cleanupTestCase() {
        if (previousRuntime.isNull()) qunsetenv("XDG_RUNTIME_DIR");
        else qputenv("XDG_RUNTIME_DIR", previousRuntime);
    }
    void rejectsNonPublicDestinations_data() {
        QTest::addColumn<QString>("address");
        for (const auto *address : {"0.1.2.3", "10.20.30.40", "127.0.0.1", "169.254.169.254", "172.16.1.1",
                "192.168.1.1", "100.100.100.200", "192.0.2.1", "198.18.0.1", "224.0.0.1", "255.255.255.255",
                "::", "::1", "::ffff:127.0.0.1", "fc00::1", "fe80::1", "2001:db8::1", "2002:7f00:1::1",
                "64:ff9b::7f00:1", "2001::1", "3fff::1"}) QTest::newRow(address) << QString::fromLatin1(address);
    }
    void rejectsNonPublicDestinations() {
        QFETCH(QString, address);
        QVERIFY(!Island::publicArtworkAddress(QHostAddress(address)));
    }
    void validatesUrlsAndPublicAddresses() {
        QVERIFY(Island::publicArtworkAddress(QHostAddress("1.1.1.1")));
        QVERIFY(Island::publicArtworkAddress(QHostAddress("2606:4700:4700::1111")));
        for (const auto *url : {"http://example.com/a.png", "file:///tmp/a.png", "https://user:pass@example.com/a",
                "https://@example.com/a", "https://127.0.0.1/a", "https://[::1]/a", "https://host.local/a",
                "https://host/a", "https://example.com:0/a"}) QVERIFY2(!Island::validArtworkUrl(QUrl(QString::fromLatin1(url))), url);
        QVERIFY(Island::validArtworkUrl(QUrl("https://images.example.com/cover.png?opaque=secret")));
    }
    void parsesRealHttpBodiesWithHardLimits() {
        const auto bytes = png();
        auto parsed = Island::parseArtworkResponse(response(bytes, "Content-Length: " + QByteArray::number(bytes.size()) + "\r\n"));
        QVERIFY(parsed.error.isEmpty());
        QCOMPARE(parsed.bytes, bytes);
        QCOMPARE(parsed.mime, "image/png");
        auto chunks = QByteArray::number(bytes.size(), 16) + "\r\n" + bytes + "\r\n0\r\n\r\n";
        parsed = Island::parseArtworkResponse(response(chunks, "Transfer-Encoding: chunked\r\n"));
        QVERIFY2(parsed.error.isEmpty(), qPrintable(parsed.error));
        QCOMPARE(parsed.bytes, bytes);
        QVERIFY(!Island::parseArtworkResponse(response(bytes, "Content-Length: 99999999\r\n")).error.isEmpty());
        QVERIFY(!Island::parseArtworkResponse(response(QByteArray(1024 * 1024 + 1, 'a'))).error.isEmpty());
        QVERIFY(!Island::parseArtworkResponse(response("100001\r\n", "Transfer-Encoding: chunked\r\n")).error.isEmpty());
        QVERIFY(!Island::parseArtworkResponse(response(chunks, "Transfer-Encoding: chunked\r\nContent-Length: 1\r\n")).error.isEmpty());
        QVERIFY(!Island::parseArtworkResponse(response(bytes, "Content-Encoding: gzip\r\n")).error.isEmpty());
        QVERIFY(!Island::parseArtworkResponse(response(bytes, "Content-Type: image/jpeg\r\n")).error.isEmpty());
        QVERIFY(!Island::parseArtworkResponse("HTTP/1.1 200 OK\r\n" + QByteArray(16385, 'a')).error.isEmpty());
        parsed = Island::parseArtworkResponse("HTTP/1.1 302 Found\r\nLocation: /next.png\r\n\r\n");
        QVERIFY(parsed.error.isEmpty());
        QCOMPARE(parsed.redirect.toString(), "/next.png");
    }
    void realPngAndJpegDecodeAndStripMetadata() {
        QString error;
        auto image = Island::decodeArtwork(png(QSize(1024, 1024)), "image/png", &error);
        QVERIFY2(!image.isNull(), qPrintable(error));
        QCOMPARE(image.size(), QSize(256, 256));
        QVERIFY(image.textKeys().isEmpty());
        QCOMPARE(image.format(), QImage::Format_ARGB32);
        QVERIFY(image.sizeInBytes() <= 256 * 256 * 4);
        QByteArray jpeg;
        QBuffer out(&jpeg);
        out.open(QIODevice::WriteOnly);
        QVERIFY(image.save(&out, "JPEG"));
        image = Island::decodeArtwork(jpeg, "image/jpeg", &error);
        QVERIFY2(!image.isNull(), qPrintable(error));
        QVERIFY(Island::decodeArtwork(jpeg + jpeg, "image/jpeg", &error).isNull());
        QVERIFY(Island::decodeArtwork(jpeg, "image/png", &error).isNull());
        QVERIFY(Island::decodeArtwork("<svg/>", "image/svg+xml", &error).isNull());
    }
    void rejectsOversizeAnimationAndCorruptionBeforeDecode() {
        QString error;
        QVERIFY(Island::decodeArtwork(png(QSize(2049, 1)), "image/png", &error).isNull());
        QVERIFY(Island::decodeArtwork(png(QSize(2048, 1024)), "image/png", &error).isNull());
        QVERIFY(Island::decodeArtwork(QByteArray(1024 * 1024 + 1, 'a'), "image/png", &error).isNull());
        auto animated = png();
        animated.insert(33, QByteArray::fromHex("000000086163544c000000010000000000000000"));
        QVERIFY(Island::decodeArtwork(animated, "image/png", &error).isNull());
        auto corrupt = png();
        qToBigEndian<quint32>(0xffffffff, reinterpret_cast<uchar *>(corrupt.data() + 8));
        QVERIFY(Island::decodeArtwork(corrupt, "image/png", &error).isNull());
        QVERIFY(Island::decodeArtwork(png().chopped(1), "image/png", &error).isNull());
        QVERIFY(Island::decodeArtwork(png() + 'x', "image/png", &error).isNull());
    }
    void thumbnailProfileAcceptsPhotosButArtworkLimitsStay() {
        QString error;
        const auto photo = png(QSize(3000, 2000));
        QVERIFY(Island::decodeArtwork(photo, "image/png", &error).isNull());
        auto image = Island::decodeThumbnail(photo, "image/png", &error);
        QVERIFY2(!image.isNull(), qPrintable(error));
        QCOMPARE(image.size(), QSize(128, 85));
        QVERIFY(image.textKeys().isEmpty());
        QByteArray jpeg;
        QBuffer out(&jpeg);
        out.open(QIODevice::WriteOnly);
        QVERIFY(QImage(QSize(4000, 3000), QImage::Format_RGB32).save(&out, "JPEG"));
        QVERIFY(jpeg.size() > 1024 * 1024 || Island::decodeArtwork(jpeg, "image/jpeg", &error).isNull());
        image = Island::decodeThumbnail(jpeg, "image/jpeg", &error);
        QVERIFY2(!image.isNull(), qPrintable(error));
        QCOMPARE(image.size(), QSize(128, 96));
        QVERIFY(Island::decodeThumbnail(png(QSize(8193, 1)), "image/png", &error).isNull());
        QVERIFY(Island::decodeThumbnail(png(QSize(4200, 4200)), "image/png", &error).isNull());
        QVERIFY(Island::decodeThumbnail(QByteArray(Island::ThumbnailInputLimit + 1, 'a'), "image/png", &error).isNull());
        auto corrupt = png();
        qToBigEndian<quint32>(0xffffffff, reinterpret_cast<uchar *>(corrupt.data() + 8));
        QVERIFY(Island::decodeThumbnail(corrupt, "image/png", &error).isNull());
    }
    void thumbnailHonoursJpegOrientationWithoutChangingArtwork() {
        QImage source(QSize(3, 2), QImage::Format_RGB32);
        source.fill(Qt::red);
        QByteArray jpeg;
        QBuffer out(&jpeg);
        out.open(QIODevice::WriteOnly);
        QVERIFY(source.save(&out, "JPEG"));
        // EXIF/TIFF IFD0 orientation 6 means rotate the displayed image 90 degrees.
        const QByteArray exif = QByteArray::fromHex(
            "ffe1002245786966000049492a0008000000010012010300010000000600000000000000");
        jpeg.insert(2, exif);
        QString error;
        const auto thumbnail = Island::decodeThumbnail(jpeg, "image/jpeg", &error);
        QVERIFY2(!thumbnail.isNull(), qPrintable(error));
        QCOMPARE(thumbnail.size(), QSize(2, 3));
        const auto artwork = Island::decodeArtwork(jpeg, "image/jpeg", &error);
        QVERIFY2(!artwork.isNull(), qPrintable(error));
        QCOMPARE(artwork.size(), QSize(3, 2));
    }
    void thumbnailServiceWritesFreedesktopEntriesThroughTheDecoder() {
        QTemporaryDir files, cache;
        QVERIFY(files.isValid() && cache.isValid());
        auto write = [&](const QString &name, const QByteArray &bytes) {
            QFile file(files.filePath(name));
            if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size()) return QString();
            return QUrl::fromLocalFile(file.fileName()).toString(QUrl::FullyEncoded);
        };
        auto md5 = [](const QString &uri) {
            return QString::fromLatin1(QCryptographicHash::hash(uri.toUtf8(), QCryptographicHash::Md5).toHex()) + ".png";
        };
        const auto photo = write("holiday photo.png", png(QSize(640, 480)));
        auto corrupt = png();
        corrupt.chop(20);
        const auto broken = write("broken.png", corrupt);
        const auto text = write("notes.txt", "plain text");
        QVERIFY(!photo.isEmpty() && !broken.isEmpty() && !text.isEmpty());
        // The cache home does not exist yet; the service creates it.
        Island::ThumbnailService service(nullptr, DECODER_PATH, cache.path() + "/fresh-cache/thumbnails");
        QSignalSpy finished(&service, &Island::ThumbnailService::finished);
        service.request("photo", photo, md5(photo));
        service.request("broken", broken, md5(broken));
        service.request("text", text, md5(text));
        service.request("folder", QUrl::fromLocalFile(files.path()).toString(), md5("folder"));
        service.request("missing", QUrl::fromLocalFile(files.filePath("gone.png")).toString(), md5("gone"));
        service.request("name", photo, "../escape.png");
        service.request("remote", "https://example.com/a.png", md5("remote"));
        QTRY_COMPARE_WITH_TIMEOUT(finished.size(), 7, 15000);
        QHash<QString, QString> status;
        QString stored;
        for (const auto &call : finished) {
            QVERIFY2(!status.contains(call[0].toString()), "every request is answered exactly once");
            status[call[0].toString()] = call[1].toString();
            if (call[0].toString() == "photo") stored = call[2].toString();
            else QVERIFY(call[2].toString().isEmpty());
        }
        QCOMPARE(status["photo"], "ready");
        QCOMPARE(status["broken"], "failed");
        QCOMPARE(status["text"], "unsupported");
        QCOMPARE(status["folder"], "unsupported");
        QCOMPARE(status["missing"], "unsupported");
        QCOMPARE(status["name"], "invalid");
        QCOMPARE(status["remote"], "invalid");
        QCOMPARE(stored, cache.path() + "/fresh-cache/thumbnails/normal/" + md5(photo));
        QImageReader reader(stored);
        const auto image = reader.read();
        QCOMPARE(image.size(), QSize(128, 96));
        QCOMPARE(image.text("Thumb::URI"), photo);
        QCOMPARE(image.text("Thumb::MTime"), QString::number(QFileInfo(files.filePath("holiday photo.png")).lastModified().toSecsSinceEpoch()));
        struct stat st {};
        QVERIFY(!::stat(QFile::encodeName(stored).constData(), &st));
        QCOMPARE(st.st_mode & 0777, 0600u);
        QVERIFY(!::stat(QFile::encodeName(cache.path() + "/fresh-cache/thumbnails/normal").constData(), &st));
        QCOMPARE(st.st_mode & 0777, 0700u);
        QCOMPARE(QDir(cache.path() + "/fresh-cache/thumbnails/normal").entryList(QDir::Files), QStringList{md5(photo)});
    }
    // A large shelved file streams straight from disk into the decoder child:
    // the service neither reads it into memory nor blocks on it.
    void largeThumbnailSourceNeverEntersTheService() {
        QTemporaryDir files, cache;
        QVERIFY(files.isValid() && cache.isValid());
        QFile file(files.filePath("large.png"));
        QVERIFY(file.open(QIODevice::WriteOnly));
        QByteArray chunk(1024 * 1024, '\0');
        QVERIFY(file.write(QByteArray::fromHex("89504e470d0a1a0a")) == 8);
        for (int i = 0; i < 30; ++i) QVERIFY(file.write(chunk) == chunk.size());
        file.close();
        chunk = QByteArray();
        auto peakKiB = [] {
            QFile status("/proc/self/status");
            if (!status.open(QIODevice::ReadOnly)) return -1LL;
            for (const auto &line : status.readAll().split('\n'))
                if (line.startsWith("VmHWM:")) return line.mid(6).trimmed().split(' ').first().toLongLong();
            return -1LL;
        };
        const auto before = peakKiB();
        QVERIFY(before > 0);
        const auto uri = QUrl::fromLocalFile(file.fileName()).toString(QUrl::FullyEncoded);
        Island::ThumbnailService service(nullptr, DECODER_PATH, cache.path());
        QSignalSpy finished(&service, &Island::ThumbnailService::finished);
        service.request("large", uri,
            QString::fromLatin1(QCryptographicHash::hash(uri.toUtf8(), QCryptographicHash::Md5).toHex()) + ".png");
        QTRY_COMPARE_WITH_TIMEOUT(finished.size(), 1, 15000);
        QCOMPARE(finished[0][1].toString(), "failed");
        const auto growth = peakKiB() - before;
        QVERIFY2(growth < 8 * 1024, QByteArray::number(growth) + " KiB");
    }
    void thumbnailCacheRequiresMatchingUriAndModificationTime() {
        QTemporaryDir files, cache;
        QVERIFY(files.isValid() && cache.isValid());
        QFile source(files.filePath("photo.png"));
        QVERIFY(source.open(QIODevice::WriteOnly));
        QVERIFY(source.write(png(QSize(80, 40))) > 0);
        source.close();
        const auto uri = QUrl::fromLocalFile(source.fileName()).toString(QUrl::FullyEncoded);
        const auto name = QString::fromLatin1(QCryptographicHash::hash(uri.toUtf8(), QCryptographicHash::Md5).toHex()) + ".png";
        const auto root = cache.path() + "/thumbnails";
        Island::ThumbnailService first(nullptr, DECODER_PATH, root);
        QSignalSpy firstResult(&first, &Island::ThumbnailService::finished);
        first.request("first", uri, name);
        QTRY_COMPARE_WITH_TIMEOUT(firstResult.size(), 1, 10000);
        QCOMPARE(firstResult[0][1].toString(), "ready");
        const auto cached = firstResult[0][2].toString();

        // The freedesktop cache is shared with other applications, so even a
        // valid hit is parsed only in the decoder child: without the child,
        // no cache entry is ever accepted.
        Island::ThumbnailService hit(nullptr, "/missing-thumbnail-decoder", root);
        QSignalSpy hitResult(&hit, &Island::ThumbnailService::finished);
        hit.request("hit", uri, name);
        QTRY_COMPARE_WITH_TIMEOUT(hitResult.size(), 1, 10000);
        QCOMPARE(hitResult[0][1].toString(), "failed");
        Island::ThumbnailService checkedHit(nullptr, DECODER_PATH, root);
        QSignalSpy checkedResult(&checkedHit, &Island::ThumbnailService::finished);
        checkedHit.request("checked", uri, name);
        QTRY_COMPARE_WITH_TIMEOUT(checkedResult.size(), 1, 10000);
        QCOMPARE(checkedResult[0][1].toString(), "ready");
        QCOMPARE(checkedResult[0][2].toString(), cached);

        // Replacing the image at the same URI invalidates its old thumbnail.
        const auto priorMtime = QFileInfo(source.fileName()).lastModified().toSecsSinceEpoch();
        QVERIFY(source.open(QIODevice::WriteOnly | QIODevice::Truncate));
        QVERIFY(source.write(png(QSize(40, 80))) > 0);
        source.close();
        QVERIFY(source.open(QIODevice::ReadOnly));
        QVERIFY(source.setFileTime(QDateTime::currentDateTimeUtc().addSecs(10), QFileDevice::FileModificationTime));
        source.close();
        QVERIFY(QFileInfo(source.fileName()).lastModified().toSecsSinceEpoch() != priorMtime);
        Island::ThumbnailService changed(nullptr, DECODER_PATH, root);
        QSignalSpy changedResult(&changed, &Island::ThumbnailService::finished);
        changed.request("changed", uri, name);
        QTRY_COMPARE_WITH_TIMEOUT(changedResult.size(), 1, 10000);
        QCOMPARE(changedResult[0][1].toString(), "ready");
        QImageReader fresh(cached);
        const auto freshImage = fresh.read();
        QCOMPARE(freshImage.size(), QSize(40, 80));
        QCOMPARE(freshImage.text("Thumb::MTime"), QString::number(QFileInfo(source.fileName()).lastModified().toSecsSinceEpoch()));

        // A cache file with the right name and mtime but a different URI is invalid.
        QImage forged(QSize(10, 10), QImage::Format_ARGB32);
        forged.fill(Qt::green);
        forged.setText("Thumb::URI", "file:///someone-else.png");
        forged.setText("Thumb::MTime", QString::number(QFileInfo(source.fileName()).lastModified().toSecsSinceEpoch()));
        QVERIFY(forged.save(cached, "PNG"));
        Island::ThumbnailService wrongUri(nullptr, DECODER_PATH, root);
        QSignalSpy wrongResult(&wrongUri, &Island::ThumbnailService::finished);
        wrongUri.request("wrong", uri, name);
        QTRY_COMPARE_WITH_TIMEOUT(wrongResult.size(), 1, 10000);
        QCOMPARE(wrongResult[0][1].toString(), "ready");
        QImageReader repaired(cached);
        const auto repairedImage = repaired.read();
        QCOMPARE(repairedImage.size(), QSize(40, 80));
        QCOMPARE(repairedImage.text("Thumb::URI"), uri);

        // A large-cache entry written by another application is checked in
        // the child too, and what the UI gets is the child's own re-encoded
        // copy in our normal cache: scaled to 128 px, carrying only the two
        // thumbnail keys, never the third-party file itself.
        QVERIFY(QDir().mkpath(root + "/large"));
        const auto large = root + "/large/" + name;
        QVERIFY(QFile::remove(cached));
        QImage foreign(QSize(200, 100), QImage::Format_ARGB32);
        foreign.fill(Qt::blue);
        foreign.setText("Thumb::URI", uri);
        foreign.setText("Thumb::MTime", QString::number(QFileInfo(source.fileName()).lastModified().toSecsSinceEpoch()));
        foreign.setText("Software", "someone else's thumbnailer");
        QVERIFY(foreign.save(large, "PNG"));
        Island::ThumbnailService noChild(nullptr, "/missing-thumbnail-decoder", root);
        QSignalSpy noChildResult(&noChild, &Island::ThumbnailService::finished);
        noChild.request("large-no-child", uri, name);
        QTRY_COMPARE_WITH_TIMEOUT(noChildResult.size(), 1, 10000);
        QCOMPARE(noChildResult[0][1].toString(), "failed");
        Island::ThumbnailService largeHit(nullptr, DECODER_PATH, root);
        QSignalSpy largeResult(&largeHit, &Island::ThumbnailService::finished);
        largeHit.request("large", uri, name);
        QTRY_COMPARE_WITH_TIMEOUT(largeResult.size(), 1, 10000);
        QCOMPARE(largeResult[0][1].toString(), "ready");
        QCOMPARE(largeResult[0][2].toString(), cached);
        QImageReader served(cached);
        const auto servedImage = served.read();
        QCOMPARE(servedImage.size(), QSize(128, 64));
        QCOMPARE(servedImage.pixelColor(10, 10), QColor(Qt::blue));
        QCOMPARE(servedImage.text("Thumb::URI"), uri);
        QCOMPARE(servedImage.text("Software"), QString());
    }
    // The child's cached-entry mode: bounded PNG input, the two thumbnail
    // keys kept and nothing else, at most 128 px.
    // The child owns every thumbnail image step: it stamps a fresh thumbnail
    // with the file's keys, and refuses a cache entry whose keys differ.
    void decoderChildStampsAndChecksThumbnailKeys() {
        auto run = [](const QStringList &arguments, const QByteArray &input, QByteArray *output) {
            QProcess child;
            child.start(DECODER_PATH, arguments);
            child.write(input);
            child.closeWriteChannel();
            if (!child.waitForFinished(5000)) return -1;
            *output = child.readAllStandardOutput();
            return child.exitCode();
        };
        QByteArray fresh;
        QCOMPARE(run({"image/png", "--thumbnail", "file:///a.png", "42"}, png(QSize(300, 150)), &fresh), 0);
        QImage image;
        QVERIFY(image.loadFromData(fresh, "PNG"));
        QCOMPARE(image.size(), QSize(128, 64));
        QCOMPARE(image.text("Thumb::URI"), "file:///a.png");
        QCOMPARE(image.text("Thumb::MTime"), "42");
        QCOMPARE(Island::pngSize(fresh), QSize(128, 64));
        QByteArray again;
        QCOMPARE(run({"image/png", "--cached-thumbnail", "file:///a.png", "42"}, fresh, &again), 0);
        QVERIFY(image.loadFromData(again, "PNG"));
        QCOMPARE(image.text("Thumb::URI"), "file:///a.png");
        QByteArray stale;
        QCOMPARE(run({"image/png", "--cached-thumbnail", "file:///a.png", "43"}, fresh, &stale), 3);
        QVERIFY(stale.isEmpty());
        QCOMPARE(run({"image/png", "--cached-thumbnail", "file:///b.png", "42"}, fresh, &stale), 3);
        QCOMPARE(run({"image/png", "--thumbnail", "file:///a.png", "not-a-time"}, png(), &stale), 2);
    }
    void cachedThumbnailSanitizer() {
        QImage entry(QSize(256, 128), QImage::Format_ARGB32);
        entry.fill(Qt::red);
        entry.setText("Thumb::URI", "file:///a.png");
        entry.setText("Thumb::MTime", "42");
        entry.setText("Comment", "extra");
        QByteArray bytes;
        QBuffer buffer(&bytes);
        buffer.open(QIODevice::WriteOnly);
        QVERIFY(entry.save(&buffer, "PNG"));
        QString error;
        const auto clean = Island::sanitizeCachedThumbnail(bytes, &error);
        QVERIFY2(!clean.isNull(), qPrintable(error));
        QCOMPARE(clean.size(), QSize(128, 64));
        QCOMPARE(clean.text("Thumb::URI"), "file:///a.png");
        QCOMPARE(clean.text("Thumb::MTime"), "42");
        QCOMPARE(clean.textKeys().size(), 2);
        QImage tooLarge(QSize(300, 10), QImage::Format_ARGB32);
        tooLarge.fill(Qt::red);
        QByteArray largeBytes;
        QBuffer largeBuffer(&largeBytes);
        largeBuffer.open(QIODevice::WriteOnly);
        QVERIFY(tooLarge.save(&largeBuffer, "PNG"));
        QVERIFY(Island::sanitizeCachedThumbnail(largeBytes, &error).isNull());
        QVERIFY(Island::sanitizeCachedThumbnail("not a png", &error).isNull());
        QVERIFY(Island::sanitizeCachedThumbnail(QByteArray(1024 * 1024 + 1, 'x'), &error).isNull());
    }
    void thumbnailQueueIsBounded() {
        QTemporaryDir files, cache;
        QFile file(files.filePath("a.png"));
        QVERIFY(file.open(QIODevice::WriteOnly) && file.write(png()) > 0);
        file.close();
        const auto uri = QUrl::fromLocalFile(file.fileName()).toString();
        Island::ThumbnailService service(nullptr, DECODER_PATH, cache.path());
        QSignalSpy finished(&service, &Island::ThumbnailService::finished);
        const auto name = QString(32, 'a') + ".png";
        // The first request occupies the decoder, the next QueueLimit wait,
        // and one more is refused at once.
        for (int i = 0; i <= Island::ThumbnailService::QueueLimit + 1; ++i)
            service.request(QString::number(i), uri, name);
        QCOMPARE(finished.size(), 1);
        QCOMPARE(finished[0][0].toString(), QString::number(Island::ThumbnailService::QueueLimit + 1));
        QCOMPARE(finished[0][1].toString(), "busy");
        QTRY_COMPARE_WITH_TIMEOUT(finished.size(), Island::ThumbnailService::QueueLimit + 2, 20000);
        for (int i = 1; i < finished.size(); ++i) QCOMPARE(finished[i][1].toString(), "ready");
    }
    // The fetch runs in its child: the loader reads its status line and body,
    // hands the body to the decoder, and never loads a TLS backend itself.
    void fetchRunsInAChildAndTlsNeverLoadsHere() {
        QTemporaryDir fixture;
        QVERIFY(fixture.isValid());
        QFile body(fixture.filePath("body.png"));
        QVERIFY(body.open(QIODevice::WriteOnly));
        body.write(png(QSize(40, 30)));
        body.close();
        auto script = [&](const QString &name, const QByteArray &text) {
            QFile file(fixture.filePath(name));
            if (!file.open(QIODevice::WriteOnly)) return QString();
            file.write("#!/bin/sh\n" + text);
            file.close();
            file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
            return file.fileName();
        };
        const auto good = script("fetch-ok", "printf 'ok image/png\\n'; cat '" + body.fileName().toUtf8() + "'\n");
        const auto refused = script("fetch-error", "printf 'error art-tls\\n'\n");
        const auto garbage = script("fetch-garbage", "printf 'ok text/html\\n<html>'\n");
        const auto crashed = script("fetch-crash", "kill -9 $$\n");
        struct Case { QString path, code; };
        for (const auto &item : {Case{good, {}}, Case{refused, "art-tls"}, Case{garbage, "art-fetch"}, Case{crashed, "art-fetch"}}) {
            Island::ArtworkLoader loader(nullptr, DECODER_PATH, item.path);
            QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
            loader.request(QUrl("https://images.example.com/cover.png"), "child");
            QVERIFY(loader.fetch_);
            QTRY_VERIFY_WITH_TIMEOUT(!ready.isEmpty() || !failed.isEmpty(), 6000);
            if (item.code.isEmpty()) {
                QVERIFY2(failed.isEmpty(), failed.isEmpty() ? "" : qPrintable(failed[0][1].toString()));
                QCOMPARE(QImageReader(QUrl(ready[0][1].toString()).toLocalFile()).size(), QSize(40, 30));
            } else {
                QCOMPARE(failed[0][1].toString(), item.code);
            }
            QVERIFY(!loader.fetch_);
        }
        QFile maps("/proc/self/maps");
        QVERIFY(maps.open(QIODevice::ReadOnly));
        QVERIFY(!maps.readAll().contains("libqopensslbackend"));
    }
    void privateUrlNeverStartsTransport() {
        Island::ArtworkLoader loader(nullptr, DECODER_PATH);
        QSignalSpy failed(&loader, &Island::ArtworkLoader::failed);
        loader.request(QUrl("https://127.0.0.1/private?secret=not-logged"), "private");
        QCOMPARE(failed.size(), 1);
        QCOMPARE(failed[0][1].toString(), "art-url-policy");
        QVERIFY(!loader.fetch_);
        QVERIFY(!loader.busy());
    }
    // A player's own cover file reads locally and decodes in the child,
    // with no DNS lookup or socket, and a full-size scan beyond the remote
    // artwork's pixel limit still produces a 256 px cover.
    void localCoverDecodesWithoutNetwork() {
        QTemporaryDir files;
        QVERIFY(files.isValid());
        const auto path = files.filePath("cover.png");
        QFile cover(path);
        QVERIFY(cover.open(QIODevice::WriteOnly));
        QVERIFY(cover.write(png(QSize(1500, 1500))) > 0);
        cover.close();
        QVERIFY(Island::localArtworkUrl(QUrl::fromLocalFile(path)));
        Island::ArtworkLoader loader(nullptr, DECODER_PATH);
        QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
        loader.request(QUrl::fromLocalFile(path), "local");
        QVERIFY(!loader.fetch_);
        QTRY_VERIFY_WITH_TIMEOUT(!ready.isEmpty() || !failed.isEmpty(), 6000);
        QVERIFY2(failed.isEmpty(), failed.isEmpty() ? "" : qPrintable(failed[0][1].toString()));
        const auto published = QUrl(ready[0][1].toString()).toLocalFile();
        QVERIFY(published != path);
        QImageReader image(published);
        QCOMPARE(image.size(), QSize(256, 256));
        QVERIFY(image.read().textKeys().isEmpty());
        // The same path with new contents is a new cover, not a cache hit.
        QTest::qWait(20);
        QVERIFY(cover.open(QIODevice::WriteOnly | QIODevice::Truncate));
        QVERIFY(cover.write(png(QSize(300, 200))) > 0);
        cover.close();
        loader.request(QUrl::fromLocalFile(path), "local-2");
        QTRY_COMPARE_WITH_TIMEOUT(ready.size(), 2, 6000);
        QCOMPARE(QImageReader(QUrl(ready[1][1].toString()).toLocalFile()).size(), QSize(256, 170));
    }
    void localCoverRefusesUnsafeInputs_data() {
        QTest::addColumn<QString>("kind");
        QTest::addColumn<QString>("code");
        QTest::newRow("directory") << "directory" << "art-local-file";
        QTest::newRow("device") << "device" << "art-local-file";
        QTest::newRow("text") << "text" << "art-mime";
        QTest::newRow("missing") << "missing" << "art-local-read";
    }
    void localCoverRefusesUnsafeInputs() {
        QFETCH(QString, kind);
        QFETCH(QString, code);
        QTemporaryDir files;
        QString path = kind == "directory" ? files.path() : kind == "device" ? QString("/dev/zero")
            : files.filePath(kind == "text" ? "notes.png" : "absent.png");
        if (kind == "text") {
            QFile text(path);
            QVERIFY(text.open(QIODevice::WriteOnly));
            text.write("not an image");
        }
        Island::ArtworkLoader loader(nullptr, DECODER_PATH);
        QSignalSpy failed(&loader, &Island::ArtworkLoader::failed);
        loader.request(QUrl::fromLocalFile(path), "unsafe");
        QCOMPARE(failed.size(), 1);
        QCOMPARE(failed[0][1].toString(), code);
        QVERIFY(!loader.decoder_);
        QVERIFY(!loader.busy());
    }
    void localArtworkUrlIsStrict() {
        QVERIFY(Island::localArtworkUrl(QUrl("file:///tmp/cover.png")));
        QVERIFY(Island::localArtworkUrl(QUrl("file://localhost/tmp/cover.png")));
        QVERIFY(!Island::localArtworkUrl(QUrl("file://server/share/cover.png")));
        QVERIFY(!Island::localArtworkUrl(QUrl("file:///tmp/cover.png?size=large")));
        QVERIFY(!Island::localArtworkUrl(QUrl("https://art.example.test/cover.png")));
        QVERIFY(!Island::localArtworkUrl(QUrl("cover.png")));
    }
    void realChildPublishesPrivateAtomicFilesAndCleansUp_data() {
        QTest::addColumn<int>("attempt");
        // Repeated real maximum-pixel PNG scaling exercises decoder startup and
        // resource caps, including independent image-scaling worker pools.
        for (int attempt = 0; attempt < 20; ++attempt)
            QTest::newRow(qPrintable(QString::number(attempt))) << attempt;
    }
    void realChildPublishesPrivateAtomicFilesAndCleansUp() {
        QFETCH(int, attempt);
        Q_UNUSED(attempt);
        QString directory;
        {
            Island::ArtworkLoader loader(nullptr, DECODER_PATH);
            QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
            decode(loader, png(QSize(1024, 1024)));
            QTRY_VERIFY_WITH_TIMEOUT(!ready.isEmpty() || !failed.isEmpty(), 6000);
            QVERIFY2(failed.isEmpty(), failed.isEmpty() ? "" : qPrintable(failed[0][1].toString()));
            QCOMPARE(ready[0][0].toString(), "1");
            const auto path = QUrl(ready[0][1].toString()).toLocalFile();
            directory = loader.directory_;
            struct stat st {};
            QVERIFY(!::lstat(QFile::encodeName(directory).constData(), &st));
            QCOMPARE(st.st_mode & 0777, mode_t(0700));
            QVERIFY(!::lstat(QFile::encodeName(path).constData(), &st));
            QCOMPARE(st.st_mode & 0777, mode_t(0600));
            QVERIFY(S_ISREG(st.st_mode));
            QImageReader image(path);
            QCOMPARE(image.size(), QSize(256, 256));
            QVERIFY(image.read().textKeys().isEmpty());
            QCOMPARE(QDir(directory).entryList({"*.tmp"}, QDir::Files).size(), 0);
            QVERIFY(!loader.decoder_);
            QVERIFY(!loader.deadline_.isActive());
        }
        QVERIFY(!QFile::exists(directory));
    }
    // The helper publishes the decoder's PNG as it is and keeps only its
    // pixel count: the header is checked, the pixels never decoded here.
    void publishedArtworkIsTheDecoderOutput() {
        Island::ArtworkLoader loader(nullptr, DECODER_PATH);
        QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
        const auto input = png(QSize(320, 240));
        decode(loader, input);
        QTRY_VERIFY_WITH_TIMEOUT(!ready.isEmpty() || !failed.isEmpty(), 6000);
        QVERIFY(failed.isEmpty());
        QProcess child;
        child.start(DECODER_PATH, {"image/png"});
        child.write(input);
        child.closeWriteChannel();
        QVERIFY(child.waitForFinished(5000));
        QFile published(QUrl(ready[0][1].toString()).toLocalFile());
        QVERIFY(published.open(QIODevice::ReadOnly));
        QCOMPARE(published.readAll(), child.readAllStandardOutput());
        QCOMPARE(loader.cache_.size(), 1);
        QCOMPARE(loader.cache_.begin()->pixelBytes, 256LL * 192 * 4);
        QCOMPARE(Island::decodedPngSize(input), QSize());
        auto header = png(QSize(16, 8));
        QCOMPARE(Island::decodedPngSize(header), QSize(16, 8));
        header[16 + 2] = 0x10;
        QCOMPARE(Island::decodedPngSize(header), QSize());
        QCOMPARE(Island::decodedPngSize("not a png at all, but long enough to read"), QSize());
    }
    void cacheQuotaRetentionAndExpiryUseOnlyOwnedFiles() {
        Island::ArtworkLoader loader(nullptr, DECODER_PATH);
        QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
        QStringList retained;
        for (int i = 1; i <= 12; ++i) {
            ready.clear();
            decode(loader, png(), i);
            QTRY_VERIFY_WITH_TIMEOUT(!ready.isEmpty() || !failed.isEmpty(), 6000);
            QVERIFY2(failed.isEmpty(), failed.isEmpty() ? "" : qPrintable(QString("image %1: %2").arg(i).arg(failed[0][1].toString())));
            const auto path = ready[0][1].toString();
            retained.prepend(path);
            retained = retained.mid(0, 2);
            loader.retain(retained);
            QVERIFY(loader.cache_.size() <= 8);
            qint64 memory = 0, files = 0;
            int references = 0;
            for (const auto &entry : loader.cache_) {
                memory += entry.pixelBytes; files += entry.bytes;
                if (entry.referenced) ++references;
            }
            QVERIFY(memory <= 4 * 1024 * 1024);
            QVERIFY(files <= 8 * 1024 * 1024);
            QVERIFY(references <= 2);
        }
        QFile sentinel(runtime.filePath("unowned.txt"));
        QVERIFY(sentinel.open(QIODevice::WriteOnly));
        sentinel.write("keep"); sentinel.close();
        loader.retain({QUrl::fromLocalFile(sentinel.fileName()).toString()});
        for (auto &entry : loader.cache_) entry.released = -300001;
        loader.evict();
        QVERIFY(loader.cache_.isEmpty());
        QVERIFY(QFile::exists(sentinel.fileName()));
        QVERIFY(!loader.expiry_.isActive());
    }
    void canceledChildCannotPublishAndDeadlineStopsChild() {
        Island::ArtworkLoader loader(nullptr, DECODER_PATH);
        QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
        decode(loader, png(QSize(1024, 1024)));
        loader.cancel();
        QTRY_VERIFY_WITH_TIMEOUT(!loader.decoder_, 3000);
        QCOMPARE(ready.size(), 0);
        QCOMPARE(failed.size(), 0);
        // A real child waits on stdin: timeout must terminate it, not merely
        // ignore its eventual completion. Production timeout is exactly 5s.
        loader.generation_ = "deadline";
        QCOMPARE(loader.deadline_.interval(), 5000);
        auto *process = new QProcess(&loader);
        loader.decoder_ = process;
        process->start(DECODER_PATH, {"image/png"});
        QVERIFY(process->waitForStarted(1000));
        loader.deadline_.start(10);
        QTRY_COMPARE_WITH_TIMEOUT(failed.size(), 1, 1000);
        QCOMPARE(failed[0][1].toString(), "art-timeout");
        QTRY_VERIFY_WITH_TIMEOUT(!loader.decoder_, 3000);
        QCOMPARE(ready.size(), 0);
    }
};
class ArtworkTlsServer : public QTcpServer {
public:
    QSslCertificate certificate;
    QSslKey key;
    QList<QByteArray> requests;
    std::function<QByteArray(const QByteArray &)> reply;
    void incomingConnection(qintptr descriptor) override {
        auto *socket = new QSslSocket(this);
        if (!socket->setSocketDescriptor(descriptor)) { socket->deleteLater(); return; }
        socket->setLocalCertificate(certificate);
        socket->setPrivateKey(key);
        socket->setPeerVerifyMode(QSslSocket::VerifyNone);
        socket->setReadBufferSize(8192);
        connect(socket, &QSslSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QSslSocket::readyRead, this, [this, socket] {
            auto request = socket->property("request").toByteArray() + socket->readAll();
            if (request.size() > 8192) { socket->abort(); return; }
            socket->setProperty("request", request);
            if (!request.contains("\r\n\r\n") || socket->property("answered").toBool()) return;
            socket->setProperty("answered", true);
            requests.append(request);
            const auto response = reply(request);
            if (response.isEmpty()) return;
            socket->write(response);
            socket->disconnectFromHost();
        });
        socket->startServerEncryption();
    }
};

// Runs only through --network-fixture in a private network namespace.
// Production address policy remains unchanged; no private-address exception.
class ArtworkNetworkTest : public QObject {
    Q_OBJECT
    QTemporaryDir runtime;
    QSslCertificate certificate;
    QSslKey key;
    QByteArray bytes;
    void prepare(ArtworkTlsServer &server) {
        server.certificate = certificate;
        server.key = key;
        QVERIFY(server.listen(QHostAddress::AnyIPv4));
    }
    // The fetch child trusts only the fixture's CA, passed on its command line.
    void trust(Island::ArtworkLoader &loader) { loader.fetchArguments_ = {"--ca-file", runtime.filePath("cert.pem")}; }
    static QUrl url(const ArtworkTlsServer &server, const QString &path = "/cover.png", const QString &host = "1.1.1.1") {
        return QUrl("https://" + host + ':' + QString::number(server.serverPort()) + path);
    }
    QByteArray imageResponse() const {
        return "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: "
            + QByteArray::number(bytes.size()) + "\r\n\r\n" + bytes;
    }
private slots:
    void initTestCase() {
        QVERIFY(runtime.isValid());
        QVERIFY(QFile::setPermissions(runtime.path(), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        qputenv("XDG_RUNTIME_DIR", QFile::encodeName(runtime.path()));
        QTcpServer probe;
        QVERIFY2(probe.listen(QHostAddress("1.1.1.1")), "requires namespace with isolated test public address");
        probe.close();
        QVERIFY(probe.listen(QHostAddress("1.1.1.2")));
        QProcess openssl;
        openssl.start("openssl", {"req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=1.1.1.1", "-addext", "subjectAltName=IP:1.1.1.1",
            "-keyout", runtime.filePath("key.pem"), "-out", runtime.filePath("cert.pem")});
        QVERIFY(openssl.waitForFinished(10000));
        QCOMPARE(openssl.exitCode(), 0);
        QFile certFile(runtime.filePath("cert.pem")), keyFile(runtime.filePath("key.pem"));
        QVERIFY(certFile.open(QIODevice::ReadOnly));
        QVERIFY(keyFile.open(QIODevice::ReadOnly));
        certificate = QSslCertificate(certFile.readAll());
        key = QSslKey(keyFile.readAll(), QSsl::Rsa);
        QVERIFY(!certificate.isNull() && !key.isNull());
        QImage image(1024, 1024, QImage::Format_ARGB32);
        image.fill(Qt::darkBlue);
        QBuffer output(&bytes);
        output.open(QIODevice::WriteOnly);
        QVERIFY(image.save(&output, "PNG"));
    }
    void realHttpsHasNoAmbientCredentialsAndSanitizes() {
        ArtworkTlsServer server;
        prepare(server);
        server.reply = [this](const QByteArray &) { return imageResponse(); };
        Island::ArtworkLoader loader(nullptr, DECODER_PATH, FETCH_PATH);
        trust(loader);
        QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
        loader.request(url(server, "/cover.png?opaque=not-logged"), "https-generation");
        QTRY_VERIFY_WITH_TIMEOUT(!ready.isEmpty() || !failed.isEmpty(), 6000);
        QVERIFY2(failed.isEmpty(), failed.isEmpty() ? "" : qPrintable(failed[0][1].toString()));
        QCOMPARE(server.requests.size(), 1);
        const auto request = server.requests[0].toLower();
        QVERIFY(request.startsWith("get /cover.png?opaque=not-logged http/1.1\r\n"));
        for (const auto *header : {"cookie:", "referer:", "authorization:", "proxy-authorization:"}) QVERIFY(!request.contains(header));
        const auto path = QUrl(ready[0][1].toString()).toLocalFile();
        QCOMPARE(QImageReader(path).size(), QSize(256, 256));
        QVERIFY(path.startsWith(runtime.path()));
    }
    void twoRedirectsSucceedAndThirdIsRefused() {
        ArtworkTlsServer server;
        prepare(server);
        int redirects = 2;
        server.reply = [this, &server, &redirects](const QByteArray &) {
            return server.requests.size() <= redirects
                ? QByteArray("HTTP/1.1 302 Found\r\nLocation: /redirect-") + QByteArray::number(server.requests.size()) + "\r\n\r\n"
                : imageResponse();
        };
        Island::ArtworkLoader loader(nullptr, DECODER_PATH, FETCH_PATH);
        trust(loader);
        QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
        loader.request(url(server), "two");
        QTRY_VERIFY_WITH_TIMEOUT(!ready.isEmpty() || !failed.isEmpty(), 6000);
        QVERIFY(failed.isEmpty());
        QCOMPARE(ready.size(), 1);
        QCOMPARE(server.requests.size(), 3);
        loader.clear(); ready.clear(); server.requests.clear(); redirects = 3;
        loader.request(url(server), "three");
        QTRY_VERIFY_WITH_TIMEOUT(!failed.isEmpty(), 6000);
        QCOMPARE(failed[0][1].toString(), "art-redirect-limit");
        QCOMPARE(ready.size(), 0);
        QCOMPARE(server.requests.size(), 3);
    }
    void redirectPrivateDowngradeAndCertificateMismatchFailClosed() {
        ArtworkTlsServer server;
        prepare(server);
        QString destination;
        server.reply = [&destination](const QByteArray &) {
            return "HTTP/1.1 302 Found\r\nLocation: " + destination.toUtf8() + "\r\n\r\n";
        };
        Island::ArtworkLoader loader(nullptr, DECODER_PATH, FETCH_PATH);
        trust(loader);
        QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
        for (const auto *target : {"https://127.0.0.1/private", "https://10.0.0.1/private", "http://1.1.1.1/plain"}) {
            failed.clear(); server.requests.clear(); destination = QString::fromLatin1(target);
            loader.request(url(server), "bad-redirect");
            QTRY_VERIFY_WITH_TIMEOUT(!failed.isEmpty(), 6000);
            QCOMPARE(failed[0][1].toString(), "art-url-policy");
            QCOMPARE(server.requests.size(), 1);
        }
        failed.clear(); server.requests.clear();
        loader.request(url(server, "/wrong-certificate", "1.1.1.2"), "wrong-certificate");
        QTRY_VERIFY_WITH_TIMEOUT(!failed.isEmpty(), 6000);
        QCOMPARE(failed[0][1].toString(), "art-tls");
        QCOMPARE(server.requests.size(), 0);
        QCOMPARE(ready.size(), 0);
    }
    void bodyOverBudgetAndSlowPeerAreBounded() {
        ArtworkTlsServer server;
        prepare(server);
        server.reply = [](const QByteArray &) {
            return "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\n\r\n" + QByteArray(1024 * 1024 + 1, 'x');
        };
        Island::ArtworkLoader loader(nullptr, DECODER_PATH, FETCH_PATH);
        trust(loader);
        QSignalSpy ready(&loader, &Island::ArtworkLoader::ready), failed(&loader, &Island::ArtworkLoader::failed);
        loader.request(url(server), "oversize");
        QTRY_VERIFY_WITH_TIMEOUT(!failed.isEmpty(), 6000);
        QCOMPARE(failed[0][1].toString(), "art-byte-limit");
        failed.clear();
        server.reply = [](const QByteArray &) { return QByteArray(); };
        QElapsedTimer elapsed;
        elapsed.start();
        loader.request(url(server, "/stall"), "timeout");
        QTRY_VERIFY_WITH_TIMEOUT(!failed.isEmpty(), 6000);
        QCOMPARE(failed[0][1].toString(), "art-timeout");
        QVERIFY(elapsed.elapsed() >= 4500 && elapsed.elapsed() < 6000);
        QCOMPARE(ready.size(), 0);
    }
};

int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    auto arguments = app.arguments();
    if (arguments.contains("--decoder-resource-probe")) {
        // Full-pixel-budget real images below the compressed cap; PNG uses a
        // bounded palette so incompressible RGB does not exceed the input cap.
        const bool pngProbe = arguments.contains("--png");
        QImage image(1024, 1024, QImage::Format_RGB32);
        quint32 state = 0x12345678;
        for (int y = 0; y < image.height(); ++y) {
            auto *pixels = reinterpret_cast<QRgb *>(image.scanLine(y));
            for (int x = 0; x < image.width(); ++x) {
                state ^= state << 13; state ^= state >> 17; state ^= state << 5;
                const auto value = (state & 7) * 36;
                pixels[x] = pngProbe ? qRgb(value, value, value) : 0xff000000 | (state & 0xffffff);
            }
        }
        QByteArray bytes;
        QBuffer buffer(&bytes);
        buffer.open(QIODevice::WriteOnly);
        if (!image.save(&buffer, pngProbe ? "PNG" : "JPEG", pngProbe ? -1 : 75) || bytes.size() > 1024 * 1024) return 2;
        QProcess process;
        QElapsedTimer elapsed;
        elapsed.start();
        process.start(DECODER_PATH, {pngProbe ? "image/png" : "image/jpeg", "--measure"});
        process.write(bytes);
        process.closeWriteChannel();
        if (!process.waitForFinished(10000)) { process.kill(); process.waitForFinished(); return 3; }
        const auto output = process.readAllStandardOutput();
        fprintf(stdout, "resource-probe input-bytes=%lld output-bytes=%lld wall-ms=%lld\n",
            static_cast<long long>(bytes.size()), static_cast<long long>(output.size()),
            static_cast<long long>(elapsed.elapsed()));
        fprintf(stderr, "%s", process.readAllStandardError().constData());
        return process.exitCode();
    }
    if (arguments.removeAll("--network-fixture")) {
        ArtworkNetworkTest tests;
        return QTest::qExec(&tests, arguments);
    }
    ArtworkLoaderTest tests;
    return QTest::qExec(&tests, arguments);
}
#include "artwork-loader-test.moc"
