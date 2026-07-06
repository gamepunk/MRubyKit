#ifndef CMRUBY_SHIM_H
#define CMRUBY_SHIM_H

// ── 核心：VM 生命周期、值类型、基础宏 ──
#include <mruby.h>
#include <mruby/value.h>
#include <mruby/data.h>
#include <mruby/class.h>

// ── 脚本执行 / 编译 ──
#include <mruby/compile.h>
#include <mruby/proc.h>
#include <mruby/irep.h>

// ── 常用内建类型操作 ──
#include <mruby/string.h>
#include <mruby/array.h>
#include <mruby/hash.h>
#include <mruby/variable.h>
#include <mruby/numeric.h>

// ── 异常处理 ──
#include <mruby/error.h>

// ── 自定义方法注册 ──
#include <mruby/dump.h>

// ── GC 相关 ──
#include <mruby/gc.h>

// ── Swift 无法调用的函数式宏，包装为普通 C 内联函数 ──

// 类型判断
static inline mrb_bool mrb_bridge_nil_p    (mrb_value o) { return mrb_type(o) == MRB_TT_FALSE && !mrb_integer(o); }
static inline mrb_bool mrb_bridge_true_p   (mrb_value o) { return mrb_type(o) == MRB_TT_TRUE; }
static inline mrb_bool mrb_bridge_false_p  (mrb_value o) { return mrb_type(o) == MRB_TT_FALSE && !!mrb_integer(o); }
static inline mrb_bool mrb_bridge_bool_p   (mrb_value o) { return mrb_type(o) == MRB_TT_TRUE || mrb_type(o) == MRB_TT_FALSE; }
static inline mrb_bool mrb_bridge_integer_p(mrb_value o) { return mrb_type(o) == MRB_TT_INTEGER; }
static inline mrb_bool mrb_bridge_float_p  (mrb_value o) { return mrb_type(o) == MRB_TT_FLOAT; }
static inline mrb_bool mrb_bridge_string_p (mrb_value o) { return mrb_type(o) == MRB_TT_STRING; }
static inline mrb_bool mrb_bridge_array_p  (mrb_value o) { return mrb_type(o) == MRB_TT_ARRAY; }
static inline mrb_bool mrb_bridge_hash_p   (mrb_value o) { return mrb_type(o) == MRB_TT_HASH; }
static inline mrb_bool mrb_bridge_symbol_p (mrb_value o) { return mrb_type(o) == MRB_TT_SYMBOL; }

// 值提取
static inline mrb_int   mrb_bridge_integer(mrb_value o) { return mrb_integer(o); }
static inline mrb_float mrb_bridge_float  (mrb_value o) { return mrb_float(o); }
static inline mrb_bool  mrb_bridge_test   (mrb_value o) { return mrb_type(o) != MRB_TT_FALSE; }

// Array 长度
static inline mrb_int mrb_bridge_ary_len(mrb_value ary) { return RARRAY_LEN(ary); }

// 更多类型判断
static inline mrb_bool mrb_bridge_object_p   (mrb_value o) { return mrb_type(o) == MRB_TT_OBJECT; }
static inline mrb_bool mrb_bridge_exception_p(mrb_value o) { return mrb_type(o) == MRB_TT_EXCEPTION; }
static inline mrb_bool mrb_bridge_range_p    (mrb_value o) { return mrb_type(o) == MRB_TT_RANGE; }
static inline mrb_bool mrb_bridge_proc_p     (mrb_value o) { return mrb_type(o) == MRB_TT_PROC; }
static inline mrb_bool mrb_bridge_class_p    (mrb_value o) { return mrb_type(o) == MRB_TT_CLASS; }
static inline mrb_bool mrb_bridge_module_p   (mrb_value o) { return mrb_type(o) == MRB_TT_MODULE; }
static inline mrb_bool mrb_bridge_data_p     (mrb_value o) { return mrb_type(o) == MRB_TT_CDATA; }
static inline mrb_bool mrb_bridge_fiber_p    (mrb_value o) { return mrb_type(o) == MRB_TT_FIBER; }
static inline mrb_bool mrb_bridge_undef_p    (mrb_value o) { return mrb_type(o) == MRB_TT_UNDEF; }
static inline mrb_bool mrb_bridge_istruct_p  (mrb_value o) { return mrb_type(o) == MRB_TT_ISTRUCT; }

// 检查对象是否为指定类的实例（Ruby is_a?）
static inline mrb_bool mrb_bridge_obj_is_kind_of(mrb_state *mrb, mrb_value obj, struct RClass *c) {
  return mrb_obj_is_kind_of(mrb, obj, c);
}

// 检查对象是否响应某方法（Ruby respond_to?）
static inline mrb_bool mrb_bridge_respond_to(mrb_state *mrb, mrb_value obj, mrb_sym mid) {
  return mrb_respond_to(mrb, obj, mid);
}

// 宏包装：从 mrb_value 获取 RClass 指针
static inline struct RClass* mrb_bridge_class_ptr(mrb_value v) {
  return mrb_class_ptr(v);
}

// 宏包装：从 mrb_value 获取 RException 指针
static inline struct RException* mrb_bridge_exc_ptr(mrb_value v) {
  return mrb_exc_ptr(v);
}

// 宏包装：创建 mruby undefined 值（MRB_TT_UNDEF）
// 对应 JavaScript 的 `undefined`，mruby 内部使用。
// 在 Ruby 层面不常用，但可通过 C API 创建。
static inline mrb_value mrb_bridge_undef_value(void) {
  mrb_value v;
  SET_UNDEF_VALUE(v);
  return v;
}

#endif /* CMRUBY_SHIM_H */
