#!/usr/bin/env bash
# Проверка перед коммитом: импорт, линт (предупреждения = ошибки), все тесты.
# Использование: tools/check.sh [путь к godot]
set -u
GODOT="${1:-${GODOT:-godot}}"
cd "$(dirname "$0")/.."

cleanup() { rm -f override.cfg; }
trap cleanup EXIT

# Предупреждения GDScript, включённые по умолчанию, поднимаем до ошибок только на время проверки.
cat > override.cfg <<'CFG'
[debug]
gdscript/warnings/unused_variable=2
gdscript/warnings/unused_local_constant=2
gdscript/warnings/unused_private_class_variable=2
gdscript/warnings/unused_parameter=2
gdscript/warnings/unused_signal=2
gdscript/warnings/shadowed_variable=2
gdscript/warnings/shadowed_variable_base_class=2
gdscript/warnings/shadowed_global_identifier=2
gdscript/warnings/unreachable_code=2
gdscript/warnings/unreachable_pattern=2
gdscript/warnings/standalone_expression=2
gdscript/warnings/standalone_ternary=2
gdscript/warnings/incompatible_ternary=2
gdscript/warnings/narrowing_conversion=2
gdscript/warnings/integer_division=2
gdscript/warnings/int_as_enum_without_cast=2
gdscript/warnings/int_as_enum_without_match=2
gdscript/warnings/static_called_on_instance=2
gdscript/warnings/redundant_await=2
gdscript/warnings/confusable_identifier=2
gdscript/warnings/inference_on_variant=2
gdscript/warnings/native_method_override=2
gdscript/warnings/get_node_default_without_onready=2
gdscript/warnings/onready_with_export=2
gdscript/warnings/missing_tool=2
gdscript/warnings/empty_file=2
gdscript/warnings/deprecated_keyword=2
gdscript/warnings/assert_always_true=2
gdscript/warnings/assert_always_false=2
gdscript/warnings/enum_variable_without_default=2
gdscript/warnings/unassigned_variable=2
gdscript/warnings/unassigned_variable_op_assign=2
CFG

status=0
echo "== импорт ресурсов"
"$GODOT" --headless --import --path . >/tmp/gc_import.log 2>&1 || true
grep -E "ERROR|SCRIPT ERROR" /tmp/gc_import.log && status=1

echo "== линт скриптов"
timeout 120 "$GODOT" --headless --path . res://tools/lint.tscn 2>&1 | tee /tmp/gc_lint.log | grep -E "lint:|LINT FAIL|Parse Error|ERROR" || true
grep -qE "LINT FAIL|SCRIPT ERROR|Parse Error" /tmp/gc_lint.log && status=1

echo "== запуск главной сцены (5 с)"
"$GODOT" --headless --path . --quit-after 300 res://ui/main.tscn >/tmp/gc_run.log 2>&1
grep -E "ERROR|WARNING|SCRIPT ERROR" /tmp/gc_run.log && status=1

echo "== тесты"
"$GODOT" --headless --path . res://tests/test_runner.tscn 2>&1 | tee /tmp/gc_tests.log | grep -vE "^(Godot Engine|$)"
[ "${PIPESTATUS[0]}" -eq 0 ] || status=1
grep -qE "SCRIPT ERROR|^ERROR" /tmp/gc_tests.log && { echo "в логе тестов есть ошибки"; status=1; }

if [ $status -eq 0 ]; then echo "== ВСЁ ЗЕЛЁНОЕ"; else echo "== ЕСТЬ ПРОБЛЕМЫ"; fi
exit $status
