#!/usr/bin/env bash
# =============================================================================
# fetch-upstream.sh — clone Mondics's Confluent-on-LinuxONE reference at a
#                     pinned SHA into base/upstream/ (gitignored, never committed)
# =============================================================================
# Locked decision D-01: upstream code is never redistributed. We clone a
# specific SHA at activation time. Network access required (see KNOWN-GAPS.md).
#
# Usage:
#   bash base/fetch-upstream.sh
#   (called automatically by .flox/env/manifest.toml on-activate hook)
#
# Idempotency: no-ops if upstream/ already contains the correct SHA.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Pinned upstream reference — bump this SHA when you want to pull in updates
# from Mondics's repo. Always pin a specific commit, never a branch tip.
# ---------------------------------------------------------------------------
UPSTREAM_REPO="https://github.com/mmondics/Confluent-LinuxONE-Mirror.git"
UPSTREAM_SHA="05828eb90b3c508fddd99475b7d3fd42b00f67a3"  # pinned 2026-05-20 HEAD

# Resolve path relative to this script's location regardless of call site
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_DIR="${SCRIPT_DIR}/upstream"

# ---------------------------------------------------------------------------
# Idempotency check — skip if upstream/ already at the correct SHA
# ---------------------------------------------------------------------------
if [ -d "${UPSTREAM_DIR}/.git" ]; then
  current_sha=$(git -C "${UPSTREAM_DIR}" rev-parse HEAD 2>/dev/null || echo "unknown")
  if [ "${current_sha}" = "${UPSTREAM_SHA}" ]; then
    echo "[fetch-upstream] base/upstream/ already at ${UPSTREAM_SHA:0:12} — skipping."
    exit 0
  else
    echo "[fetch-upstream] base/upstream/ at ${current_sha:0:12}, want ${UPSTREAM_SHA:0:12} — re-fetching."
    rm -rf "${UPSTREAM_DIR}"
  fi
fi

# ---------------------------------------------------------------------------
# Clone at depth 1 then checkout the pinned SHA
# (--depth 1 fetches minimal history; checkout SHA pulls the specific commit)
# ---------------------------------------------------------------------------
echo "[fetch-upstream] Cloning ${UPSTREAM_REPO} ..."
git clone --depth 1 "${UPSTREAM_REPO}" "${UPSTREAM_DIR}"

echo "[fetch-upstream] Checking out pinned SHA ${UPSTREAM_SHA:0:12} ..."
# Unshallow so we can checkout the pinned commit if it differs from HEAD
git -C "${UPSTREAM_DIR}" fetch --unshallow 2>/dev/null || true
git -C "${UPSTREAM_DIR}" checkout "${UPSTREAM_SHA}"

actual_sha=$(git -C "${UPSTREAM_DIR}" rev-parse HEAD)
if [ "${actual_sha}" != "${UPSTREAM_SHA}" ]; then
  echo "[fetch-upstream] ERROR: HEAD is ${actual_sha}, expected ${UPSTREAM_SHA}" >&2
  exit 1
fi

echo "[fetch-upstream] Done. base/upstream/ is at ${UPSTREAM_SHA:0:12}."
echo "[fetch-upstream] Do NOT edit files under base/upstream/ — re-run this script to refresh."
