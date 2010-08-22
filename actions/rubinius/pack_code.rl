/* This file was generated by Ragel. Your edits will be lost.
 *
 * This is a state machine implementation of Array#pack.
 *
 * vim: filetype=cpp
 */

#include "vm/config.h"

#include "vm.hpp"
#include "object_utils.hpp"
#include "on_stack.hpp"
#include "objectmemory.hpp"

#include "builtin/array.hpp"
#include "builtin/exception.hpp"
#include "builtin/float.hpp"
#include "builtin/module.hpp"
#include "builtin/object.hpp"
#include "builtin/string.hpp"

namespace rubinius {
  namespace pack {
    static Object* integer(STATE, CallFrame* call_frame, Object* obj) {
      Array* args = Array::create(state, 1);
      args->set(state, 0, obj);

      return G(rubinius)->send(state, call_frame, state->symbol("pack_to_int"), args);
    }

    inline static String* encoding_string(STATE, CallFrame* call_frame, Object* obj,
                                          const char* coerce_name)
    {
      String* s = try_as<String>(obj);
      if(s) return s;

      Array* args = Array::create(state, 1);
      args->set(state, 0, obj);

      std::string coerce_method("pack_");
      coerce_method += coerce_name;
      Object* result = G(rubinius)->send(state, call_frame,
            state->symbol(coerce_method.c_str()), args);

      if(!result) return 0;
      return as<String>(result);
    }

    static Object* float_t(STATE, CallFrame* call_frame, Object* obj) {
      Array* args = Array::create(state, 1);
      args->set(state, 0, obj);

      return G(rubinius)->send(state, call_frame, state->symbol("pack_to_float"), args);
    }

    inline uint16_t swap16(uint16_t x) {
      return (((x & 0x00ff)<<8) | ((x & 0xff00)>>8));
    }

    inline uint32_t swap32(uint32_t x) {
      return (((x & 0x000000ff) << 24)
             |((x & 0xff000000) >> 24)
             |((x & 0x0000ff00) << 8)
             |((x & 0x00ff0000) >> 8));
    }

    inline uint64_t swap64(uint64_t x) {
      return (((x & 0x00000000000000ffLL) << 56)
             |((x & 0xff00000000000000LL) >> 56)
             |((x & 0x000000000000ff00LL) << 40)
             |((x & 0x00ff000000000000LL) >> 40)
             |((x & 0x0000000000ff0000LL) << 24)
             |((x & 0x0000ff0000000000LL) >> 24)
             |((x & 0x00000000ff000000LL) << 8)
             |((x & 0x000000ff00000000LL) >> 8));
    }

    inline static void swapf(std::string& str, float value) {
      uint32_t x;

      memcpy(&x, &value, sizeof(float));
      x = swap32(x);

      str.append((const char*)&x, sizeof(uint32_t));
    }

    inline static void swapd(std::string& str, double value) {
      uint64_t x;

      memcpy(&x, &value, sizeof(double));
      x = swap64(x);

      str.append((const char*)&x, sizeof(uint64_t));
    }

    inline static void double_element(std::string& str, double value) {
      str.append((const char*)&value, sizeof(double));
    }

    inline static void float_element(std::string& str, float value) {
      str.append((const char*)&value, sizeof(float));
    }

#define QUOTABLE_PRINTABLE_BUFSIZE 1024

    static void quotable_printable(String* s, std::string& str, int count) {
      static char hex_table[] = "0123456789ABCDEF";
      char buf[QUOTABLE_PRINTABLE_BUFSIZE];

      uint8_t* b = s->byte_address();
      uint8_t* e = b + s->size();
      int i = 0, n = 0, prev = -1;

      for(; b < e; b++) {
        if((*b > 126) || (*b < 32 && *b != '\n' && *b != '\t') || (*b == '=')) {
          buf[i++] = '=';
          buf[i++] = hex_table[*b >> 4];
          buf[i++] = hex_table[*b & 0x0f];
          n += 3;
          prev = -1;
        } else if(*b == '\n') {
          if(prev == ' ' || prev == '\t') {
            buf[i++] = '=';
            buf[i++] = *b;
          }
          buf[i++] = *b;
          n = 0;
          prev = *b;
        } else {
          buf[i++] = *b;
          n++;
          prev = *b;
        }

        if(n > count) {
          buf[i++] = '=';
          buf[i++] = '\n';
          n = 0;
          prev = '\n';
        }

        if(i > QUOTABLE_PRINTABLE_BUFSIZE - 5) {
          str.append(buf, i);
          i = 0;
        }
      }

      if(n > 0) {
        buf[i++] = '=';
        buf[i++] = '\n';
      }

      if(i > 0) {
        str.append(buf, i);
      }
    }

