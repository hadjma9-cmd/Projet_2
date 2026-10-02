/*
 * MIT License

Copyright (c) 2023 AmirHosseinCH

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#include "EmojiModel.hpp"
#include "core/path/Paths.hpp"
#include "tool/Constants.hpp"

namespace {
// Liste des emojis lue et indexee une seule fois pour toute l'application. Chaque selecteur relisait et
// analysait les 560 Ko du fichier, sur le fil de l'interface. Les copies faites par EmojiModel sont
// partagees (Qt) tant qu'on n'y accede qu'en lecture : d'ou les acces const ci-dessous.
struct EmojiData {
	QMap<QString, QJsonArray> emojies;
	QMap<QString, QVector<QJsonObject>> keywords;
};

const EmojiData &emojiData() {
	static const EmojiData data = [] {
		EmojiData result;
		QFile file(QString(":/data/emoji/emoji.json"));
		if (!file.open(QIODevice::ReadOnly)) return result;
		QByteArray bytes = file.readAll();
		file.close();
		QJsonDocument doc = QJsonDocument::fromJson(bytes);
		QJsonObject rootObj = doc.object();
		for (auto category{rootObj.begin()}; category != rootObj.end(); ++category) {
			result.emojies[category.key()] = category.value().toArray();
			QJsonArray &emojiesData = result.emojies[category.key()];
			for (auto it{emojiesData.begin()}; it != emojiesData.end(); ++it) {
				QJsonObject emoji = it->toObject();
				QJsonArray allKeywords = emoji.value("keywords").toArray();
				for (auto k{allKeywords.begin()}; k != allKeywords.end(); ++k) {
					result.keywords[k->toString()].append(emoji);
				}
			}
		}
		return result;
	}();
	return data;
}
} // namespace

EmojiModel::EmojiModel() : emojies(emojiData().emojies), keywords(emojiData().keywords) {
}

int EmojiModel::count(QString category) {
	return emojies.value(category).size();
}

QString EmojiModel::path(QString category, int index, int skinColor) {
	QJsonObject emoji = emojies.value(category).at(index).toObject();
	if (emoji.contains("types") && skinColor != -1) {
		QJsonArray types = emoji.value("types").toArray();
		return mIconsPath + types[skinColor].toString() + mIconsType;
	} else return mIconsPath + emoji.value("code").toString() + mIconsType;
}

QVector<QString> EmojiModel::search(QString searchKey, int skinColor) {
	bool foundFirstItem{false};
	QVector<QString> searchResult;
	for (auto it{keywords.cbegin()}; it != keywords.cend(); ++it) {
		if (it.key().startsWith(searchKey)) {
			const QVector<QJsonObject> &emojiesData{it.value()};
			for (auto emoji{emojiesData.cbegin()}; emoji != emojiesData.cend(); ++emoji) {
				if (emoji->contains("types") && skinColor != -1) {
					QJsonArray types = emoji->value("types").toArray();
					QString path = mIconsPath + types[skinColor].toString() + mIconsType;
					if (!searchResult.contains(path)) searchResult.append(path);
				} else {
					QString path = mIconsPath + emoji->value("code").toString() + mIconsType;
					if (!searchResult.contains(path)) searchResult.append(path);
				}
			}
			foundFirstItem = true;
		} else if (foundFirstItem) {
			break;
		}
	}
	return searchResult;
}

void EmojiModel::setIconsPath(QString path) {
	mIconsPath = path;
}

void EmojiModel::setIconsType(QString type) {
	mIconsType = type;
}
