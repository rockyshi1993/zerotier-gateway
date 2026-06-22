#!/usr/bin/env bash

ztg_log_info() { printf '[INFO] %s\n' "$*"; }
ztg_log_warn() { printf '[WARN] %s\n' "$*" >&2; }
ztg_log_error() { printf '[ERROR] %s\n' "$*" >&2; }
ztg_log_step() { printf '\n==> %s\n' "$*"; }