    static const char uu_table[] =
      "`!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_";
    static const char b64_table[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

#define b64_uu_byte1(t, b)      t[077 & (*b >> 2)]
#define b64_uu_byte2(t, b, c)   t[077 & (((*b << 4) & 060) | ((c >> 4) & 017))]
#define b64_uu_byte3(t, b, c)   t[077 & (((b[1] << 2) & 074) | ((c >> 6) & 03))];
#define b64_uu_byte4(t, b)      t[077 & b[2]];

    static void b64_uu_encode(String* s, std::string& str, size_t count,
                              const char* table, int padding, bool encode_size)
    {
      char *buf = ALLOCA_N(char, count * 4 / 3 + 6);
      size_t i, chars, line, total = s->size();
      uint8_t* b = s->byte_address();

      for(i = 0; total > 0; i = 0, total -= line) {
        line = total > count ? count : total;

        if(encode_size) buf[i++] = line + ' ';

        for(chars = line; chars >= 3; chars -= 3, b += 3) {
          buf[i++] = b64_uu_byte1(table, b);
          buf[i++] = b64_uu_byte2(table, b, b[1]);
          buf[i++] = b64_uu_byte3(table, b, b[2]);
          buf[i++] = b64_uu_byte4(table, b);
        }

        if(chars == 2) {
          buf[i++] = b64_uu_byte1(table, b);
          buf[i++] = b64_uu_byte2(table, b, b[1]);
          buf[i++] = b64_uu_byte3(table, b, '\0');
          buf[i++] = padding;
        } else if(chars == 1) {
          buf[i++] = b64_uu_byte1(table, b);
          buf[i++] = b64_uu_byte2(table, b, '\0');
          buf[i++] = padding;
          buf[i++] = padding;
        }

        b += chars;
        buf[i++] = '\n';
        str.append(buf, i);
      }
    }

    inline static size_t bit_extra(String* s, bool rest, size_t& count) {
      size_t extra = 0;

      if(rest) {
        count = s->size();
      } else {
        size_t size = s->size();
        if(count > size) {
          extra = (count - size + 1) / 2;
          count = size;
        }
      }

      return extra;
    }

    static void bit_high(String* s, std::string& str, size_t count) {
      uint8_t* b = s->byte_address();
      int byte = 0;

      for(size_t i = 0; i++ < count; b++) {
        byte |= *b & 1;
        if(i & 7) {
          byte <<= 1;
        } else {
          str.push_back(byte & 0xff);
          byte = 0;
        }
      }

      if (count & 7) {
        byte <<= 7 - (count & 7);
        str.push_back(byte & 0xff);
      }
    }

    static void bit_low(String* s, std::string& str, size_t count) {
      uint8_t* b = s->byte_address();
      int byte = 0;

      for(size_t i = 0; i++ < count; b++) {
        if(*b & 1)
          byte |= 128;

        if(i & 7) {
          byte >>= 1;
        } else {
          str.push_back(byte & 0xff);
          byte = 0;
        }
      }

      if(count & 7) {
        byte >>= 7 - (count & 7);
        str.push_back(byte & 0xff);
      }
    }

    inline static size_t hex_extra(String* s, bool rest, size_t& count) {
      size_t extra = 0;

      if(rest) {
        count = s->size();
      } else {
        size_t size = s->size();
        if(count > size) {
          extra = (count + 1) / 2 - (size + 1) / 2;
          count = size;
        }
      }

      return extra;
    }

    static void hex_high(String* s, std::string& str, size_t count) {
      uint8_t* b = s->byte_address();
      int byte = 0;

      for(size_t i = 0; i++ < count; b++) {
        if(ISALPHA(*b)) {
          byte |= ((*b & 15) + 9) & 15;
        } else {
          byte |= *b & 15;
        }

        if(i & 1) {
          byte <<= 4;
        } else {
          str.push_back(byte & 0xff);
          byte = 0;
        }
      }

      if(count & 1) {
        str.push_back(byte & 0xff);
      }
    }

    static void hex_low(String* s, std::string& str, size_t count) {
      uint8_t* b = s->byte_address();
      int byte = 0;

      for(size_t i = 0; i++ < count; b++) {
        if(ISALPHA(*b)) {
          byte |= (((*b & 15) + 9) & 15) << 4;
        } else {
          byte |= (*b & 15) << 4;
        }

        if(i & 1) {
          byte >>= 4;
        } else {
          str.push_back(byte & 0xff);
          byte = 0;
        }
      }

      if(count & 1) {
        str.push_back(byte & 0xff);
      }
    }
  }

#define BITS_LONG   (RBX_SIZEOF_LONG * 8)
#define BITS_64     (64)

#define CONVERT_INTEGER(T, v, m, b, n)    \
  if((n)->fixnum_p()) {                   \
    v = (T)STRIP_FIXNUM_TAG(n);           \
  } else {                                \
    Bignum* big = as<Bignum>(n);          \
    big->verify_size(state, b);           \
    v = big->m();                         \
  }

#define CONVERT_TO_INT(n)   CONVERT_INTEGER(int, int_value, to_int, BITS_LONG, n)
#define CONVERT_TO_LONG(n)  CONVERT_INTEGER(long long, long_value, to_long_long, BITS_64, n)

#define PACK_INT_ELEMENTS(mask)   PACK_ELEMENTS(Integer, pack::integer, INT, mask)
#define PACK_LONG_ELEMENTS(mask)  PACK_ELEMENTS(Integer, pack::integer, LONG, mask)

#define pack_float_elements(format)   pack_elements(Float, pack::float_t, format)

#define pack_double_le                pack_float_elements(pack_double_element_le)
#define pack_double_be                pack_float_elements(pack_double_element_be)

#define pack_float_le                 pack_float_elements(pack_float_element_le)
#define pack_float_be                 pack_float_elements(pack_float_element_be)

#define pack_elements(T, coerce, format)        \
  for(; index < stop; index++) {                \
    Object* item = self->get(state, index);     \
    T* value = try_as<T>(item);                 \
    if(!value) {                                \
      item = coerce(state, call_frame, item);   \
      if(!item) return 0;                       \
      value = as<T>(item);                      \
    }                                           \
    format(value);                              \
  }

#define PACK_ELEMENTS(T, coerce, size, format)  \
  for(; index < stop; index++) {                \
    Object* item = self->get(state, index);     \
    T* value = try_as<T>(item);                 \
    if(!value) {                                \
      item = coerce(state, call_frame, item);   \
      if(!item) return 0;                       \
      value = as<T>(item);                      \
    }                                           \
    CONVERT_TO_ ## size(value);                 \
    format;                                     \
  }

#define PACK_STRING_ELEMENT(coerce)  {                              \
  Object* item = self->get(state, index);                           \
  String* value = try_as<String>(item);                             \
  if(!value) {                                                      \
    value = pack::encoding_string(state, call_frame, item, coerce); \
    if(!value) return 0;                                            \
  }                                                                 \
  if(RTEST(value->tainted_p(state))) tainted = true;                \
  size_t size = value->size();                                      \
  if(rest) count = size;                                            \
  if(count <= size) {                                               \
    str.append((const char*)value->byte_address(), count);          \
    count = 0;                                                      \
  } else {                                                          \
    str.append((const char*)value->byte_address(), size);           \
    count = count - size;                                           \
  }                                                                 \
  index++;                                                          \
}

#define BYTE1(x)        (((x) & 0x00000000000000ff))
#define BYTE2(x)        (((x) & 0x000000000000ff00) >> 8)
#define BYTE3(x)        (((x) & 0x0000000000ff0000) >> 16)
#define BYTE4(x)        (((x) & 0x00000000ff000000) >> 24)

#define BYTE5(x)        (((x) & 0x000000ff00000000LL) >> 32)
#define BYTE6(x)        (((x) & 0x0000ff0000000000LL) >> 40)
#define BYTE7(x)        (((x) & 0x00ff000000000000LL) >> 48)
#define BYTE8(x)        (((x) & 0xff00000000000000LL) >> 56)

#ifdef RBX_LITTLE_ENDIAN
# define MASK_16BITS     LE_MASK_16BITS
# define MASK_32BITS     LE_MASK_32BITS
# define MASK_64BITS     LE_MASK_64BITS

# define pack_double_element_le(v)  (pack::double_element(str, (v)->val))
# define pack_double_element_be(v)  (pack::swapd(str, (v)->val))
# define pack_double                pack_double_le

# define pack_float_element_le(v)   (pack::float_element(str, (v)->val))
# define pack_float_element_be(v)   (pack::swapf(str, (v)->val))
# define pack_float                 pack_float_le
#else
# define MASK_16BITS     BE_MASK_16BITS
# define MASK_32BITS     BE_MASK_32BITS
# define MASK_64BITS     BE_MASK_64BITS

# define pack_double_element_le(v)  (pack::swapd(str, (v)->val))
# define pack_double_element_be(v)  (pack::double_element(str, (v)->val))
# define pack_double                pack_double_be

# define pack_float_element_le(v)   (pack::swapf(str, (v)->val))
# define pack_float_element_be(v)   (pack::float_element(str, (v)->val))
# define pack_float                 pack_float_be
#endif

#define LE_MASK_64BITS              \
  str.push_back(BYTE1(long_value)); \
  str.push_back(BYTE2(long_value)); \
  str.push_back(BYTE3(long_value)); \
  str.push_back(BYTE4(long_value)); \
  str.push_back(BYTE5(long_value)); \
  str.push_back(BYTE6(long_value)); \
  str.push_back(BYTE7(long_value)); \
  str.push_back(BYTE8(long_value)); \

#define BE_MASK_64BITS              \
  str.push_back(BYTE8(long_value)); \
  str.push_back(BYTE7(long_value)); \
  str.push_back(BYTE6(long_value)); \
  str.push_back(BYTE5(long_value)); \
  str.push_back(BYTE4(long_value)); \
  str.push_back(BYTE3(long_value)); \
  str.push_back(BYTE2(long_value)); \
  str.push_back(BYTE1(long_value)); \

#define LE_MASK_32BITS             \
  str.push_back(BYTE1(int_value)); \
  str.push_back(BYTE2(int_value)); \
  str.push_back(BYTE3(int_value)); \
  str.push_back(BYTE4(int_value)); \

#define BE_MASK_32BITS             \
  str.push_back(BYTE4(int_value)); \
  str.push_back(BYTE3(int_value)); \
  str.push_back(BYTE2(int_value)); \
  str.push_back(BYTE1(int_value)); \

#define LE_MASK_16BITS             \
  str.push_back(BYTE1(int_value)); \
  str.push_back(BYTE2(int_value)); \

#define BE_MASK_16BITS             \
  str.push_back(BYTE2(int_value)); \
  str.push_back(BYTE1(int_value)); \

#define MASK_BYTE                  \
  str.push_back(BYTE1(int_value));

  String* Array::pack(STATE, String* directives, CallFrame* call_frame) {
    // Ragel-specific variables
    std::string d(directives->c_str(), directives->size());
    const char *p  = d.c_str();
    const char *pe = p + d.size();
    const char *eof = pe;
    int cs;

    // pack-specific variables
    Array* self = this;
    OnStack<1> sv(state, self);

    size_t index = 0;
    size_t count = 0;
    size_t stop = 0;
    bool rest = false;
    bool platform = false;
    bool tainted = false;

    int int_value = 0;
    long long long_value = 0;
    std::string str("");

    // Use information we have to reduce repeated allocation.
    str.reserve(size() * 4);

%%{

  machine pack;

  include "pack.rl";

}%%

    if(pack_first_final && pack_error && pack_en_main) {
      // do nothing
    }

    return force_as<String>(Primitives::failure());
  }
}
