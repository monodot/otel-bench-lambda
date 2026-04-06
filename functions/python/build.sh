#!/usr/bin/env bash
# Build the Python Lambda deployment ZIP.
# Run this from any directory before `terraform apply`.
#
# Output: functions/python/dist/function.zip
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
zip -j dist/function.zip lambda_function.py
echo "Built: functions/python/dist/function.zip"
