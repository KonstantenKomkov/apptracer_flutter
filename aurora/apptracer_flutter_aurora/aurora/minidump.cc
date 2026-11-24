#include "minidump.h"
#include <array>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>

// Little-endian MINIDUMP_DIRECTORY and Breakpad MD_LINUX_MAPS. Only the
// directory and the maps stream need to be in memory, even for large dumps.
namespace apptracer {
namespace {
uint32_t le32(const unsigned char* data) {
  return uint32_t(data[0]) | (uint32_t(data[1]) << 8) |
         (uint32_t(data[2]) << 16) | (uint32_t(data[3]) << 24);
}
}  // namespace

bool containsSessionMapping(const std::filesystem::path& dump,
                            const std::filesystem::path& marker) {
  std::ifstream in(dump, std::ios::binary | std::ios::ate);
  const auto length = in.tellg();
  in.seekg(0);
  std::array<unsigned char, 32> header{};
  if (!in.read(reinterpret_cast<char*>(header.data()), header.size()) ||
      std::string(reinterpret_cast<char*>(header.data()), 4) != "MDMP") return false;
  const auto count = le32(header.data() + 8);
  const auto directory = le32(header.data() + 12);
  if (count > 512 || uint64_t(directory) + 12ULL * count > uint64_t(length)) return false;
  in.seekg(directory);
  for (uint32_t i = 0; i < count; ++i) {
    std::array<unsigned char, 12> entry{};
    if (!in.read(reinterpret_cast<char*>(entry.data()), entry.size())) return false;
    if (le32(entry.data()) != 0x47670009) continue;
    const auto size = le32(entry.data() + 4);
    const auto offset = le32(entry.data() + 8);
    if (size > 8 * 1024 * 1024 || uint64_t(offset) + size > uint64_t(length)) return false;
    std::string maps(size, '\0');
    in.seekg(offset);
    if (!in.read(maps.data(), size)) return false;
    std::istringstream lines(maps);
    std::string line;
    while (std::getline(lines, line)) {
      std::istringstream record(line);
      std::string range, permissions, fileOffset, device, inode, path;
      if (!(record >> range >> permissions >> fileOffset >> device >> inode)) continue;
      std::getline(record >> std::ws, path);
      if (path == marker.native()) return true;
    }
    return false;
  }
  return false;
}
}  // namespace apptracer
