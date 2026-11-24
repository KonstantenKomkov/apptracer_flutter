#pragma once
#include <filesystem>

namespace apptracer {
bool containsSessionMapping(const std::filesystem::path& dump,
                            const std::filesystem::path& marker);
}
