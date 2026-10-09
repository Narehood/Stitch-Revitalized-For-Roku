# Dependency and diagnostics policy

The Roku channel contains BrightScript, assets, and settings; it does not contain the npm toolchain. All JavaScript dependencies are development tools. The Python demux service is a separate runtime and is audited without exceptions using the locked runtime dependency export and `pip-audit` in CI.

Run `npm run audit` to check the npm graph. The check prints raw audit totals and fails on every unapproved high or critical finding. It does not claim that approved findings have been patched.

## Temporary build dependency exception

As of October 7, 2026, [GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm) affects `braces` and no patched release is available. The compiler/linter/deployer inherit its high-severity classification. The vulnerable input is a deeply nested glob pattern; these tools receive fixed patterns from repository configuration, not stream URLs, chat, or remote user input. This package is absent from both the Roku ZIP and proxy runtime.

`security/npm-audit-policy.json` allows only this advisory in development-only `braces` 3.0.3, including its development-only callers. The exception expires November 6, 2026. A new advisory, different version, runtime installation, unresolved dependency edge, invalid audit response, or an available fix must fail the check. Remove the exception when a compatible upstream patch lands. Reviewers must assess this residual risk alongside the modernization diff.

The raw graph also reports moderate [GHSA-vcc3-ghjq-m6fr](https://github.com/advisories/GHSA-vcc3-ghjq-m6fr) in the simulator's old source-map decoding chain. Version 0.5 is ESM and does not provide the callable CommonJS export expected by that chain. Do not force a major API override without verifying simulator compatibility. This remains a documented development-only maintenance item; the check retains the project's high-severity blocking threshold. Simulator fixtures use explicit trusted local paths.

## Credentials and diagnostics

Keep `DEV.md`, local compiler configuration, device credentials, `.env` files, and the optional `env` package configuration out of version control. Signed playback URLs and OAuth tokens must never appear in diagnostic logs or committed fixtures. Secure chat may use OAuth; the anonymous plaintext fallback must never transmit it.

Remote diagnostics are off by default and require a fresh explicit settings opt-in plus a maintainer-configured HTTPS endpoint. The old fork-specific endpoint/key is removed. Optional diagnostics use a session identifier rather than a persistent device identifier, and exception payloads omit raw messages. Configure the optional, ignored `env` file only when maintaining your own diagnostics service:

```json
{
  "analytics": {
    "captureUrl": "https://YOUR_SERVICE/capture/",
    "apiKey": "YOUR_WRITE_KEY"
  }
}
```

The configured file is included in a built channel if present. Treat its contents as client-visible; never place a server-side secret in it.
