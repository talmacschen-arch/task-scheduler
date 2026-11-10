#!/usr/bin/env python3
"""
cron_match.py - Cron 表达式时间匹配工具

用法：
    # 检查当前时间是否匹配 cron 表达式
    python3 cron_match.py "30 2 * * *"

    # 检查指定时间是否匹配
    python3 cron_match.py "30 2 * * *" "2026-03-20 02:30"

退出码：
    0 - 匹配
    1 - 不匹配
    2 - 表达式格式错误

支持的 cron 字段格式：
    *       任意值
    */N     每隔 N
    N       固定值
    N,M     多个值
    N-M     范围
    N-M/S   范围内步进
"""

import sys
from datetime import datetime


def parse_cron_field(field_str, min_val, max_val):
    """解析单个 cron 字段，返回匹配值的集合"""
    values = set()

    for part in field_str.split(','):
        part = part.strip()

        if part == '*':
            values.update(range(min_val, max_val + 1))

        elif part.startswith('*/'):
            step = int(part[2:])
            if step <= 0:
                raise ValueError(f"invalid step: {step}")
            values.update(range(min_val, max_val + 1, step))

        elif '/' in part:
            # N-M/S 格式
            range_part, step_str = part.split('/')
            step = int(step_str)
            if '-' in range_part:
                start, end = map(int, range_part.split('-'))
            else:
                start = int(range_part)
                end = max_val
            values.update(range(start, end + 1, step))

        elif '-' in part:
            start, end = map(int, part.split('-'))
            values.update(range(start, end + 1))

        else:
            values.add(int(part))

    return values


def cron_match(cron_expr, check_time=None):
    """
    检查时间是否匹配 cron 表达式

    参数:
        cron_expr: "分 时 日 月 星期" 格式的 cron 表达式
        check_time: datetime 对象，默认当前时间

    返回:
        True/False
    """
    if check_time is None:
        check_time = datetime.now()

    fields = cron_expr.strip().split()
    if len(fields) != 5:
        raise ValueError(f"cron expression must have 5 fields, got {len(fields)}")

    minute_str, hour_str, day_str, month_str, weekday_str = fields

    try:
        minutes = parse_cron_field(minute_str, 0, 59)
        hours = parse_cron_field(hour_str, 0, 23)
        days = parse_cron_field(day_str, 1, 31)
        months = parse_cron_field(month_str, 1, 12)
        weekdays = parse_cron_field(weekday_str, 0, 7)
    except (ValueError, IndexError) as e:
        raise ValueError(f"invalid cron expression: {e}")

    # 星期天可以是 0 或 7
    if 7 in weekdays:
        weekdays.add(0)

    current_weekday = check_time.weekday()
    # Python: Monday=0, cron: Sunday=0, Monday=1
    cron_weekday = (current_weekday + 1) % 7

    return (check_time.minute in minutes and
            check_time.hour in hours and
            check_time.day in days and
            check_time.month in months and
            cron_weekday in weekdays)


def main():
    if len(sys.argv) < 2:
        print("Usage: cron_match.py <cron_expr> [datetime]", file=sys.stderr)
        sys.exit(2)

    cron_expr = sys.argv[1]

    check_time = None
    if len(sys.argv) >= 3:
        try:
            check_time = datetime.strptime(sys.argv[2], "%Y-%m-%d %H:%M")
        except ValueError:
            print(f"Invalid datetime format: {sys.argv[2]}", file=sys.stderr)
            print("Expected: YYYY-MM-DD HH:MM", file=sys.stderr)
            sys.exit(2)

    try:
        if cron_match(cron_expr, check_time):
            sys.exit(0)
        else:
            sys.exit(1)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
