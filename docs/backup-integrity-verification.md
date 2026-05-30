# Backup Integrity Verification (#559)

## Overview

Backups are only useful if they can actually be restored. `verify-backup-integrity.sh`
checks that a backup archive is structurally sound and complete **before** it is
relied upon for recovery, and `scripts/test-backup-integrity.sh` proves the
verifier accepts good backups and rejects every class of corruption.

```bash
# Verify a single backup
./scripts/verify-backup-integrity.sh /var/backups/atomicip/backup_20260101_000000.tar.gz

# Run the verifier's own test suite
bash scripts/test-backup-integrity.sh
```

## What the verifier checks

1. **SHA-256 checksum** — if a `<backup>.sha256` sidecar is present (written
   automatically by `backup-contract-state.sh`), the archive's checksum must
   match it. A mismatch means the file was altered or truncated.
2. **Archive integrity** — `tar -tzf` must succeed (not corrupt/truncated).
3. **Required files present** — `metadata.json`, `ip_registry_state.json` and
   `atomic_swap_state.json` must all exist.
4. **Valid JSON** — every `*.json` in the backup must parse.

The script exits `0` only if every check passes; otherwise it exits `1` with a
description of the failure.

## Checksums

`backup-contract-state.sh` now writes a checksum sidecar next to each archive:

```
backup_20260101_000000.tar.gz
backup_20260101_000000.tar.gz.sha256
```

Both are uploaded to S3 when `BACKUP_S3_BUCKET` is configured. If no sidecar is
present (e.g. a legacy backup), the checksum step is skipped with a note and the
remaining structural checks still run — so the change is backward compatible.

## Test matrix

The suite in `scripts/test-backup-integrity.sh` covers:

| # | Input | Expected |
|---|-------|----------|
| 1 | Well-formed backup | Pass |
| 2 | Backup + matching checksum sidecar | Pass (checksum verified) |
| 3 | Archive changed after checksum written | Fail (checksum mismatch) |
| 4 | Corrupt/garbage archive | Fail (corruption) |
| 5 | Missing required state file | Fail (missing file) |
| 6 | Malformed JSON in a state file | Fail (invalid JSON) |
| 7 | No file argument | Fail (usage) |
| 8 | Nonexistent file | Fail (not found) |

## Regular verification

Integrity should be checked routinely, not only at restore time:

- **On creation** — `backup-contract-state.sh` writes the checksum sidecar so
  every backup is self-verifying.
- **On a schedule** — run `verify-backup-integrity.sh` against the most recent
  archive(s) from a cron job or scheduled CI workflow and alert on any non-zero
  exit.
- **Before restore** — `restore-contract-state.sh` and `activate-dr-site.sh`
  should be preceded by a verification pass (the DR drill in
  `docs/disaster-recovery-testing.md` enforces this ordering).
