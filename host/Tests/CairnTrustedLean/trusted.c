#include "cairn_trusted.h"

extern cairn_obj *lean_mk_string_from_bytes(const char *s, size_t sz);
extern cairn_obj *cairn_tf_wrap_lean(uint32_t family, uint32_t size, uint32_t weight,
                                     uint8_t italic, uint32_t width, cairn_obj *s);
extern cairn_obj *cairn_text_host_check(uint32_t family, uint32_t size, uint32_t weight,
                                        uint8_t italic, cairn_obj *s);

cairn_obj *cairn_tf_host_metrics(uint32_t family, uint32_t size, uint32_t weight, uint8_t italic,
                                 const uint8_t *utf8, size_t len) {
    return cairn_text_host_check(family, size, weight, italic,
                                 lean_mk_string_from_bytes((const char *)utf8, len));
}

cairn_obj *cairn_tf_wrap(uint32_t family, uint32_t size, uint32_t weight, uint8_t italic,
                         uint32_t width, const uint8_t *utf8, size_t len) {
    return cairn_tf_wrap_lean(family, size, weight, italic, width,
                              lean_mk_string_from_bytes((const char *)utf8, len));
}
