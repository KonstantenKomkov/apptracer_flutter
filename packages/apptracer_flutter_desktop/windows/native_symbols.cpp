#include "sentry.h"
#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <windows.h>
#include <filesystem>
#include <vector>

// Pinned to sentry-native 0.16.6. This file is linked only into sentry-crash,
// never into the crashed process. Missing or mismatched symbols leave the
// original SDK frames intact. No subprocess or network symbolizer is used.
namespace {
struct Function {
  uint64_t address, size;
  std::string name;
};
struct Line {
  uint64_t address, size;
  int number, file;
};
struct Symbols {
  std::map<int, std::string> files;
  std::vector<Function> functions;
  std::vector<Line> lines;
  bool valid = false;
};
static std::string text(sentry_value_t value) {
  const char *value_text = sentry_value_as_string(value);
  return value_text ? value_text : "";
}
static std::string field(sentry_value_t value, const char *key) {
  return text(sentry_value_get_by_key(value, key));
}
static std::string basename(const std::string &path) {
  return path.substr(path.find_last_of("/\\") + 1);
}
static std::string debug_id(const std::string &input) {
  std::string result;
  for (unsigned char c : input) {
    if (c == '-') continue;
    if (!std::isxdigit(c)) return "";
    result.push_back(std::toupper(c));
  }
  return result.size() >= 33 && result.size() <= 40 ? result : "";
}
static std::filesystem::path store_path() {
  wchar_t path[32768];
  DWORD length = GetModuleFileNameW(nullptr, path, 32768);
  if (length == 0 || length >= 32768) return {};
  return std::filesystem::path(path).parent_path() / L"symbols";
}
static Symbols load(const std::string &module, const std::string &id) {
  Symbols result;
  if (module.empty() || module == "." || module == ".." || id.empty())
    return result;
  std::ifstream input(store_path() / module / id / (module + ".sym"));
  std::string line, magic, os, arch, identity, name;
  if (!std::getline(input, line))
    return result;
  std::istringstream header(line);
  header >> magic >> os >> arch >> identity >> name;
  if (magic != "MODULE" || os != "windows" || arch != "x86_64" ||
      identity != id || name != module)
    return result;
  bool in_function = false;
  size_t bytes = line.size();
  while (std::getline(input, line)) {
    bytes += line.size();
    if (bytes > 64 * 1024 * 1024)
      return Symbols();
    std::istringstream row(line);
    if (line.rfind("FILE ", 0) == 0) {
      int file = -1;
      if (!(row >> magic >> file))
        return Symbols();
      std::string path;
      std::getline(row >> std::ws, path);
      if (file >= 0 && !path.empty())
        result.files[file] = path;
      in_function = false;
    } else if (line.rfind("FUNC ", 0) == 0) {
      std::string address;
      uint64_t size, parameter;
      row >> magic >> address;
      if (address == "m")
        row >> address;
      std::istringstream hex(address);
      uint64_t start;
      if (!(hex >> std::hex >> start) ||
          !(row >> std::hex >> size >> parameter))
        return Symbols();
      std::string function;
      std::getline(row >> std::ws, function);
      result.functions.push_back({start, size, function});
      in_function = true;
    } else if (in_function && !line.empty() &&
               std::isxdigit(static_cast<unsigned char>(line[0]))) {
      uint64_t address, size;
      int number, file;
      if (row >> std::hex >> address >> size >> std::dec >> number >> file)
        if (size > 0 && number > 0)
          result.lines.push_back({address, size, number, file});
    } else if (line.rfind("INLINE", 0) != 0 && !line.empty()) {
      in_function = false;
    }
  }
  std::sort(result.functions.begin(), result.functions.end(),
            [](const Function &a, const Function &b) {
              return a.address < b.address;
            });
  std::sort(result.lines.begin(), result.lines.end(),
            [](const Line &a, const Line &b) { return a.address < b.address; });
  result.valid = !input.bad();
  return result;
}
static void set_string(sentry_value_t value, const char *key,
                       const std::string &data) {
  sentry_value_set_by_key(value, key,
                                 sentry_value_new_string(data.c_str()));
}
static void resolve_frames(sentry_value_t frames, sentry_value_t images,
                           std::map<std::string, Symbols> &cache) {
  for (size_t i = 0; i < sentry_value_get_length(frames); ++i) {
    auto frame = sentry_value_get_by_index(frames, i);
    std::string package = field(frame, "package"),
                instruction = field(frame, "instruction_addr");
    if (package.empty() || instruction.empty())
      continue;
    for (size_t j = 0; j < sentry_value_get_length(images); ++j) {
      auto image = sentry_value_get_by_index(images, j);
      if (field(image, "code_file") != package || field(image, "type") != "pe")
        continue;
      std::string id = debug_id(field(image, "debug_id")),
                  module = basename(field(image, "debug_file"));
      if (id.empty())
        break;
      auto key = module + "/" + id;
      if (!cache.count(key))
        cache.emplace(key, load(module, id));
      const auto &symbols = cache.at(key);
      if (!symbols.valid)
        break;
      uint64_t pc, base;
      std::istringstream a(instruction), b(field(image, "image_addr"));
      if (!(a >> std::hex >> pc) || !(b >> std::hex >> base) || pc < base)
        break;
      auto address = pc - base;
      if (field(frame, "trust") != "context" && address > 0)
        --address;
      auto function = std::upper_bound(
          symbols.functions.begin(), symbols.functions.end(), address,
          [](uint64_t value, const Function &f) { return value < f.address; });
      if (function != symbols.functions.begin()) {
        --function;
        if (address - function->address < function->size)
          set_string(frame, "function", function->name);
      }
      auto line = std::upper_bound(
          symbols.lines.begin(), symbols.lines.end(), address,
          [](uint64_t value, const Line &l) { return value < l.address; });
      if (line != symbols.lines.begin()) {
        --line;
        auto source = symbols.files.find(line->file);
        if (address - line->address < line->size &&
            source != symbols.files.end()) {
          set_string(frame, "filename", source->second);
          set_string(frame, "abs_path", source->second);
          sentry_value_set_by_key(frame, "lineno",
                                         sentry_value_new_int32(line->number));
        }
      }
      break;
    }
  }
}
} // namespace

extern "C" int apptracer_set_value(sentry_value_t event,
                                              const char *key,
                                              sentry_value_t value) {
  int result = sentry_value_set_by_key(event, key, value);
  if (result != 0 || !key || std::strcmp(key, "debug_meta") != 0)
    return result;
  try {
    auto images = sentry_value_get_by_key(value, "images");
    std::map<std::string, Symbols> cache;
    for (const char *collection : {"exception", "threads"}) {
      auto values = sentry_value_get_by_key(
          sentry_value_get_by_key(event, collection), "values");
      for (size_t i = 0; i < sentry_value_get_length(values); ++i) {
        auto stack = sentry_value_get_by_key(
            sentry_value_get_by_index(values, i), "stacktrace");
        resolve_frames(sentry_value_get_by_key(stack, "frames"), images, cache);
      }
    }
  } catch (...) { /* Symbol failure must never prevent official SDK delivery. */
  }
  return result;
}
