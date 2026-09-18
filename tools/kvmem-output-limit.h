#pragma once

#include "nlohmann/json.hpp"
#include <algorithm>
#include <cstdint>
#include <string>

inline int kvmem_generation_limit(int context, bool enabled, uint32_t reserve, bool resident) {
    return enabled && reserve > 0 && !resident ?
        static_cast<int>(std::min<uint64_t>(context, reserve)) : context;
}

inline bool kvmem_output_limit(const nlohmann::json & body, int limit, int & value, std::string & error) {
    const char * key = body.contains("max_tokens") ? "max_tokens" : "max_completion_tokens";
    if (body.contains(key)) {
        const auto & n = body[key];
        if (!n.is_number_integer() || n.get<double>() < -1 || n.get<double>() > limit || n == 0) {
            error = std::string(key) + " must be -1 (server default) or an integer in 1.." + std::to_string(limit);
            return false;
        }
        if (n != -1) value = n.get<int>();
    }
    if (value < 1) value = limit;
    value = std::min(value, limit);
    return true;
}

