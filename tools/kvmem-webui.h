#pragma once

#include "kvmem-chat-sampling.h"
#include "httplib.h"
#include <filesystem>

#include "kvmem-output-limit.h"

inline nlohmann::json kvmem_ui_sampling(bool thinking, const nlohmann::json & overrides) {
    auto sp = kvmem_chat_sampling_defaults(thinking);
    std::string error;
    if (!kvmem_chat_sampling_override(overrides, sp, error)) throw std::runtime_error(error);
    return {{"temperature", sp.temp}, {"top_p", sp.top_p}, {"top_k", sp.top_k}, {"min_p", sp.min_p},
            {"presence_penalty", sp.penalty_present}, {"frequency_penalty", sp.penalty_freq},
            {"repeat_penalty", sp.penalty_repeat}};
}

inline bool kvmem_mount_ui(httplib::Server & server, const std::string & requested, bool disabled, const char * argv0) {
    namespace fs = std::filesystem;
    if (disabled) return true;
    std::error_code ec;
    auto binary = fs::read_symlink("/proc/self/exe", ec);
    if (ec) binary = fs::absolute(argv0);
    const auto directory = requested.empty() ? binary.parent_path().parent_path() / "share/kvmem/ui" : fs::path(requested);
    if (!fs::is_regular_file(directory / "index.html")) {
        if (requested.empty()) return true;
        fprintf(stderr, "UI directory has no index.html: %s\n", directory.string().c_str());
        return false;
    }
    if (!server.set_mount_point("/", directory.string())) return false;
    server.set_file_request_handler([](const httplib::Request & req, httplib::Response & res) {
        res.set_header("Cache-Control", req.path.find("/_app/immutable/") == 0 ?
                       "public, max-age=31536000, immutable" : "no-cache");
    });
    fprintf(stderr, "KVMEM_UI directory=%s\n", directory.string().c_str());
    return true;
}
