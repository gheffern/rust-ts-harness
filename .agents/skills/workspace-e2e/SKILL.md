---
name: workspace-e2e
description: >-
  Execute live HTTP health checks and Playwright browser end-to-end verification
  against the running application, serialized through scripts/with-cpu-lock.sh e2e.
---

# End-to-End Verification Runner (`workspace-e2e`)

Executes live health probes (`E2E_HEALTH_PATH`) and Playwright E2E specs (`web/e2e/playwright.config.ts`) serialized via `scripts/with-cpu-lock.sh e2e`.

## Execution

```bash
./scripts/run-e2e.sh [options] [-- <playwright-args...>]
```

### Common Examples
* **Run Full Health + Playwright Suite**:
  ```bash
  ./scripts/run-e2e.sh -u http://127.0.0.1:8080
  ```
* **Run Only Health Probe or Only Playwright Spec**:
  ```bash
  ./scripts/run-e2e.sh --health-only
  ./scripts/run-e2e.sh --playwright-only --spec e2e/smoke.spec.ts
  ```
* **Run Playwright Inside Container (`--container`)**:
  ```bash
  ./scripts/run-e2e.sh --container -u http://127.0.0.1:8080
  ```

## Logs
* Artifacts and JSON reports are written to `/tmp/<PROJECT_SLUG>-e2e-logs/latest/`.
