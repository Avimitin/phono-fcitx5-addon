#include "addon.h"
#include "check.h"
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <libime/pinyin/pinyindictionary.h>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>

using namespace fcitx;
using namespace phono_fcitx;

class Context : public InputContext {
public:
    explicit Context(InputContextManager &manager) : InputContext(manager, "dictionary-test") { created(); }
    ~Context() override { destroy(); }
    const char *frontend() const override { return "test"; }
    void commitStringImpl(const std::string &text) override { committed += text; }
    void deleteSurroundingTextImpl(int, unsigned int) override {}
    void forwardKeyImpl(const ForwardKeyEvent &) override {}
    void updatePreeditImpl() override {}
    std::string committed;
};

void writeDict(const std::filesystem::path &file, const std::string &word) {
    libime::PinyinDictionary dict;
    dict.addWord(libime::PinyinDictionary::SystemDict, "ce'shi'ci'ku", word);
    dict.save(libime::PinyinDictionary::SystemDict, file.c_str(), libime::PinyinDictFormat::Binary);
}

int main() {
    try {
        auto pattern = (std::filesystem::temp_directory_path() / "phono-dictionaries-XXXXXX").string();
        const auto *directory = mkdtemp(pattern.data());
        CHECK(directory);
        const std::filesystem::path root(directory);
        const auto data = root / "data", config = root / "config", system = root / "system";
        setenv("XDG_DATA_HOME", data.c_str(), 1);
        setenv("XDG_CONFIG_HOME", config.c_str(), 1);
        setenv("XDG_DATA_DIRS", system.c_str(), 1);
        setenv("FCITX_DATA_DIRS", (system / "fcitx5").c_str(), 1);
        const auto userDicts = data / "fcitx5/pinyin/dictionaries";
        const auto systemDicts = system / "fcitx5/pinyin/dictionaries";
        std::filesystem::create_directories(userDicts);
        std::filesystem::create_directories(systemDicts);
        writeDict(systemDicts / "shared.dict", "测式词库");
        writeDict(userDicts / "shared.dict", "测事词库");
        writeDict(systemDicts / "extra.dict", "测世词库");
        writeDict(systemDicts / "disabled.dict", "测市词库");
        writeDict(userDicts / "ignored.txt", "测试辞库");
        std::ofstream(userDicts / "disabled.dict.disable");
        std::ofstream(userDicts / "extra.disable"); // Only name.dict.disable disables name.dict.
        std::ofstream(userDicts / "broken.dict") << "invalid dictionary";

        char name[] = "dictionary-test", disable[] = "--disable=all";
        char *argv[] = {name, disable, nullptr};
        Instance instance(2, argv);
        instance.addonManager().registerDefaultLoader(nullptr);
        instance.initialize();
        Engine engine(&instance);
        Context ic(instance.inputContextManager());
        ic.focusIn();
        RawConfig settings;
        settings.setValueByPath("Enabled", "False");
        settings.setValueByPath("ShuangpinScheme", "Xiaohe");
        engine.setConfig(settings);
        auto *state = engine.state(&ic);
        auto *dict = state->pinyin.ime()->dict();
        auto hasWord = [&](const std::string &word) {
            for (size_t i = libime::PinyinDictionary::UserDict + 1; i < dict->dictSize(); ++i)
                if (dict->lookupWord(i, "ce'shi'ci'ku", word)) return true;
            return false;
        };
        CHECK(hasWord("测事词库") && hasWord("测世词库"));
        CHECK(!hasWord("测式词库") && !hasWord("测市词库") && !hasWord("测试辞库"));
        auto hasCandidate = [&] {
            for (const auto &candidate : state->pinyin.candidatesToCursor())
                if (candidate.toString() == "测世词库") return true;
            return false;
        };
        for (bool shuangpin : {false, true}) {
            InputMethodEntry entry(shuangpin ? "phono-shuangpin" : "phono", "Phono", "zh_CN", "phono");
            InputContextEvent activated(&ic, EventType::InputContextFocusIn);
            engine.activate(entry, activated);
            for (unsigned char c : std::string(shuangpin ? "ceuiciku" : "ceshiciku")) {
                KeyEvent event(&ic, Key(static_cast<KeySym>(c)), false);
                engine.keyEvent(entry, event);
            }
            CHECK(hasCandidate());
            state->pinyin.clear();
        }

        // Reload while composing; keep the input, cursor and personal dictionary.
        dict->addWord(libime::PinyinDictionary::UserDict, "ce'shi'ci'ku", "测是词库");
        state->pinyin.type("ceuiciku");
        state->pinyin.setCursor(4);
        const auto generation = state->generation;
        std::filesystem::remove(userDicts / "shared.dict");
        std::filesystem::remove(userDicts / "disabled.dict.disable");
        std::filesystem::remove(systemDicts / "extra.dict");
        engine.reloadConfig();
        CHECK(hasWord("测式词库") && hasWord("测市词库"));
        CHECK(!hasWord("测事词库") && !hasWord("测世词库"));
        CHECK(dict->lookupWord(libime::PinyinDictionary::UserDict, "ce'shi'ci'ku", "测是词库"));
        CHECK(state->pinyin.userInput() == "ceuiciku" && state->pinyin.cursor() == 4);
        CHECK(state->generation != generation);
        engine.select(&ic, generation, false, 0);
        CHECK(ic.committed.empty());
        const auto size = dict->dictSize();
        engine.reloadConfig();
        CHECK(dict->dictSize() == size);
        CHECK(dict->lookupWord(libime::PinyinDictionary::SystemDict, "ni'hao", "你好"));
        std::filesystem::remove_all(root);
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
